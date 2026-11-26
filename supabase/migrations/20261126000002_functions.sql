-- جميع عمليات الكتابة تمر عبر هذه الدوال فقط. لا صلاحية كتابة مباشرة على الجداول.

create function public.is_super_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role_key = 'super_admin'
  );
$$;

create function public.require_super_admin() returns uuid
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return auth.uid();
end $$;

create function public.get_public_settings() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from public.settings where is_public;
$$;

-- يستدعيها الخادم فقط (service_role) بعد رفع الصورتين إلى التخزين الخاص
create function public.register_account(
  p_user_id      uuid,
  p_account_type public.account_type,
  p_phone        text,
  p_email        text,
  p_locale       text,
  p_documents    jsonb,
  p_ip           text default null,
  p_user_agent   text default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_doc   jsonb;
  v_type  public.document_type;
  v_terms text;
  v_dupes integer;
begin
  if not exists (select 1 from auth.users u where u.id = p_user_id and lower(u.email) = p_email) then
    raise exception 'user_mismatch' using errcode = '22023';
  end if;
  if exists (select 1 from public.user_roles r where r.user_id = p_user_id) then
    raise exception 'admin_cannot_register' using errcode = '42501';
  end if;
  if p_documents is null or jsonb_typeof(p_documents) <> 'array'
     or jsonb_array_length(p_documents) <> 2
     or (select count(distinct d ->> 'doc_type') from jsonb_array_elements(p_documents) d) <> 2 then
    raise exception 'two_documents_required' using errcode = '22023';
  end if;

  select value #>> '{}' into v_terms from public.settings where key = 'legal.terms_version';

  insert into public.profiles (id, account_type, phone, email, locale, terms_version)
  values (p_user_id, p_account_type, p_phone, p_email, p_locale, v_terms);

  for v_doc in select * from jsonb_array_elements(p_documents) loop
    v_type := (v_doc ->> 'doc_type')::public.document_type;
    if (v_doc ->> 'storage_path') is null
       or not starts_with(v_doc ->> 'storage_path', p_user_id::text || '/') then
      raise exception 'invalid_storage_path' using errcode = '22023';
    end if;
    if not exists (select 1 from storage.objects o
                   where o.bucket_id = 'identity-documents' and o.name = v_doc ->> 'storage_path') then
      raise exception 'document_not_uploaded' using errcode = '22023';
    end if;

    -- إعادة استخدام الصورة نفسها: تنبيه للإدارة فقط، دون حظر تلقائي
    select count(*) into v_dupes from public.identity_documents i where i.sha256 = v_doc ->> 'sha256';

    insert into public.identity_documents
      (profile_id, doc_type, storage_path, sha256, mime_type, size_bytes, width, height)
    values
      (p_user_id, v_type, v_doc ->> 'storage_path', v_doc ->> 'sha256', v_doc ->> 'mime_type',
       (v_doc ->> 'size_bytes')::int, (v_doc ->> 'width')::int, (v_doc ->> 'height')::int);

    if v_dupes > 0 then
      insert into public.security_events (kind, severity, profile_id, details)
      values ('duplicate_identity_document', 'warning', p_user_id,
              jsonb_build_object('doc_type', v_type, 'matches', v_dupes));
    end if;
  end loop;

  insert into public.account_status_history (profile_id, from_status, to_status, actor_id)
  values (p_user_id, null, 'pending', p_user_id);
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, details, ip, user_agent)
  values (p_user_id, 'account.registered', 'profile', p_user_id,
          jsonb_build_object('account_type', p_account_type), p_ip, p_user_agent);
end $$;

-- سياسة الاحتفاظ تتبع حالة الحساب تلقائياً
create function public.apply_document_retention() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_days integer;
begin
  if new.status = old.status then
    return new;
  end if;

  if new.status = 'banned' then
    -- حفظ الأدلة
    update public.identity_documents set legal_hold = true, purge_after = null
      where profile_id = new.id and purged_at is null;
    return new;
  end if;

  if new.status in ('rejected', 'approved') then
    select (value #>> '{}')::integer into v_days from public.settings
      where key = 'retention.' || new.status::text || '_documents_days';
  end if;

  update public.identity_documents
     set legal_hold  = false,
         purge_after = case when v_days is null then null else now() + make_interval(days => v_days) end
   where profile_id = new.id and purged_at is null;
  return new;
end $$;
create trigger profiles_retention after update of status on public.profiles
  for each row execute function public.apply_document_retention();

create function public.review_registration(
  p_profile_id          uuid,
  p_decision            text,
  p_reason              text    default null,
  p_verified_name       text    default null,
  p_age_confirmed       boolean default false,
  p_documents_confirmed boolean default false
) returns public.account_status
language plpgsql security definer set search_path = '' as $$
declare
  v_admin uuid := public.require_super_admin();
  v_from  public.account_status;
  v_to    public.account_status;
begin
  select status into v_from from public.profiles where id = p_profile_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  if v_from <> 'pending' then
    raise exception 'not_pending' using errcode = '55000';
  end if;

  if p_decision = 'approve' then
    if coalesce(length(btrim(p_verified_name)), 0) < 3 then
      raise exception 'verified_name_required' using errcode = '22023';
    end if;
    if p_age_confirmed is not true then
      raise exception 'age_confirmation_required' using errcode = '22023';
    end if;
    if p_documents_confirmed is not true or
       (select count(*) from public.identity_documents
         where profile_id = p_profile_id and purged_at is null) <> 2 then
      raise exception 'documents_confirmation_required' using errcode = '22023';
    end if;
    v_to := 'approved';
    update public.profiles
       set status = v_to, verified_name = btrim(p_verified_name), age_verified = true,
           status_reason = null, reviewed_by = v_admin, reviewed_at = now()
     where id = p_profile_id;
  elsif p_decision = 'reject' then
    if coalesce(length(btrim(p_reason)), 0) < 5 then
      raise exception 'reason_required' using errcode = '22023';
    end if;
    v_to := 'rejected';
    update public.profiles
       set status = v_to, status_reason = btrim(p_reason), reviewed_by = v_admin, reviewed_at = now()
     where id = p_profile_id;
  else
    raise exception 'invalid_decision' using errcode = '22023';
  end if;

  insert into public.account_status_history (profile_id, from_status, to_status, reason, actor_id)
  values (p_profile_id, v_from, v_to, nullif(btrim(p_reason), ''), v_admin);
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'account.' || v_to::text, 'profile', p_profile_id,
          jsonb_build_object('from', v_from));
  return v_to;
end $$;

-- تجميد / حظر / إعادة تفعيل / إعادة فتح طلب مرفوض
create function public.set_account_status(
  p_profile_id uuid,
  p_new_status public.account_status,
  p_reason     text
) returns public.account_status
language plpgsql security definer set search_path = '' as $$
declare
  v_admin   uuid := public.require_super_admin();
  v_profile public.profiles%rowtype;
begin
  if coalesce(length(btrim(p_reason)), 0) < 5 then
    raise exception 'reason_required' using errcode = '22023';
  end if;
  select * into v_profile from public.profiles where id = p_profile_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  if not (
       (v_profile.status = 'approved'  and p_new_status in ('suspended', 'banned'))
    or (v_profile.status = 'suspended' and p_new_status in ('approved', 'banned'))
    or (v_profile.status = 'pending'   and p_new_status = 'banned')
    or (v_profile.status = 'rejected'  and p_new_status in ('pending', 'banned'))
    or (v_profile.status = 'banned'    and p_new_status in ('approved', 'pending'))
  ) then
    raise exception 'invalid_transition' using errcode = '55000';
  end if;
  -- لا تفعيل لحساب لم تتم الموافقة عليه من قبل
  if p_new_status = 'approved' and not v_profile.age_verified then
    raise exception 'never_approved' using errcode = '55000';
  end if;
  if p_new_status = 'pending' and
     (select count(*) from public.identity_documents
       where profile_id = p_profile_id and purged_at is null) <> 2 then
    raise exception 'documents_purged' using errcode = '55000';
  end if;

  update public.profiles
     set status = p_new_status,
         status_reason = case when p_new_status in ('approved', 'pending') then null else btrim(p_reason) end,
         reviewed_by = v_admin, reviewed_at = now()
   where id = p_profile_id;

  insert into public.account_status_history (profile_id, from_status, to_status, reason, actor_id)
  values (p_profile_id, v_profile.status, p_new_status, btrim(p_reason), v_admin);
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, details)
  values (v_admin, 'account.status_changed', 'profile', p_profile_id,
          jsonb_build_object('from', v_profile.status, 'to', p_new_status, 'reason', btrim(p_reason)));
  return p_new_status;
end $$;

-- الطريق الوحيد لمعرفة مسار الملف: يسجل العرض أولاً ثم يعيد المسار
create function public.log_document_view(
  p_document_id uuid, p_ip text default null, p_user_agent text default null
) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_admin uuid := public.require_super_admin();
  v_doc   public.identity_documents%rowtype;
begin
  select * into v_doc from public.identity_documents where id = p_document_id;
  if not found or v_doc.purged_at is not null then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, details, ip, user_agent)
  values (v_admin, 'document.viewed', 'identity_document', v_doc.id,
          jsonb_build_object('profile_id', v_doc.profile_id, 'doc_type', v_doc.doc_type),
          p_ip, p_user_agent);
  return v_doc.storage_path;
end $$;

create function public.documents_due_for_purge(p_limit integer default 100)
returns table (id uuid, storage_path text)
language sql stable security definer set search_path = '' as $$
  select d.id, d.storage_path from public.identity_documents d
  where d.purged_at is null and not d.legal_hold and d.purge_after <= now()
  order by d.purge_after limit p_limit;
$$;

create function public.mark_document_purged(p_document_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_doc public.identity_documents%rowtype;
begin
  select * into v_doc from public.identity_documents where id = p_document_id for update;
  if not found or v_doc.purged_at is not null or v_doc.legal_hold
     or v_doc.purge_after is null or v_doc.purge_after > now() then
    raise exception 'not_due' using errcode = '55000';
  end if;
  if exists (select 1 from storage.objects o
             where o.bucket_id = 'identity-documents' and o.name = v_doc.storage_path) then
    raise exception 'object_still_exists' using errcode = '55000';
  end if;
  update public.identity_documents set purged_at = now() where id = p_document_id;
  insert into public.audit_logs (action, entity_type, entity_id, details)
  values ('document.purged', 'identity_document', p_document_id,
          jsonb_build_object('profile_id', v_doc.profile_id));
end $$;

-- تسجيلات انقطعت في منتصفها (مستخدم بلا ملف حساب) أقدم من ساعة
create function public.orphaned_registrations()
returns table (user_id uuid, object_names text[])
language sql stable security definer set search_path = '' as $$
  select u.id,
         array(select o.name from storage.objects o
               where o.bucket_id = 'identity-documents' and starts_with(o.name, u.id::text || '/'))
  from auth.users u
  where u.created_at < now() - interval '1 hour'
    and not exists (select 1 from public.profiles p where p.id = u.id)
    and not exists (select 1 from public.user_roles r where r.user_id = u.id);
$$;

create function public.check_rate_limit(p_bucket text, p_limit integer, p_window_seconds integer)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_start timestamptz :=
    to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  v_hits integer;
begin
  insert into public.rate_limits as r (bucket, window_start) values (p_bucket, v_start)
  on conflict (bucket, window_start) do update set hits = r.hits + 1
  returning r.hits into v_hits;
  delete from public.rate_limits where bucket = p_bucket and window_start < v_start;
  return v_hits <= p_limit;
end $$;

create function public.bootstrap_super_admin(p_user_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  lock table public.user_roles in exclusive mode;
  if exists (select 1 from public.user_roles where role_key = 'super_admin') then
    raise exception 'super_admin_exists' using errcode = '55000';
  end if;
  if exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'user_has_profile' using errcode = '55000';
  end if;
  insert into public.user_roles (user_id, role_key) values (p_user_id, 'super_admin');
  insert into public.audit_logs (actor_id, action, entity_type, entity_id)
  values (p_user_id, 'admin.bootstrapped', 'user', p_user_id);
end $$;
