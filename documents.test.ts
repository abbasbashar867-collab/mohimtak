import { test } from "node:test";
import assert from "node:assert/strict";
import sharp from "sharp";
import { processDocumentImage } from "../../src/lib/images/process-document";
import { registerAccount, type RegistrationPorts } from "../../src/lib/registration/service";
import type { RegistrationInput } from "../../src/lib/validation/registration";

// صور اصطناعية فقط، لا مستندات حقيقية
function card(label: string, width = 1200, height = 760) {
  const lines = Array.from({ length: 9 }, (_, i) =>
    `<text x="60" y="${110 + i * 70}" font-size="44" font-family="sans-serif">${label} 0123456789 TEST ${i}</text>`).join("");
  return sharp(Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><rect width="100%" height="100%" fill="#e8e8e0"/>${lines}</svg>`));
}
const jpeg = (label: string) => card(label).jpeg().toBuffer();

test("image: clear card accepted and re-encoded without metadata", async () => {
  const withExif = await card("ID").withExif({ IFD0: { Copyright: "secret-location" } }).jpeg().toBuffer();
  assert.ok((await sharp(withExif).metadata()).exif);
  const r = await processDocumentImage(Buffer.concat([withExif, Buffer.from("<?php evil ?>")]));
  assert.ok(r.ok, JSON.stringify(r));
  assert.equal((await sharp(r.image.data).metadata()).exif, undefined);
  assert.ok(!r.image.data.includes("<?php"));
  assert.match(r.image.sha256, /^[0-9a-f]{64}$/);
});
test("image: PNG and WebP converted to JPEG", async () => {
  for (const buf of [await card("A").png().toBuffer(), await card("B").webp().toBuffer()]) {
    const r = await processDocumentImage(buf);
    assert.ok(r.ok);
    assert.equal((await sharp(r.image.data).metadata()).format, "jpeg");
  }
});
test("image: bad files rejected", async () => {
  const cases: [Buffer, string][] = [
    [Buffer.from("%PDF-1.7 not an image"), "not_image"],
    [Buffer.from("<svg xmlns='http://www.w3.org/2000/svg'/>"), "not_image"],
    [Buffer.concat([Buffer.from([0xff, 0xd8, 0xff]), Buffer.alloc(500, 7)]), "not_image"],
    [Buffer.alloc(2 * 1024 * 1024 + 1), "too_large"],
    [await card("small", 500, 300).jpeg().toBuffer(), "too_small"],
    [await card("blur").blur(25).jpeg().toBuffer(), "unreadable"],
    [await sharp({ create: { width: 1200, height: 800, channels: 3, background: "#000" } }).jpeg().toBuffer(), "unreadable"],
  ];
  for (const [buf, problem] of cases) assert.deepEqual(await processDocumentImage(buf), { ok: false, problem }, problem);
});

async function input(): Promise<RegistrationInput> {
  return {
    accountType: "company", phone: "+9647701234567", email: "c@test.invalid", password: "abc12345", referralCode: null,
    files: {
      national_id_front: new Blob([new Uint8Array(await jpeg("NATIONAL"))]),
      residence_card_front: new Blob([new Uint8Array(await jpeg("RESIDENCE"))]),
    },
  };
}
function fake(over: Partial<RegistrationPorts> = {}) {
  const log: string[] = [];
  const files = new Set<string>();
  const ports: RegistrationPorts = {
    async checkReferralCode() { return "valid"; },
    async isTaken() { return false; },
    async createUser() { log.push("createUser"); return { id: "u1" }; },
    async upload(p) { files.add(p); },
    async register({ documents }) { log.push(`register:${documents.length}`); return "ok"; },
    async removeFiles(p) { for (const x of p) files.delete(x); log.push("removeFiles"); },
    async deleteUser() { log.push("deleteUser"); },
    ...over,
  };
  return { ports, log, files };
}

test("service: success stores two private files under the user folder", async () => {
  const f = fake();
  assert.deepEqual(await registerAccount(await input(), f.ports), { ok: true });
  assert.equal(f.files.size, 2);
  assert.ok([...f.files].every((p) => p.startsWith("u1/")));
  assert.deepEqual(f.log, ["createUser", "register:2"]);
});
test("service: duplicate detected before anything is created", async () => {
  const f = fake({ async isTaken() { return true; } });
  assert.deepEqual(await registerAccount(await input(), f.ports), { ok: false, error: "duplicate" });
  assert.deepEqual(f.log, []);
});
test("service: any later failure removes files and user", async () => {
  let count = 0;
  const failures: [Partial<RegistrationPorts>, string][] = [
    [{ async register() { throw new Error("db down"); } }, "server"],
    [{ async register() { return "duplicate" as const; } }, "duplicate"],
    [{ async upload() { if (++count === 2) throw new Error("storage down"); } }, "server"],
  ];
  for (const [over, error] of failures) {
    const f = fake(over);
    assert.deepEqual(await registerAccount(await input(), f.ports), { ok: false, error });
    assert.equal(f.files.size, 0);
    assert.ok(f.log.includes("deleteUser"));
  }
});
test("service: invalid or identical images create nothing", async () => {
  const bad = await input();
  bad.files.residence_card_front = new Blob(["junk"]);
  const f = fake();
  assert.deepEqual(await registerAccount(bad, f.ports), { ok: false, error: "image", field: "residence_card_front", problem: "not_image" });
  const same = await input();
  same.files.residence_card_front = same.files.national_id_front;
  assert.deepEqual(await registerAccount(same, f.ports), { ok: false, error: "same_image" });
  assert.deepEqual(f.log, []);
});

test("service: bad referral code creates nothing; valid code reaches the database", async () => {
  for (const state of ["invalid", "inactive"] as const) {
    const f = fake({ async checkReferralCode() { return state; } });
    const r = await registerAccount({ ...(await input()), referralCode: "MHT-001" }, f.ports);
    assert.deepEqual(r, { ok: false, error: `referral_${state}` });
    assert.deepEqual(f.log, []);
  }
  let sent: string | null = null;
  const f = fake({ async register({ input }) { sent = input.referralCode; return "ok"; } });
  assert.ok((await registerAccount({ ...(await input()), referralCode: "MHT-001" }, f.ports)).ok);
  assert.equal(sent, "MHT-001");
});
test("service: code suspended between check and save rolls everything back", async () => {
  const f = fake({ async register() { return "referral_inactive" as const; } });
  const r = await registerAccount({ ...(await input()), referralCode: "MHT-001" }, f.ports);
  assert.deepEqual(r, { ok: false, error: "referral_inactive" });
  assert.equal(f.files.size, 0);
  assert.ok(f.log.includes("deleteUser"));
});
