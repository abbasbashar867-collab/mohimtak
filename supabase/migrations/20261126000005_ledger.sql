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
