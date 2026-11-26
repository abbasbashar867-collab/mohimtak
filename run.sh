#!/usr/bin/env bash
# يشغّل قاعدة PostgreSQL مؤقتة، يطبق الـ migrations، ثم الاختبارات. لا يلمس أي قاعدة حقيقية.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${PG_BIN:-$(pg_config --bindir 2>/dev/null || echo /usr/lib/postgresql/16/bin)}"
[ -x "$BIN/initdb" ] || BIN=/usr/lib/postgresql/16/bin
WORK="$(mktemp -d)"; PORT="${PG_TEST_PORT:-55432}"
as_pg() { if [ "$(id -u)" = 0 ]; then su postgres -s /bin/bash -c "$*"; else bash -c "$*"; fi; }
cp -r "$ROOT/supabase" "$ROOT/tests" "$WORK/"
[ "$(id -u)" = 0 ] && chown -R postgres "$WORK"
cleanup() { as_pg "$BIN/pg_ctl -D $WORK/data -m immediate stop" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT
as_pg "$BIN/initdb -D $WORK/data -U postgres -A trust -E UTF8" >/dev/null
as_pg "$BIN/pg_ctl -D $WORK/data -o '-p $PORT -k $WORK -c listen_addresses=' -l $WORK/log -w start" >/dev/null
PSQL="psql -X -q -v ON_ERROR_STOP=1 -h $WORK -p $PORT -U postgres"
prepare() {
  $PSQL -d postgres -c "create database $1"
  $PSQL -d "$1" -f "$WORK/tests/db/supabase_shim.sql"
  for f in "$WORK"/supabase/migrations/*.sql; do $PSQL -d "$1" -f "$f"; done
}
prepare t1
OUT="$($PSQL -d t1 -o /dev/null -f "$WORK/tests/db/registration_test.sql" 2>&1)" || true
# إعادة طباعة النتائج
$PSQL -d t1 -At -c "select case when ok then 'PASS ' else 'FAIL ' end || name from t.results order by n"
SUMMARY="$($PSQL -d t1 -At -c "select count(*) filter (where ok) || ' ' || count(*) filter (where not ok) from t.results")"
[ -n "$OUT" ] && echo "$OUT" | grep -E "ERROR|FATAL" || true
read -r PASSED FAILED <<<"$SUMMARY"
SCRIPT_ERRORS=$(echo "$OUT" | grep -c "ERROR" || true)

# ===== المسوّقون والإحالات =====
prepare t3
OUT3="$($PSQL -d t3 -o /dev/null -f "$WORK/tests/db/referrals_test.sql" 2>&1)" || true
$PSQL -d t3 -At -c "select case when ok then 'PASS ' else 'FAIL ' end || name from t.results order by n"
read -r P3 F3 <<<"$($PSQL -d t3 -At -c "select count(*) filter (where ok) || ' ' || count(*) filter (where not ok) from t.results")"
echo "$OUT3" | grep -E "ERROR|FATAL" || true
PASSED=$((PASSED+P3)); FAILED=$((FAILED+F3))
SCRIPT_ERRORS=$((SCRIPT_ERRORS + $(echo "$OUT3" | grep -c "ERROR" || true)))

# ===== التزامن: جلستان حقيقيتان تعملان في اللحظة نفسها =====
prepare t2
$PSQL -d t2 -o /dev/null <<'SQL'
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-000000000001','admin@test.invalid'),
 ('00000000-0000-0000-0000-000000000002','a@test.invalid'),
 ('00000000-0000-0000-0000-000000000003','b@test.invalid');
insert into storage.objects (bucket_id, name)
 select 'identity-documents', format('00000000-0000-0000-0000-00000000000%s/%s.jpg', u, d)
 from generate_series(2,3) u, unnest(array['national_id_front','residence_card_front']) d;
set role service_role; select public.bootstrap_super_admin('00000000-0000-0000-0000-000000000001');
SQL
reg() { cat <<SQL
begin; set local role service_role;
select public.register_account('00000000-0000-0000-0000-00000000000$1','client','+9647700000000','$2@test.invalid','ar',
 (select jsonb_agg(jsonb_build_object('doc_type',d,'storage_path','00000000-0000-0000-0000-00000000000$1/'||d||'.jpg',
   'sha256',repeat('$1',64),'mime_type','image/jpeg','size_bytes',1,'width',1,'height',1))
  from unnest(array['national_id_front','residence_card_front']) d));
select pg_sleep(1); commit;
SQL
}
reg 2 a | $PSQL -d t2 >/dev/null 2>&1 & P1=$!
reg 3 b | $PSQL -d t2 >/dev/null 2>&1 & P2=$!
R1=0; R2=0; wait $P1 || R1=1; wait $P2 || R2=1
check() { if [ "$1" = "$2" ]; then echo "PASS $3"; PASSED=$((PASSED+1)); else echo "FAIL $3 (got $1)"; FAILED=$((FAILED+1)); fi; }
check "$((R1+R2))" 1 "concurrency: same phone registered twice -> exactly one succeeds"
check "$($PSQL -d t2 -At -c 'select count(*) from public.profiles')" 1 "concurrency: one profile only"
ID="$($PSQL -d t2 -At -c 'select id from public.profiles')"
review() { cat <<SQL
begin; set local role authenticated; set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select public.review_registration('$ID', $1);
select pg_sleep(1); commit;
SQL
}
review "'approve', null, 'Test Name', true, true" | $PSQL -d t2 >/dev/null 2>&1 & P1=$!
review "'reject', 'not readable'" | $PSQL -d t2 >/dev/null 2>&1 & P2=$!
R1=0; R2=0; wait $P1 || R1=1; wait $P2 || R2=1
check "$((R1+R2))" 1 "concurrency: approve vs reject -> exactly one wins"
check "$($PSQL -d t2 -At -c 'select count(*) from public.account_status_history')" 2 "concurrency: single decision recorded"

# ===== تزامن العمولات: طلبا صرف لنفس العمولة في اللحظة نفسها =====
prepare t4
$PSQL -d t4 -o /dev/null -f "$WORK/tests/db/referrals_test.sql" >/dev/null 2>&1
pay() { cat <<SQL
begin; set local role authenticated; set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
select public.admin_create_payout((select id from public.marketers where code='MHT-001'),
  array[(select id from public.commissions where profile_id = '00000000-0000-0000-0000-000000000020')]);
select pg_sleep(1); commit;
SQL
}
pay | $PSQL -d t4 >/dev/null 2>&1 & P1=$!
pay | $PSQL -d t4 >/dev/null 2>&1 & P2=$!
R1=0; R2=0; wait $P1 || R1=1; wait $P2 || R2=1
check "$((R1+R2))" 1 "T10 concurrency: two payout requests for one commission -> exactly one"
check "$($PSQL -d t4 -At -c 'select count(*) from public.marketer_payout_items where not released')" 1 "T10 concurrency: single active payout item"

# ===== الترقية على قاعدة فيها بيانات + نسخ احتياطي واستعادة =====
$PSQL -d postgres -c "create database up"
$PSQL -d up -f "$WORK/tests/db/supabase_shim.sql"
for f in "$WORK"/supabase/migrations/2026112600000[1-4]_*.sql; do $PSQL -d up -f "$f"; done
$PSQL -d up -o /dev/null <<'SQL'
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000002','old@test.invalid');
insert into storage.objects (bucket_id, name)
 select 'identity-documents', '00000000-0000-0000-0000-000000000002/'||d||'.jpg' from unnest(array['national_id_front','residence_card_front']) d;
select public.register_account('00000000-0000-0000-0000-000000000002','client','+9647700000000','old@test.invalid','ar',
 (select jsonb_agg(jsonb_build_object('doc_type',d,'storage_path','00000000-0000-0000-0000-000000000002/'||d||'.jpg',
   'sha256',repeat('a',64),'mime_type','image/jpeg','size_bytes',1,'width',1,'height',1))
  from unnest(array['national_id_front','residence_card_front']) d));
SQL
snapshot() { $PSQL -d "$1" -At -c "select md5(coalesce((select string_agg(p::text, '|' order by id) from public.profiles p),'') || coalesce((select string_agg(d::text,'|' order by id) from public.identity_documents d),'') || coalesce((select string_agg(a::text,'|' order by id) from public.audit_logs a),''))"; }
BEFORE="$(snapshot up)"
DUMP="$WORK/backup.dump"
pg_dump -h "$WORK" -p "$PORT" -U postgres -Fc -f "$DUMP" up
$PSQL -d postgres -c "create database restored"
UPG=0; for f in "$WORK"/supabase/migrations/2026112600000[5-9]_*.sql; do $PSQL -d up -f "$f" || UPG=1; done
check "$UPG" 0 "upgrade: new migrations apply on a database with data"
check "$(snapshot up)" "$BEFORE" "upgrade: existing rows unchanged"
RST=0; pg_restore -h "$WORK" -p "$PORT" -U postgres -d restored --exit-on-error "$DUMP" || RST=1
check "$RST" 0 "backup: restore succeeds"
check "$(snapshot restored)" "$BEFORE" "backup: restored data identical"
check "$($PSQL -d restored -At -c "select count(*) from pg_policies where schemaname='public'")" "$($PSQL -d t1 -At -c "select count(*) from pg_policies where schemaname='public' and tablename in (select tablename from pg_tables where schemaname='public') and tablename not like 'ledger%' and tablename not in ('marketers','referrals','referral_verifications','referral_evidence','referral_milestones','commissions','marketer_payouts','marketer_payout_items')")" "backup: security policies restored"

echo "----"
echo "TOTAL $((PASSED+FAILED))  PASSED $PASSED  FAILED $FAILED  SCRIPT_ERRORS $SCRIPT_ERRORS"
[ "$FAILED" = 0 ] && [ "$SCRIPT_ERRORS" = 0 ]
