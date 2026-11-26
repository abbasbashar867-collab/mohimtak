import Link from "next/link";
import { createMarketer } from "@/actions/admin";
import { ActionForm, Field, Section, Select } from "@/components/AdminUI";
import { Flash } from "@/components/Flash";
import { requireAdmin } from "@/lib/auth/session";
import { dateTime, searchFilter } from "@/lib/format";
import { getI18n } from "@/lib/i18n/server";
import { referralLabel, type ReferralStatus } from "@/lib/labels";

type Marketer = { id: string; name: string; code: string; phone: string; status: "active" | "suspended" };
type Waiting = { id: string; status: ReferralStatus; code_used: string; linked_at: string; account_type: "client" | "company"; marketers: { name: string } | null };

export default async function Marketers({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const { db } = await requireAdmin();
  const { t } = await getI18n();
  const q = await searchParams;
  let query = db.from("marketers").select("id, name, code, phone, status").order("created_at", { ascending: false }).limit(200);
  const search = searchFilter(q.q, ["name", "code", "phone", "email"]);
  if (search) query = query.or(search);
  if (q.status === "active" || q.status === "suspended") query = query.eq("status", q.status);
  const [list, waiting] = await Promise.all([
    query,
    db.from("referrals").select("id, status, code_used, linked_at, account_type, marketers(name)").in("status", ["pending_verification", "needs_review"]).order("linked_at").limit(100),
  ]);
  if (list.error || waiting.error) throw new Error("could not load marketers");

  return (
    <>
      <h1 className="mb-4 text-2xl font-bold">{t.admin.marketers}</h1>
      <Flash ok={q.ok} err={q.err} />
      <Section title={t.mk.add}>
        <ActionForm action={createMarketer} back="/admin/marketers" button={t.mk.add}>
          <Field label={t.admin.name} name="name" />
          <Field label={t.mk.phone} name="phone" type="tel" dir="ltr" />
          <Field label={t.mk.email} name="email" type="email" dir="ltr" />
          <Field label={`${t.mk.code} (MHT-001)`} name="code" dir="ltr" />
        </ActionForm>
      </Section>
      <Section title={t.mk.awaiting_verification}>
        <ul>
          {(waiting.data?.length ?? 0) === 0 && <li className="text-muted">{t.admin.empty}</li>}
          {(waiting.data as unknown as Waiting[]).map((r) => (
            <li key={r.id} className="row">
              <p>{r.marketers?.name} · <span dir="ltr">{r.code_used}</span> · {t.register[r.account_type]} · {referralLabel(t, r.status)} · <span className="text-sm text-muted">{dateTime(r.linked_at)}</span></p>
              <Link href={`/admin/referrals/${r.id}`} className="btn-quiet">{t.admin.open}</Link>
            </li>
          ))}
        </ul>
      </Section>
      <form className="card mt-5 flex flex-wrap items-end gap-2">
        <Field label={t.admin.search} name="q" defaultValue={q.q} required={false} />
        <Select label={t.admin.state} name="status" defaultValue={q.status} options={[["", t.admin.all], ["active", t.mk.active], ["suspended", t.mk.suspended]]} />
        <button className="btn">{t.admin.filter}</button>
      </form>
      <ul className="card mt-4">
        {(list.data?.length ?? 0) === 0 && <li className="text-muted">{t.admin.empty}</li>}
        {(list.data as unknown as Marketer[]).map((m) => (
          <li key={m.id} className="row">
            <p><b>{m.name}</b> · <span dir="ltr">{m.code}</span> · <span dir="ltr" className="text-muted">{m.phone}</span></p>
            <div className="flex gap-2"><span className="chip">{t.mk[m.status]}</span><Link href={`/admin/marketers/${m.id}`} className="btn-quiet">{t.admin.open}</Link></div>
          </li>
        ))}
      </ul>
    </>
  );
}
