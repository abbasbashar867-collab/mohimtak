import { SiteHeader } from "@/components/SiteHeader";
import { getI18n } from "@/lib/i18n/server";

export default async function Page() {
  const { t } = await getI18n();
  return (
    <>
      <SiteHeader />
      <main className="mx-auto max-w-2xl px-4 py-8">
        <h1 className="mb-3 text-2xl font-bold">{t.nav.terms}</h1>
        <p className="notice notice-bad mb-4">{t.legal.draft}</p>
        <ul className="card list-disc space-y-3 ps-8">{t.legal.terms.map((line) => <li key={line}>{line}</li>)}</ul>
      </main>
    </>
  );
}
