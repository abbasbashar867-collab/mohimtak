import { SiteHeader } from "@/components/SiteHeader";
import { getI18n } from "@/lib/i18n/server";
import { RegisterForm } from "./RegisterForm";

export default async function RegisterPage() {
  const { t } = await getI18n();
  return (
    <>
      <SiteHeader />
      <main className="mx-auto max-w-lg px-4 py-8">
        <h1 className="mb-5 text-2xl font-bold">{t.register.title}</h1>
        <RegisterForm labels={t.register} errors={t.errors} loginLabel={t.nav.login} />
      </main>
    </>
  );
}
