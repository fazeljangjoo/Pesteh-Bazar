// v91 p3 — «ویرایش بدون محدودیت»: قواعد خالص (بدون پایگاه‌داده) که آینهٔ سرورند (backend/api/pb_recalc.php).
// سرور بعد از ویرایش لاتِ مصرف‌شده همهٔ اسناد پایین‌دستی (کوت، فروش، جداسازی، فراوری، کارگاه، استخر شکست، اسناد حسابداری) را
// دوباره حساب می‌کند و دستگاه با همگام‌سازی همان اعداد را می‌گیرد؛ اینجا فقط قاعدهٔ وزن و فی کوت برای نمای فوری آفلاین.

String _kg(double v) {
  final String s = v.toStringAsFixed(3);
  return s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
}

/// قاعدهٔ یکپارچگی وزن: وزن خالص تازه نباید از مقدار تاکنون فروخته/مصرف‌شده کمتر باشد. null = مجاز.
String? weightRuleError(double newNet, double oldNet, double oldRemaining, {String label = 'این خرید'}) {
  final double used = double.parse((oldNet - oldRemaining).toStringAsFixed(3));
  if (used > 1e-6 && newNet + 1e-6 < used) {
    return 'وزن خالص تازه (${_kg(newNet)} کیلو) از مقداری که از $label تاکنون فروخته یا مصرف شده (${_kg(used)} کیلو) کمتر است؛ ابتدا سندهای مصرف را اصلاح کنید';
  }
  return null;
}

/// فی کوت از مبدأها (همان فرمول ثبت کوت): Σ(وزن × فی) ÷ (Σ وزن، یا وزن خالص کوت اگر ضایعات دارد). null = مبدأ ندارد.
double? mixPriceOf(List<({double w, double price})> sources, {double? waste, required double mixNet}) {
  double sumW = 0, sumVal = 0;
  for (final s in sources) {
    if (s.w <= 0) continue;
    sumW += s.w;
    sumVal += s.w * s.price;
  }
  if (sumW <= 0) return null;
  final double div = waste == null ? sumW : mixNet;
  if (div <= 0) return null;
  return double.parse((sumVal / div).toStringAsFixed(2));
}
