import Link from "next/link";
import type { ReactNode } from "react";
import { SiteHeader } from "@/components/SiteHeader";
import { requireAdmin } from "@/lib/auth/session";
import { getI18n } from "@/lib/i18n/server";

export default async function AdminLayout({ children }: { children: ReactNode }) {
  await requireAdmin();
  const { t } = await getI18n();
  const links = [
    ["/admin", t.admin.accounts], ["/admin/marketers", t.admin.marketers], ["/admin/payouts", t.admin.payouts],
    ["/admin/referral-settings", t.admin.settings], ["/admin/audit", t.admin.audit],
  ] as const;
  return (
    <>
      <SiteHeader signedIn />
      <div className="mx-auto max-w-5xl px-4 py-5">
        <p className="mb-2 text-sm text-muted">{t.admin.title}</p>
        <nav className="mb-5 flex flex-wrap gap-2">{links.map(([href, label]) => <Link key={href} href={href} className="chip">{label}</Link>)}</nav>
        {children}
      </div>
    </>
  );
}
