-- مهمتك: التثبيت الأول على مشروع Supabase فارغ. يُشغّل مرة واحدة.
begin;

-- ===== 20261126000001_identity_schema.sql =====
-- مهمتك | المرحلة 1: الهوية والحسابات والتدقيق
create type public.account_type   as enum ('client', 'company');
create type public.account_status as enum ('pending', 'approved', 'rejected', 'suspended', 'banned');
create type public.document_type  as enum ('national_id_front', 'residence_card_front');

-- الأدوار: لا يوجد في النسخة الحالية سوى المدير العام
create table public.roles (
  key         text primary key,
  description text not null
);
create table public.permissions (
  key         text primary key,
  description text not null
);
create table public.role_permissions (
  role_key       text not null references public.roles (key),
  permission_key text not null references public.permissions (key),
  primary key (role_key, permission_key)
);
create table public.user_roles (
  user_id    uuid not null references auth.users (id) on delete restrict,
  role_key   text not null references public.roles (key),
  granted_at timestamptz not null default now(),
  primary key (user_id, role_key)
);
create unique index user_roles_single_super_admin
  on public.user_roles (role_key) where role_key = 'super_admin';

insert into public.roles (key, description) values ('super_admin', 'المدير العام');
insert into public.permissions (key, description) values
  ('accounts.review',  'مراجعة طلبات التسجيل وإدارة حالة الحسابات'),
  ('documents.view',   'عرض مستندات الهوية'),
  ('documents.retain', 'إدارة الاحتفاظ بالمستندات'),
  ('audit.view',       'عرض سجل التدقيق');
insert into public.role_permissions (role_key, permission_key)
  select 'super_admin', key from public.permissions;

-- حساب العميل أو الشركة. لا يُطلب من المستخدم أي اسم أو تاريخ ميلاد عند التسجيل.
create table public.profiles (
  id                uuid primary key references auth.users (id) on delete restrict,
  account_type      public.account_type   not null,
  status            public.account_status not null default 'pending',
  phone             text not null,
  email             text not null,
  -- يسجله المدير من الهوية عند الموافقة (يُطبع لاحقاً على بطاقة العضوية)
  verified_name     text,
  age_verified      boolean not null default false,
  locale            text not null default 'ar',
  terms_version     text not null,
  terms_accepted_at timestamptz not null default now(),
  status_reason     text,
  reviewed_by       uuid references auth.users (id),
  reviewed_at       timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint profiles_phone_unique unique (phone),
  constraint profiles_email_unique unique (email),
  constraint profiles_phone_format check (phone ~ '^\+9647[0-9]{9}$'),
  constraint profiles_email_lower  check (email = lower(email) and length(email) between 5 and 254),
  constraint profiles_locale       check (locale in ('ar', 'en', 'ckb')),
  constraint profiles_reason_required check (
    status not in ('rejected', 'suspended', 'banned')
    or coalesce(length(btrim(status_reason)), 0) >= 5
  ),
  constraint profiles_approval_complete check (
    status <> 'approved'
    or (coalesce(length(btrim(verified_name)), 0) >= 3 and age_verified
        and reviewed_by is not null and reviewed_at is not null)
  )
);
create index profiles_status_created_idx on public.profiles (status, created_at desc);

create table public.identity_documents (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid not null references public.profiles (id) on delete restrict,
  doc_type     public.document_type not null,
  storage_path text not null unique,
  sha256       text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  mime_type    text not null check (mime_type = 'image/jpeg'),
  size_bytes   integer not null check (size_bytes between 1 and 2097152),
  width        integer not null check (width > 0),
  height       integer not null check (height > 0),
  uploaded_at  timestamptz not null default now(),
  purge_after  timestamptz,
  legal_hold   boolean not null default false,
  purged_at    timestamptz,
  constraint identity_documents_one_per_type unique (profile_id, doc_type)
);
create index identity_documents_sha_idx   on public.identity_documents (sha256);
create index identity_documents_purge_idx on public.identity_documents (purge_after)
  where purged_at is null and not legal_hold;

create table public.account_status_history (
  id          bigint generated always as identity primary key,
  profile_id  uuid not null references public.profiles (id) on delete restrict,
  from_status public.account_status,
  to_status   public.account_status not null,
  reason      text,
  actor_id    uuid,
  created_at  timestamptz not null default now()
);
create index account_status_history_profile_idx on public.account_status_history (profile_id, id);

create table public.audit_logs (
  id          bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_id    uuid,
  action      text not null,
  entity_type text not null,
  entity_id   uuid,
  details     jsonb not null default '{}'::jsonb,
  ip          text,
  user_agent  text
);
create index audit_logs_time_idx   on public.audit_logs (occurred_at desc);
create index audit_logs_entity_idx on public.audit_logs (entity_type, entity_id);

create table public.security_events (
  id          bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  kind        text not null,
  severity    text not null check (severity in ('info', 'warning', 'critical')),
  profile_id  uuid references public.profiles (id),
  details     jsonb not null default '{}'::jsonb
);
create index security_events_profile_idx on public.security_events (profile_id);

create table public.settings (
  key        text primary key,
  value      jsonb not null,
  is_public  boolean not null default false,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
insert into public.settings (key, value, is_public) values
  ('support.whatsapp',                     '"+9647826849259"', true),
  ('legal.terms_version',                  '"2026-11-draft"',  true),
  ('retention.rejected_documents_days',    '30',               false),
  -- null = تبقى مستندات الحساب المقبول ما دام الحساب قائماً
  ('retention.approved_documents_days',    'null',             false);

create table public.rate_limits (
  bucket       text not null,
  window_start timestamptz not null,
  hits         integer not null default 1,
  primary key (bucket, window_start)
);

-- السجلات التاريخية لا تُعدَّل ولا تُحذف
create function public.forbid_mutation() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'append_only: % cannot be modified', tg_table_name using errcode = '42501';
end $$;

create trigger audit_logs_append_only before update or delete on public.audit_logs
  for each row execute function public.forbid_mutation();
create trigger audit_logs_no_truncate before truncate on public.audit_logs
  for each statement execute function public.forbid_mutation();
create trigger status_history_append_only before update or delete on public.account_status_history
  for each row execute function public.forbid_mutation();
create trigger status_history_no_truncate before truncate on public.account_status_history
  for each statement execute function public.forbid_mutation();

create function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ===== 20261126000002_functions.sql =====
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

-- ===== 20261126000003_security.sql =====
-- Supabase يمنح صلاحيات واسعة افتراضياً؛ نسحبها كلها ثم نمنح المطلوب فقط.
revoke all on all tables    in schema public from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

-- حتى مفتاح الخادم لا يعدّل السجلات أو الحسابات مباشرة
revoke insert, update, delete, truncate on all tables in schema public from service_role;

alter table public.roles                  enable row level security;
alter table public.permissions            enable row level security;
alter table public.role_permissions       enable row level security;
alter table public.user_roles             enable row level security;
alter table public.profiles               enable row level security;
alter table public.identity_documents     enable row level security;
alter table public.account_status_history enable row level security;
alter table public.audit_logs             enable row level security;
alter table public.security_events        enable row level security;
alter table public.settings               enable row level security;
alter table public.rate_limits            enable row level security;

grant select on public.roles, public.permissions, public.role_permissions, public.user_roles,
  public.profiles, public.identity_documents, public.account_status_history,
  public.audit_logs, public.security_events, public.settings to authenticated;

create policy roles_admin       on public.roles            for select to authenticated using ((select public.is_super_admin()));
create policy permissions_admin on public.permissions      for select to authenticated using ((select public.is_super_admin()));
create policy role_perm_admin   on public.role_permissions for select to authenticated using ((select public.is_super_admin()));
create policy user_roles_own    on public.user_roles       for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_super_admin()));
create policy profiles_own_or_admin on public.profiles     for select to authenticated
  using (id = (select auth.uid()) or (select public.is_super_admin()));
-- حتى صاحب المستند لا يصل إليه: المدير العام فقط
create policy documents_admin   on public.identity_documents     for select to authenticated using ((select public.is_super_admin()));
create policy history_admin     on public.account_status_history for select to authenticated using ((select public.is_super_admin()));
create policy audit_admin       on public.audit_logs             for select to authenticated using ((select public.is_super_admin()));
create policy events_admin      on public.security_events        for select to authenticated using ((select public.is_super_admin()));
create policy settings_admin    on public.settings               for select to authenticated using ((select public.is_super_admin()));

grant execute on function public.get_public_settings() to anon, authenticated, service_role;
grant execute on function public.is_super_admin()      to authenticated;
grant execute on function public.review_registration(uuid, text, text, text, boolean, boolean) to authenticated;
grant execute on function public.set_account_status(uuid, public.account_status, text)         to authenticated;
grant execute on function public.log_document_view(uuid, text, text)                           to authenticated;

revoke execute on all functions in schema public from service_role;
grant execute on function public.get_public_settings() to service_role;
grant execute on function public.register_account(uuid, public.account_type, text, text, text, jsonb, text, text) to service_role;
grant execute on function public.documents_due_for_purge(integer)      to service_role;
grant execute on function public.mark_document_purged(uuid)            to service_role;
grant execute on function public.orphaned_registrations()              to service_role;
grant execute on function public.check_rate_limit(text, integer, integer) to service_role;
grant execute on function public.bootstrap_super_admin(uuid)           to service_role;

-- ===== 20261126000004_storage.sql =====
-- تخزين خاص: لا رابط عام ولا أي سياسة وصول للمستخدمين. القراءة عبر الخادم فقط بعد التسجيل في سجل التدقيق.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('identity-documents', 'identity-documents', false, 2097152, array['image/jpeg'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- سياسة مانعة: تبقى سارية حتى لو أُضيفت لاحقاً سياسة سماح عامة بالخطأ
create policy identity_documents_server_only on storage.objects
  as restrictive for all to anon, authenticated
  using (bucket_id <> 'identity-documents')
  with check (bucket_id <> 'identity-documents');

-- ===== 20261126000005_ledger.sql =====
-- دفتر القيد المزدوج: أساس النظام المالي كله. تستخدمه العمولات الآن، والبطاقات والشحن والمهام لاحقاً.
create type public.entry_direction as enum ('debit', 'credit');

create table public.ledger_accounts (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,
  kind       text not null check (kind in ('asset', 'liability', 'revenue', 'expense')),
  owner_type text,
  owner_id   uuid,
  created_at timestamptz not null default now()
);

create table public.ledger_transactions (
  id             uuid primary key default gen_random_uuid(),
  number         bigint generated always as identity unique,
  type           text not null,
  amount_iqd     bigint not null check (amount_iqd > 0),
  owner_type     text not null,
  owner_id       uuid not null,
  actor_id       uuid not null,
  reason         text not null check (length(btrim(reason)) >= 3),
  status         text not null default 'posted' check (status = 'posted'),
  reference_type text not null,
  reference_id   uuid not null,
  -- لا يمكن عكس العملية نفسها مرتين
  reverses_id    uuid unique references public.ledger_transactions (id),
  idempotency_key text not null unique,
  created_at     timestamptz not null default now()
);
create index ledger_transactions_owner_idx on public.ledger_transactions (owner_type, owner_id, created_at);

create table public.ledger_entries (
  id             bigint generated always as identity primary key,
  transaction_id uuid not null references public.ledger_transactions (id),
  account_id     uuid not null references public.ledger_accounts (id),
  direction      public.entry_direction not null,
  amount_iqd     bigint not null check (amount_iqd > 0)
);
create index ledger_entries_tx_idx on public.ledger_entries (transaction_id);
create index ledger_entries_account_idx on public.ledger_entries (account_id);

create function public.assert_ledger_balanced() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_tx uuid;
  v_debit bigint;
  v_credit bigint;
  v_amount bigint;
begin
  if tg_table_name = 'ledger_entries' then v_tx := new.transaction_id; else v_tx := new.id; end if;
  select amount_iqd into v_amount from public.ledger_transactions where id = v_tx;
  select coalesce(sum(amount_iqd) filter (where direction = 'debit'), 0),
         coalesce(sum(amount_iqd) filter (where direction = 'credit'), 0)
    into v_debit, v_credit from public.ledger_entries where transaction_id = v_tx;
  if v_debit <> v_credit or v_debit <> v_amount then
    raise exception 'unbalanced_transaction' using errcode = '23514';
  end if;
  return null;
end $$;
create constraint trigger ledger_entries_balanced after insert on public.ledger_entries
  deferrable initially deferred for each row execute function public.assert_ledger_balanced();
create constraint trigger ledger_transactions_balanced after insert on public.ledger_transactions
  deferrable initially deferred for each row execute function public.assert_ledger_balanced();

create trigger ledger_transactions_append_only before update or delete on public.ledger_transactions
  for each row execute function public.forbid_mutation();
create trigger ledger_entries_append_only before update or delete on public.ledger_entries
  for each row execute function public.forbid_mutation();
create trigger ledger_transactions_no_truncate before truncate on public.ledger_transactions
  for each statement execute function public.forbid_mutation();
create trigger ledger_entries_no_truncate before truncate on public.ledger_entries
  for each statement execute function public.forbid_mutation();

create function public.ledger_account(p_code text, p_kind text, p_owner_type text default null, p_owner_id uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  insert into public.ledger_accounts (code, kind, owner_type, owner_id)
  values (p_code, p_kind, p_owner_type, p_owner_id) on conflict (code) do nothing;
  select id into v_id from public.ledger_accounts where code = p_code;
  return v_id;
end $$;

-- داخلية فقط: لا تُمنح لأي مستخدم ولا لمفتاح الخادم
create function public.ledger_post(
  p_type text, p_amount bigint, p_owner_type text, p_owner_id uuid, p_actor uuid, p_reason text,
  p_reference_type text, p_reference_id uuid, p_debit uuid, p_credit uuid, p_key text, p_reverses uuid default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  insert into public.ledger_transactions
    (type, amount_iqd, owner_type, owner_id, actor_id, reason, reference_type, reference_id, idempotency_key, reverses_id)
  values (p_type, p_amount, p_owner_type, p_owner_id, p_actor, p_reason, p_reference_type, p_reference_id, p_key, p_reverses)
  returning id into v_id;
  insert into public.ledger_entries (transaction_id, account_id, direction, amount_iqd)
  values (v_id, p_debit, 'debit', p_amount), (v_id, p_credit, 'credit', p_amount);
  return v_id;
end $$;

-- قيد عكسي موثق بدل تعديل القيد الأصلي
create function public.ledger_reverse(p_original uuid, p_actor uuid, p_reason text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare o public.ledger_transactions%rowtype; v_debit uuid; v_credit uuid;
begin
  select * into o from public.ledger_transactions where id = p_original;
  if not found or o.reverses_id is not null then
    raise exception 'not_reversible' using errcode = '55000';
  end if;
  select account_id into v_debit  from public.ledger_entries where transaction_id = o.id and direction = 'credit';
  select account_id into v_credit from public.ledger_entries where transaction_id = o.id and direction = 'debit';
  return public.ledger_post(o.type || '.reversal', o.amount_iqd, o.owner_type, o.owner_id, p_actor, p_reason,
    o.reference_type, o.reference_id, v_debit, v_credit, 'reversal:' || o.id, o.id);
end $$;

alter table public.ledger_accounts     enable row level security;
alter table public.ledger_transactions enable row level security;
alter table public.ledger_entries      enable row level security;
revoke all on public.ledger_accounts, public.ledger_transactions, public.ledger_entries from anon, authenticated;
revoke insert, update, delete, truncate on public.ledger_accounts, public.ledger_transactions, public.ledger_entries from service_role;
grant select on public.ledger_accounts, public.ledger_transactions, public.ledger_entries to authenticated;
create policy ledger_accounts_admin on public.ledger_accounts     for select to authenticated using ((select public.is_super_admin()));
create policy ledger_tx_admin       on public.ledger_transactions for select to authenticated using ((select public.is_super_admin()));
create policy ledger_entries_admin  on public.ledger_entries      for select to authenticated using ((select public.is_super_admin()));
revoke execute on function public.assert_ledger_balanced(), public.ledger_account(text, text, text, uuid),
  public.ledger_post(text, bigint, text, uuid, uuid, text, text, uuid, uuid, uuid, text, uuid),
  public.ledger_reverse(uuid, uuid, text) from public, anon, authenticated, service_role;

-- ===== 20261126000006_referrals.sql =====
-- المسوّقون والإحالات والعمولات. المدير العام هو المتحكم الوحيد.
create type public.marketer_status   as enum ('active', 'suspended');
create type public.referral_status   as enum ('pending_verification', 'needs_review', 'approved', 'rejected');
create type public.referral_source   as enum ('registration_code', 'admin_manual', 'admin_exception');
create type public.confirmation      as enum ('confirmed', 'denied', 'unreachable');
create type public.milestone_type    as enum ('card_purchased', 'first_task_accepted', 'balance_topup', 'first_campaign_started');
create type public.commission_status as enum ('pending_review', 'approved', 'rejected', 'paid', 'reversed');
create type public.payout_status     as enum ('pending', 'paid', 'rejected', 'reversed');

create table public.marketers (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(btrim(name)) between 3 and 120),
  phone      text not null unique check (phone ~ '^\+9647[0-9]{9}$'),
  email      text not null unique check (email = lower(email) and email like '%_@_%._%'),
  code       text not null unique check (code ~ '^[A-Z0-9][A-Z0-9-]{2,19}$'),
  status     public.marketer_status not null default 'active',
  created_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger marketers_touch before update on public.marketers
  for each row execute function public.touch_updated_at();

create table public.referrals (
  id               uuid primary key default gen_random_uuid(),
  -- مصدر واحد لكل حساب إلى الأبد
  profile_id       uuid not null unique references public.profiles (id),
  marketer_id      uuid not null references public.marketers (id),
  account_type     public.account_type not null,
  code_used        text not null,
  source           public.referral_source not null,
  starts_at        timestamptz not null,
  ends_at          timestamptz not null,
  linked_at        timestamptz not null default now(),
  link_reason      text,
  exception_reason text,
  linked_by        uuid not null,
  status           public.referral_status not null default 'pending_verification',
  review_flags     text[] not null default '{}',
  decision_reason  text,
  decided_by       uuid,
  decided_at       timestamptz,
  check (ends_at > starts_at),
  check (source <> 'admin_exception' or coalesce(length(btrim(exception_reason)), 0) >= 5),
  check (status not in ('approved', 'rejected') or (decision_reason is not null and decided_by is not null))
);
create index referrals_marketer_idx on public.referrals (marketer_id, status, linked_at desc);

create table public.referral_verifications (
  id               bigint generated always as identity primary key,
  referral_id      uuid not null references public.referrals (id),
  first_contact_at timestamptz not null,
  confirmation     public.confirmation not null,
  channel          text not null check (length(btrim(channel)) >= 3),
  notes            text not null check (length(btrim(notes)) >= 5),
  recorded_by      uuid not null,
  recorded_at      timestamptz not null default now()
);
create index referral_verifications_idx on public.referral_verifications (referral_id, id desc);

create table public.referral_evidence (
  id           uuid primary key default gen_random_uuid(),
  referral_id  uuid not null references public.referrals (id),
  storage_path text not null unique,
  sha256       text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  uploaded_by  uuid not null,
  uploaded_at  timestamptz not null default now(),
  unique (referral_id, sha256)
);
create index referral_evidence_sha_idx on public.referral_evidence (sha256);

-- أحداث النشاط المثبتة. لا تُدخل يدوياً: تسجلها دوال البطاقات والمالية والمهام فقط (المرحلتان 6 و7).
create table public.referral_milestones (
  id                 uuid primary key default gen_random_uuid(),
  profile_id         uuid not null references public.profiles (id),
  milestone          public.milestone_type not null,
  source_type        text not null,
  source_id          uuid not null,
  amount_iqd         bigint check (amount_iqd >= 0),
  platform_share_iqd bigint check (platform_share_iqd >= 0 and platform_share_iqd <= amount_iqd),
  recorded_at        timestamptz not null default now(),
  unique (profile_id, milestone),          -- الأول فقط: لا تتكرر العمولة عند التجديد
  unique (source_type, source_id),         -- لا تُحتسب العملية مرتين
  check (milestone <> 'card_purchased' or amount_iqd > 0),
  check (milestone <> 'balance_topup' or (amount_iqd > 0 and platform_share_iqd is not null))
);

create table public.commissions (
  id             uuid primary key default gen_random_uuid(),
  marketer_id    uuid not null references public.marketers (id),
  referral_id    uuid not null unique references public.referrals (id),
  profile_id     uuid not null unique references public.profiles (id),
  account_type   public.account_type not null,
  pair_id        uuid,
  base_iqd       bigint not null check (base_iqd > 0),
  rate_bps       integer not null check (rate_bps between 1 and 5000),
  amount_iqd     bigint not null check (amount_iqd > 0),
  basis          jsonb not null,
  status         public.commission_status not null default 'pending_review',
  decision_reason text,
  decided_by     uuid,
  decided_at     timestamptz,
  ledger_tx_id   uuid references public.ledger_transactions (id),
  created_at     timestamptz not null default now()
);
create index commissions_marketer_idx on public.commissions (marketer_id, status);

create table public.marketer_payouts (
  id             uuid primary key default gen_random_uuid(),
  marketer_id    uuid not null references public.marketers (id),
  amount_iqd     bigint not null check (amount_iqd > 0),
  status         public.payout_status not null default 'pending',
  requested_by   uuid not null,
  requested_at   timestamptz not null default now(),
  paid_on        date,
  method         text,
  reference      text,
  decision_reason text,
  decided_by     uuid,
  decided_at     timestamptz,
  ledger_tx_id   uuid references public.ledger_transactions (id),
  check (status not in ('paid', 'reversed') or (paid_on is not null and method is not null and reference is not null))
);
create unique index marketer_payouts_reference_unique on public.marketer_payouts (lower(method), lower(reference))
  where status in ('paid', 'reversed');

create table public.marketer_payout_items (
  payout_id     uuid not null references public.marketer_payouts (id),
  commission_id uuid not null references public.commissions (id),
  released      boolean not null default false,
  primary key (payout_id, commission_id)
);
-- العمولة لا تدخل في أكثر من طلب صرف قائم
create unique index payout_items_one_active on public.marketer_payout_items (commission_id) where not released;

insert into public.settings (key, value) values
  ('referral.validity_days',        '7'),
  ('referral.client_rate_bps',      '500'),
  ('referral.company_rate_bps',     '1000'),
  ('referral.client_basis',         '["card_fee"]'),
  ('referral.company_basis',        '["card_fee","topup_platform_share"]'),
  -- pair: عميل مقابل شركة. unlock: أول زوج يفتح الأهلية لكل إحالات المسوّق المؤهلة
  ('referral.pairing_mode',         '"pair"'),
  ('referral.min_payout_iqd',       '25000');

-- ===== حماية السجلات =====
create function public.guard_referral_update() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.profile_id, new.marketer_id, new.account_type, new.code_used, new.source, new.starts_at,
      new.ends_at, new.linked_at, new.linked_by, new.link_reason, new.exception_reason)
     is distinct from
     (old.profile_id, old.marketer_id, old.account_type, old.code_used, old.source, old.starts_at,
      old.ends_at, old.linked_at, old.linked_by, old.link_reason, old.exception_reason) then
    raise exception 'referral_source_is_immutable' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger referrals_immutable_source before update on public.referrals
  for each row execute function public.guard_referral_update();

create function public.guard_commission_update() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.marketer_id, new.referral_id, new.profile_id, new.base_iqd, new.rate_bps, new.amount_iqd, new.basis)
     is distinct from
     (old.marketer_id, old.referral_id, old.profile_id, old.base_iqd, old.rate_bps, old.amount_iqd, old.basis) then
    raise exception 'commission_amount_is_immutable' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger commissions_immutable before update on public.commissions
  for each row execute function public.guard_commission_update();

do $$
declare t text;
begin
  foreach t in array array['marketers','referrals','referral_verifications','referral_evidence',
    'referral_milestones','commissions','marketer_payouts','marketer_payout_items'] loop
    execute format('create trigger %I before delete on public.%I for each row execute function public.forbid_mutation()', t || '_no_delete', t);
    execute format('create trigger %I before truncate on public.%I for each statement execute function public.forbid_mutation()', t || '_no_truncate', t);
  end loop;
  foreach t in array array['referral_verifications','referral_evidence','referral_milestones'] loop
    execute format('create trigger %I before update on public.%I for each row execute function public.forbid_mutation()', t || '_no_update', t);
  end loop;
end $$;

-- ===== 20261126000007_referral_functions.sql =====
create function public.setting_int(p_key text) returns integer
language sql stable security definer set search_path = '' as $$
  select (value #>> '{}')::integer from public.settings where key = p_key
$$;

create function public.require_reason(p_reason text) returns text
language plpgsql immutable set search_path = '' as $$
begin
  if coalesce(length(btrim(p_reason)), 0) < 5 then
    raise exception 'reason_required' using errcode = '22023';
  end if;
  return btrim(p_reason);
end $$;

create function public.audit(p_actor uuid, p_action text, p_entity text, p_id uuid, p_details jsonb default '{}')
returns void language sql security definer set search_path = '' as $$
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, details)
  values (p_actor, p_action, p_entity, p_id, p_details)
$$;

-- ===== المسوّقون =====
create function public.admin_create_marketer(p_name text, p_phone text, p_email text, p_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.require_super_admin(); v_id uuid;
begin
  insert into public.marketers (name, phone, email, code, created_by)
  values (btrim(p_name), p_phone, lower(btrim(p_email)), upper(btrim(p_code)), v_admin)
  returning id into v_id;
  perform public.audit(v_admin, 'marketer.created', 'marketer', v_id,
    jsonb_build_object('code', upper(btrim(p_code))));
  return v_id;
end $$;

create function public.admin_update_marketer(
  p_id uuid, p_name text, p_phone text, p_email text, p_code text, p_status public.marketer_status, p_reason text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.require_super_admin(); v_old public.marketers%rowtype;
        v_reason text := public.require_reason(p_reason);
begin
  select * into v_old from public.marketers where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if upper(btrim(p_code)) <> v_old.code
     and exists (select 1 from public.referrals where marketer_id = p_id) then
    raise exception 'code_locked' using errcode = '55000';
  end if;
  update public.marketers set name = btrim(p_name), phone = p_phone, email = lower(btrim(p_email)),
    code = upper(btrim(p_code)), status = p_status where id = p_id;
  perform public.audit(v_admin, 'marketer.updated', 'marketer', p_id, jsonb_build_object(
    'reason', v_reason,
    'before', jsonb_build_object('name', v_old.name, 'phone', v_old.phone, 'email', v_old.email, 'code', v_old.code, 'status', v_old.status),
    'after', jsonb_build_object('name', btrim(p_name), 'phone', p_phone, 'email', lower(btrim(p_email)), 'code', upper(btrim(p_code)), 'status', p_status)));
end $$;

-- valid | inactive | invalid  (لا تُعاد أي بيانات عن المسوّق)
create function public.check_referral_code(p_code text) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select case when status = 'active' then 'valid' else 'inactive' end
       from public.marketers where code = upper(btrim(p_code))),
    'invalid')
$$;

-- البريد بصيغته الأساسية لكشف التكرار المتنكر
create function public.canonical_email(p_email text) returns text
language sql immutable set search_path = '' as $$
  select case when split_part(lower(p_email), '@', 2) in ('gmail.com', 'googlemail.com')
    then replace(split_part(split_part(lower(p_email), '@', 1), '+', 1), '.', '') || '@gmail.com'
    else split_part(split_part(lower(p_email), '@', 1), '+', 1) || '@' || split_part(lower(p_email), '@', 2) end
$$;

create function public.referral_flags(p_profile uuid, p_marketer uuid) returns text[]
language sql stable security definer set search_path = '' as $$
  select array_remove(array[
    case when exists (
      select 1 from public.identity_documents mine join public.identity_documents other
        on other.sha256 = mine.sha256 and other.profile_id <> mine.profile_id
      where mine.profile_id = p_profile) then 'duplicate_document' end,
    case when exists (
      select 1 from public.profiles p, public.profiles o
      where p.id = p_profile and o.id <> p.id
        and public.canonical_email(o.email) = public.canonical_email(p.email)) then 'similar_email' end,
    case when exists (
      select 1 from public.profiles p join public.marketers m on m.id = p_marketer
      where p.id = p_profile and (p.phone = m.phone
        or public.canonical_email(p.email) = public.canonical_email(m.email))) then 'matches_marketer_contact' end
  ], null)
$$;

create function public.link_referral(
  p_profile uuid, p_marketer uuid, p_source public.referral_source, p_actor uuid, p_reason text, p_exception text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_profile public.profiles%rowtype; v_m public.marketers%rowtype; v_id uuid; v_flags text[];
begin
  select * into v_profile from public.profiles where id = p_profile for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  -- قفل يمنع إيقاف المسوّق أثناء الربط
  select * into v_m from public.marketers where id = p_marketer for share;
  if not found then raise exception 'invalid_code' using errcode = 'MH001'; end if;
  if v_m.status <> 'active' then raise exception 'inactive_code' using errcode = 'MH002'; end if;
  if exists (select 1 from public.referrals where profile_id = p_profile) then
    raise exception 'referral_exists' using errcode = '23505';
  end if;
  v_flags := public.referral_flags(p_profile, p_marketer);
  insert into public.referrals (profile_id, marketer_id, account_type, code_used, source, starts_at, ends_at,
    linked_by, link_reason, exception_reason, status, review_flags)
  values (p_profile, p_marketer, v_profile.account_type, v_m.code, p_source, v_profile.created_at,
    v_profile.created_at + make_interval(days => public.setting_int('referral.validity_days')),
    p_actor, p_reason, p_exception,
    case when cardinality(v_flags) > 0 then 'needs_review'::public.referral_status else 'pending_verification' end,
    v_flags)
  returning id into v_id;
  perform public.audit(p_actor, 'referral.linked', 'referral', v_id, jsonb_build_object(
    'profile_id', p_profile, 'marketer_id', p_marketer, 'source', p_source, 'flags', v_flags,
    'reason', p_reason, 'exception_reason', p_exception));
  return v_id;
end $$;

-- التسجيل مع كود اختياري داخل معاملة واحدة: الكود الخاطئ يلغي التسجيل كله
create function public.register_account_referred(
  p_user_id uuid, p_account_type public.account_type, p_phone text, p_email text, p_locale text,
  p_documents jsonb, p_referral_code text default null, p_ip text default null, p_user_agent text default null
) returns void language plpgsql security definer set search_path = '' as $$
declare v_marketer uuid;
begin
  perform public.register_account(p_user_id, p_account_type, p_phone, p_email, p_locale, p_documents, p_ip, p_user_agent);
  if p_referral_code is not null then
    select id into v_marketer from public.marketers where code = upper(btrim(p_referral_code));
    if v_marketer is null then raise exception 'invalid_code' using errcode = 'MH001'; end if;
    perform public.link_referral(p_user_id, v_marketer, 'registration_code', p_user_id, null, null);
  end if;
end $$;

-- الربط اليدوي بأثر رجعي: المدير فقط، وبعد انتهاء المدة يلزم استثناء موثق
create function public.admin_link_referral(p_profile uuid, p_marketer uuid, p_reason text, p_exception_reason text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.require_super_admin(); v_created timestamptz; v_late boolean;
        v_reason text := public.require_reason(p_reason);
begin
  select created_at into v_created from public.profiles where id = p_profile;
  if v_created is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  v_late := now() > v_created + make_interval(days => public.setting_int('referral.validity_days'));
  if v_late and coalesce(length(btrim(p_exception_reason)), 0) < 5 then
    raise exception 'exception_required' using errcode = 'MH003';
  end if;
  return public.link_referral(p_profile, p_marketer,
    case when v_late then 'admin_exception'::public.referral_source else 'admin_manual' end,
    v_admin, v_reason, case when v_late then btrim(p_exception_reason) end);
end $$;

-- ===== التحقق المستقل =====
create function public.admin_record_verification(
  p_referral uuid, p_first_contact_at timestamptz, p_confirmation public.confirmation, p_channel text, p_notes text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.require_super_admin(); v_status public.referral_status;
begin
  select status into v_status from public.referrals where id = p_referral for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_status not in ('pending_verification', 'needs_review') then
    raise exception 'already_decided' using errcode = '55000';
  end if;
  if p_first_contact_at > now() then raise exception 'contact_in_future' using errcode = '22023'; end if;
  insert into public.referral_verifications (referral_id, first_contact_at, confirmation, channel, notes, recorded_by)
  values (p_referral, p_first_contact_at, p_confirmation, btrim(p_channel), btrim(p_notes), v_admin);
  if p_confirmation = 'denied' then
    update public.referrals set status = 'needs_review' where id = p_referral;
  end if;
  perform public.audit(v_admin, 'referral.verification_recorded', 'referral', p_referral,
    jsonb_build_object('confirmation', p_confirmation));
end $$;

create function public.admin_add_referral_evidence(p_referral uuid, p_path text, p_sha256 text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.require_super_admin(); v_status public.referral_status;
begin
  select status into v_status from public.referrals where id = p_referral for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_status not in ('pending_verification', 'needs_review') then
    raise exception 'already_decided' using errcode = '55000';
  end if;
  if not starts_with(p_path, p_referral::text || '/') or not exists (
    select 1 from storage.objects where bucket_id = 'referral-evidence' and name = p_path) then
    raise exception 'invalid_storage_path' using errcode = '22023';
  end if;
  insert into public.referral_evidence (referral_id, storage_path, sha256, uploaded_by)
  values (p_referral, p_path, p_sha256, v_admin);
  if exists (select 1 from public.referral_evidence where sha256 = p_sha256 and referral_id <> p_referral) then
    update public.referrals set status = 'needs_review',
      review_flags = array(select distinct unnest(review_flags || 'reused_evidence'::text))
      where id = p_referral;
  end if;
  perform public.audit(v_admin, 'referral.evidence_added', 'referral', p_referral, '{}');
end $$;

create function public.log_evidence_view(p_evidence uuid, p_ip text default null, p_user_agent text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.require_super_admin(); v_e public.referral_evidence%rowtype;
begin
  select * into v_e from public.referral_evidence where id = p_evidence;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, details, ip, user_agent)
  values (v_admin, 'evidence.viewed', 'referral_evidence', v_e.id,
    jsonb_build_object('referral_id', v_e.referral_id), p_ip, p_user_agent);
  return v_e.storage_path;
end $$;

-- ===== أهلية العمولة =====
-- مؤهلة = إحالة معتمدة + حساب مقبول حالياً + كل شروط النشاط لنوع الحساب
create function public.referral_is_qualified(p_referral uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.referrals r join public.profiles p on p.id = r.profile_id
    where r.id = p_referral and r.status = 'approved' and p.status = 'approved'
      and not exists (
        select 1 from unnest(case when r.account_type = 'client'
            then array['card_purchased','first_task_accepted']::public.milestone_type[]
            else array['card_purchased','balance_topup','first_campaign_started']::public.milestone_type[] end) need
        where not exists (select 1 from public.referral_milestones m
                          where m.profile_id = r.profile_id and m.milestone = need)))
$$;

create function public.create_commission(p_referral uuid, p_pair uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare r public.referrals%rowtype; v_basis jsonb; v_items jsonb; v_base bigint; v_rate integer; v_amount bigint; v_id uuid;
begin
  select * into r from public.referrals where id = p_referral;
  select value into v_basis from public.settings where key = 'referral.' || r.account_type || '_basis';
  v_rate := public.setting_int('referral.' || r.account_type || '_rate_bps');
  select coalesce(jsonb_agg(item), '[]'), coalesce(sum((item ->> 'amount_iqd')::bigint), 0) into v_items, v_base
  from (
    select jsonb_build_object('basis', b.name, 'milestone_id', m.id, 'source_type', m.source_type,
             'source_id', m.source_id,
             'amount_iqd', case when b.name = 'topup_platform_share' then m.platform_share_iqd else m.amount_iqd end) item
    from jsonb_array_elements_text(v_basis) b(name)
    join public.referral_milestones m on m.profile_id = r.profile_id and m.milestone =
      case when b.name = 'card_fee' then 'card_purchased'::public.milestone_type else 'balance_topup' end
  ) x;
  v_amount := v_base * v_rate / 10000;
  if v_amount <= 0 then return false; end if;
  insert into public.commissions (marketer_id, referral_id, profile_id, account_type, pair_id, base_iqd, rate_bps, amount_iqd, basis)
  values (r.marketer_id, r.id, r.profile_id, r.account_type, p_pair, v_base, v_rate, v_amount, v_items)
  returning id into v_id;
  perform public.audit(r.linked_by, 'commission.created', 'commission', v_id,
    jsonb_build_object('amount_iqd', v_amount, 'base_iqd', v_base, 'rate_bps', v_rate));
  return true;
end $$;

create function public.evaluate_commissions(p_marketer uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare v_mode text; v_created integer := 0; v_clients uuid[]; v_companies uuid[];
        v_new uuid; v_partner uuid; v_pair uuid; v_type public.account_type; v_other public.account_type;
begin
  -- تقييم واحد في كل لحظة لكل مسوّق: يمنع تكرار الأزواج
  perform pg_advisory_xact_lock(hashtextextended('commission:' || p_marketer::text, 0));
  if not exists (select 1 from public.marketers where id = p_marketer and status = 'active') then return 0; end if;
  select value #>> '{}' into v_mode from public.settings where key = 'referral.pairing_mode';

  select coalesce(array_agg(r.id order by r.linked_at, r.id) filter (where r.account_type = 'client'), '{}'),
         coalesce(array_agg(r.id order by r.linked_at, r.id) filter (where r.account_type = 'company'), '{}')
    into v_clients, v_companies
  from public.referrals r
  where r.marketer_id = p_marketer and public.referral_is_qualified(r.id)
    and not exists (select 1 from public.commissions c where c.referral_id = r.id);

  if v_mode = 'unlock' then
    -- يلزم وجود طرف مؤهل من كل نوع
    if (cardinality(v_clients) > 0 or exists (select 1 from public.commissions where marketer_id = p_marketer and account_type = 'client' and status in ('pending_review','approved','paid')))
       and (cardinality(v_companies) > 0 or exists (select 1 from public.commissions where marketer_id = p_marketer and account_type = 'company' and status in ('pending_review','approved','paid'))) then
      foreach v_new in array v_clients || v_companies loop
        if public.create_commission(v_new, null) then v_created := v_created + 1; end if;
      end loop;
    end if;
    return v_created;
  end if;

  -- 1) أكمل الأزواج التي رُفض أحد طرفيها
  foreach v_type in array array['client','company']::public.account_type[] loop
    v_other := case when v_type = 'client' then 'company'::public.account_type else 'client' end;
    for v_pair in
      select c.pair_id from public.commissions c
      where c.marketer_id = p_marketer and c.account_type = v_other and c.status in ('pending_review','approved')
        and c.pair_id is not null and not exists (
          select 1 from public.commissions o where o.pair_id = c.pair_id and o.account_type = v_type
            and o.status in ('pending_review','approved','paid'))
      order by c.created_at
    loop
      v_partner := case when v_type = 'client' then v_clients[1] else v_companies[1] end;
      exit when v_partner is null;
      if public.create_commission(v_partner, v_pair) then v_created := v_created + 1; end if;
      if v_type = 'client' then v_clients := v_clients[2:]; else v_companies := v_companies[2:]; end if;
    end loop;
  end loop;

  -- 2) أزواج جديدة: عميل مقابل شركة
  while cardinality(v_clients) > 0 and cardinality(v_companies) > 0 loop
    v_pair := gen_random_uuid();
    -- كتلة فرعية: إن لم ينتج أحد الطرفين مبلغاً فلا يُنشأ أي منهما
    begin
      if not public.create_commission(v_clients[1], v_pair) then
        v_clients := v_clients[2:];
        raise exception 'skip' using errcode = 'MH009';
      end if;
      if not public.create_commission(v_companies[1], v_pair) then
        v_companies := v_companies[2:];
        raise exception 'skip' using errcode = 'MH009';
      end if;
      v_created := v_created + 2;
      v_clients := v_clients[2:];
      v_companies := v_companies[2:];
    exception when sqlstate 'MH009' then null;
    end;
  end loop;
  return v_created;
end $$;

-- تستدعيها وحدات البطاقات والمالية والمهام داخل معاملاتها. غير ممنوحة لأي مفتاح خارجي.
create function public.record_referral_milestone(
  p_profile uuid, p_milestone public.milestone_type, p_source_type text, p_source_id uuid,
  p_amount bigint default null, p_platform_share bigint default null
) returns void language plpgsql security definer set search_path = '' as $$
declare v_marketer uuid;
begin
  if exists (select 1 from public.referral_milestones where profile_id = p_profile and milestone = p_milestone) then
    return; -- التجديد أو التكرار لا يُحتسب
  end if;
  insert into public.referral_milestones (profile_id, milestone, source_type, source_id, amount_iqd, platform_share_iqd)
  values (p_profile, p_milestone, p_source_type, p_source_id, p_amount, p_platform_share);
  select marketer_id into v_marketer from public.referrals where profile_id = p_profile;
  if v_marketer is not null then perform public.evaluate_commissions(v_marketer); end if;
end $$;

create function public.admin_decide_referral(p_referral uuid, p_decision text, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.require_super_admin(); r public.referrals%rowtype;
        v public.referral_verifications%rowtype; v_created timestamptz; v_reason text := public.require_reason(p_reason);
        c public.commissions%rowtype;
begin
  select * into r from public.referrals where id = p_referral;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform pg_advisory_xact_lock(hashtextextended('commission:' || r.marketer_id::text, 0));
  select * into r from public.referrals where id = p_referral for update;

  if p_decision = 'approve' then
    if r.status not in ('pending_verification', 'needs_review') then
      raise exception 'already_decided' using errcode = '55000';
    end if;
    select * into v from public.referral_verifications where referral_id = r.id order by id desc limit 1;
    if not found or v.confirmation <> 'confirmed' then
      raise exception 'confirmation_required' using errcode = 'MH004';
    end if;
    select created_at into v_created from public.profiles where id = r.profile_id;
    if v.first_contact_at > v_created then
      raise exception 'contact_after_registration' using errcode = 'MH005';
    end if;
    if not exists (select 1 from public.referral_evidence where referral_id = r.id) then
      raise exception 'evidence_required' using errcode = 'MH006';
    end if;
    update public.referrals set status = 'approved', decision_reason = v_reason, decided_by = v_admin, decided_at = now()
      where id = r.id;
  elsif p_decision = 'reject' then
    if r.status = 'rejected' then raise exception 'already_decided' using errcode = '55000'; end if;
    if exists (select 1 from public.commissions cm join public.marketer_payout_items i on i.commission_id = cm.id
               where cm.referral_id = r.id and not i.released) then
      raise exception 'has_payout' using errcode = 'MH007';
    end if;
    for c in select * from public.commissions where referral_id = r.id and status in ('pending_review', 'approved') for update loop
      if c.status = 'approved' then perform public.ledger_reverse(c.ledger_tx_id, v_admin, v_reason); end if;
      update public.commissions set status = case when c.status = 'approved' then 'reversed'::public.commission_status else 'rejected' end,
        decision_reason = v_reason, decided_by = v_admin, decided_at = now() where id = c.id;
    end loop;
    update public.referrals set status = 'rejected', decision_reason = v_reason, decided_by = v_admin, decided_at = now()
      where id = r.id;
  else
    raise exception 'invalid_decision' using errcode = '22023';
  end if;
  perform public.audit(v_admin, 'referral.' || p_decision, 'referral', r.id, jsonb_build_object('reason', v_reason));
  perform public.evaluate_commissions(r.marketer_id);
end $$;

create function public.admin_evaluate_commissions(p_marketer uuid) returns integer
language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_super_admin();
  return public.evaluate_commissions(p_marketer);
end $$;

-- شرط الطرفين يُفحص من جديد عند الاعتماد وعند الصرف
create function public.commission_has_counterpart(p_commission uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.commissions c join public.commissions o
      on o.marketer_id = c.marketer_id and o.account_type <> c.account_type
     and (c.pair_id is null or o.pair_id = c.pair_id)
    where c.id = p_commission and o.status in ('pending_review', 'approved', 'paid')
      and public.referral_is_qualified(o.referral_id))
$$;

create function public.admin_decide_commission(p_commission uuid, p_decision text, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.require_super_admin(); c public.commissions%rowtype;
        v_reason text := public.require_reason(p_reason); v_tx uuid; v_new public.commission_status;
begin
  select * into c from public.commissions where id = p_commission;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform pg_advisory_xact_lock(hashtextextended('commission:' || c.marketer_id::text, 0));
  select * into c from public.commissions where id = p_commission for update;
  v_tx := c.ledger_tx_id;

  if p_decision = 'approve' and c.status = 'pending_review' then
    if not public.referral_is_qualified(c.referral_id) or not public.commission_has_counterpart(c.id)
       or not exists (select 1 from public.marketers where id = c.marketer_id and status = 'active') then
      raise exception 'not_eligible' using errcode = 'MH008';
    end if;
    v_tx := public.ledger_post('commission.approved', c.amount_iqd, 'marketer', c.marketer_id, v_admin, v_reason,
      'commission', c.id,
      public.ledger_account('expense:referral_commissions', 'expense'),
      public.ledger_account('payable:marketer:' || c.marketer_id, 'liability', 'marketer', c.marketer_id),
      'commission:' || c.id);
    v_new := 'approved';
  elsif p_decision = 'reject' and c.status = 'pending_review' then
    v_new := 'rejected';
  elsif p_decision = 'reverse' and c.status = 'approved' then
    if exists (select 1 from public.marketer_payout_items where commission_id = c.id and not released) then
      raise exception 'has_payout' using errcode = 'MH007';
    end if;
    perform public.ledger_reverse(c.ledger_tx_id, v_admin, v_reason);
    v_new := 'reversed';
  else
    raise exception 'invalid_transition' using errcode = '55000';
  end if;
  update public.commissions set status = v_new, decision_reason = v_reason, decided_by = v_admin,
    decided_at = now(), ledger_tx_id = v_tx where id = c.id;
  perform public.audit(v_admin, 'commission.' || v_new, 'commission', c.id, jsonb_build_object('reason', v_reason));
  perform public.evaluate_commissions(c.marketer_id);
end $$;

-- ===== الصرف =====
create function public.admin_create_payout(p_marketer uuid, p_commissions uuid[]) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.require_super_admin(); v_total bigint; v_count integer; v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('commission:' || p_marketer::text, 0));
  select count(*), coalesce(sum(amount_iqd), 0) into v_count, v_total from public.commissions c
   where c.id = any(p_commissions) and c.marketer_id = p_marketer and c.status = 'approved'
     and public.referral_is_qualified(c.referral_id) and public.commission_has_counterpart(c.id)
     and not exists (select 1 from public.marketer_payout_items i where i.commission_id = c.id and not i.released);
  if v_count = 0 or v_count <> (select count(distinct x) from unnest(p_commissions) x) then
    raise exception 'not_eligible' using errcode = 'MH008';
  end if;
  if v_total < public.setting_int('referral.min_payout_iqd') then
    raise exception 'below_minimum' using errcode = 'MH010';
  end if;
  insert into public.marketer_payouts (marketer_id, amount_iqd, requested_by)
  values (p_marketer, v_total, v_admin) returning id into v_id;
  insert into public.marketer_payout_items (payout_id, commission_id)
  select v_id, x from (select distinct unnest(p_commissions) x) u;
  perform public.audit(v_admin, 'payout.requested', 'payout', v_id, jsonb_build_object('amount_iqd', v_total));
  return v_id;
end $$;

create function public.admin_decide_payout(
  p_payout uuid, p_decision text, p_amount bigint default null, p_paid_on date default null,
  p_method text default null, p_reference text default null, p_reason text default null
) returns void language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.require_super_admin(); p public.marketer_payouts%rowtype; v_tx uuid; v_reason text;
begin
  select * into p from public.marketer_payouts where id = p_payout;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform pg_advisory_xact_lock(hashtextextended('commission:' || p.marketer_id::text, 0));
  select * into p from public.marketer_payouts where id = p_payout for update;
  v_tx := p.ledger_tx_id;

  if p_decision = 'pay' and p.status = 'pending' then
    if p_amount is distinct from p.amount_iqd then raise exception 'amount_mismatch' using errcode = 'MH011'; end if;
    if p_paid_on is null or p_paid_on > (now() at time zone 'Asia/Baghdad')::date
       or coalesce(length(btrim(p_method)), 0) < 2 or coalesce(length(btrim(p_reference)), 0) < 3 then
      raise exception 'payment_details_required' using errcode = '22023';
    end if;
    if exists (select 1 from public.marketer_payout_items i join public.commissions c on c.id = i.commission_id
               where i.payout_id = p.id and (c.status <> 'approved'
                 or not public.referral_is_qualified(c.referral_id) or not public.commission_has_counterpart(c.id))) then
      raise exception 'not_eligible' using errcode = 'MH008';
    end if;
    v_tx := public.ledger_post('payout.paid', p.amount_iqd, 'marketer', p.marketer_id, v_admin,
      'دفع يدوي: ' || btrim(p_method) || ' / ' || btrim(p_reference), 'payout', p.id,
      public.ledger_account('payable:marketer:' || p.marketer_id, 'liability', 'marketer', p.marketer_id),
      public.ledger_account('asset:cash_manual', 'asset'), 'payout:' || p.id);
    update public.marketer_payouts set status = 'paid', paid_on = p_paid_on, method = btrim(p_method),
      reference = btrim(p_reference), decided_by = v_admin, decided_at = now(), ledger_tx_id = v_tx where id = p.id;
    update public.commissions set status = 'paid' where id in
      (select commission_id from public.marketer_payout_items where payout_id = p.id);
  elsif p_decision = 'reject' and p.status = 'pending' then
    v_reason := public.require_reason(p_reason);
    update public.marketer_payouts set status = 'rejected', decision_reason = v_reason, decided_by = v_admin, decided_at = now()
      where id = p.id;
    update public.marketer_payout_items set released = true where payout_id = p.id;
  elsif p_decision = 'reverse' and p.status = 'paid' then
    v_reason := public.require_reason(p_reason);
    perform public.ledger_reverse(p.ledger_tx_id, v_admin, v_reason);
    update public.marketer_payouts set status = 'reversed', decision_reason = v_reason, decided_by = v_admin, decided_at = now()
      where id = p.id;
    update public.commissions set status = 'approved' where id in
      (select commission_id from public.marketer_payout_items where payout_id = p.id);
    update public.marketer_payout_items set released = true where payout_id = p.id;
  else
    raise exception 'invalid_transition' using errcode = '55000';
  end if;
  perform public.audit(v_admin, 'payout.' || p_decision, 'payout', p.id,
    jsonb_build_object('amount_iqd', p.amount_iqd, 'reason', p_reason, 'reference', p_reference));
end $$;

create function public.admin_update_referral_settings(
  p_client_bps integer, p_company_bps integer, p_client_basis text[], p_company_basis text[],
  p_pairing_mode text, p_reason text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_admin uuid := public.require_super_admin(); v_reason text := public.require_reason(p_reason); v_before jsonb;
begin
  if p_client_bps is null or p_company_bps is null or p_client_bps < 1 or p_company_bps > 5000
     or p_company_bps <= p_client_bps then
    raise exception 'invalid_rates' using errcode = '22023';
  end if;
  if p_client_basis is distinct from array['card_fee'] then
    raise exception 'invalid_basis' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_company_basis), 0) = 0
     or not p_company_basis <@ array['card_fee','topup_gross','topup_platform_share']
     or p_company_basis @> array['topup_gross','topup_platform_share']
     or cardinality(p_company_basis) <> (select count(distinct x) from unnest(p_company_basis) x) then
    raise exception 'invalid_basis' using errcode = '22023';
  end if;
  if p_pairing_mode is null or p_pairing_mode not in ('pair', 'unlock') then
    raise exception 'invalid_pairing' using errcode = '22023';
  end if;
  select jsonb_object_agg(key, value) into v_before from public.settings where key like 'referral.%';
  update public.settings s set value = n.value, updated_by = v_admin, updated_at = now()
  from (values
    ('referral.client_rate_bps', to_jsonb(p_client_bps)), ('referral.company_rate_bps', to_jsonb(p_company_bps)),
    ('referral.client_basis', to_jsonb(p_client_basis)), ('referral.company_basis', to_jsonb(p_company_basis)),
    ('referral.pairing_mode', to_jsonb(p_pairing_mode))) n(key, value)
  where s.key = n.key;
  perform public.audit(v_admin, 'referral.settings_updated', 'settings', null, jsonb_build_object(
    'reason', v_reason, 'before', v_before,
    'after', (select jsonb_object_agg(key, value) from public.settings where key like 'referral.%')));
end $$;

-- إحصاءات ملف المسوّق، مع تصفية بتاريخ الربط ونوع الحساب
create function public.admin_marketer_stats(
  p_marketer uuid, p_from timestamptz default null, p_to timestamptz default null,
  p_type public.account_type default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  perform public.require_super_admin();
  with r as (
    select r.*, p.status as account_status from public.referrals r join public.profiles p on p.id = r.profile_id
    where r.marketer_id = p_marketer and (p_from is null or r.linked_at >= p_from)
      and (p_to is null or r.linked_at < p_to) and (p_type is null or r.account_type = p_type)
  ), c as (select c.* from public.commissions c join r on r.id = c.referral_id)
  select jsonb_build_object(
    'clients', (select count(*) from r where account_type = 'client'),
    'companies', (select count(*) from r where account_type = 'company'),
    'clients_approved', (select count(*) from r where account_type = 'client' and account_status = 'approved'),
    'companies_approved', (select count(*) from r where account_type = 'company' and account_status = 'approved'),
    'clients_first_task', (select count(*) from r join public.referral_milestones m on m.profile_id = r.profile_id and m.milestone = 'first_task_accepted' where r.account_type = 'client'),
    'companies_first_campaign', (select count(*) from r join public.referral_milestones m on m.profile_id = r.profile_id and m.milestone = 'first_campaign_started' where r.account_type = 'company'),
    'awaiting_verification', (select count(*) from r where status in ('pending_verification', 'needs_review')),
    'rejected', (select count(*) from r where status = 'rejected'),
    'commission_due_iqd', (select coalesce(sum(amount_iqd), 0) from c where status = 'approved'),
    'commission_pending_iqd', (select coalesce(sum(amount_iqd), 0) from c where status = 'pending_review'),
    'commission_approved_total_iqd', (select coalesce(sum(amount_iqd), 0) from c where status in ('approved', 'paid')),
    'commission_paid_iqd', (select coalesce(sum(amount_iqd), 0) from c where status = 'paid')
  ) into v;
  return v;
end $$;

-- ===== الصلاحيات =====
do $$
declare t text;
begin
  foreach t in array array['marketers','referrals','referral_verifications','referral_evidence',
    'referral_milestones','commissions','marketer_payouts','marketer_payout_items'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('revoke insert, update, delete, truncate on public.%I from service_role', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('create policy %I on public.%I for select to authenticated using ((select public.is_super_admin()))', t || '_admin', t);
  end loop;
end $$;

-- اسحب التنفيذ عن كل دوال هذه المرحلة ثم امنح المطلوب فقط
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in (
    'setting_int','require_reason','audit','admin_create_marketer','admin_update_marketer','check_referral_code',
    'canonical_email','referral_flags','link_referral','register_account_referred','admin_link_referral',
    'admin_record_verification','admin_add_referral_evidence','log_evidence_view','referral_is_qualified',
    'create_commission','evaluate_commissions','record_referral_milestone','admin_decide_referral',
    'admin_evaluate_commissions','commission_has_counterpart','admin_decide_commission','admin_create_payout',
    'admin_decide_payout','admin_update_referral_settings','admin_marketer_stats','guard_referral_update',
    'guard_commission_update') loop
    execute format('revoke execute on function %s from public, anon, authenticated, service_role', f);
    if f::text ~ '^(admin_|log_evidence_view)' then
      execute format('grant execute on function %s to authenticated', f);
    elsif f::text ~ '^(check_referral_code|register_account_referred)\(' then
      execute format('grant execute on function %s to service_role', f);
    end if;
  end loop;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('referral-evidence', 'referral-evidence', false, 2097152, array['image/jpeg'])
on conflict (id) do update set public = false;
create policy referral_evidence_server_only on storage.objects
  as restrictive for all to anon, authenticated
  using (bucket_id <> 'referral-evidence') with check (bucket_id <> 'referral-evidence');

commit;
