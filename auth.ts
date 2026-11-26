"use server";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { destinationFor } from "@/lib/auth/routing";
import { getViewer } from "@/lib/auth/session";
import { clientIp } from "@/lib/security/request";
import { allowRequest } from "@/lib/supabase/admin";
import { userClient } from "@/lib/supabase/server";
import { normalizeEmail } from "@/lib/validation/registration";

export async function login(form: FormData) {
  const email = normalizeEmail(String(form.get("email") ?? ""));
  const password = String(form.get("password") ?? "");
  if (!email || !password) redirect("/login?error=credentials");
  const ip = clientIp(await headers(), process.env.TRUSTED_IP_HEADER);
  const allowed = (await allowRequest(`login:ip:${ip}`, 30, 900)) && (await allowRequest(`login:${ip}:${email}`, 8, 900));
  if (!allowed) redirect("/login?error=rate");
  const { error } = await (await userClient()).auth.signInWithPassword({ email, password });
  if (error) redirect("/login?error=credentials");
  const viewer = await getViewer();
  redirect(viewer ? destinationFor(viewer) : "/login");
}

export async function logout() {
  await (await userClient()).auth.signOut();
  redirect("/login");
}
