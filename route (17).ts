import { NextResponse } from "next/server";
export const dynamic = "force-dynamic";
export function GET() {
  const ok = Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY && process.env.SUPABASE_SECRET_KEY);
  return NextResponse.json({ ok, supabaseConfigured: ok, time: new Date().toISOString() }, { status: ok ? 200 : 503 });
}
