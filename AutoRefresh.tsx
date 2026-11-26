"use client";
import { useRouter } from "next/navigation";
import { useEffect } from "react";

/** ينقل صاحب الحساب إلى واجهته فور موافقة الإدارة. */
export function AutoRefresh({ seconds }: { seconds: number }) {
  const router = useRouter();
  useEffect(() => {
    const timer = setInterval(() => router.refresh(), seconds * 1000);
    return () => clearInterval(timer);
  }, [router, seconds]);
  return null;
}
