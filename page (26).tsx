import Link from "next/link";
import { setNewPassword } from "@/actions/recovery";
import { SiteHeader } from "@/components/SiteHeader";
import { SubmitButton } from "@/components/SubmitButton";
import { getI18n } from "@/lib/i18n/server";
import { extras } from "@/lib/i18n/extra";

export const dynamic = "force-dynamic";

export default async function Reset({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { locale } = await getI18n();
  const x = extras[locale];
  const { error } = await searchParams;
  return (
    <>
      <SiteHeader />
      <main className="mx-auto max-w-sm px-4 py-10">
        <h1 className="mb-5 text-center text-2xl font-bold">{x.resetTitle}</h1>
        {error && <p role="alert" className="notice notice-bad mb-4">{error === "weak" ? x.weak : x.resetFailed}</p>}
        <form action={setNewPassword} className="card space-y-4">
          <label className="block"><span className="label">{x.newPassword}</span>
            <input name="password" type="password" minLength={8} autoComplete="new-password" required dir="ltr" className="field" /></label>
          <SubmitButton className="btn w-full">{x.save}</SubmitButton>
        </form>
        <p className="mt-4 text-center text-sm"><Link href="/forgot" className="text-accent">{x.forgotLink}</Link></p>
      </main>
    </>
  );
}
