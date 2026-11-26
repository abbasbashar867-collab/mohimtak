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
