import "server-only";
import { userClient } from "./supabase/server";

export const SUPPORT_FALLBACK = "+9647826849259";

/** رقم الدعم من إعدادات قاعدة البيانات. */
export async function supportPhone(): Promise<string> {
  try {
    const { data } = await (await userClient()).rpc("get_public_settings");
    return (data as Record<string, string> | null)?.["support.whatsapp"] ?? SUPPORT_FALLBACK;
  } catch {
    return SUPPORT_FALLBACK;
  }
}
