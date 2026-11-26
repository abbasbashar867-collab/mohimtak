-- اختبارات قاعدة البيانات: كل سطر ينتج PASS أو FAIL
\set QUIET on
set client_min_messages = warning;
create schema t;
create table t.results (n serial, ok boolean, name text);
grant usage on schema t to anon, authenticated, service_role;
grant all on all tables in schema t to anon, authenticated, service_role;
grant all on all sequences in schema t to anon, authenticated, service_role;

create function t.ok(cond boolean, name text) returns void language sql as
  $$ insert into t.results (ok, name) values (coalesce(cond, false), name) $$;
-- يتوقع فشل العبارة برمز خطأ محدد
create function t.throws(stmt text, code text, name text) returns void language plpgsql as $$
begin
  execute stmt;
  insert into t.results (ok, name) values (false, name || ' (no error raised)');
exception when others then
  insert into t.results (ok, name)
  values (sqlstate = code, name || case when sqlstate = code then '' else ' got ' || sqlstate || ' ' || sqlerrm end);
end $$;

-- حسابات وهمية: 1=مدير، 2=عميل، 3=شركة، 4=سيرفض، 5=دخيل
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-000000000001', 'admin@test.invalid'),
 ('00000000-0000-0000-0000-000000000002', 'client@test.invalid'),
 ('00000000-0000-0000-0000-000000000003', 'company@test.invalid'),
 ('00000000-0000-0000-0000-000000000004', 'reject@test.invalid'),
 ('00000000-0000-0000-0000-000000000005', 'other@test.invalid');

create function t.upload(u int) returns void language sql as $$
  insert into storage.objects (bucket_id, name)
  select 'identity-documents', format('00000000-0000-0000-0000-00000000000%s/%s.jpg', u, d)
  from unnest(array['national_id_front','residence_card_front']) d
$$;
create function t.docs(u int, seed text) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object(
    'doc_type', d, 'storage_path', format('00000000-0000-0000-0000-00000000000%s/%s.jpg', u, d),
    'sha256', encode(sha256(convert_to(seed || d, 'utf8')), 'hex'),
    'mime_type', 'image/jpeg', 'size_bytes', 1000, 'width', 1200, 'height', 800))
  from unnest(array['national_id_front','residence_card_front']) d
$$;
create function t.reg(u int, kind text, phone text, email text, docs jsonb) returns text language sql as $$
  select format('select public.register_account(%L, %L, %L, %L, %L, %L::jsonb)',
    '00000000-0000-0000-0000-00000000000' || u, kind, phone, email, 'ar', docs)
$$;
create function t.act(u int) returns text language sql as
  $$ select set_config('request.jwt.claim.sub', case when u = 0 then '' else '00000000-0000-0000-0000-00000000000' || u end, false) $$;
grant execute on all functions in schema t to anon, authenticated, service_role;

select t.upload(2), t.upload(3), t.upload(4);

-- ===== المدير العام =====
set role service_role;
select public.bootstrap_super_admin('00000000-0000-0000-0000-000000000001');
select t.throws($q$select public.bootstrap_super_admin('00000000-0000-0000-0000-000000000005')$q$, '55000', 'bootstrap: second super admin refused');

-- ===== التسجيل =====
select t.throws(t.reg(2,'client','07701111111','client@test.invalid', t.docs(2,'a')), '23514', 'register: unnormalized phone refused');
select t.throws(t.reg(2,'client','+9647701111111','wrong@test.invalid', t.docs(2,'a')), '22023', 'register: email must match auth user');
select t.throws(t.reg(2,'client','+9647701111111','client@test.invalid', t.docs(2,'a') - 1), '22023', 'register: one document refused');
select t.throws(t.reg(2,'client','+9647701111111','client@test.invalid', jsonb_build_array(t.docs(2,'a')->0, t.docs(2,'a')->0)), '22023', 'register: same doc type twice refused');
select t.throws(t.reg(2,'client','+9647701111111','client@test.invalid', t.docs(3,'a')), '22023', 'register: another user folder refused');
select t.throws(t.reg(5,'client','+9647705555555','other@test.invalid', t.docs(5,'z')), '22023', 'register: documents not uploaded refused');
select t.throws(t.reg(1,'client','+9647709999999','admin@test.invalid', t.docs(1,'q')), '42501', 'register: admin cannot become client');
select t.ok((select count(*) = 0 from public.profiles), 'register: failed attempts leave no partial rows');

select public.register_account('00000000-0000-0000-0000-000000000002','client','+9647701111111','client@test.invalid','ar', t.docs(2,'a'));
select t.throws(t.reg(3,'company','+9647701111111','company@test.invalid', t.docs(3,'b')), '23505', 'register: duplicate phone refused');
-- الشركة بنفس النموذج تماماً، وتعيد استخدام صورتي العميل لاختبار التنبيه
select public.register_account('00000000-0000-0000-0000-000000000003','company','+9647702222222','company@test.invalid','en',
  (select jsonb_agg(d || jsonb_build_object('storage_path', replace(d->>'storage_path','000000000002/','000000000003/'))) from jsonb_array_elements(t.docs(2,'a')) d));
select public.register_account('00000000-0000-0000-0000-000000000004','client','+9647704444444','reject@test.invalid','ckb', t.docs(4,'d'));
select t.throws(t.reg(2,'client','+9647708888888','client@test.invalid', t.docs(2,'e')), '23505', 'register: same user twice refused');
reset role;
select t.ok((select bool_and(status = 'pending') and count(*) = 3 from public.profiles), 'register: all accounts start pending');
select t.ok((select count(*) = 6 from public.identity_documents), 'register: two documents per account');
select t.ok((select count(*) = 2 from public.security_events where kind = 'duplicate_identity_document'), 'fraud: reused document flagged');
select t.ok((select status = 'pending' from public.profiles where account_type = 'company'), 'fraud: flagged account not auto-banned');

-- ===== زائر غير مسجل =====
set role anon; select t.act(0);
select t.throws('select * from public.profiles', '42501', 'anon: cannot read profiles');
select t.throws('select * from public.identity_documents', '42501', 'anon: cannot read documents');
select t.ok((select count(*) = 0 from storage.objects), 'anon: cannot see storage objects');
select t.ok(public.get_public_settings() ->> 'support.whatsapp' = '+9647816849259', 'anon: public settings only');
select t.ok(not public.get_public_settings() ? 'retention.rejected_documents_days', 'anon: private settings hidden');
select t.throws(t.reg(5,'client','+9647705555555','other@test.invalid','[]'), '42501', 'anon: cannot call register_account');
reset role;

-- ===== عميل (قيد المراجعة) يحاول التلاعب =====
set role authenticated; select t.act(2);
select t.ok((select count(*) = 1 from public.profiles), 'client: sees only own profile');
select t.ok((select count(*) = 0 from public.identity_documents), 'client: cannot see documents, even own');
select t.ok((select count(*) = 0 from public.audit_logs), 'client: cannot read audit log');
select t.ok((select count(*) = 0 from public.settings), 'client: cannot read settings table');
select t.throws($q$update public.profiles set status = 'approved'$q$, '42501', 'client: cannot self-approve');
select t.throws($q$insert into public.user_roles values (auth.uid(), 'super_admin')$q$, '42501', 'client: cannot grant self admin');
select t.throws($q$select public.review_registration(auth.uid(), 'approve', null, 'Fake Name', true, true)$q$, '42501', 'client: cannot call review');
select t.throws($q$select public.set_account_status(auth.uid(), 'approved', 'please approve')$q$, '42501', 'client: cannot change status');
select t.throws($q$select public.log_document_view(gen_random_uuid())$q$, '42501', 'client: cannot fetch document path');
select t.throws($q$select public.bootstrap_super_admin(auth.uid())$q$, '42501', 'client: cannot bootstrap admin');
select t.throws($q$select public.check_rate_limit('x', 1, 60)$q$, '42501', 'client: cannot touch rate limiter');
select t.throws($q$select * from public.documents_due_for_purge()$q$, '42501', 'client: cannot list purge queue');
select t.ok((select count(*) = 0 from storage.objects), 'client: cannot see storage objects');
select t.throws($q$insert into storage.objects (bucket_id, name) values ('identity-documents', 'x.jpg')$q$, '42501', 'client: cannot write to storage');
reset role;
-- حتى مع سياسة سماح خاطئة تبقى المستندات محجوبة
create policy oops_allow_all on storage.objects for all to authenticated using (true) with check (true);
set role authenticated;
select t.ok((select count(*) = 0 from storage.objects), 'storage: restrictive policy beats permissive mistake');
reset role; drop policy oops_allow_all on storage.objects;

-- ===== المدير: المراجعة =====
set role authenticated; select t.act(1);
select t.ok((select count(*) = 3 from public.profiles), 'admin: sees all requests');
select t.ok((select count(*) = 6 from public.identity_documents), 'admin: sees document records');
select t.ok((select count(*) = 0 from storage.objects), 'admin: no direct storage access (server proxy only)');
select t.ok(public.log_document_view((select id from public.identity_documents where profile_id = '00000000-0000-0000-0000-000000000002' and doc_type = 'national_id_front'), '10.0.0.1', 'test') like '00000000-0000-0000-0000-000000000002/%', 'admin: view returns path');
select t.ok((select count(*) = 1 from public.audit_logs where action = 'document.viewed' and actor_id = auth.uid() and ip = '10.0.0.1'), 'audit: document view recorded');
select t.throws($q$select public.review_registration('00000000-0000-0000-0000-000000000002','approve',null,'', true, true)$q$, '22023', 'approve: name required');
select t.throws($q$select public.review_registration('00000000-0000-0000-0000-000000000002','approve',null,'Test Client', false, true)$q$, '22023', 'approve: age 18+ confirmation required');
select t.throws($q$select public.review_registration('00000000-0000-0000-0000-000000000002','approve',null,'Test Client', true, false)$q$, '22023', 'approve: document confirmation required');
select t.throws($q$select public.review_registration('00000000-0000-0000-0000-000000000004','reject','  ')$q$, '22023', 'reject: reason required');
select t.ok(public.review_registration('00000000-0000-0000-0000-000000000002','approve',null,'Test Client', true, true) = 'approved', 'approve: client');
select t.ok(public.review_registration('00000000-0000-0000-0000-000000000003','approve',null,'Test Owner', true, true) = 'approved', 'approve: company');
select t.throws($q$select public.review_registration('00000000-0000-0000-0000-000000000002','reject','changed my mind')$q$, '55000', 'review: cannot review twice');
select t.ok(public.review_registration('00000000-0000-0000-0000-000000000004','reject','Image is not readable') = 'rejected', 'reject: with reason');
select t.throws($q$select public.set_account_status('00000000-0000-0000-0000-000000000004','approved','try to skip')$q$, '55000', 'status: rejected cannot jump to approved');
select t.throws($q$update public.profiles set status = 'banned'$q$, '42501', 'admin: no direct table writes');
select t.throws($q$delete from public.audit_logs$q$, '42501', 'admin: cannot delete audit log');
reset role;

select t.ok((select purge_after between now() + interval '29 days' and now() + interval '31 days' from public.identity_documents where profile_id = '00000000-0000-0000-0000-000000000004' limit 1), 'retention: rejected documents scheduled (30 days)');
select t.ok((select bool_and(purge_after is null) from public.identity_documents where profile_id = '00000000-0000-0000-0000-000000000002'), 'retention: approved documents kept');

-- ===== تجميد / حظر / إعادة تفعيل =====
set role authenticated; select t.act(1);
select t.ok(public.set_account_status('00000000-0000-0000-0000-000000000002','suspended','Under review') = 'suspended', 'status: suspend');
select t.ok(public.set_account_status('00000000-0000-0000-0000-000000000002','banned','Confirmed fraud') = 'banned', 'status: ban');
reset role;
select t.ok((select bool_and(legal_hold) from public.identity_documents where profile_id = '00000000-0000-0000-0000-000000000002'), 'retention: ban preserves evidence');
set role authenticated;
select t.ok(public.set_account_status('00000000-0000-0000-0000-000000000002','approved','Appeal accepted') = 'approved', 'status: reactivate');
reset role;
select t.ok((select not bool_or(legal_hold) from public.identity_documents where profile_id = '00000000-0000-0000-0000-000000000002'), 'retention: hold lifted on reactivation');
select t.ok((select count(*) = 5 from public.account_status_history where profile_id = '00000000-0000-0000-0000-000000000002'), 'history: every transition recorded');

-- ===== الحذف الآمن =====
update public.identity_documents set purge_after = now() - interval '1 minute' where profile_id = '00000000-0000-0000-0000-000000000004';
set role service_role;
select t.ok((select count(*) = 2 from public.documents_due_for_purge()), 'purge: due documents listed');
select t.throws(format('select public.mark_document_purged(%L)', (select id from public.documents_due_for_purge() limit 1)), '55000', 'purge: refused while file still exists');
select t.throws($q$update public.identity_documents set purged_at = now()$q$, '42501', 'service: no direct table writes');
reset role;
-- Storage API يحذف الملف؛ نحاكيه هنا
delete from storage.objects where name like '00000000-0000-0000-0000-000000000004/%';
set role service_role;
select public.mark_document_purged(id) from public.documents_due_for_purge();
select t.ok((select count(*) = 0 from public.documents_due_for_purge()), 'purge: queue emptied');
reset role;
set role authenticated; select t.act(1);
select t.throws(format('select public.log_document_view(%L)', (select id from public.identity_documents where purged_at is not null limit 1)), 'P0002', 'purge: purged document not viewable');
select t.throws($q$select public.set_account_status('00000000-0000-0000-0000-000000000004','pending','reopen request')$q$, '55000', 'purge: cannot reopen without documents');
reset role;

-- ===== السجلات غير قابلة للتعديل حتى لمالك القاعدة =====
select t.throws($q$update public.audit_logs set action = 'x'$q$, '42501', 'append-only: audit update blocked');
select t.throws($q$delete from public.account_status_history$q$, '42501', 'append-only: history delete blocked');
select t.throws($q$truncate public.audit_logs$q$, '42501', 'append-only: truncate blocked');

-- ===== التسجيلات المنقطعة وتحديد المعدل =====
update auth.users set created_at = now() - interval '2 hours';
set role service_role;
select t.ok((select array_agg(user_id) = array['00000000-0000-0000-0000-000000000005'::uuid] from public.orphaned_registrations()), 'cleanup: only orphan listed (admin excluded)');
select t.ok(public.check_rate_limit('ip:1', 2, 3600), 'rate: 1st allowed');
select t.ok(public.check_rate_limit('ip:1', 2, 3600), 'rate: 2nd allowed');
select t.ok(not public.check_rate_limit('ip:1', 2, 3600), 'rate: 3rd blocked');
select t.ok(public.check_rate_limit('ip:2', 2, 3600), 'rate: buckets independent');
reset role;

select t.ok((select bool_and(relrowsecurity) from pg_class where relnamespace = 'public'::regnamespace and relkind = 'r'), 'RLS enabled on every public table');
select t.ok((select not public from storage.buckets where id = 'identity-documents'), 'bucket is private');

\pset tuples_only on
\pset format unaligned
select case when ok then 'PASS ' else 'FAIL ' end || name from t.results order by n;
select format('TOTAL %s  PASSED %s  FAILED %s', count(*), count(*) filter (where ok), count(*) filter (where not ok)) from t.results;
