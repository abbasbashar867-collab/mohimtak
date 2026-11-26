"use server";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { appUrl } from "@/lib/env";
import { clientIp } from "@/lib/security/request";
import { allowRequest } from "@/lib/supabase/admin";
import { userClient } from "@/lib/supabase/server";
import { normalizeEmail } from "@/lib/validation/registration";

export async function requestReset(form: FormData) {
  const email = normalizeEmail(String(form.get("email") ?? ""));
  const ip = clientIp(await headers(), process.env.TRUSTED_IP_HEADER);
  if (email && (await allowRequest(`reset:${ip}`, 5, 3600).catch(() => false))) {
    // النتيجة لا تكشف إن كان البريد مسجلاً
    await (await userClient()).auth.resetPasswordForEmail(email, { redirectTo: `${appUrl()}/auth/callback?next=/reset` }).catch(() => null);
  }
  redirect("/forgot?sent=1");
}

export async function setNewPassword(form: FormData) {
  const password = String(form.get("password") ?? "");
  if (password.length < 8) redirect("/reset?error=weak");
  const db = await userClient();
  const { data } = await db.auth.getUser();
  if (!data.user) redirect("/reset?error=link");
  const { error } = await db.auth.updateUser({ password });
  if (error) redirect("/reset?error=link");
  await db.auth.signOut();
  redirect("/login?reset=1");
}
