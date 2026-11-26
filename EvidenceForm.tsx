"use client";
import { useState } from "react";
import { ImageInput } from "./ImageInput";

export function EvidenceForm({ referralId, labels }: { referralId: string; labels: { evidence: string; choose: string; hint: string; preparing: string; failed: string; upload: string } }) {
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  return (
    <form action={`/api/admin/referrals/${referralId}/evidence`} method="post" encType="multipart/form-data" onSubmit={() => setSent(true)} className="space-y-3">
      <ImageInput name="evidence" label={labels.evidence} choose={labels.choose} hint={labels.hint} preparing={labels.preparing} failed={labels.failed} onBusy={setBusy} />
      <button className="btn" disabled={busy || sent}>{labels.upload}</button>
    </form>
  );
}
