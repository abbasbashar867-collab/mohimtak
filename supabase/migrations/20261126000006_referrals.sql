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
