const features = [
  { n: "01", title: "انشر مهمتك", desc: "حوّل احتياجك إلى مهمة واضحة وحدد تفاصيلها." },
  { n: "02", title: "نفّذ واكسب", desc: "اكتشف المهام المتاحة واجمع النقاط مقابل الإنجاز." },
  { n: "03", title: "شارك بالجوائز", desc: "استخدم نقاطك للدخول إلى غرف الجوائز والمسابقات." },
];
export default function Home() {
  return (
    <main dir="rtl" className="min-h-screen overflow-hidden">
      <header className="mx-auto flex max-w-6xl items-center justify-between px-5 py-5">
        <a href="/" className="flex items-center gap-3 text-xl font-black tracking-tight"><span className="grid h-11 w-11 place-items-center rounded-2xl bg-blue-600 text-white">م</span> مهمتك</a>
        <nav className="flex items-center gap-2 text-sm"><a className="rounded-full border border-line px-4 py-2" href="#how">كيف تعمل؟</a><a className="rounded-full bg-blue-600 px-4 py-2 font-bold text-white" href="#start">ابدأ الآن</a></nav>
      </header>
      <section className="relative mx-auto grid max-w-6xl items-center gap-12 px-5 pb-20 pt-14 md:grid-cols-2 md:pt-24">
        <div className="absolute -right-24 top-10 h-72 w-72 rounded-full bg-blue-500/10 blur-3xl" />
        <div className="relative">
          <span className="mb-6 inline-flex rounded-full border border-blue-500/30 bg-blue-500/10 px-4 py-2 text-sm font-semibold text-blue-500">منصة المهام والتفاعل</span>
          <h1 className="max-w-xl text-5xl font-black leading-[1.35] tracking-tight md:text-6xl">كل مهمة إلها <span className="text-blue-500">قيمة.</span><br/>وكل إنجاز إله مقابل.</h1>
          <p className="mt-6 max-w-lg text-lg leading-9 text-muted">مهمتك تجمع الشركات والأشخاص بمكان واحد؛ مهام واضحة، إنجاز موثّق، ونظام نقاط يفتح لك فرص أكثر.</p>
          <div id="start" className="mt-9 flex flex-wrap gap-3"><a href="#how" className="rounded-xl bg-blue-600 px-7 py-3.5 font-bold text-white shadow-lg shadow-blue-600/20">اكتشف المنصة</a><a href="#features" className="rounded-xl border border-line px-7 py-3.5 font-bold">تعرّف على المزايا</a></div>
          <p className="mt-5 text-xs text-muted">نسخة معاينة للواجهة — بعض الخدمات قيد التطوير.</p>
        </div>
        <div className="relative mx-auto w-full max-w-md">
          <div className="absolute -inset-5 rounded-[2.5rem] bg-gradient-to-br from-blue-500/20 to-cyan-400/5 blur-2xl"/>
          <div className="relative rounded-[2rem] border border-line bg-card p-5 shadow-2xl">
            <div className="flex items-center justify-between"><span className="text-sm font-bold">لوحة مهمتك</span><span className="rounded-full bg-green-500/10 px-3 py-1 text-xs font-bold text-green-500">معاينة</span></div>
            <div className="mt-6 rounded-2xl bg-gradient-to-l from-blue-700 to-blue-500 p-6 text-white"><p className="text-sm text-blue-100">رصيد النقاط</p><div className="mt-2 text-4xl font-black">2,450 <span className="text-base">نقطة</span></div><div className="mt-5 h-2 rounded-full bg-white/20"><div className="h-2 w-2/3 rounded-full bg-white"/></div><p className="mt-2 text-xs text-blue-100">واصل إنجاز المهام حتى تزيد فرصك</p></div>
            <div className="mt-5 grid grid-cols-2 gap-3"><div className="rounded-xl border border-line p-4"><p className="text-xs text-muted">مهام مكتملة</p><b className="mt-2 block text-2xl">18</b></div><div className="rounded-xl border border-line p-4"><p className="text-xs text-muted">تذاكر الجوائز</p><b className="mt-2 block text-2xl">05</b></div></div>
            <div className="mt-5"><div className="mb-3 flex justify-between text-sm"><b>مهام مقترحة</b><span className="text-blue-500">عرض الكل</span></div>{["مشاهدة محتوى وإثبات الإنجاز","التفاعل مع حملة شركة"].map((x,i)=><div key={x} className="mb-2 flex items-center gap-3 rounded-xl border border-line p-3"><span className="grid h-9 w-9 place-items-center rounded-lg bg-blue-500/10 text-blue-500">{i+1}</span><span className="text-sm font-semibold">{x}</span><span className="mr-auto text-xs text-blue-500">+{(i+1)*150}</span></div>)}</div>
          </div>
        </div>
      </section>
      <section id="how" className="border-y border-line bg-card/60 px-5 py-16"><div className="mx-auto max-w-6xl"><p className="text-sm font-bold text-blue-500">بخطوات بسيطة</p><h2 className="mt-3 text-3xl font-black">شلون تشتغل مهمتك؟</h2><div id="features" className="mt-8 grid gap-4 md:grid-cols-3">{features.map(f=><article key={f.n} className="rounded-2xl border border-line bg-bg p-6"><span className="text-sm font-black text-blue-500">{f.n}</span><h3 className="mt-5 text-xl font-extrabold">{f.title}</h3><p className="mt-3 leading-8 text-muted">{f.desc}</p></article>)}</div></div></section>
      <footer className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-5 py-8 text-sm text-muted"><span>© مهمتك 2026</span><span>منصة عراقية قيد التطوير</span></footer>
    </main>
  );
}
