import "server-only";
import { NextResponse, type NextRequest } from "next/server";
import { getViewer } from "../auth/session";
import { serviceClient } from "../supabase/admin";
import { clientIp } from "./request";

/** يسجل العرض في قاعدة البيانات أولاً، ثم يمرر الملف عبر الخادم دون أي رابط مباشر. */
export async function servePrivateImage(
  request: NextRequest, id: string, logFunction: string, idArgument: string, bucket: string,
) {
  const missing = () => new NextResponse(null, { status: 404 });
  if (!/^[0-9a-f-]{36}$/i.test(id)) return missing();
  const viewer = await getViewer();
  if (!viewer?.isAdmin) return missing();
  const { data: path, error } = await viewer.db.rpc(logFunction, {
    [idArgument]: id,
    p_ip: clientIp(request.headers, process.env.TRUSTED_IP_HEADER),
    p_user_agent: request.headers.get("user-agent")?.slice(0, 300) ?? null,
  });
  if (error || typeof path !== "string") return missing();
  const file = await serviceClient().storage.from(bucket).download(path);
  if (file.error || !file.data) return missing();
  return new NextResponse(await file.data.arrayBuffer(), {
    headers: {
      "Content-Type": "image/jpeg",
      "Content-Disposition": "inline",
      "Cache-Control": "private, no-store, max-age=0",
      "X-Content-Type-Options": "nosniff",
      "Content-Security-Policy": "default-src 'none'; sandbox",
      "Cross-Origin-Resource-Policy": "same-origin",
    },
  });
}
