import { createPayout, decideCommission, decidePayout } from "@/actions/admin";
import { dateTime, iqd } from "@/lib/format";
import type { Dict } from "@/lib/i18n/config";
import { commissionLabel, payoutLabel, type CommissionStatus, type PayoutStatus } from "@/lib/labels";
import { ActionForm, Field } from "./AdminUI";
import { SubmitButton } from "./SubmitButton";

export type Commission = {
  id: string; marketer_id: string; account_type: "client" | "company"; status: CommissionStatus; amount_iqd: number; base_iqd: number; rate_bps: number;
  basis: { basis: "card_fee" | "topup_gross" | "topup_platform_share"; amount_iqd: number }[]; decision_reason: string | null; created_at: string;
  profiles: { verified_name: string | null } | null; marketers?: { name: string } | null;
};
export type Payout = {
  id: string; marketer_id: string; amount_iqd: number; status: PayoutStatus; requested_at: string; paid_on: string | null; method: string | null;
  reference: string | null; decision_reason: string | null; marketers?: { name: string } | null;
};

export function CommissionList({ t, rows, back }: { t: Dict; rows: Commission[]; back: string }) {
  if (rows.length === 0) return <p className="text-muted">{t.admin.empty}</p>;
  return (
    <ul>{rows.map((c) => (
      <li key={c.id} className="border-b border-line py-3 last:border-0">
        <p><b>{iqd(c.amount_iqd)}</b> · {c.profiles?.verified_name} ({t.register[c.account_type]}) {c.marketers && `· ${c.marketers.name}`} <span className="chip">{commissionLabel(t, c.status)}</span></p>
        <p className="text-sm text-muted">{t.mk.base}: {iqd(c.base_iqd)} ({c.basis.map((b) => `${t.mk[b.basis]} ${iqd(b.amount_iqd)}`).join(" + ")}) · {t.mk.rate} {c.rate_bps / 100}% · {dateTime(c.created_at)}</p>
        {c.decision_reason && <p className="text-sm text-muted">{c.decision_reason}</p>}
        {c.status === "pending_review" && (
          <>
            <ActionForm action={decideCommission} back={back} hidden={{ id: c.id, decision: "approve" }} reasonLabel={t.admin.reason} button={t.mk.approveC} />
            <ActionForm action={decideCommission} back={back} hidden={{ id: c.id, decision: "reject" }} reasonLabel={t.admin.reason} button={t.mk.rejectC} quiet />
          </>
        )}
        {c.status === "approved" && <ActionForm action={decideCommission} back={back} hidden={{ id: c.id, decision: "reverse" }} reasonLabel={t.admin.reason} button={t.mk.reverse} quiet />}
      </li>
    ))}</ul>
  );
}

export function PayoutRequestForm({ t, marketerId, eligible, back, minimum }: { t: Dict; marketerId: string; eligible: Commission[]; back: string; minimum: number }) {
  return (
    <form action={createPayout} className="space-y-2">
      <p className="text-sm text-muted">{t.mk.minPayout}: {iqd(minimum)}</p>
      <input type="hidden" name="id" value={marketerId} />
      <input type="hidden" name="back" value={back} />
      {eligible.length === 0 && <p className="text-muted">{t.admin.empty}</p>}
      {eligible.map((c) => (
        <label key={c.id} className="flex items-center gap-2"><input type="checkbox" name="commission" value={c.id} defaultChecked /> {iqd(c.amount_iqd)} · {c.profiles?.verified_name}</label>
      ))}
      {eligible.length > 0 && <SubmitButton>{t.mk.createPayout}</SubmitButton>}
    </form>
  );
}

export function PayoutList({ t, rows, back }: { t: Dict; rows: Payout[]; back: string }) {
  if (rows.length === 0) return <p className="text-muted">{t.admin.empty}</p>;
  const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Baghdad" }).format(new Date());
  return (
    <ul>{rows.map((p) => (
      <li key={p.id} className="border-b border-line py-3 last:border-0">
        <p><b>{iqd(p.amount_iqd)}</b> {p.marketers && `· ${p.marketers.name}`} <span className="chip">{payoutLabel(t, p.status)}</span> <span className="text-sm text-muted">{dateTime(p.requested_at)}</span></p>
        {p.paid_on && <p className="text-sm text-muted">{p.paid_on} · {p.method} · {p.reference}</p>}
        {p.decision_reason && <p className="text-sm text-muted">{p.decision_reason}</p>}
        {p.status === "pending" && (
          <>
            <ActionForm action={decidePayout} back={back} hidden={{ id: p.id, decision: "pay" }} button={t.mk.pay}>
              <Field label={t.mk.amount} name="amount" type="number" />
              <Field label={t.mk.paidOn} name="paid_on" type="date" defaultValue={today} />
              <Field label={t.mk.method} name="method" />
              <Field label={t.mk.reference} name="reference" />
            </ActionForm>
            <ActionForm action={decidePayout} back={back} hidden={{ id: p.id, decision: "reject" }} reasonLabel={t.admin.reason} button={t.mk.rejectC} quiet />
          </>
        )}
        {p.status === "paid" && <ActionForm action={decidePayout} back={back} hidden={{ id: p.id, decision: "reverse" }} reasonLabel={t.admin.reason} button={t.mk.reverse} quiet />}
      </li>
    ))}</ul>
  );
}
