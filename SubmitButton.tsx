"use client";
import { useFormStatus } from "react-dom";
import type { ReactNode } from "react";

/** يمنع الإرسال المكرر. */
export function SubmitButton({ children, className = "btn", name, value }: { children: ReactNode; className?: string; name?: string; value?: string }) {
  const { pending } = useFormStatus();
  return <button type="submit" name={name} value={value} disabled={pending} className={className}>{children}</button>;
}
