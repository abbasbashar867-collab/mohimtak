import Link from "next/link";
import { requestReset } from "@/actions/recovery";
import { SiteHeader } from "@/components/SiteHeader";
import { SubmitButton } from "@/components/SubmitButton";
import { getI18n } from "@/lib/i18n/server";
import { extras } from "@/lib/i18n/extra";

export default async function Forgot({ searchParams }: { searchParams: Promise<{ sent?: string }> }) {
  const { t, locale } = await getI18n();
  const x = extras[locale];
  const { sent } = await searchParams;
  return (
    <>
      <SiteHeader />
      <main className="mx-auto max-w-sm px-4 py-10">
        <h1 className="mb-2 text-center text-2xl font-bold">{x.forgotTitle}</h1>
        <p className="mb-5 text-center text-muted">{x.forgotHint}</p>
        {sent && <p role="status" className="notice notice-ok mb-4">{x.sent}</p>}
        <form action={requestReset} className="card space-y-4">
          <label className="block"><span className="label">{t.register.email}</span>
            <input name="email" type="email" autoComplete="email" required dir="ltr" className="field" /></label>
          <SubmitButton className="btn w-full">{x.send}</SubmitButton>
        </form>
        <p className="mt-4 text-center text-sm"><Link href="/login" className="text-accent">{x.back}</Link></p>
      </main>
    </>
  );
}
