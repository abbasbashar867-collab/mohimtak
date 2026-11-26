import { test } from "node:test";
import assert from "node:assert/strict";
import { normalizeIraqiPhone } from "../../src/lib/validation/phone";
import { isStrongPassword, parseRegistration } from "../../src/lib/validation/registration";
import { destinationFor } from "../../src/lib/auth/routing";
import { isSameOrigin, clientIp } from "../../src/lib/security/request";

const file = () => new Blob([new Uint8Array([1, 2, 3])]);
function form(over: Record<string, string | Blob | null> = {}) {
  const base: Record<string, string | Blob | null> = {
    account_type: "client", phone: "0770 123 4567", email: " User@Test.Invalid ",
    password: "abc12345", national_id_front: file(), residence_card_front: file(), ...over,
  };
  const f = new FormData();
  for (const [k, v] of Object.entries(base)) if (v !== null) f.append(k, v);
  return f;
}

test("phone: all accepted spellings normalize to one value", () => {
  for (const p of ["07701234567", "+9647701234567", "009647701234567", "9647701234567", "٠٧٧٠١٢٣٤٥٦٧", "۰۷۷۰۱۲۳۴۵۶۷", "0770-123-4567"]) {
    assert.equal(normalizeIraqiPhone(p), "+9647701234567", p);
  }
  assert.equal(normalizeIraqiPhone("07816849259"), "+9647816849259");
});
test("phone: invalid numbers rejected", () => {
  for (const p of ["", "0770123456", "077012345678", "06701234567", "+15551234567", "0770abc4567"]) {
    assert.equal(normalizeIraqiPhone(p), null, p);
  }
});
test("password rules", () => {
  assert.ok(isStrongPassword("abc12345"));
  assert.ok(isStrongPassword("كلمةسر١٢٣"));
  for (const p of ["abc1234", "abcdefgh", "12345678", "a1".repeat(37)]) assert.ok(!isStrongPassword(p), p);
});
test("registration: identical form for client and company", () => {
  for (const account_type of ["client", "company"]) {
    const r = parseRegistration(form({ account_type }));
    assert.ok(r.ok);
    assert.equal(r.value.email, "user@test.invalid");
    assert.equal(r.value.phone, "+9647701234567");
  }
});
test("registration: each required field enforced", () => {
  for (const field of ["account_type", "phone", "email", "password", "national_id_front", "residence_card_front"] as const) {
    const r = parseRegistration(form({ [field]: null }));
    assert.deepEqual(r, { ok: false, error: field });
  }
  assert.deepEqual(parseRegistration(form({ account_type: "admin" })), { ok: false, error: "account_type" });
  assert.deepEqual(parseRegistration(form({ national_id_front: "text" })), { ok: false, error: "national_id_front" });
});
test("registration: extra or removed fields refused", () => {
  for (const extra of ["full_name", "birth_date", "address", "selfie", "national_id_back", "status", "role"]) {
    assert.deepEqual(parseRegistration(form({ [extra]: "x" })), { ok: false, error: "unexpected_field" }, extra);
  }
  const twice = form();
  twice.append("account_type", "company");
  assert.deepEqual(parseRegistration(twice), { ok: false, error: "invalid_request" });
});
test("routing: only approved accounts reach a portal", () => {
  for (const status of ["pending", "rejected", "suspended", "banned"] as const) {
    assert.equal(destinationFor({ isAdmin: false, profile: { account_type: "client", status } }), "/account/status");
  }
  assert.equal(destinationFor({ isAdmin: false, profile: { account_type: "client", status: "approved" } }), "/client");
  assert.equal(destinationFor({ isAdmin: false, profile: { account_type: "company", status: "approved" } }), "/company");
  assert.equal(destinationFor({ isAdmin: false, profile: null }), "/account/status");
  assert.equal(destinationFor({ isAdmin: true, profile: null }), "/admin");
});
test("csrf origin check and ip parsing", () => {
  const app = "https://example.test";
  assert.ok(isSameOrigin(new Headers({ origin: app }), app));
  assert.ok(!isSameOrigin(new Headers({ origin: "https://evil.test" }), app));
  assert.ok(!isSameOrigin(new Headers(), app));
  assert.ok(!isSameOrigin(new Headers({ origin: "null" }), app));
  assert.equal(clientIp(new Headers({ "x-forwarded-for": "1.2.3.4, 5.6.7.8" })), "1.2.3.4");
});

test("registration: referral code optional, normalized, format checked", () => {
  const none = parseRegistration(form());
  assert.ok(none.ok && none.value.referralCode === null);
  const yes = parseRegistration(form({ referral_code: " mht-001 " }));
  assert.ok(yes.ok && yes.value.referralCode === "MHT-001");
  for (const referral_code of ["", "a b", "x", "'; drop table"]) {
    assert.deepEqual(parseRegistration(form({ referral_code })), { ok: false, error: "referral_invalid" }, referral_code);
  }
});
