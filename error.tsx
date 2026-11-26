"use client";
export default function ErrorPage({ reset }: { error: Error; reset: () => void }) {
  return (
    <main className="mx-auto max-w-sm px-4 py-20 text-center">
      <p className="mb-4 text-lg font-bold">حدث خطأ غير متوقع · Something went wrong</p>
      <button onClick={reset} className="btn">إعادة المحاولة / Retry</button>
    </main>
  );
}
