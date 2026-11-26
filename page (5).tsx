import Link from "next/link";
import { notFound } from "next/navigation";
import { evaluateCommissions, updateMarketer } from "@/actions/admin";
import { ActionForm, Field, Section, Select } from "@/components/AdminUI";
import { CommissionList, PayoutList, PayoutRequestForm, type Commission, type Payout } from "@/components/CommissionLists";
import { Flash } from "@/components/Flash";
import type { AccountStatus } from "@/lib/auth/routing";
import { requireAdmin } from "@/lib/auth/session";
import { dateTime, dayStart, iqd, searchFilter } from "@/lib/format";
import { getI18n } from "@/lib/i18n/server";
import { milestonesFor, referralLabel, REFERRAL_STATUSES, type ReferralStatus } from "@/lib/labels";

type Marketer = { id: string; name: string; code: string; phone: string; email: string; status: "active" | "suspended" };
type Referral = { id: string; profile_id: string; account_type: "client" | "company"; status: ReferralStatus; linked_at: string; decision_reason: string | null;
  profiles: { verified_name: string | null; email: string; status: AccountStatus } | null };
const COUNTS = ["clients", "companies", "clients_approved", "companies_approved", "clients_first_task", "companies_first_campaign", "awaiting_verification", "rejected"] as const;
const MONEY = ["commission_due_iqd", "commission_pending_iqd", "commission_approved_total_iqd", "commission_paid_iqd"] as const;

export default async function MarketerFile({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | undefined>> }) {
  const { db } = await requireAdmin();
  const { t } = await getI18n();
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const q = await searchParams;
  const type = q.type === "client" || q.type === "company" ? q.type : null;
  const status = REFERRAL_STATUSES.find((s) => s === q.status);
  const from = dayStart(q.from), to = dayStart(q.to, 1);

  let query = db.from("referrals").select("id, profile_id, account_type, status, linked_at, decision_reason, profiles!inner(verified_name, email, status)")
    .eq("marketer_id", id).order("linked_at", { ascending: false }).limit(300);
  if (type) query = query.eq("account_type", type);
  if (status) query = query.eq("status", status);
  if (from) query = query.gte("linked_at", from);
  if (to) query = query.lt("linked_at", to);
  const search = searchFilter(q.q, ["verified_name", "email", "phone"]);
  if (search) query = query.or(search, { referencedTable: "profiles" });

  const [m, stats, referrals, commissions, payouts, items, minimum] = await Promise.all([
    db.from("marketers").select("*").eq("id", id).maybeSingle(),
    db.rpc("admin_marketer_stats", { p_marketer: id, p_from: from, p_to: to, p_type: type }),
    query,
    db.from("commissions").select("*, profiles(verified_name)").eq("marketer_id", id).order("created_at", { ascending: false }),
    db.from("marketer_payouts").select("*").eq("marketer_id", id).order("requested_at", { ascending: false }),
    db.from("marketer_payout_items").select("commission_id").eq("released", false),
    db.from("settings").select("value").eq("key", "referral.min_payout_iqd").single(),
  ]);
  if (!m.data) notFound();
  if (stats.error || referrals.error || commissions.error || payouts.error || items.error || minimum.error) throw new Error("could not load marketer");
  const marketer = m.data as unknown as Marketer;
  const rows = referrals.data as unknown as Referral[];
  const done = new Set<string>();
  if (rows.length) {
    const res = await db.from("referral_milestones").select("profile_id, milestone").in("profile_id", rows.map((r) => r.profile_id));
    for (const x of (res.data ?? []) as unknown as { profile_id: string; milestone: string }[]) done.add(`${x.profile_id}:${x.milestone}`);
  }
  const all = commissions.data as unknown as Commission[];
  const reserved = new Set((items.data as unknown as { commission_id: string }[]).map((i) => i.commission_id));
  const back = `/admin/marketers/${id}`;
  const values = stats.data as Record<string, number>;

  return (
    <>
      <Flash ok={q.ok} err={q.err} />
      <h1 className="mt-3 text-2xl font-bold">{marketer.name} <span dir="ltr" className="text-accent">{marketer.code}</span></h1>
      <p><span className="chip">{t.mk[marketer.status]}</span> <span dir="ltr" className="text-muted">{marketer.phone} · {marketer.email}</span></p>

      <form className="card mt-4 flex flex-wrap items-end gap-2">
        <Select label={t.admin.type} name="type" defaultValue={q.type} options={[["", t.admin.all], ["client", t.register.client], ["company", t.register.company]]} />
        <Select label={t.admin.state} name="status" defaultValue={q.status} options={[["", t.admin.all], ...REFERRAL_STATUSES.map((s): [string, string] => [s, referralLabel(t, s)])]} />
        <Field label={t.admin.from} name="from" type="date" defaultValue={q.from} required={false} />
        <Field label={t.admin.to} name="to" type="date" defaultValue={q.to} required={false} />
        <Field label={t.admin.search} name="q" defaultValue={q.q} required={false} />
        <button className="btn">{t.admin.filter}</button>
      </form>

      <dl className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
        {COUNTS.map((k) => <div key={k} className="card"><dt className="text-sm text-muted">{t.mk[k]}</dt><dd className="text-2xl font-bold">{values[k]}</dd></div>)}
        {MONEY.map((k) => <div key={k} className="card"><dt className="text-sm text-muted">{t.mk[k]}</dt><dd className="text-lg font-bold">{iqd(values[k])}</dd></div>)}
      </dl>

      <Section title={t.mk.referrals}>
        <ul>
          {rows.length === 0 && <li className="text-muted">{t.admin.empty}</li>}
          {rows.map((r) => (
            <li key={r.id} className="row">
              <div>
                <p><b>{r.profiles?.verified_name ?? r.profiles?.email}</b> · {t.register[r.account_type]} · {referralLabel(t, r.status)} · {r.profiles && t.status[r.profiles.status]}</p>
                <p className="text-sm text-muted">{dateTime(r.linked_at)} · {milestonesFor(r.account_type).map((x) => `${done.has(`${r.profile_id}:${x}`) ? "✓" : "○"} ${t.mk[x]}`).join(" · ")}</p>
                {r.status === "rejected" && <p className="text-sm text-muted">{r.decision_reason}</p>}
              </div>
              <Link href={`/admin/referrals/${r.id}`} className="btn-quiet">{t.admin.open}</Link>
            </li>
          ))}
        </ul>
      </Section>

      <Section title={t.mk.commissions}>
        <p className="mb-3 text-sm text-muted">{t.mk.milestonesNote}</p>
        <ActionForm action={evaluateCommissions} back={back} hidden={{ id }} button={t.mk.reevaluate} quiet />
        <CommissionList t={t} rows={all} back={back} />
      </Section>
      <Section title={t.mk.payouts}>
        <PayoutRequestForm t={t} marketerId={id} back={back} minimum={Number((minimum.data as unknown as { value: number }).value)}
          eligible={all.filter((c) => c.status === "approved" && !reserved.has(c.id))} />
        <div className="mt-4"><PayoutList t={t} rows={payouts.data as unknown as Payout[]} back={back} /></div>
      </Section>

      <Section title={t.mk.edit}>
        <p className="text-sm text-muted">{t.mk.codeLocked}</p>
        <ActionForm action={updateMarketer} back={back} hidden={{ id }} reasonLabel={t.admin.reason} button={t.admin.save}>
          <Field label={t.admin.name} name="name" defaultValue={marketer.name} />
          <Field label={t.mk.phone} name="phone" defaultValue={marketer.phone} dir="ltr" />
          <Field label={t.mk.email} name="email" type="email" defaultValue={marketer.email} dir="ltr" />
          <Field label={t.mk.code} name="code" defaultValue={marketer.code} dir="ltr" />
          <Select label={t.admin.state} name="status" defaultValue={marketer.status} options={[["active", t.mk.active], ["suspended", t.mk.suspended]]} />
        </ActionForm>
      </Section>
    </>
  );
}
