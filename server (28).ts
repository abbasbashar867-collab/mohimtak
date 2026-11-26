import "server-only";
import { cookies } from "next/headers";
import { dictionaries, toLocale } from "./config";

export async function getI18n() {
  const store = await cookies();
  const locale = toLocale(store.get("locale")?.value);
  return { locale, t: dictionaries[locale], theme: store.get("theme")?.value === "light" ? "light" : "dark" };
}
