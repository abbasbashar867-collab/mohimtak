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
  ('support.whatsapp',                     '"+9647816849259"', true),
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
