import type { Locale } from "./config";

const ar = {
  forgotLink: "نسيت كلمة المرور؟", forgotTitle: "استعادة كلمة المرور", forgotHint: "اكتب بريدك وسنرسل لك رابط الاستعادة.",
  send: "إرسال الرابط", sent: "إن كان البريد مسجلاً فقد أرسلنا إليه رابط الاستعادة.", back: "رجوع لتسجيل الدخول",
  resetTitle: "كلمة مرور جديدة", newPassword: "كلمة المرور الجديدة", save: "حفظ", resetFailed: "الرابط منتهٍ أو غير صالح. اطلب رابطاً جديداً.",
  resetDone: "تم تغيير كلمة المرور. سجّل الدخول.", weak: "كلمة المرور قصيرة (8 رموز على الأقل).",
  featuresTitle: "لماذا مهمتك؟",
  features: [
    ["مراجعة بشرية", "كل حساب يمر بمراجعة الهوية وبطاقة السكن قبل التفعيل."],
    ["أمان عالٍ", "مستنداتك في تخزين خاص ولا تُعرض إلا للإدارة مع تسجيل كل وصول."],
    ["شفافية مالية", "سجلات مالية لا تُحذف، والتصحيح بقيد عكسي."],
    ["ثلاث لغات", "العربية والإنجليزية والكردية، مع وضع داكن وفاتح."],
    ["نظام مسوّقين", "كود إحالة لكل مسوّق وعمولات واضحة قابلة للمتابعة."],
    ["يعمل على الهاتف", "واجهة سريعة تتثبت كتطبيق على الموبايل."],
  ],
  faqTitle: "أسئلة شائعة",
  faq: [
    ["من يستطيع التسجيل؟", "الأفراد (عميل) والشركات في العراق ممن عمرهم 18 سنة فأكثر."],
    ["ماذا أحتاج للتسجيل؟", "صورة الهوية الوطنية وبطاقة السكن ورقم هاتف عراقي وبريد إلكتروني."],
    ["كم تستغرق المراجعة؟", "تراجع الإدارة الطلب وتتغير حالة حسابك، ويمكنك متابعتها بعد تسجيل الدخول."],
    ["هل بياناتي آمنة؟", "نعم، المستندات في تخزين خاص وتُحذف حسب سياسة الاحتفاظ."],
  ],
  cta: "ابدأ الآن", stats: { title: "إحصائيات المنصة", pending: "طلبات قيد المراجعة", approved: "حسابات مفعّلة", clients: "عملاء", companies: "شركات", total: "الإجمالي" },
};
const en: typeof ar = {
  forgotLink: "Forgot password?", forgotTitle: "Reset password", forgotHint: "Enter your email and we'll send a reset link.",
  send: "Send link", sent: "If the email is registered, we sent it a reset link.", back: "Back to log in",
  resetTitle: "New password", newPassword: "New password", save: "Save", resetFailed: "The link is expired or invalid. Request a new one.",
  resetDone: "Password changed. Please log in.", weak: "Password too short (min 8 characters).",
  featuresTitle: "Why Mohimtak?",
  features: [
    ["Human review", "Every account's ID and residence card are reviewed before activation."],
    ["Strong security", "Documents sit in private storage, visible only to admins, with every access logged."],
    ["Financial transparency", "Ledger records are never deleted; corrections are reversing entries."],
    ["Three languages", "Arabic, English and Kurdish, with dark and light modes."],
    ["Marketer program", "A referral code per marketer with clear, trackable commissions."],
    ["Mobile-first", "A fast interface you can install as an app on your phone."],
  ],
  faqTitle: "FAQ",
  faq: [
    ["Who can sign up?", "Individuals (clients) and companies in Iraq who are 18 or older."],
    ["What do I need?", "A photo of your national ID and residence card, an Iraqi phone number and an email."],
    ["How long is the review?", "Admins review your request and your status updates; track it after logging in."],
    ["Is my data safe?", "Yes. Documents are in private storage and deleted per the retention policy."],
  ],
  cta: "Get started", stats: { title: "Platform stats", pending: "Pending requests", approved: "Active accounts", clients: "Clients", companies: "Companies", total: "Total" },
};
const ckb: typeof ar = {
  forgotLink: "وشەی نهێنیت لەبیرچووە؟", forgotTitle: "گەڕاندنەوەی وشەی نهێنی", forgotHint: "ئیمەیڵەکەت بنووسە و بەستەری گەڕاندنەوە دەنێرین.",
  send: "ناردنی بەستەر", sent: "ئەگەر ئیمەیڵەکە تۆمارکرابێت، بەستەری گەڕاندنەوەمان بۆ ناردووە.", back: "گەڕانەوە بۆ چوونەژوورەوە",
  resetTitle: "وشەی نهێنی نوێ", newPassword: "وشەی نهێنی نوێ", save: "پاشەکەوتکردن", resetFailed: "بەستەرەکە بەسەرچووە یان هەڵەیە. بەستەرێکی نوێ داوا بکە.",
  resetDone: "وشەی نهێنی گۆڕدرا. بچۆرە ژوورەوە.", weak: "وشەی نهێنی کورتە (لانیکەم ٨ پیت).",
  featuresTitle: "بۆچی مهمتەک؟",
  features: [
    ["پێداچوونەوەی مرۆیی", "هەموو هەژمارێک پێش چالاککردن ناسنامە و کارتی نیشتەجێبوون پشکنین دەکرێت."],
    ["پاراستنی بەهێز", "بەڵگەنامەکان لە هەڵگرتنی تایبەتدان و تەنها بەڕێوەبەر دەیبینێت، هەموو بینینێک تۆمار دەکرێت."],
    ["ڕوونی دارایی", "تۆمارە داراییەکان ناسڕدرێنەوە و چاکسازی بە تۆماری پێچەوانەیە."],
    ["سێ زمان", "عەرەبی، ئینگلیزی و کوردی، لەگەڵ ڕووکاری تاریک و ڕووناک."],
    ["سیستەمی بازاڕگەر", "کۆدی ئاماژەپێدان بۆ هەر بازاڕگەرێک و کۆمیسیۆنی ڕوون."],
    ["بۆ مۆبایل", "ڕووکارێکی خێرا کە وەک ئەپ دابمەزرێت."],
  ],
  faqTitle: "پرسیارە باوەکان",
  faq: [
    ["کێ دەتوانێت تۆمار بێت؟", "تاک (کڕیار) و کۆمپانیا لە عێراق کە تەمەنیان ١٨ ساڵ یان زیاترە."],
    ["چیم پێویستە؟", "وێنەی ناسنامە و کارتی نیشتەجێبوون، ژمارەی مۆبایلی عێراقی و ئیمەیڵ."],
    ["پێداچوونەوە چەند دەخایەنێت؟", "بەڕێوەبەر داواکارییەکەت دەپشکنێت و دۆخەکەت دەگۆڕێت."],
    ["زانیارییەکانم پارێزراون؟", "بەڵێ، بەڵگەنامەکان لە هەڵگرتنی تایبەتدان."],
  ],
  cta: "دەستپێبکە", stats: { title: "ئامارەکانی پلاتفۆرم", pending: "داواکاری چاوەڕوان", approved: "هەژماری چالاک", clients: "کڕیار", companies: "کۆمپانیا", total: "کۆی گشتی" },
};
export const extras: Record<Locale, typeof ar> = { ar, en, ckb };
