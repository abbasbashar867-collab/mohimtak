export type AccountStatus = "pending" | "approved" | "rejected" | "suspended" | "banned";

export interface Viewer {
  isAdmin: boolean;
  profile: { account_type: "client" | "company"; status: AccountStatus } | null;
}

/** الواجهة الوحيدة المسموحة لكل حساب. */
export function destinationFor({ isAdmin, profile }: Viewer): "/admin" | "/client" | "/company" | "/account/status" {
  if (isAdmin) return "/admin";
  if (profile?.status === "approved") return profile.account_type === "company" ? "/company" : "/client";
  return "/account/status";
}
