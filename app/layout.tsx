import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = { title: "مهمتك | منصة المهام", description: "منصة مهمتك للمهام والتفاعل والجوائز" };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ar" dir="rtl"><body className="min-h-screen antialiased">{children}</body></html>;
}
