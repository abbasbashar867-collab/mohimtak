import { SiteHeader } from "./SiteHeader";
import { getI18n } from "@/lib/i18n/server";

export async function PortalHome({ kind, name }: { kind: "client" | "company"; name: string | null }) {
  const { t } = await getI18n();
  return (
    <>
      <SiteHeader signedIn />
      <main className="mx-auto max-w-5xl px-4 py-10">
        <div className="card space-y-3">
          <p className="text-sm text-muted">{kind === "client" ? t.portal.clientTitle : t.portal.companyTitle}</p>
          <h1 className="text-2xl font-bold">{t.portal.welcome} {name}</h1>
          <span className="chip chip-on">{t.portal.active}</span>
          <p className="text-muted">{t.portal.soon}</p>
        </div>
      </main>
    </>
  );
}
