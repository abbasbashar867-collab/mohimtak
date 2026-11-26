import { createHash } from "node:crypto";
import sharp from "sharp";

export const MAX_UPLOAD_BYTES = 2 * 1024 * 1024;
const MIN_LONG_SIDE = 800;
const MIN_SHORT_SIDE = 500;
const MAX_PIXELS = 40_000_000;
// حدود أولية متحفظة: ترفض الصور الفارغة أو الضبابية جداً فقط. تعاير لاحقاً على صور حقيقية.
const MIN_CONTRAST = 12;
const MIN_SHARPNESS = 4;

export type ImageProblem = "too_large" | "not_image" | "too_small" | "unreadable";

export interface ProcessedImage {
  data: Buffer;
  sha256: string;
  width: number;
  height: number;
  size: number;
}

function sniff(buf: Buffer): boolean {
  const jpeg = buf.length > 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff;
  const png = buf.length > 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  const webp = buf.length > 12 && buf.toString("ascii", 0, 4) === "RIFF" && buf.toString("ascii", 8, 12) === "WEBP";
  return jpeg || png || webp;
}

/** تتحقق من الملف وتعيد ترميزه (تحذف EXIF والموقع وأي محتوى ملحق بالملف). */
export async function processDocumentImage(
  input: Buffer,
): Promise<{ ok: true; image: ProcessedImage } | { ok: false; problem: ImageProblem }> {
  if (input.length > MAX_UPLOAD_BYTES) return { ok: false, problem: "too_large" };
  if (!sniff(input)) return { ok: false, problem: "not_image" };

  try {
    const { data, info } = await sharp(input, { limitInputPixels: MAX_PIXELS, failOn: "warning" })
      .rotate()
      .resize({ width: 2000, height: 2000, fit: "inside", withoutEnlargement: true })
      .flatten({ background: "#ffffff" })
      .jpeg({ quality: 85 })
      .toBuffer({ resolveWithObject: true });

    if (Math.max(info.width, info.height) < MIN_LONG_SIDE || Math.min(info.width, info.height) < MIN_SHORT_SIDE) {
      return { ok: false, problem: "too_small" };
    }
    if (data.length > MAX_UPLOAD_BYTES) return { ok: false, problem: "too_large" };

    const gray = () => sharp(data).greyscale().resize({ width: 1000 });
    const [contrast, edges] = await Promise.all([
      gray().raw().toBuffer().then(stdev),
      gray()
        .convolve({ width: 3, height: 3, kernel: [0, 1, 0, 1, -4, 1, 0, 1, 0], offset: 128 })
        .raw().toBuffer().then(stdev),
    ]);
    if (contrast < MIN_CONTRAST || edges < MIN_SHARPNESS) return { ok: false, problem: "unreadable" };

    return {
      ok: true,
      image: {
        data,
        sha256: createHash("sha256").update(data).digest("hex"),
        width: info.width,
        height: info.height,
        size: data.length,
      },
    };
  } catch {
    return { ok: false, problem: "not_image" };
  }
}

function stdev(pixels: Buffer): number {
  let sum = 0;
  let squares = 0;
  for (const p of pixels) {
    sum += p;
    squares += p * p;
  }
  const mean = sum / pixels.length;
  return Math.sqrt(Math.max(0, squares / pixels.length - mean * mean));
}
