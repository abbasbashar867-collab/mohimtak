"use server";
import { redirect } from "next/navigation";
import { requireAdmin } from "@/lib/auth/session";
import { normalizeIraqiPhone } from "@/lib/validation/phone";

const text = (f: FormData, k: string) => String(f.get(k) ?? "").trim();
const optional = (f: FormData, k: string) => text(f, k) || null;

/** صفحة الرجوع: مسارات الإدارة فقط. */
function back(form: FormData, result: string): never {
  const to = text(form, "back");
  const path = /^\/admin(\/[a-z0-9\-]+)*$/i.test(to) ? to : "/admin";
  redirect(`${path}?${result}`);
}

/** كل عملية تنفذ بجلسة المدير؛ قاعدة البيانات تتحقق من الصلاحية والحالة. */
async function run(form: FormData, fn: string, args: Record<string, unknown>): Promise<never> {
  const { db } = await requireAdmin();
  const { error } = await db.rpc(fn, args);
  back(form, error ? `err=${encodeURIComponent(error.code ?? "unknown")}` : "ok=1");
}

export async function reviewRegistration(f: FormData) {
  await run(f, "review_registration", {
    p_profile_id: text(f, "id"), p_decision: text(f, "decision"), p_reason: optional(f, "reason"),
    p_verified_name: optional(f, "verified_name"), p_age_confirmed: f.get("age") === "on",
    p_documents_confirmed: f.get("docs") === "on",
  });
}
export async function setAccountStatus(f: FormData) {
  await run(f, "set_account_status", { p_profile_id: text(f, "id"), p_new_status: text(f, "status"), p_reason: text(f, "reason") });
}

const marketerArgs = (f: FormData) => ({
  p_name: text(f, "name"), p_phone: normalizeIraqiPhone(text(f, "phone")) ?? text(f, "phone"),
  p_email: text(f, "email"), p_code: text(f, "code"),
});
export async function createMarketer(f: FormData) {
  await run(f, "admin_create_marketer", marketerArgs(f));
}
export async function updateMarketer(f: FormData) {
  await run(f, "admin_update_marketer", {
    p_id: text(f, "id"), ...marketerArgs(f), p_status: text(f, "status"), p_reason: text(f, "reason"),
  });
}
export async function linkReferral(f: FormData) {
  await run(f, "admin_link_referral", {
    p_profile: text(f, "profile"), p_marketer: text(f, "marketer"), p_reason: text(f, "reason"),
    p_exception_reason: optional(f, "exception"),
  });
}
export async function recordVerification(f: FormData) {
  const contact = text(f, "first_contact");
  await run(f, "admin_record_verification", {
    p_referral: text(f, "id"), p_first_contact_at: contact ? `${contact}:00+03:00` : null,
    p_confirmation: text(f, "confirmation"), p_channel: text(f, "channel"), p_notes: text(f, "notes"),
  });
}
export async function decideReferral(f: FormData) {
  await run(f, "admin_decide_referral", { p_referral: text(f, "id"), p_decision: text(f, "decision"), p_reason: text(f, "reason") });
}
export async function evaluateCommissions(f: FormData) {
  await run(f, "admin_evaluate_commissions", { p_marketer: text(f, "id") });
}
export async function decideCommission(f: FormData) {
  await run(f, "admin_decide_commission", { p_commission: text(f, "id"), p_decision: text(f, "decision"), p_reason: text(f, "reason") });
}
export async function createPayout(f: FormData) {
  await run(f, "admin_create_payout", { p_marketer: text(f, "id"), p_commissions: f.getAll("commission").map(String) });
}
export async function decidePayout(f: FormData) {
  const amount = text(f, "amount");
  await run(f, "admin_decide_payout", {
    p_payout: text(f, "id"), p_decision: text(f, "decision"), p_amount: /^\d+$/.test(amount) ? Number(amount) : null,
    p_paid_on: optional(f, "paid_on"), p_method: optional(f, "method"), p_reference: optional(f, "reference"),
    p_reason: optional(f, "reason"),
  });
}
export async function updateReferralSettings(f: FormData) {
  // النسب تُدخل كنسبة مئوية وتُخزن بنقاط الأساس
  const bps = (k: string) => Math.round(Number(text(f, k)) * 100) || 0;
  await run(f, "admin_update_referral_settings", {
    p_client_bps: bps("client_rate"), p_company_bps: bps("company_rate"), p_client_basis: ["card_fee"],
    p_company_basis: f.getAll("company_basis").map(String), p_pairing_mode: text(f, "pairing"), p_reason: text(f, "reason"),
  });
}
