import type { Metadata, Viewport } from "next";
import { Noto_Sans_Arabic } from "next/font/google";
import type { ReactNode } from "react";
import { dirOf } from "@/lib/i18n/config";
import { getI18n } from "@/lib/i18n/server";
import { whatsappLink } from "@/lib/format";
import { supportPhone } from "@/lib/support";
import Link from "next/link";
import "./globals.css";
import { appUrl } from "@/lib/env";

export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#2563eb" };

const font = Noto_Sans_Arabic({ subsets: ["arabic", "latin"], variable: "--font-arabic" });

export async function generateMetadata(): Promise<Metadata> {
  const { t } = await getI18n();
  return {
    metadataBase: new URL(appUrl()),
    title: { default: `${t.app.name} | MOHIMTAK`, template: `%s | ${t.app.name}` },
    description: t.app.description,
    openGraph: { title: `${t.app.name} | MOHIMTAK`, description: t.app.description, type: "website", images: ["/brand/icon-512.png"] },
    twitter: { card: "summary", title: t.app.name, description: t.app.description },
  };
}

export default async function RootLayout({ children }: { children: ReactNode }) {
  const { t, locale, theme } = await getI18n();
  const phone = await supportPhone();
  return (
    <html lang={locale} dir={dirOf(locale)} className={`${font.variable} ${theme === "dark" ? "dark" : ""}`}>
      <body className="min-h-screen font-sans antialiased">
        {children}
        <footer className="mx-auto flex max-w-5xl flex-wrap gap-4 px-4 pb-24 pt-8 text-sm text-muted">
          <Link href="/legal/terms">{t.nav.terms}</Link>
          <Link href="/legal/privacy">{t.nav.privacy}</Link>
        </footer>
        <a href={whatsappLink(phone)} target="_blank" rel="noopener noreferrer" className="fixed bottom-4 end-4 rounded-full bg-green-600 px-5 py-3 font-semibold text-white shadow-lg">
            {t.nav.whatsapp}
        </a>
      </body>
    </html>
  );
}
