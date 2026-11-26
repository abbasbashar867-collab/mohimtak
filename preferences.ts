"use server";
import { cookies } from "next/headers";
import { revalidatePath } from "next/cache";
import { toLocale } from "@/lib/i18n/config";

const options = { path: "/", maxAge: 31536000, sameSite: "lax" as const };

export async function setLocale(form: FormData) {
  (await cookies()).set("locale", toLocale(String(form.get("locale"))), options);
  revalidatePath("/", "layout");
}
export async function setTheme(form: FormData) {
  (await cookies()).set("theme", form.get("theme") === "light" ? "light" : "dark", options);
  revalidatePath("/", "layout");
}
