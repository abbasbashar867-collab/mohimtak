import Link from "next/link";
import { Field, Select } from "@/components/AdminUI";
import { requireAdmin } from "@/lib/auth/session";
import type { AccountStatus } from "@/lib/auth/routing";
import { dateTime, dayStart, searchFilter } from "@/lib/format";
import { getI18n } from "@/lib/i18n/server";
import { extras } from "@/lib/i18n/extra";

const STATUSES: AccountStatus[] = ["pending", "approved", "rejected", "suspended", "banned"];
type Row = { id: string; account_type: "client" | "company"; status: AccountStatus; phone: string; email: string; verified_name: string | null; created_at: string };

export default async function Accounts({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const { db } = await requireAdmin();
  const { t, locale } = await getI18n();
  const x = extras[locale].stats;
  const count = async (f: (q: any) => any) => (await f(db.from("profiles").select("id", { count: "exact", head: true }))).count ?? 0;
  const [total, pendingN, approvedN, clientsN, companiesN] = await Promise.all([
    count((q) => q), count((q) => q.eq("status", "pending")), count((q) => q.eq("status", "approved")),
    count((q) => q.eq("account_type", "client")), count((q) => q.eq("account_type", "company")),
  ]);
  const q = await searchParams;
  const status = q.status === "all" ? null : STATUSES.find((s) => s === q.status) ?? "pending";
  let query = db.from("profiles").select("id, account_type, status, phone, email, verified_name, created_at").order("created_at", { ascending: false }).limit(100);
  if (status) query = query.eq("status", status);
  if (q.type === "client" || q.type === "company") query = query.eq("account_type", q.type);
  const search = searchFilter(q.q, ["verified_name", "phone", "email"]);
  if (search) query = query.or(search);
  const from = dayStart(q.from), to = dayStart(q.to, 1);
  if (from) query = query.gte("created_at", from);
  if (to) query = query.lt("created_at", to);
  const { data, error } = await query;
  if (error) throw new Error("could not load accounts");
  const rows = data as unknown as Row[];

  return (
    <>
      <h1 className="mb-4 text-2xl font-bold">{t.admin.accounts}</h1>
      <section aria-label={x.title} className="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-5">
        {([[x.total, total], [x.pending, pendingN], [x.approved, approvedN], [x.clients, clientsN], [x.companies, companiesN]] as [string, number][]).map(([label, n]) => (
          <div key={label} className="card text-center"><p className="text-2xl font-bold text-accent">{n}</p><p className="text-xs text-muted">{label}</p></div>
        ))}
      </section>
      <form className="card flex flex-wrap items-end gap-2">
        <Select label={t.admin.state} name="status" defaultValue={status ?? "all"} options={[["all", t.admin.all], ...STATUSES.map((s): [string, string] => [s, t.status[s]])]} />
        <Select label={t.admin.type} name="type" defaultValue={q.type} options={[["", t.admin.all], ["client", t.register.client], ["company", t.register.company]]} />
        <Field label={t.admin.search} name="q" defaultValue={q.q} required={false} />
        <Field label={t.admin.from} name="from" type="date" defaultValue={q.from} required={false} />
        <Field label={t.admin.to} name="to" type="date" defaultValue={q.to} required={false} />
        <button className="btn">{t.admin.filter}</button>
      </form>
      <ul className="card mt-4">
        {rows.length === 0 && <li className="text-muted">{t.admin.empty}</li>}
        {rows.map((r) => (
          <li key={r.id} className="row">
            <div>
              <p className="font-semibold">{r.verified_name ?? r.email}</p>
              <p className="text-sm text-muted">{t.register[r.account_type]} · <span dir="ltr">{r.phone}</span> · {dateTime(r.created_at)}</p>
            </div>
            <div className="flex items-center gap-2"><span className="chip">{t.status[r.status]}</span><Link href={`/admin/accounts/${r.id}`} className="btn-quiet">{t.admin.open}</Link></div>
          </li>
        ))}
      </ul>
    </>
  );
}
