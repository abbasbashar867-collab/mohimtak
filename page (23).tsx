import { notFound } from "next/navigation";
import { createSuperAdmin } from "@/actions/setup";
import { SubmitButton } from "@/components/SubmitButton";
import { getI18n } from "@/lib/i18n/server";

export const dynamic = "force-dynamic";

/** تظهر فقط ما دام SETUP_TOKEN موجوداً في إعدادات الخادم. */
export default async function SetupPage({ searchParams }: { searchParams: Promise<{ result?: string }> }) {
  if ((process.env.SETUP_TOKEN ?? "").length < 24) notFound();
  const { t } = await getI18n();
  const { result } = await searchParams;
  return (
    <main className="mx-auto max-w-sm px-4 py-10">
      <h1 className="mb-5 text-2xl font-bold">{t.setup.title}</h1>
      {result === "done" && <p role="status" className="notice notice-ok mb-4">{t.setup.done}</p>}
      {result === "failed" && <p role="alert" className="notice notice-bad mb-4">{t.setup.failed}</p>}
      <form action={createSuperAdmin} className="card space-y-4">
        <label className="block"><span className="label">{t.setup.token}</span><input name="token" type="password" required dir="ltr" className="field" /></label>
        <label className="block"><span className="label">{t.register.email}</span><input name="email" type="email" required dir="ltr" className="field" /></label>
        <label className="block"><span className="label">{t.setup.password}</span><input name="password" type="password" minLength={14} autoComplete="new-password" required dir="ltr" className="field" /></label>
        <SubmitButton className="btn w-full">{t.setup.create}</SubmitButton>
      </form>
    </main>
  );
}
