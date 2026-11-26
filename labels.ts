import type { Dict } from "./i18n/config";

export type ReferralStatus = "pending_verification" | "needs_review" | "approved" | "rejected";
export type CommissionStatus = "pending_review" | "approved" | "rejected" | "paid" | "reversed";
export type PayoutStatus = "pending" | "paid" | "rejected" | "reversed";
export const REFERRAL_STATUSES: ReferralStatus[] = ["pending_verification", "needs_review", "approved", "rejected"];

export const referralLabel = (t: Dict, s: ReferralStatus) => ({
  pending_verification: t.mk.pending_verification, needs_review: t.mk.needs_review, approved: t.mk.approved_r, rejected: t.mk.rejected_r,
})[s];
export const commissionLabel = (t: Dict, s: CommissionStatus) => ({
  pending_review: t.mk.pending_review, approved: t.mk.approved, rejected: t.mk.rejected_c, paid: t.mk.paid, reversed: t.mk.reversed,
})[s];
export const payoutLabel = (t: Dict, s: PayoutStatus) => ({
  pending: t.mk.pending, paid: t.mk.paid, rejected: t.mk.rejected_c, reversed: t.mk.reversed_p,
})[s];
export const milestonesFor = (type: "client" | "company") =>
  type === "client" ? (["card_purchased", "first_task_accepted"] as const) : (["card_purchased", "balance_topup", "first_campaign_started"] as const);
