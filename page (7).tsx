import Link from "next/link";
import { notFound } from "next/navigation";
import { linkReferral, reviewRegistration, setAccountStatus } from "@/actions/admin";
import { ActionForm, Field, Section, Select } from "@/components/AdminUI";
import { Flash } from "@/components/Flash";
import type { AccountStatus } from "@/lib/auth/routing";
import { requireAdmin } from "@/lib/auth/session";
import { dateTime, whatsappLink } from "@/lib/format";
import { getI18n } from "@/lib/i18n/server";
import { referralLabel, type ReferralStatus } from "@/lib/labels";

type Profile = { id: string; account_type: "client" | "company"; status: AccountStatus; phone: string; email: string; verified_name: string | null; status_reason: string | null; created_at: string };
type Doc = { id: string; doc_type: "national_id_front" | "residence_card_front"; purged_at: string | null };
type Event = { id: number; kind: string; details: { doc_type?: string } };
type History = { id: number; from_status: AccountStatus | null; to_status: AccountStatus; reason: string | null; created_at: string };
type Referral = { id: string; status: ReferralStatus; code_used: string; marketers: { name: string } | null };

/** الإجراءات المتاحة لكل حالة (قاعدة البيانات تفرضها أيضاً). */
const TRANSITIONS: Record<AccountStatus, AccountStatus[]> = {
  pending: ["banned"], approved: ["suspended", "banned"], suspended: ["approved", "banned"], rejected: ["pending", "banned"], banned: ["approved", "pending"],
};

export default async function Account({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ ok?: string; err?: string }> }) {
  const { db } = await requireAdmin();
  const { t } = await getI18n();
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const [p, docs, events, history, referral, marketers] = await Promise.all([
    db.from("profiles").select("*").eq("id", id).maybeSingle(),
    db.from("identity_documents").select("id, doc_type, purged_at").eq("profile_id", id).order("doc_type"),
    db.from("security_events").select("id, kind, details").eq("profile_id", id),
    db.from("account_status_history").select("*").eq("profile_id", id).order("id"),
    db.from("referrals").select("id, status, code_used, marketers(name)").eq("profile_id", id).maybeSingle(),
    db.from("marketers").select("id, name, code").eq("status", "active").order("name"),
  ]);
  if (!p.data) notFound();
  const profile = p.data as unknown as Profile;
  const ref = referral.data as unknown as Referral | null;
  const back = `/admin/accounts/${id}`;
  const verb: Record<AccountStatus, string> = { approved: t.admin.reactivate, suspended: t.admin.suspend, banned: t.admin.ban, pending: t.admin.reopen, rejected: t.admin.reject };
  // حساب لم يُقبل سابقاً لا يمكن "إعادة تفعيله"
  const options = TRANSITIONS[profile.status].filter((s) => s !== "approved" || profile.verified_name);

  return (
    <>
      <Flash {...await searchParams} />
      <div className="card mt-3 space-y-1">
        <h1 className="text-2xl font-bold">{profile.verified_name ?? t.register[profile.account_type]}</h1>
        <p><span className="chip chip-on">{t.status[profile.status]}</span> <span className="chip">{t.register[profile.account_type]}</span></p>
        <p dir="ltr" className="text-start">{profile.phone} · {profile.email}</p>
        <p className="text-sm text-muted">{dateTime(profile.created_at)}</p>
        {profile.status_reason && <p className="notice notice-bad">{profile.status_reason}</p>}
        <a href={whatsappLink(profile.phone)} target="_blank" rel="noopener noreferrer" className="btn-quiet">{t.nav.whatsapp}</a>
      </div>

      {(events.data?.length ?? 0) > 0 && (
        <Section title={t.admin.flags}>
          {(events.data as unknown as Event[]).map((e) => <p key={e.id} className="notice notice-bad mb-2">{t.mk.duplicate_document}: {e.details.doc_type === "national_id_front" ? t.register.nationalId : t.register.residence}</p>)}
        </Section>
      )}

      <Section title={t.admin.documents}>
        <div className="grid gap-4 sm:grid-cols-2">
          {((docs.data ?? []) as unknown as Doc[]).map((d) => (
            <figure key={d.id}>
              <figcaption className="label">{d.doc_type === "national_id_front" ? t.register.nationalId : t.register.residence}</figcaption>
              {d.purged_at ? <p className="text-muted">{t.admin.purged}</p> : (
                <a href={`/api/admin/documents/${d.id}`} target="_blank" rel="noopener noreferrer" className="btn-quiet">{t.mk.view}</a>
              )}
            </figure>
          ))}
        </div>
      </Section>

      {profile.status === "pending" && (
        <Section title={t.mk.decision}>
          <ActionForm action={reviewRegistration} back={back} hidden={{ id, decision: "approve" }} button={t.admin.approve}>
            <Field label={t.admin.verifiedName} name="verified_name" />
            <label className="flex w-full items-center gap-2"><input type="checkbox" name="age" required /> {t.admin.ageOk}</label>
            <label className="flex w-full items-center gap-2"><input type="checkbox" name="docs" required /> {t.admin.docsOk}</label>
          </ActionForm>
          <hr className="my-4 border-line" />
          <ActionForm action={reviewRegistration} back={back} hidden={{ id, decision: "reject" }} reasonLabel={t.admin.reason} button={t.admin.reject} quiet />
        </Section>
      )}

      {options.length > 0 && (
        <Section title={t.admin.state}>
          <ActionForm action={setAccountStatus} back={back} hidden={{ id }} reasonLabel={t.admin.reason} button={t.admin.save} quiet>
            <Select label={t.admin.action} name="status" defaultValue={options[0]} options={options.map((s): [string, string] => [s, verb[s]])} />
          </ActionForm>
        </Section>
      )}

      <Section title={t.admin.referral}>
        {ref ? (
          <div className="row"><p>{ref.marketers?.name} · <span dir="ltr">{ref.code_used}</span> · {referralLabel(t, ref.status)}</p><Link href={`/admin/referrals/${ref.id}`} className="btn-quiet">{t.admin.open}</Link></div>
        ) : (marketers.data?.length ?? 0) > 0 ? (
          <ActionForm action={linkReferral} back={back} hidden={{ profile: id }} reasonLabel={t.admin.reason} button={t.admin.link} quiet>
            <Select label={t.admin.marketer} name="marketer" defaultValue={(marketers.data as unknown as { id: string }[])[0].id}
              options={(marketers.data as unknown as { id: string; name: string; code: string }[]).map((m): [string, string] => [m.id, `${m.name} (${m.code})`])} />
            <Field label={t.admin.exception} name="exception" required={false} />
          </ActionForm>
        ) : <p className="text-muted">{t.admin.empty}</p>}
      </Section>

      <Section title={t.admin.history}>
        <ul>{((history.data ?? []) as unknown as History[]).map((h) => (
          <li key={h.id} className="row text-sm"><span>{h.from_status ? `${t.status[h.from_status]} → ` : ""}{t.status[h.to_status]} {h.reason && `— ${h.reason}`}</span><span className="text-muted">{dateTime(h.created_at)}</span></li>
        ))}</ul>
      </Section>
    </>
  );
}
