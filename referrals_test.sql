\set QUIET on
set client_min_messages = warning;
create schema t;
create table t.results (n serial, ok boolean, name text);
grant usage on schema t to anon, authenticated, service_role;
grant all on all tables in schema t to anon, authenticated, service_role;
grant all on all sequences in schema t to anon, authenticated, service_role;
create function t.ok(cond boolean, name text) returns void language sql as
  $$ insert into t.results (ok, name) values (coalesce(cond, false), name) $$;
create function t.throws(stmt text, code text, name text) returns void language plpgsql as $$
begin
  execute stmt;
  set constraints all immediate;
  insert into t.results (ok, name) values (false, name || ' (no error raised)');
exception when others then
  insert into t.results (ok, name)
  values (sqlstate = code, name || case when sqlstate = code then '' else ' got ' || sqlstate || ' ' || sqlerrm end);
end $$;
create function t.u(n int) returns uuid language sql immutable as
  $$ select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid $$;
create function t.act(n int) returns text language sql as
  $$ select set_config('request.jwt.claim.sub', case when n = 0 then '' else t.u(n)::text end, false) $$;
-- يسجل حساباً وهمياً بالطريقة التي يستخدمها الخادم
create function t.register(n int, kind public.account_type, code text, seed text default null, mail text default null)
returns void language plpgsql security definer as $$
declare v_mail text := coalesce(mail, 'u' || n || '@test.invalid');
begin
  insert into auth.users (id, email) values (t.u(n), v_mail) on conflict do nothing;
  insert into storage.objects (bucket_id, name)
    select 'identity-documents', t.u(n) || '/' || d || '.jpg' from unnest(array['national_id_front','residence_card_front']) d
    on conflict do nothing;
  perform public.register_account_referred(t.u(n), kind, '+9647' || lpad(n::text, 9, '0'), v_mail, 'ar',
    (select jsonb_agg(jsonb_build_object('doc_type', d, 'storage_path', t.u(n) || '/' || d || '.jpg',
      'sha256', encode(sha256(convert_to(coalesce(seed, n::text) || d, 'utf8')), 'hex'), 'mime_type', 'image/jpeg',
      'size_bytes', 10, 'width', 1200, 'height', 800)) from unnest(array['national_id_front','residence_card_front']) d), code);
end $$;
create function t.ref(n int) returns uuid language sql as $$ select id from public.referrals where profile_id = t.u(n) $$;
create function t.com(n int) returns uuid language sql as $$ select id from public.commissions where profile_id = t.u(n) $$;
create function t.mk(c text) returns uuid language sql as $$ select id from public.marketers where code = c $$;
-- توثيق + دليل + اعتماد (بصفة المدير)
create function t.verify(n int, evidence_seed text default null) returns void language plpgsql as $$
declare r uuid := t.ref(n); p text := r || '/e.jpg';
begin
  perform public.admin_record_verification(r, (select created_at - interval '1 day' from public.profiles where id = t.u(n)),
    'confirmed', 'اتصال من رقم الإدارة', 'أكد الحساب أن المسوّق عرّفه بالمنصة');
  perform t.put(p);
  perform public.admin_add_referral_evidence(r, p, encode(sha256(convert_to(coalesce(evidence_seed, n::text), 'utf8')), 'hex'));
  perform public.admin_decide_referral(r, 'approve', 'تم التحقق من المصدر');
end $$;
create function t.put(p text) returns void language sql security definer as
  $$ insert into storage.objects (bucket_id, name) values ('referral-evidence', p) on conflict do nothing $$;
create function t.approve_account(n int) returns void language sql as
  $$ select public.review_registration(t.u(n), 'approve', null, 'Test Person', true, true) $$;
-- أحداث النشاط (ستنتجها المرحلتان 6 و7)
create function t.client_activity(n int, fee bigint default 25000) returns void language plpgsql as $$
begin
  perform public.record_referral_milestone(t.u(n), 'card_purchased', 'subscription', gen_random_uuid(), fee);
  perform public.record_referral_milestone(t.u(n), 'first_task_accepted', 'submission', gen_random_uuid());
end $$;
create function t.company_activity(n int, fee bigint default 100000, topup bigint default 1000000) returns void language plpgsql as $$
begin
  perform public.record_referral_milestone(t.u(n), 'card_purchased', 'subscription', gen_random_uuid(), fee);
  perform public.record_referral_milestone(t.u(n), 'balance_topup', 'topup', gen_random_uuid(), topup, topup / 2);
  perform public.record_referral_milestone(t.u(n), 'first_campaign_started', 'campaign', gen_random_uuid());
end $$;
grant execute on all functions in schema t to anon, authenticated, service_role;

insert into auth.users (id, email) values (t.u(1), 'admin@test.invalid');
select public.bootstrap_super_admin(t.u(1));

-- ===== المسوّقون =====
select t.act(1);
set role authenticated;
select public.admin_create_marketer('مسوّق أول', '+9647900000001', 'M1@Test.invalid', 'mht-001');
select public.admin_create_marketer('مسوّق ثان', '+9647900000002', 'm2@test.invalid', 'MHT-002');
select public.admin_create_marketer('مسوّق موقوف', '+9647900000003', 'm3@test.invalid', 'MHT-003');
select t.throws($q$select public.admin_create_marketer('مكرر الكود', '+9647900000009', 'm9@test.invalid', 'MHT-001')$q$, '23505', 'marketer: duplicate code refused');
select t.throws($q$select public.admin_create_marketer('كود سيئ', '+9647900000008', 'm8@test.invalid', 'a b')$q$, '23514', 'marketer: malformed code refused');
select public.admin_update_marketer(t.mk('MHT-003'), 'مسوّق موقوف', '+9647900000003', 'm3@test.invalid', 'MHT-003', 'suspended', 'إيقاف للاختبار');
select t.ok((select code = 'MHT-001' and email = 'm1@test.invalid' from public.marketers where name = 'مسوّق أول'), 'marketer: admin-chosen code stored normalized');
reset role;

-- 1,2,3: التحقق من الكود
select t.act(0); set role service_role;
select t.ok(public.check_referral_code('MHT-999') = 'invalid', 'T01 unknown code rejected');
select t.ok(public.check_referral_code(' mht-001 ') = 'valid', 'T02 valid code of active marketer accepted');
select t.ok(public.check_referral_code('MHT-003') = 'inactive', 'T03 suspended marketer code rejected');
select t.throws($q$select t.register(90, 'client', 'MHT-999')$q$, 'MH001', 'T01 registration with unknown code refused');
select t.throws($q$select t.register(91, 'client', 'MHT-003')$q$, 'MH002', 'T03 registration with suspended code refused');
reset role;
select t.ok(not exists (select 1 from public.profiles where id in (t.u(90), t.u(91))) and (select count(*) = 0 from public.referrals), 'T01/T03 refused code leaves no account and no referral');
select t.register(10, 'client', 'MHT-001'), t.register(20, 'company', 'mht-001'), t.register(30, 'client', null);
select t.ok((select count(*) = 3 from public.profiles) and (select count(*) = 2 from public.referrals), 'register: with and without code');
select t.ok((select r.marketer_id = t.mk('MHT-001') and r.account_type = 'client' and r.source = 'registration_code'
  and r.status = 'pending_verification' and r.ends_at = r.starts_at + interval '7 days' from public.referrals r where r.profile_id = t.u(10)),
  'referral: marketer id, type, source, 7-day window stored');
select t.ok((select count(*) = 2 from public.audit_logs where action = 'referral.linked'), 'referral: linking audited');

-- 4, 11: لا تغيير للمصدر
select t.throws($q$select public.register_account_referred(t.u(10), 'client', '+9647000000010', 'u10@test.invalid', 'ar', '[]', 'MHT-002')$q$, '22023', 'T04 re-registering to switch code refused');
set role authenticated; select t.act(10);
select t.throws($q$update public.referrals set marketer_id = t.mk('MHT-002')$q$, '42501', 'T04/T11 account owner cannot change referral');
select t.throws($q$select public.admin_link_referral(t.u(30), t.mk('MHT-002'), 'self link attempt')$q$, '42501', 'perm: user cannot link referrals');
select t.throws($q$select public.admin_create_marketer('دخيل', '+9647900000007', 'x@test.invalid', 'HACK-1')$q$, '42501', 'perm: user cannot create codes');
select t.throws($q$select public.record_referral_milestone(t.u(10), 'card_purchased', 'x', gen_random_uuid(), 99999999)$q$, '42501', 'perm: user cannot fabricate milestones');
select t.ok((select count(*) = 0 from public.marketers) and (select count(*) = 0 from public.referrals) and (select count(*) = 0 from public.commissions), 'RLS: users see no marketer data');
reset role;
set role service_role;
select t.throws($q$select public.record_referral_milestone(t.u(10), 'card_purchased', 'x', gen_random_uuid(), 99999999)$q$, '42501', 'perm: server key cannot fabricate milestones');
select t.throws($q$update public.referrals set marketer_id = t.mk('MHT-002')$q$, '42501', 'perm: server key cannot edit referrals');
reset role;
set role anon;
select t.throws($q$select public.check_referral_code('MHT-001')$q$, '42501', 'perm: code check only through rate-limited server');
reset role;
select t.act(1); set role authenticated;
select t.throws($q$select public.admin_link_referral(t.u(10), t.mk('MHT-002'), 'try to switch marketer')$q$, '23505', 'T04/T11 even admin cannot relink an account');
select t.throws($q$select public.admin_update_marketer(t.mk('MHT-001'), 'مسوّق أول', '+9647900000001', 'm1@test.invalid', 'MHT-100', 'active', 'تغيير الكود')$q$, '55000', 'T11 code locked after first referral');
reset role;
select t.throws($q$update public.referrals set marketer_id = t.mk('MHT-002') where profile_id = t.u(10)$q$, '42501', 'T11 source immutable even for database owner');
select t.throws($q$delete from public.referrals$q$, '42501', 'referral records cannot be deleted');

-- 5..8: لا عمولة قبل اكتمال الطرفين
set role authenticated;
select t.throws($q$select public.admin_decide_referral(t.ref(10), 'approve', 'بدون تحقق')$q$, 'MH004', 'verify: code alone is not proof');
select public.admin_record_verification(t.ref(10), now() - interval '2 days', 'confirmed', 'واتساب الإدارة', 'تأكيد مستقل من العميل');
select t.throws($q$select public.admin_decide_referral(t.ref(10), 'approve', 'بدون دليل')$q$, 'MH006', 'verify: evidence required');
select public.admin_record_verification(t.ref(20), now(), 'confirmed', 'اتصال', 'تواصل بعد التسجيل');
select t.throws($q$select public.admin_decide_referral(t.ref(20), 'approve', 'تواصل لاحق')$q$, 'MH005', 'verify: contact must precede registration');
select t.approve_account(10), t.approve_account(20);
select t.verify(10), t.verify(20);
reset role;
select t.ok((select count(*) = 0 from public.commissions), 'T05/T06 approved referrals without activity: nothing due');
select t.client_activity(10);
select t.ok((select count(*) = 0 from public.commissions), 'T07 client alone completes: nothing due');
-- 8: شركة وحدها لمسوّق آخر
select t.register(21, 'company', 'MHT-002');
set role authenticated; select t.approve_account(21), t.verify(21); reset role;
select t.company_activity(21);
select t.ok((select count(*) = 0 from public.commissions), 'T08 company alone completes: nothing due (no cross-marketer pairing)');
-- شركة ناقصة شرطاً واحداً
select public.record_referral_milestone(t.u(20), 'card_purchased', 'subscription', gen_random_uuid(), 100000);
select public.record_referral_milestone(t.u(20), 'balance_topup', 'topup', gen_random_uuid(), 1000000, 500000);
select t.ok((select count(*) = 0 from public.commissions), 'pair: company missing first campaign: nothing due');
-- 9
select public.record_referral_milestone(t.u(20), 'first_campaign_started', 'campaign', gen_random_uuid());
select t.ok((select count(*) = 2 and bool_and(status = 'pending_review') and count(distinct pair_id) = 1 from public.commissions where marketer_id = t.mk('MHT-001')), 'T09 both complete for same marketer: eligibility opens');
select t.ok((select amount_iqd = 1250 and base_iqd = 25000 and rate_bps = 500 from public.commissions where profile_id = t.u(10)), 'amount: client 5% of card fee');
select t.ok((select amount_iqd = 60000 and base_iqd = 600000 from public.commissions where profile_id = t.u(20)), 'amount: company 10% of card fee + platform share');
select t.client_activity(10, 100000);
select public.evaluate_commissions(t.mk('MHT-001'));
select t.ok((select count(*) = 2 from public.commissions) and (select count(*) = 1 from public.referral_milestones where profile_id = t.u(10) and milestone = 'card_purchased'), 'once: renewal and re-evaluation add nothing');
select t.throws($q$select public.record_referral_milestone(t.u(21), 'first_task_accepted', 'topup', (select source_id from public.referral_milestones where source_type = 'topup' limit 1))$q$, '23505', 'once: same source operation cannot count twice');
select t.throws($q$update public.commissions set amount_iqd = 999999$q$, '42501', 'commission amounts immutable');

-- ===== الاعتماد والصرف =====
set role authenticated;
select t.throws($q$select public.admin_create_payout(t.mk('MHT-001'), array[t.com(20)])$q$, 'MH008', 'payout: unapproved commission refused');
select public.admin_decide_commission(t.com(10), 'approve', 'مستوفية الشروط'), public.admin_decide_commission(t.com(20), 'approve', 'مستوفية الشروط');
select t.throws($q$select public.admin_decide_commission(t.com(20), 'approve', 'مرة ثانية')$q$, '55000', 'T10 double approval refused');
select t.throws($q$select public.admin_create_payout(t.mk('MHT-001'), array[t.com(10)])$q$, 'MH010', 'payout: below 25,000 minimum refused');
select t.throws($q$select public.admin_create_payout(t.mk('MHT-002'), array[t.com(20)])$q$, 'MH008', 'payout: other marketer commission refused');
select public.admin_create_payout(t.mk('MHT-001'), array[t.com(10), t.com(20)]);
select t.throws($q$select public.admin_create_payout(t.mk('MHT-001'), array[t.com(20)])$q$, 'MH008', 'T10 second request for same commission refused');
select t.throws($q$select public.admin_decide_referral(t.ref(10), 'reject', 'إلغاء أثناء الصرف')$q$, 'MH007', 'revoke blocked while payout open');
select t.throws($q$select public.admin_decide_payout((select id from public.marketer_payouts), 'pay', 1000, current_date, 'نقداً', 'R-1')$q$, 'MH011', 'payout: amount must match');
select t.throws($q$select public.admin_decide_payout((select id from public.marketer_payouts), 'pay', 61250, current_date, 'نقداً', '')$q$, '22023', 'payout: reference required');
select public.admin_decide_payout((select id from public.marketer_payouts), 'pay', 61250, current_date - 1, 'نقداً', 'R-001');
select t.throws($q$select public.admin_decide_payout((select id from public.marketer_payouts), 'pay', 61250, current_date - 1, 'نقداً', 'R-002')$q$, '55000', 'T10 paying twice refused');
select t.throws($q$select public.admin_create_payout(t.mk('MHT-001'), array[t.com(20)])$q$, 'MH008', 'T10 paid commission cannot be requested again');
select t.ok((public.admin_marketer_stats(t.mk('MHT-001')) ->> 'commission_paid_iqd')::int = 61250
  and (public.admin_marketer_stats(t.mk('MHT-001')) ->> 'clients')::int = 1
  and (public.admin_marketer_stats(t.mk('MHT-001')) ->> 'companies_first_campaign')::int = 1, 'stats: marketer file totals');
select t.ok((public.admin_marketer_stats(t.mk('MHT-001'), null, null, 'client') ->> 'companies')::int = 0
  and (public.admin_marketer_stats(t.mk('MHT-001'), now() + interval '1 day') ->> 'clients')::int = 0, 'stats: filter by type and date');
reset role;
select t.ok((select count(*) = 0 from (select transaction_id from public.ledger_entries group by 1
  having sum(case when direction = 'debit' then amount_iqd else -amount_iqd end) <> 0) x), 'ledger: every transaction balanced');
select t.ok((select coalesce(sum(case when e.direction = 'credit' then e.amount_iqd else -e.amount_iqd end), 0) = 0
  from public.ledger_entries e join public.ledger_accounts a on a.id = e.account_id where a.code like 'payable:marketer:%'), 'ledger: payable cleared after payment');
select t.throws($q$delete from public.ledger_entries$q$, '42501', 'ledger: entries cannot be deleted');
select t.throws($q$delete from public.commissions$q$, '42501', 'commissions cannot be deleted');
select t.throws($q$select public.ledger_post('x', 5, 'marketer', t.u(1), t.u(1), 'dup key', 'payout', t.u(1),
  (select id from public.ledger_accounts limit 1), (select id from public.ledger_accounts offset 1 limit 1),
  (select idempotency_key from public.ledger_transactions limit 1))$q$, '23505', 'ledger: idempotency key blocks duplicates');
select t.throws($q$insert into public.ledger_transactions (type, amount_iqd, owner_type, owner_id, actor_id, reason, reference_type, reference_id, idempotency_key) values ('x', 5, 'marketer', t.u(1), t.u(1), 'no entries', 'x', t.u(1), 'lonely')$q$, '23514', 'ledger: unbalanced transaction refused');
-- التصحيح بقيد عكسي
set role authenticated;
select public.admin_decide_payout((select id from public.marketer_payouts), 'reverse', null, null, null, null, 'التحويل لم يصل');
reset role;
select t.ok((select count(*) = 1 from public.ledger_transactions where type = 'payout.paid.reversal' and reverses_id is not null)
  and (select count(*) = 1 from public.ledger_transactions where type = 'payout.paid')
  and (select bool_and(status = 'approved') from public.commissions where marketer_id = t.mk('MHT-001')), 'correction: reversal entry, original kept');
set role authenticated;
select public.admin_decide_referral(t.ref(10), 'reject', 'ثبت أن المصدر غير صحيح');
select t.ok((select status = 'reversed' from public.commissions where profile_id = t.u(10)), 'revoke: approved commission reversed');
select t.throws($q$select public.admin_create_payout(t.mk('MHT-001'), array[t.com(20)])$q$, 'MH008', 'pair: company commission frozen without qualified client');
reset role;
-- عميل بديل مؤهل يكمل الزوج
select t.register(11, 'client', 'MHT-001');
set role authenticated; select t.approve_account(11), t.verify(11); reset role;
select t.client_activity(11);
select t.ok((select c.pair_id = (select pair_id from public.commissions where profile_id = t.u(20)) from public.commissions c where c.profile_id = t.u(11)), 'pair: new qualified client completes the pair');
-- عميل ثان بلا شركة مقابلة
select t.register(12, 'client', 'MHT-001');
set role authenticated; select t.approve_account(12), t.verify(12); reset role;
select t.client_activity(12);
select t.ok(not exists (select 1 from public.commissions where profile_id = t.u(12)), 'pair mode: extra client waits for another company');
-- تجميد الحساب يمنع الصرف
set role authenticated;
select public.set_account_status(t.u(20), 'suspended', 'مراجعة الحساب');
select t.throws($q$select public.admin_create_payout(t.mk('MHT-001'), array[t.com(20)])$q$, 'MH008', 'payout: suspended account blocks payment');
select public.set_account_status(t.u(20), 'approved', 'انتهت المراجعة');
-- وضع الفتح
select public.admin_update_referral_settings(500, 1000, array['card_fee'], array['card_fee','topup_gross'], 'unlock', 'تغيير للاختبار');
select public.admin_evaluate_commissions(t.mk('MHT-001'));
select t.ok(exists (select 1 from public.commissions where profile_id = t.u(12)), 'unlock mode: extra client becomes eligible');
select t.ok((select amount_iqd = 60000 from public.commissions where profile_id = t.u(20)), 'settings: old commissions keep their snapshot');
select t.throws($q$select public.admin_update_referral_settings(1000, 500, array['card_fee'], array['card_fee'], 'pair', 'عكس النسب')$q$, '22023', 'settings: company rate must exceed client rate');
select t.throws($q$select public.admin_update_referral_settings(500, 1000, array['card_fee'], array['topup_gross','topup_platform_share'], 'pair', 'ازدواج')$q$, '22023', 'settings: same money cannot be counted twice');
reset role;

-- 12: الأثر الرجعي
select t.register(40, 'client', null), t.register(41, 'client', null);
update public.profiles set created_at = now() - interval '8 days' where id = t.u(40);
set role authenticated;
select t.throws($q$select public.admin_link_referral(t.u(40), t.mk('MHT-002'), 'نسي إدخال الكود')$q$, 'MH003', 'T12 late retroactive referral refused');
select public.admin_link_referral(t.u(40), t.mk('MHT-002'), 'نسي إدخال الكود', 'استثناء موثق من المدير العام');
select public.admin_link_referral(t.u(41), t.mk('MHT-002'), 'نسي إدخال الكود');
select t.ok((select source = 'admin_exception' and exception_reason is not null and linked_by = t.u(1) from public.referrals where profile_id = t.u(40)), 'T12 exception documented');
select t.ok((select source = 'admin_manual' from public.referrals where profile_id = t.u(41)), 'T12 admin may link within the window');
select t.throws($q$select public.admin_link_referral(t.u(30), t.mk('MHT-003'), 'ربط بمسوّق موقوف')$q$, 'MH002', 'T03 admin cannot link to suspended marketer');
reset role;

-- ===== الاشتباه =====
select t.register(50, 'client', 'MHT-002', '10');
select t.ok((select status = 'needs_review' and 'duplicate_document' = any(review_flags) from public.referrals where profile_id = t.u(50)), 'fraud: reused ID image -> needs review, not auto rejected');
select t.register(51, 'client', 'MHT-002', null, 'm2+x@test.invalid');
select t.ok((select 'matches_marketer_contact' = any(review_flags) from public.referrals where profile_id = t.u(51)), 'fraud: self-referral flagged');
set role authenticated;
select t.approve_account(41), t.verify(41, '10');
select t.ok((select 'reused_evidence' = any(review_flags) from public.referrals where profile_id = t.u(41)), 'fraud: reused evidence flagged');
select t.ok(public.log_evidence_view((select id from public.referral_evidence limit 1)) is not null, 'evidence: admin view returns path');
select t.ok(exists (select 1 from public.audit_logs where action = 'evidence.viewed'), 'audit: evidence view logged');
select t.ok((select count(*) = 0 from storage.objects), 'storage: no direct access to evidence');
reset role;
select t.ok((select bool_and(relrowsecurity) from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r'), 'RLS enabled on every public table');
