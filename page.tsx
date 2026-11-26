import Link from "next/link";
import { notFound } from "next/navigation";
import { decideReferral, recordVerification } from "@/actions/admin";
import { ActionForm, Field, Section, Select } from "@/components/AdminUI";
import { EvidenceForm } from "@/components/EvidenceForm";
import { Flash } from "@/components/Flash";
import type { AccountStatus } from "@/lib/auth/routing";
import { requireAdmin } from "@/lib/auth/session";
import { dateTime, whatsappLink } from "@/lib/format";
import { getI18n } from "@/lib/i18n/server";
import { milestonesFor, referralLabel, type ReferralStatus } from "@/lib/labels";

type Referral = {
  id: string; profile_id: string; marketer_id: string; account_type: "client" | "company"; code_used: string; source: "registration_code" | "admin_manual" | "admin_exception";
  starts_at: string; ends_at: string; linked_at: string; link_reason: string | null; exception_reason: string | null; status: ReferralStatus;
  review_flags: ("duplicate_document" | "similar_email" | "matches_marketer_contact" | "reused_evidence")[]; decision_reason: string | null; decided_at: string | null;
  marketers: { name: string } | null; profiles: { verified_name: string | null; phone: string; email: string; status: AccountStatus } | null;
};
type Verification = { id: number; first_contact_at: string; confirmation: "confirmed" | "denied" | "unreachable"; channel: string; notes: string; recorded_at: string };
type Evidence = { id: string; uploaded_at: string };

export default async function ReferralPage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ ok?: string; err?: string }> }) {
  const { db } = await requireAdmin();
  const { t } = await getI18n();
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const res = await db.from("referrals").select("*, marketers(name), profiles(verified_name, phone, email, status)").eq("id", id).maybeSingle();
  if (!res.data) notFound();
  const r = res.data as unknown as Referral;
  const [verifications, evidence, milestones] = await Promise.all([
    db.from("referral_verifications").select("*").eq("referral_id", id).order("id", { ascending: false }),
    db.from("referral_evidence").select("id, uploaded_at").eq("referral_id", id).order("uploaded_at"),
    db.from("referral_milestones").select("milestone").eq("profile_id", r.profile_id),
  ]);
  const done = new Set(((milestones.data ?? []) as unknown as { milestone: string }[]).map((m) => m.milestone));
  const open = r.status === "pending_verification" || r.status === "needs_review";
  const back = `/admin/referrals/${id}`;

  return (
    <>
      <Flash {...await searchParams} />
      <div className="card mt-3 space-y-1">
        <h1 className="text-2xl font-bold">{t.admin.referral} · <span dir="ltr">{r.code_used}</span></h1>
        <p><span className="chip chip-on">{referralLabel(t, r.status)}</span></p>
        <p>{t.admin.marketer}: <Link className="text-accent" href={`/admin/marketers/${r.marketer_id}`}>{r.marketers?.name}</Link></p>
        <p>{t.register[r.account_type]}: <Link className="text-accent" href={`/admin/accounts/${r.profile_id}`}>{r.profiles?.verified_name ?? r.profiles?.email}</Link> · {r.profiles && t.status[r.profiles.status]}</p>
        <p className="text-sm text-muted">{t.mk.source}: {t.mk[r.source]} · {t.admin.date}: {dateTime(r.linked_at)}</p>
        <p className="text-sm text-muted">{t.mk.starts}: {dateTime(r.starts_at)} · {t.mk.ends}: {dateTime(r.ends_at)}</p>
        {r.link_reason && <p className="text-sm">{r.link_reason}</p>}
        {r.exception_reason && <p className="text-sm">{t.admin.exception}: {r.exception_reason}</p>}
        {r.decision_reason && <p className="notice notice-ok">{r.decision_reason} · {dateTime(r.decided_at)}</p>}
        {r.review_flags.map((f) => <p key={f} className="notice notice-bad">{t.mk[f]}</p>)}
        {r.profiles && <a href={whatsappLink(r.profiles.phone)} target="_blank" rel="noopener noreferrer" className="btn-quiet">{t.mk.contactAdmin}</a>}
      </div>

      <Section title={t.mk.progress}>
        <ul>
          <li>{r.profiles?.status === "approved" ? "✓" : "○"} {t.mk.accountApproved}</li>
          {milestonesFor(r.account_type).map((m) => <li key={m}>{done.has(m) ? "✓" : "○"} {t.mk[m]}</li>)}
        </ul>
      </Section>

      <Section title={t.mk.verification}>
        <ul>{((verifications.data ?? []) as unknown as Verification[]).map((v) => (
          <li key={v.id} className="border-b border-line py-2 text-sm last:border-0">
            <b>{t.mk[v.confirmation]}</b> · {v.channel} · {t.mk.firstContact}: {dateTime(v.first_contact_at)}<br />{v.notes} <span className="text-muted">({dateTime(v.recorded_at)})</span>
          </li>
        ))}</ul>
        {open && (
          <ActionForm action={recordVerification} back={back} hidden={{ id }} button={t.mk.record}>
            <Field label={t.mk.firstContact} name="first_contact" type="datetime-local" />
            <Select label={t.mk.confirmation} name="confirmation" defaultValue="unreachable" options={[["confirmed", t.mk.confirmed], ["denied", t.mk.denied], ["unreachable", t.mk.unreachable]]} />
            <Field label={t.mk.channel} name="channel" />
            <Field label={t.admin.notes} name="notes" />
          </ActionForm>
        )}
      </Section>

      <Section title={t.mk.evidence}>
        <div className="mb-3 flex flex-wrap gap-2">
          {((evidence.data ?? []) as unknown as Evidence[]).map((e, i) => (
            <a key={e.id} href={`/api/admin/evidence/${e.id}`} target="_blank" rel="noopener noreferrer" className="btn-quiet">{t.mk.view} {i + 1} · {dateTime(e.uploaded_at)}</a>
          ))}
          {(evidence.data?.length ?? 0) === 0 && <p className="text-muted">{t.admin.empty}</p>}
        </div>
        {open && <EvidenceForm referralId={id} labels={{ evidence: t.mk.evidence, choose: t.register.choose, hint: t.register.imageHint, preparing: t.register.preparing, failed: t.errors.not_image, upload: t.mk.upload }} />}
      </Section>

      {r.status !== "rejected" && (
        <Section title={t.mk.decision}>
          {open && <ActionForm action={decideReferral} back={back} hidden={{ id, decision: "approve" }} reasonLabel={t.admin.reason} button={t.admin.approve} />}
          <ActionForm action={decideReferral} back={back} hidden={{ id, decision: "reject" }} reasonLabel={t.admin.reason} button={t.admin.reject} quiet />
        </Section>
      )}
    </>
  );
}
