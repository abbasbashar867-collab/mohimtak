import "server-only";
import { createClient } from "@supabase/supabase-js";
import { env } from "../env";

/** مفتاح الخادم السري. لا يُستورد أبداً في مكوّن يعمل في المتصفح. */
export function serviceClient() {
  return createClient(env("NEXT_PUBLIC_SUPABASE_URL"), env("SUPABASE_SECRET_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export async function allowRequest(bucket: string, limit: number, windowSeconds: number): Promise<boolean> {
  const { data, error } = await serviceClient().rpc("check_rate_limit", {
    p_bucket: bucket, p_limit: limit, p_window_seconds: windowSeconds,
  });
  if (error) throw new Error("rate limit unavailable");
  return data === true;
}
