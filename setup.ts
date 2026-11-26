"use server";
import { createHash, timingSafeEqual } from "node:crypto";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { clientIp } from "@/lib/security/request";
import { allowRequest, serviceClient } from "@/lib/supabase/admin";
import { normalizeEmail } from "@/lib/validation/registration";

const digest = (v: string) => createHash("sha256").update(v).digest();

export async function createSuperAdmin(form: FormData) {
  const expected = process.env.SETUP_TOKEN ?? "";
  const ip = clientIp(await headers(), process.env.TRUSTED_IP_HEADER);
  if (expected.length < 24 || !(await allowRequest(`setup:${ip}`, 5, 3600))) redirect("/setup?result=failed");
  if (!timingSafeEqual(digest(String(form.get("token") ?? "")), digest(expected))) redirect("/setup?result=failed");
  const email = normalizeEmail(String(form.get("email") ?? ""));
  const password = String(form.get("password") ?? "");
  if (!email || password.length < 14 || Buffer.byteLength(password) > 72) redirect("/setup?result=failed");

  const db = serviceClient();
  const { data, error } = await db.auth.admin.createUser({ email, password, email_confirm: true });
  if (error || !data.user) redirect("/setup?result=failed");
  const boot = await db.rpc("bootstrap_super_admin", { p_user_id: data.user.id });
  if (boot.error) {
    await db.auth.admin.deleteUser(data.user.id);
    redirect("/setup?result=failed");
  }
  redirect("/setup?result=done");
}
