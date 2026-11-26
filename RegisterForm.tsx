"use client";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { ImageInput } from "@/components/ImageInput";
import type { Dict } from "@/lib/i18n/config";

type CodeState = "valid" | "invalid" | "inactive" | "rate" | "server" | null;

export function RegisterForm({ labels: l, errors, loginLabel }: { labels: Dict["register"]; errors: Dict["errors"]; loginLabel: string }) {
  const router = useRouter();
  const [busyImages, setBusy] = useState(0);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [referred, setReferred] = useState(false);
  const [code, setCode] = useState("");
  const [codeState, setCodeState] = useState<CodeState>(null);
  const message = (key: string) => errors[key as keyof Dict["errors"]] ?? errors.server;
  const onBusy = (busy: boolean) => setBusy((n) => n + (busy ? 1 : -1));

  async function checkCode() {
    setCodeState(null);
    try {
      const res = await fetch("/api/referral-code", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ code }) });
      const body = await res.json();
      setCodeState(res.ok ? body.state : res.status === 429 ? "rate" : "server");
    } catch {
      setCodeState("server");
    }
  }
  const codeMessage = codeState && { valid: l.codeValid, invalid: l.codeInvalid, inactive: l.codeInactive, rate: errors.rate, server: errors.server }[codeState];

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setSending(true);
    const data = new FormData(event.currentTarget);
    data.delete("referred");
    try {
      const res = await fetch("/api/register", { method: "POST", body: data });
      if (res.ok) {
        router.push("/login?registered=1");
        return;
      }
      const body = await res.json().catch(() => ({ error: "server" }));
      const prefix = body.field === "national_id_front" ? `${l.nationalId}: ` : body.field === "residence_card_front" ? `${l.residence}: ` : "";
      setError(prefix + message(body.error));
    } catch {
      setError(errors.server);
    }
    setSending(false);
  }

  return (
    <form onSubmit={submit} className="card space-y-4">
      <fieldset>
        <legend className="label">{l.type}</legend>
        <div className="grid grid-cols-2 gap-3">
          {(["client", "company"] as const).map((type) => (
            <label key={type} className="flex cursor-pointer items-center gap-2 rounded-lg border border-line bg-bg p-3 has-[:checked]:border-accent">
              <input type="radio" name="account_type" value={type} required /> {l[type]}
            </label>
          ))}
        </div>
      </fieldset>
      <ImageInput name="national_id_front" label={l.nationalId} choose={l.choose} hint={l.imageHint} preparing={l.preparing} failed={errors.not_image} onBusy={onBusy} />
      <ImageInput name="residence_card_front" label={l.residence} choose={l.choose} hint={l.imageHint} preparing={l.preparing} failed={errors.not_image} onBusy={onBusy} />
      <label className="block"><span className="label">{l.phone}</span>
        <input name="phone" type="tel" inputMode="tel" autoComplete="tel" required dir="ltr" placeholder="07XXXXXXXXX" className="field" /></label>
      <label className="block"><span className="label">{l.email}</span>
        <input name="email" type="email" autoComplete="email" required dir="ltr" className="field" /></label>
      <label className="block"><span className="label">{l.password}</span>
        <input name="password" type="password" autoComplete="new-password" minLength={8} required dir="ltr" className="field" />
        <span className="mt-1 block text-sm text-muted">{l.passwordHint}</span></label>

      <fieldset>
        <legend className="label">{l.referralQ}</legend>
        <div className="flex gap-5">
          <label className="flex items-center gap-2"><input type="radio" name="referred" checked={referred} onChange={() => setReferred(true)} /> {l.yes}</label>
          <label className="flex items-center gap-2"><input type="radio" name="referred" checked={!referred} onChange={() => { setReferred(false); setCode(""); setCodeState(null); }} /> {l.no}</label>
        </div>
        {referred && (
          <div className="mt-3">
            <label className="label" htmlFor="referral_code">{l.code}</label>
            <div className="flex gap-2">
              <input id="referral_code" name="referral_code" required dir="ltr" maxLength={20} value={code} onChange={(e) => { setCode(e.target.value); setCodeState(null); }} className="field" />
              <button type="button" onClick={checkCode} disabled={!code.trim()} className="btn-quiet">{l.check}</button>
            </div>
            {codeMessage && <p role="status" className={`notice mt-2 ${codeState === "valid" ? "notice-ok" : "notice-bad"}`}>{codeMessage}</p>}
          </div>
        )}
      </fieldset>

      <p className="text-sm text-muted">{l.consent}</p>
      {error && <p role="alert" className="notice notice-bad">{error}</p>}
      <button className="btn w-full" disabled={sending || busyImages > 0}>{sending ? l.sending : l.submit}</button>
      <p className="text-center text-sm">{l.haveAccount} <Link href="/login" className="text-accent">{loginLabel}</Link></p>
    </form>
  );
}
