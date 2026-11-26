import { normalizeIraqiPhone } from "./phone";

export const ACCOUNT_TYPES = ["client", "company"] as const;
export type AccountType = (typeof ACCOUNT_TYPES)[number];

export const DOCUMENT_TYPES = ["national_id_front", "residence_card_front"] as const;
export type DocumentType = (typeof DOCUMENT_TYPES)[number];

// الحقول المسموحة في طلب التسجيل، ولا شيء غيرها. referral_code اختياري.
export const REGISTRATION_FIELDS = ["account_type", ...DOCUMENT_TYPES, "phone", "email", "password", "referral_code"] as const;

export type ErrorCode =
  | "invalid_request" | "unexpected_field" | "account_type" | "phone" | "email" | "password"
  | "national_id_front" | "residence_card_front" | "same_image" | "referral_invalid";

export interface RegistrationInput {
  accountType: AccountType;
  phone: string;
  email: string;
  password: string;
  files: Record<DocumentType, Blob>;
  referralCode: string | null;
}

export function normalizeReferralCode(input: string): string | null {
  const code = input.trim().toUpperCase();
  return /^[A-Z0-9][A-Z0-9-]{2,19}$/.test(code) ? code : null;
}

export function normalizeEmail(input: string): string | null {
  const email = input.trim().toLowerCase();
  if (email.length > 254) return null;
  return /^[^\s@<>()"',;:]+@[^\s@<>()"',;:]+\.[a-z؀-ۿ]{2,}$/.test(email) ? email : null;
}

export function isStrongPassword(password: string): boolean {
  // 72 بايت هو الحد الأقصى لخوارزمية bcrypt
  const bytes = new TextEncoder().encode(password).length;
  return password.length >= 8 && bytes <= 72 && /\p{L}/u.test(password) && /\p{N}/u.test(password);
}

export function parseRegistration(
  form: FormData,
): { ok: true; value: RegistrationInput } | { ok: false; error: ErrorCode } {
  const allowed: readonly string[] = REGISTRATION_FIELDS;
  for (const key of new Set(form.keys())) {
    if (!allowed.includes(key)) return { ok: false, error: "unexpected_field" };
    if (form.getAll(key).length !== 1) return { ok: false, error: "invalid_request" };
  }
  const text = (key: string) => {
    const v = form.get(key);
    return typeof v === "string" ? v : "";
  };

  const accountType = ACCOUNT_TYPES.find((t) => t === text("account_type"));
  if (!accountType) return { ok: false, error: "account_type" };

  const files = {} as Record<DocumentType, Blob>;
  for (const type of DOCUMENT_TYPES) {
    const file = form.get(type);
    if (!(file instanceof Blob) || file.size === 0) return { ok: false, error: type };
    files[type] = file;
  }

  const phone = normalizeIraqiPhone(text("phone"));
  if (!phone) return { ok: false, error: "phone" };
  const email = normalizeEmail(text("email"));
  if (!email) return { ok: false, error: "email" };
  const password = text("password");
  if (!isStrongPassword(password)) return { ok: false, error: "password" };

  // وجود الحقل يعني أن المستخدم اختار "نعم"
  let referralCode: string | null = null;
  if (form.has("referral_code")) {
    referralCode = normalizeReferralCode(text("referral_code"));
    if (!referralCode) return { ok: false, error: "referral_invalid" };
  }

  return { ok: true, value: { accountType, phone, email, password, files, referralCode } };
}
