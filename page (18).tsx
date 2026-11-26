import Image from "next/image";
import Link from "next/link";
import { SiteHeader } from "@/components/SiteHeader";
import { getI18n } from "@/lib/i18n/server";
import { extras } from "@/lib/i18n/extra";

export default async function Home() {
  const { t, locale } = await getI18n();
  const x = extras[locale];
  return (
    <>
      <SiteHeader />
      <main className="mx-auto max-w-5xl px-4">
        <section className="flex flex-col items-center gap-5 py-12 text-center">
          <Image src="/brand/logo.png" alt={t.app.name} width={180} height={180} className="rounded-3xl" priority />
          <h1 className="max-w-2xl text-3xl font-bold leading-relaxed">{t.app.tagline}</h1>
          <p className="max-w-xl text-muted">{t.app.description}</p>
          <div className="flex gap-3">
            <Link href="/register" className="btn">{t.nav.register}</Link>
            <Link href="/login" className="btn-quiet">{t.nav.login}</Link>
          </div>
        </section>
        <h2 className="mb-4 text-xl font-bold">{t.home.how}</h2>
        <ol className="grid gap-3 sm:grid-cols-3">
          {[t.home.s1, t.home.s2, t.home.s3].map((step, i) => (
            <li key={step} className="card"><span className="mb-2 block text-2xl font-bold text-accent">{i + 1}</span>{step}</li>
          ))}
        </ol>
        <h2 className="mb-4 mt-12 text-xl font-bold">{x.featuresTitle}</h2>
        <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {x.features.map(([title, text]) => (
            <li key={title} className="card"><p className="mb-1 font-bold">{title}</p><p className="text-sm text-muted">{text}</p></li>
          ))}
        </ul>
        <h2 className="mb-4 mt-12 text-xl font-bold">{x.faqTitle}</h2>
        <div className="space-y-2">
          {x.faq.map(([q, a]) => (
            <details key={q} className="card"><summary className="cursor-pointer font-semibold">{q}</summary><p className="mt-2 text-muted">{a}</p></details>
          ))}
        </div>
        <section className="card my-12 text-center">
          <Link href="/register" className="btn">{x.cta}</Link>
        </section>
      </main>
    </>
  );
}
