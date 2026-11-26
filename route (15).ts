import { NextResponse, type NextRequest } from "next/server";
import { appUrl } from "@/lib/env";
import { clientIp, isSameOrigin } from "@/lib/security/request";
import { allowRequest, serviceClient } from "@/lib/supabase/admin";
import { normalizeReferralCode } from "@/lib/validation/registration";

export async function POST(request: NextRequest) {
  if (!isSameOrigin(request.headers, appUrl())) return NextResponse.json({ error: "invalid_request" }, { status: 403 });
  try {
    const ip = clientIp(request.headers, process.env.TRUSTED_IP_HEADER);
    // يمنع تخمين الأكواد
    if (!(await allowRequest(`code:${ip}`, 20, 900))) return NextResponse.json({ error: "rate" }, { status: 429 });
    const body = (await request.json().catch(() => null)) as { code?: unknown } | null;
    const code = typeof body?.code === "string" ? normalizeReferralCode(body.code) : null;
    if (!code) return NextResponse.json({ state: "invalid" });
    const { data, error } = await serviceClient().rpc("check_referral_code", { p_code: code });
    if (error) throw new Error(error.message);
    return NextResponse.json({ state: data });
  } catch {
    return NextResponse.json({ error: "server" }, { status: 500 });
  }
}
