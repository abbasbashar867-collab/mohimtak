import { randomUUID } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import { getViewer } from "@/lib/auth/session";
import { appUrl } from "@/lib/env";
import { processDocumentImage } from "@/lib/images/process-document";
import { isSameOrigin } from "@/lib/security/request";
import { serviceClient } from "@/lib/supabase/admin";

export const runtime = "nodejs";

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id) || !isSameOrigin(request.headers, appUrl())) return new NextResponse(null, { status: 404 });
  const viewer = await getViewer();
  if (!viewer?.isAdmin) return new NextResponse(null, { status: 404 });
  const done = (result: string) => NextResponse.redirect(new URL(`/admin/referrals/${id}?${result}`, appUrl()), 303);

  const length = Number(request.headers.get("content-length") ?? 0);
  if (!length || length > 3 * 1024 * 1024) return done("err=22023");
  const file = (await request.formData()).get("evidence");
  if (!(file instanceof Blob)) return done("err=22023");
  const processed = await processDocumentImage(Buffer.from(await file.arrayBuffer()));
  if (!processed.ok) return done("err=22023");

  const bucket = serviceClient().storage.from("referral-evidence");
  const path = `${id}/${randomUUID()}.jpg`;
  const upload = await bucket.upload(path, processed.image.data, { contentType: "image/jpeg", upsert: false });
  if (upload.error) return done("err=unknown");
  const { error } = await viewer.db.rpc("admin_add_referral_evidence", { p_referral: id, p_path: path, p_sha256: processed.image.sha256 });
  if (error) {
    await bucket.remove([path]);
    return done(`err=${encodeURIComponent(error.code ?? "unknown")}`);
  }
  return done("ok=1");
}
