import { updateReferralSettings } from "@/actions/admin";
import { ActionForm, Field, Select } from "@/components/AdminUI";
import { Flash } from "@/components/Flash";
import { requireAdmin } from "@/lib/auth/session";
import { getI18n } from "@/lib/i18n/server";

export default async function ReferralSettings({ searchParams }: { searchParams: Promise<{ ok?: string; err?: string }> }) {
  const { db } = await requireAdmin();
  const { t } = await getI18n();
  const { data, error } = await db.from("settings").select("key, value").like("key", "referral.%");
  if (error) throw new Error("could not load settings");
  const s = Object.fromEntries((data as unknown as { key: string; value: unknown }[]).map((r) => [r.key.replace("referral.", ""), r.value]));
  const basis = s.company_basis as string[];
  return (
    <>
      <h1 className="mb-4 text-2xl font-bold">{t.admin.settings}</h1>
      <Flash {...await searchParams} />
      <div className="card mt-3">
        <p className="text-sm text-muted">{t.mk.clientBasis}</p>
        <ActionForm action={updateReferralSettings} back="/admin/referral-settings" reasonLabel={t.admin.reason} button={t.admin.save}>
          <Field label={t.mk.clientRate} name="client_rate" type="text" defaultValue={String(Number(s.client_rate_bps) / 100)} dir="ltr" />
          <Field label={t.mk.companyRate} name="company_rate" type="text" defaultValue={String(Number(s.company_rate_bps) / 100)} dir="ltr" />
          <fieldset className="w-full"><legend className="label">{t.mk.companyBasis}</legend>
            {(["card_fee", "topup_platform_share", "topup_gross"] as const).map((b) => (
              <label key={b} className="flex items-center gap-2"><input type="checkbox" name="company_basis" value={b} defaultChecked={basis.includes(b)} /> {t.mk[b]}</label>
            ))}
          </fieldset>
          <Select label={t.mk.pairing} name="pairing" defaultValue={String(s.pairing_mode)} options={[["pair", t.mk.pair], ["unlock", t.mk.unlock]]} />
        </ActionForm>
      </div>
    </>
  );
}
