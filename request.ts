/** حماية CSRF: يجب أن يأتي الطلب المغيِّر للبيانات من الموقع نفسه (APP_URL أو نفس المضيف). */
export function isSameOrigin(headers: Headers, appUrl: string): boolean {
  const origin = headers.get("origin");
  if (!origin) return false;
  try {
    const o = new URL(origin);
    if (o.origin === new URL(appUrl).origin) return true;
    const host = (headers.get("x-forwarded-host") ?? headers.get("host") ?? "").split(",")[0].trim();
    return Boolean(host) && o.host === host;
  } catch {
    return false;
  }
}

export function clientIp(headers: Headers, trustedHeader = "x-forwarded-for"): string {
  return (
    headers.get(trustedHeader)?.split(",")[0]?.trim().slice(0, 64) ||
    headers.get("x-nf-client-connection-ip")?.slice(0, 64) ||
    headers.get("x-forwarded-for")?.split(",")[0]?.trim().slice(0, 64) ||
    "unknown"
  );
}
