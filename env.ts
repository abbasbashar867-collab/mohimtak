import "server-only";

export function env(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Missing environment variable: ${name}`);
  return value;
}
// Netlify يوفر URL تلقائياً
export const appUrl = () => process.env.APP_URL || process.env.URL || "http://localhost:3000";
