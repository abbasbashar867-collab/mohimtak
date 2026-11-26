import { NextResponse, type NextRequest } from "next/server";
import { userClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const next = request.nextUrl.searchParams.get("next") === "/reset" ? "/reset" : "/login";
  const base = request.nextUrl.origin;
  if (!code) return NextResponse.redirect(`${base}/reset?error=link`);
  const { error } = await (await userClient()).auth.exchangeCodeForSession(code);
  return NextResponse.redirect(error ? `${base}/reset?error=link` : `${base}${next}`);
}
