import "server-only";
import { notFound, redirect } from "next/navigation";
import { userClient } from "../supabase/server";
import { destinationFor, type AccountStatus } from "./routing";

export interface Profile {
  account_type: "client" | "company";
  status: AccountStatus;
  verified_name: string | null;
  status_reason: string | null;
}

export async function getViewer() {
  const db = await userClient();
  const { data: auth } = await db.auth.getUser();
  if (!auth.user) return null;
  const [role, profile] = await Promise.all([
    db.from("user_roles").select("role_key").eq("user_id", auth.user.id).eq("role_key", "super_admin").maybeSingle(),
    db.from("profiles").select("account_type, status, verified_name, status_reason").eq("id", auth.user.id).maybeSingle(),
  ]);
  if (role.error || profile.error) throw new Error("could not load account");
  return { db, userId: auth.user.id as string, isAdmin: Boolean(role.data), profile: profile.data as unknown as Profile | null };
}

/** يمنع دخول أي واجهة غير واجهة الحساب. */
export async function requireDestination(expected: "/client" | "/company" | "/account/status") {
  const viewer = await getViewer();
  if (!viewer) redirect("/login");
  const actual = destinationFor(viewer);
  if (actual !== expected) redirect(actual);
  return viewer;
}

/** لغير المدير العام تبدو صفحات الإدارة غير موجودة. */
export async function requireAdmin() {
  const viewer = await getViewer();
  if (!viewer?.isAdmin) notFound();
  return viewer;
}
