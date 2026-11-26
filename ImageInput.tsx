"use client";
import { useEffect, useState, type ChangeEvent } from "react";

const MAX_BYTES = 2 * 1024 * 1024 - 1024;

/** يصغّر الصورة في الهاتف قبل الإرسال ويستبدل بها الملف داخل الحقل. الخادم يتحقق منها من جديد. */
async function shrink(file: File): Promise<File> {
  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
  } catch {
    bitmap = await createImageBitmap(file);
  }
  const scale = Math.min(1, 2000 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  for (const quality of [0.88, 0.78, 0.65]) {
    const blob = await new Promise<Blob | null>((done) => canvas.toBlob(done, "image/jpeg", quality));
    if (blob && blob.size <= MAX_BYTES) return new File([blob], "image.jpg", { type: "image/jpeg" });
  }
  throw new Error("too large");
}

export function ImageInput({ name, label, choose, hint, preparing, failed, onBusy }: {
  name: string; label: string; choose: string; hint: string; preparing: string; failed: string; onBusy?: (busy: boolean) => void;
}) {
  const [preview, setPreview] = useState<string | null>(null);
  const [state, setState] = useState<"idle" | "busy" | "failed">("idle");
  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview); }, [preview]);

  async function change(event: ChangeEvent<HTMLInputElement>) {
    const input = event.currentTarget;
    const file = input.files?.[0];
    setPreview(null);
    if (!file) return;
    setState("busy");
    onBusy?.(true);
    try {
      let small: File;
      try {
        small = await shrink(file);
      } catch {
        // متصفحات قديمة: نرسل الملف الأصلي إن كان بحجم مقبول، والخادم يعيد ترميزه ويتحقق منه
        if (file.size > MAX_BYTES || !file.type.startsWith("image/")) throw new Error("fallback");
        small = file;
      }
      const transfer = new DataTransfer();
      transfer.items.add(small);
      input.files = transfer.files;
      setPreview(URL.createObjectURL(small));
      setState("idle");
    } catch {
      input.value = "";
      setState("failed");
    } finally {
      onBusy?.(false);
    }
  }

  return (
    <label className="block">
      <span className="label">{label}</span>
      {/* الحقل شفاف فوق زر مترجم، لأن نص حقل الملفات الأصلي يتبع لغة المتصفح */}
      <span className="field relative flex items-center gap-3 focus-within:border-accent">
        <span className="rounded-md bg-accent px-3 py-1.5 text-sm text-white">{choose}</span>
        <span aria-hidden="true">{preview ? "✓" : ""}</span>
        <input type="file" name={name} accept="image/*" required onChange={change} className="absolute inset-0 h-full w-full cursor-pointer opacity-0" />
      </span>
      <span className="mt-1 block text-sm text-muted">{state === "busy" ? preparing : state === "failed" ? failed : hint}</span>
      {preview && <img src={preview} alt="" className="mt-2 max-h-48 w-full rounded-lg border border-line object-contain" />}
    </label>
  );
}
