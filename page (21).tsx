import Image from "next/image";
import { redirect } from "next/navigation";
import { login } from "@/actions/auth";
import { SiteHeader } from "@/components/SiteHeader";
import { SubmitButton } from "@/components/SubmitButton";
import { destinationFor } from "@/lib/auth/routing";
import { getViewer } from "@/lib/auth/session";
import { getI18n } from "@/lib/i18n/server";
import Link from "next/link";
import { extras } from "@/lib/i18n/extra";

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string; registered?: string; reset?: string }> }) {
  const viewer = await getViewer();
  if (viewer) redirect(destinationFor(viewer));
  const { t, locale } = await getI18n();
  const x = extras[locale];
  const query = await searchParams;
  const error = query.error === "rate" ? t.errors.rate : query.error ? t.errors.credentials : null;
  return (
    <>
      <SiteHeader />
      <main className="mx-auto max-w-sm px-4 py-10">
        <Image src="/brand/logo.png" alt={t.app.name} width={96} height={96} className="mx-auto mb-5 rounded-2xl" />
        <h1 className="mb-5 text-center text-2xl font-bold">{t.nav.login}</h1>
        {query.registered && <p role="status" className="notice notice-ok mb-4">{t.register.done}</p>}
        {query.reset && <p role="status" className="notice notice-ok mb-4">{x.resetDone}</p>}
        <form action={login} className="card space-y-4">
          <label className="block"><span className="label">{t.register.email}</span>
            <input name="email" type="email" autoComplete="email" required dir="ltr" className="field" /></label>
          <label className="block"><span className="label">{t.register.password}</span>
            <input name="password" type="password" autoComplete="current-password" required dir="ltr" className="field" /></label>
          {error && <p role="alert" className="notice notice-bad">{error}</p>}
          <SubmitButton className="btn w-full">{t.nav.login}</SubmitButton>
        </form>
        <p className="mt-4 text-center text-sm"><Link href="/forgot" className="text-accent">{x.forgotLink}</Link></p>
      </main>
    </>
  );
}
