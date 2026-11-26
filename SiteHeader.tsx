import Image from "next/image";
import Link from "next/link";
import { logout } from "@/actions/auth";
import { setLocale, setTheme } from "@/actions/preferences";
import { localeNames, locales } from "@/lib/i18n/config";
import { getI18n } from "@/lib/i18n/server";

export async function SiteHeader({ signedIn = false }: { signedIn?: boolean }) {
  const { t, locale, theme } = await getI18n();
  return (
    <header className="border-b border-line">
      <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-3 px-4 py-3">
        <Link href="/" className="flex items-center gap-2 font-bold">
          <Image src="/brand/logo.png" alt={t.app.name} width={44} height={44} className="rounded-xl" priority />
          <span>{t.app.name}</span>
        </Link>
        <nav className="flex flex-wrap items-center gap-2 text-sm">
          <form action={setLocale} className="flex gap-1" aria-label={t.nav.language}>
            {locales.map((l) => (
              <button key={l} name="locale" value={l} className={l === locale ? "chip chip-on" : "chip"}>{localeNames[l]}</button>
            ))}
          </form>
          <form action={setTheme}>
            <button name="theme" value={theme === "dark" ? "light" : "dark"} className="chip">{theme === "dark" ? t.nav.light : t.nav.dark}</button>
          </form>
          {signedIn ? (
            <form action={logout}><button className="chip">{t.nav.logout}</button></form>
          ) : (
            <><Link href="/login" className="chip">{t.nav.login}</Link><Link href="/register" className="chip chip-on">{t.nav.register}</Link></>
          )}
        </nav>
      </div>
    </header>
  );
}
