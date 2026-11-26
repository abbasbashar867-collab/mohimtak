import { NextResponse, type NextRequest } from "next/server";
import { appUrl } from "@/lib/env";
import { toLocale } from "@/lib/i18n/config";
import { registerAccount, type RegistrationPorts } from "@/lib/registration/service";
import { clientIp, isSameOrigin } from "@/lib/security/request";
import { allowRequest, serviceClient } from "@/lib/supabase/admin";
import { parseRegistration } from "@/lib/validation/registration";

export const runtime = "nodejs";
const BUCKET = "identity-documents";
// أقل من حد 4.5MB لجسم الطلب في الاستضافات المجانية
const MAX_BODY = 4.4 * 1024 * 1024;
const fail = (status: number, body: Record<string, string>) => NextResponse.json(body, { status });

export async function POST(request: NextRequest) {
  try {
    if (!isSameOrigin(request.headers, appUrl())) return fail(403, { error: "invalid_request" });
    const length = Number(request.headers.get("content-length") ?? 0);
    if (length > MAX_BODY) return fail(413, { error: "too_large" });
    const ip = clientIp(request.headers, process.env.TRUSTED_IP_HEADER);
    // حد واسع لأن عدة أشخاص قد يستخدمون شبكة واحدة
    if (!(await allowRequest(`register:${ip}`, 15, 3600))) return fail(429, { error: "rate" });

    const parsed = parseRegistration(await request.formData());
    if (!parsed.ok) return fail(400, { error: parsed.error });

    const db = serviceClient();
    const userAgent = request.headers.get("user-agent")?.slice(0, 300) ?? null;
    const locale = toLocale(request.cookies.get("locale")?.value);
    const ports: RegistrationPorts = {
      async checkReferralCode(code) {
        const { data, error } = await db.rpc("check_referral_code", { p_code: code });
        if (error) throw new Error(error.message);
        return data as "valid" | "invalid" | "inactive";
      },
      async isTaken(email, phone) {
        for (const [column, value] of [["email", email], ["phone", phone]] as const) {
          const { data, error } = await db.from("profiles").select("id").eq(column, value).limit(1);
          if (error) throw new Error(error.message);
          if (data.length) return true;
        }
        return false;
      },
      async createUser(email, password) {
        const { data, error } = await db.auth.admin.createUser({ email, password, email_confirm: true });
        if (error?.code === "email_exists") return "duplicate";
        if (error || !data.user) throw new Error(error?.message ?? "createUser failed");
        return { id: data.user.id };
      },
      async upload(path, data) {
        const { error } = await db.storage.from(BUCKET).upload(path, data, { contentType: "image/jpeg", upsert: false });
        if (error) throw new Error(error.message);
      },
      async register({ userId, input, documents }) {
        const { error } = await db.rpc("register_account_referred", {
          p_user_id: userId, p_account_type: input.accountType, p_phone: input.phone, p_email: input.email,
          p_locale: locale, p_documents: documents, p_referral_code: input.referralCode, p_ip: ip, p_user_agent: userAgent,
        });
        if (!error) return "ok";
        if (error.code === "23505") return "duplicate";
        if (error.code === "MH001") return "referral_invalid";
        if (error.code === "MH002") return "referral_inactive";
        throw new Error(error.message);
      },
      async removeFiles(paths) {
        const { error } = await db.storage.from(BUCKET).remove(paths);
        if (error) throw new Error(error.message);
      },
      async deleteUser(id) {
        const { error } = await db.auth.admin.deleteUser(id);
        if (error) throw new Error(error.message);
      },
    };

    const result = await registerAccount(parsed.value, ports);
    if (result.ok) return NextResponse.json({ ok: true }, { status: 201 });
    if (result.error === "image") return fail(400, { error: result.problem, field: result.field });
    return fail(result.error === "server" ? 500 : result.error === "duplicate" ? 409 : 400, { error: result.error });
  } catch (error) {
    console.error("register route", error instanceof Error ? error.message : "unknown");
    return fail(500, { error: "server" });
  }
}
