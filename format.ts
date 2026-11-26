/** يعزل النص اللاتيني حتى لا يتبعثر ترتيبه داخل الواجهة من اليمين لليسار */
const ltr = (s: string) => `\u2066${s}\u2069`;
export const iqd = (n: number | null | undefined) => ltr(`${Number(n ?? 0).toLocaleString("en-US")} IQD`);
export const dateTime = (v: string | null | undefined) =>
  v ? ltr(new Intl.DateTimeFormat("en-GB", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Baghdad" }).format(new Date(v))) : "—";
/** حدود يوم بتوقيت بغداد من حقل <input type="date"> */
export function dayStart(value: string | undefined, addDays = 0): string | null {
  if (!value || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const d = new Date(`${value}T00:00:00+03:00`);
  if (Number.isNaN(d.getTime())) return null;
  d.setUTCDate(d.getUTCDate() + addDays);
  return d.toISOString();
}
export const whatsappLink = (phone: string) => `https://wa.me/${phone.replace(/\D/g, "")}`;
/** يزيل الرموز التي تغير معنى مرشحات PostgREST. يُستخدم دائماً داخل علامتي تنصيص. */
export function searchFilter(q: string | undefined, columns: string[]): string | null {
  let term = (q ?? "").replace(/[^\p{L}\p{N} @+_.\-]/gu, "").trim().slice(0, 60);
  if (/^07\d+$/.test(term)) term = term.slice(1);
  return term ? columns.map((c) => `${c}.ilike."%${term}%"`).join(",") : null;
}
