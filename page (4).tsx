import { Section } from "@/components/AdminUI";
import { CommissionList, PayoutList, type Commission, type Payout } from "@/components/CommissionLists";
import { Flash } from "@/components/Flash";
import { requireAdmin } from "@/lib/auth/session";
import { getI18n } from "@/lib/i18n/server";

export default async function Payouts({ searchParams }: { searchParams: Promise<{ ok?: string; err?: string }> }) {
  const { db } = await requireAdmin();
  const { t } = await getI18n();
  const [commissions, payouts] = await Promise.all([
    db.from("commissions").select("*, profiles(verified_name), marketers(name)").eq("status", "pending_review").order("created_at").limit(200),
    db.from("marketer_payouts").select("*, marketers(name)").order("requested_at", { ascending: false }).limit(300),
  ]);
  if (commissions.error || payouts.error) throw new Error("could not load payouts");
  return (
    <>
      <h1 className="mb-4 text-2xl font-bold">{t.admin.payouts}</h1>
      <Flash {...await searchParams} />
      <Section title={t.mk.commission_pending_iqd}><CommissionList t={t} rows={commissions.data as unknown as Commission[]} back="/admin/payouts" /></Section>
      <Section title={t.mk.payouts}><PayoutList t={t} rows={payouts.data as unknown as Payout[]} back="/admin/payouts" /></Section>
    </>
  );
}
