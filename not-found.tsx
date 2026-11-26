import Link from "next/link";
export default function NotFound() {
  return (
    <main className="mx-auto max-w-sm px-4 py-20 text-center">
      <p className="text-6xl font-bold text-accent">404</p>
      <p className="my-4 text-muted">الصفحة غير موجودة · Page not found</p>
      <Link href="/" className="btn">الرئيسية / Home</Link>
    </main>
  );
}
