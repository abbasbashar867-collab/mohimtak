import { ar, type Dict } from "./ar";
import { ckb } from "./ckb";
import { en } from "./en";

export const locales = ["ar", "en", "ckb"] as const;
export type Locale = (typeof locales)[number];
export const localeNames: Record<Locale, string> = { ar: "العربية", en: "English", ckb: "کوردی" };
export const dictionaries: Record<Locale, Dict> = { ar, en, ckb };
export const toLocale = (v: string | undefined): Locale => locales.find((l) => l === v) ?? "ar";
export const dirOf = (l: Locale) => (l === "en" ? "ltr" : "rtl");
export type { Dict };
