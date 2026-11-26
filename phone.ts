// أرقام الموبايل العراقية بصيغة موحدة +9647XXXXXXXXX
export function normalizeDigits(input: string): string {
  return input
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0));
}

export function normalizeIraqiPhone(input: string): string | null {
  const cleaned = normalizeDigits(input).replace(/[\s\-().‎‏]/g, "");
  const match = /^(?:\+964|00964|964|0)(7\d{9})$/.exec(cleaned);
  return match ? `+964${match[1]}` : null;
}
