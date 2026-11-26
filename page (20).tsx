import { PortalHome } from "@/components/PortalHome";
import { requireDestination } from "@/lib/auth/session";

export default async function Page() {
  const { profile } = await requireDestination("/company");
  return <PortalHome kind="company" name={profile?.verified_name ?? null} />;
}
