import { getI18n } from "@/lib/i18n/server";

export async function Flash({ ok, err }: { ok?: string; err?: string }) {
  const { t } = await getI18n();
  if (ok) return <p role="status" className="notice notice-ok">{t.admin.done}</p>;
  if (!err) return null;
  const known = Object.hasOwn(t.dbErrors, err) ? t.dbErrors[err as keyof typeof t.dbErrors] : t.admin.failed;
  return <p role="alert" className="notice notice-bad">{known}</p>;
}
