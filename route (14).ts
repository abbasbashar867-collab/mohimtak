import { createHash, timingSafeEqual } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import { serviceClient } from "@/lib/supabase/admin";

export const runtime = "nodejs";
const BUCKET = "identity-documents";
const digest = (v: string) => createHash("sha256").update(v).digest();

/** حذف المستندات المنتهية مدة الاحتفاظ بها وتنظيف التسجيلات المنقطعة. تستدعى يومياً. */
export async function POST(request: NextRequest) {
  const secret = process.env.CRON_SECRET ?? "";
  const given = request.headers.get("authorization") ?? "";
  if (secret.length < 24 || !timingSafeEqual(digest(given), digest(`Bearer ${secret}`))) {
    return new NextResponse(null, { status: 404 });
  }
  const db = serviceClient();
  let purged = 0, orphans = 0, errors = 0;

  const due = await db.rpc("documents_due_for_purge", { p_limit: 100 });
  if (due.error) errors++;
  for (const doc of (due.data ?? []) as { id: string; storage_path: string }[]) {
    const removed = await db.storage.from(BUCKET).remove([doc.storage_path]);
    if (removed.error) { errors++; continue; }
    const marked = await db.rpc("mark_document_purged", { p_document_id: doc.id });
    if (marked.error) errors++; else purged++;
  }

  const stale = await db.rpc("orphaned_registrations");
  if (stale.error) errors++;
  for (const row of (stale.data ?? []) as { user_id: string; object_names: string[] }[]) {
    if (row.object_names.length && (await db.storage.from(BUCKET).remove(row.object_names)).error) { errors++; continue; }
    if ((await db.auth.admin.deleteUser(row.user_id)).error) errors++; else orphans++;
  }
  return NextResponse.json({ purged, orphans, errors }, { status: errors ? 500 : 200 });
}
