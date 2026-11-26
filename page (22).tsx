import { PortalHome } from "@/components/PortalHome";
import { requireDestination } from "@/lib/auth/session";

export default async function Page() {
  const { profile } = await requireDestination("/client");
  return <PortalHome kind="client" name={profile?.verified_name ?? null} />;
}
