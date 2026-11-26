import { randomUUID } from "node:crypto";
import { processDocumentImage, type ImageProblem, type ProcessedImage } from "../images/process-document";
import { DOCUMENT_TYPES, type DocumentType, type RegistrationInput } from "../validation/registration";

export interface DocumentRecord {
  doc_type: DocumentType;
  storage_path: string;
  sha256: string;
  mime_type: "image/jpeg";
  size_bytes: number;
  width: number;
  height: number;
}

/** المنافذ الخارجية، مفصولة لكي تُختبر خطوات التسجيل والتراجع دون Supabase. */
export type CodeState = "valid" | "invalid" | "inactive";

export interface RegistrationPorts {
  checkReferralCode(code: string): Promise<CodeState>;
  isTaken(email: string, phone: string): Promise<boolean>;
  createUser(email: string, password: string): Promise<{ id: string } | "duplicate">;
  upload(path: string, data: Buffer): Promise<void>;
  register(args: {
    userId: string;
    input: Pick<RegistrationInput, "accountType" | "phone" | "email" | "referralCode">;
    documents: DocumentRecord[];
  }): Promise<"ok" | "duplicate" | "referral_invalid" | "referral_inactive">;
  removeFiles(paths: string[]): Promise<void>;
  deleteUser(id: string): Promise<void>;
}

export type RegistrationResult =
  | { ok: true }
  | { ok: false; error: "duplicate" | "server" | "same_image" | "referral_invalid" | "referral_inactive" }
  | { ok: false; error: "image"; field: DocumentType; problem: ImageProblem };

export async function registerAccount(input: RegistrationInput, ports: RegistrationPorts): Promise<RegistrationResult> {
  const images = {} as Record<DocumentType, ProcessedImage>;
  for (const type of DOCUMENT_TYPES) {
    const result = await processDocumentImage(Buffer.from(await input.files[type].arrayBuffer()));
    if (!result.ok) return { ok: false, error: "image", field: type, problem: result.problem };
    images[type] = result.image;
  }
  if (images.national_id_front.sha256 === images.residence_card_front.sha256) {
    return { ok: false, error: "same_image" };
  }

  let userId: string | null = null;
  const uploaded: string[] = [];
  try {
    if (input.referralCode) {
      const state = await ports.checkReferralCode(input.referralCode);
      if (state !== "valid") return { ok: false, error: `referral_${state}` };
    }
    if (await ports.isTaken(input.email, input.phone)) return { ok: false, error: "duplicate" };
    const user = await ports.createUser(input.email, input.password);
    if (user === "duplicate") return { ok: false, error: "duplicate" };
    userId = user.id;

    const documents: DocumentRecord[] = [];
    for (const type of DOCUMENT_TYPES) {
      const image = images[type];
      const path = `${userId}/${type}-${randomUUID()}.jpg`;
      uploaded.push(path); // قبل الرفع: لو انقطع الاتصال بعد وصول الملف نحذفه أيضاً
      await ports.upload(path, image.data);
      documents.push({
        doc_type: type, storage_path: path, sha256: image.sha256, mime_type: "image/jpeg",
        size_bytes: image.size, width: image.width, height: image.height,
      });
    }

    const outcome = await ports.register({ userId, input, documents });
    if (outcome === "ok") return { ok: true };
    await rollback(ports, userId, uploaded);
    return { ok: false, error: outcome };
  } catch (error) {
    console.error("registration failed", error instanceof Error ? error.message : "unknown");
    if (userId) await rollback(ports, userId, uploaded);
    return { ok: false, error: "server" };
  }
}

async function rollback(ports: RegistrationPorts, userId: string, paths: string[]) {
  // ما يتعذر حذفه الآن تلتقطه مهمة التنظيف الدورية
  try {
    if (paths.length) await ports.removeFiles(paths);
    await ports.deleteUser(userId);
  } catch (error) {
    console.error("registration rollback failed", error instanceof Error ? error.message : "unknown");
  }
}
