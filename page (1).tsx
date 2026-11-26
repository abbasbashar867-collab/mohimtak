import Link from "next/link";
import { requireAdmin } from "@/lib/auth/session";
import { dateTime } from "@/lib/format";
import { getI18n } from "@/lib/i18n/server";

type Row = { id: number; occurred_at: string; actor_id: string | null; action: string; entity_type: string; entity_id: string | null; details: unknown; ip: string | null };

export default async function Audit({ searchParams }: { searchParams: Promise<{ before?: string }> }) {
  const { db } = await requireAdmin();
  const { t } = await getI18n();
  const before = Number((await searchParams).before);
  let query = db.from("audit_logs").select("*").order("id", { ascending: false }).limit(100);
  if (Number.isInteger(before) && before > 0) query = query.lt("id", before);
  const { data, error } = await query;
  if (error) throw new Error("could not load audit log");
  const rows = data as unknown as Row[];
  return (
    <>
      <h1 className="mb-4 text-2xl font-bold">{t.admin.audit}</h1>
      <ul className="card">
        {rows.length === 0 && <li className="text-muted">{t.admin.empty}</li>}
        {rows.map((r) => (
          <li key={r.id} className="border-b border-line py-3 text-sm last:border-0">
            <p className="font-semibold" dir="ltr">{r.action} · {dateTime(r.occurred_at)}</p>
            <p className="break-all text-muted" dir="ltr">{t.admin.actor}: {r.actor_id ?? "system"} · {r.entity_type} {r.entity_id} {r.ip}</p>
            <p className="break-all text-muted" dir="ltr">{JSON.stringify(r.details)}</p>
          </li>
        ))}
      </ul>
      {rows.length === 100 && <Link href={`/admin/audit?before=${rows[99].id}`} className="btn-quiet mt-4">←</Link>}
    </>
  );
}
