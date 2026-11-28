import 'dart:convert';

import 'entity_store.dart' show kEntityRegistry;
import 'utils.dart';

/// v96: متن فارسیِ سادهٔ هر ردیف گزارش ممیزی.
/// هر ردیف این‌طور خوانده می‌شود: «۱۴۰۵/۰۹/۰۸ ساعت ۱۴:۳۵ — علی (بازاریاب): ۱۲ مشتری بازاریابی از اکسل وارد کرد».
/// کلید خام عملیات (مثل import.commit)، نام فنی جدول، شناسه (uid) و JSON هرگز نمایش داده نمی‌شود.
/// فقط لایهٔ نمایش است؛ با سرور فعلی (بدون staff_role) هم کار می‌کند.

/// نام فارسی رکوردها (ستون entity در audit_log). entity.<name> از [kEntityRegistry] خوانده می‌شود.
const Map<String, String> kAuditEntityFa = <String, String>{
  'purchase': 'خرید',
  'sale': 'فروش',
  'mix': 'مخلوط',
  'payment': 'پرداخت',
  'receipt': 'دریافت',
  'due': 'سررسید',
  'party': 'طرف حساب',
  'loan': 'قرض/وام',
  'stock_transfer': 'انتقال انبار',
  'staff': 'کاربر',
  'role': 'نقش',
  'account': 'حساب',
  'backup': 'پشتیبان',
  'category': 'دسته‌بندی',
  'type': 'نوع',
  'intake': 'پذیرش اتاق انس',
  'intake_price_settings': 'گرم مرجع قیمت',
  'voucher': 'سند حسابداری',
  'fiscal_year': 'سال مالی',
  'import': 'ورود از اکسل',
  'fx_reval': 'تسعیر ارز',
  'stock_count': 'انبارگردانی',
  'pay_approval': 'تأیید پرداخت',
  'tafsili': 'حساب تفصیلی',
  'account_roles': 'نگاشت حساب‌ها',
  'upgrade_run': 'ارتقای نسخه',
  'lot': 'لات',
  'lot_quality': 'شاخص کیفی لات',
  'workshop': 'عملیات کارگاه',
  'crack_run': 'گزارش خط شکست',
  'processing': 'فراوری',
  'consignment': 'امانی',
  'purchase_return': 'برگشت از خرید',
  'sale_return': 'برگشت از فروش',
  'orchard_cost': 'هزینهٔ باغ',
  'harvest': 'برداشت باغ',
  'feed_adjust': 'تعدیل پستهٔ خرجی',
  'doc_correction': 'سند اصلاحی',
  'bank_statement': 'صورت‌حساب بانک',
  'bank_recon': 'تطبیق بانک',
  'backup_drill': 'تمرین بازیابی',
  'letters_of_credit': 'اعتبار اسنادی',
  'sale_export': 'فاکتور صادراتی',
  'pay_approval_limit': 'سقف تأیید پرداخت',
  'period_lock': 'دورهٔ ماهانه',
  'doc_approval': 'تأیید سند',
  'approval_limit': 'سقف تأیید',
  'proforma': 'پیش‌فاکتور',
  'broker': 'دلال',
  'broker_rule': 'قانون کمیسیون',
  'broker_payment': 'پرداخت کمیسیون',
  'cheque': 'چک',
  'separation': 'جداسازی',
  'separation_settings': 'تنظیمات جداسازی',
  'pct_def': 'تعریف درصد پذیرش',
  'api_keys': 'کلید اتصال',
  'webhooks': 'وب‌هوک',
  '2fa': 'ورود دو مرحله‌ای',
  'sessions': 'نشست‌های ورود',
  'alert_thresholds': 'آستانهٔ موجودی کم',
  'alerts': 'هشدار',
  'ops_anomalies': 'هشدار بازده',
  'tech_features': 'قابلیت‌های فناورانه',
};

/// نوع سندهای خودکار حسابداری (posting.php) به فارسی.
const Map<String, String> kAuditDocTypeFa = <String, String>{
  'purchase': 'خرید',
  'sale': 'فروش',
  'preturn': 'برگشت از خرید',
  'sreturn': 'برگشت از فروش',
  'bpay': 'پرداخت دلال',
  'cheque_ev': 'رویداد چک',
  'cons_in': 'ورود امانی',
  'cons_out': 'خروج امانی',
  'cons_out_ret': 'برگشت امانی',
  'cons_out_sold': 'فروش امانی',
  'cons_pay': 'پرداخت امانی',
  'cons_sale': 'فروش امانی',
  'count_adj': 'تعدیل انبارگردانی',
  'expense': 'هزینه',
  'fx_adjust': 'تعدیل نرخ ارز',
  'fx_reval': 'تسعیر ارز',
  'fx_reval_rev': 'برگشت تسعیر ارز',
  'fx_settle_pay': 'تسویهٔ ارزی پرداخت',
  'fx_settle_recv': 'تسویهٔ ارزی دریافت',
  'inst_pay': 'پرداخت قسط',
  'inst_recv': 'دریافت قسط',
  'loan': 'قرض/وام',
  'mix_staged': 'مخلوط مرحله‌ای',
  'orch_alloc': 'تسهیم هزینهٔ باغ',
  'orch_cost': 'هزینهٔ باغ',
  'owner_draw': 'برداشت مالک',
  'payroll': 'حقوق',
  'payroll_adv': 'مساعدهٔ حقوق',
  'payroll_pay': 'پرداخت حقوق',
  'proc_recv': 'دریافت از فراوری',
  'proc_send': 'ارسال به فراوری',
  'proc_toll': 'کارمزد فراوری',
  'sep': 'جداسازی',
  'settlement': 'تسویه',
  'stl_adv_p': 'پیش‌پرداخت',
  'stl_adv_s': 'پیش‌دریافت',
  'xch_move': 'حواله صرافی',
};

const Map<String, String> _kImportKindFa = <String, String>{
  'parties': 'طرف حساب',
  'opening_stock': 'لات موجودی اول دوره',
  'categories_types': 'دسته و نوع',
  'ounces': 'درجهٔ انس',
  'warehouses': 'انبار',
  'grade_prices': 'قیمت روزانه',
  'fx_rates': 'نرخ ارز',
  'accounts': 'حساب',
  'mk_leads': 'مشتری بازاریابی',
};

const Map<String, String> _kVoucherStatusFa = <String, String>{
  'draft': 'پیش‌نویس',
  'temporary': 'موقت',
  'final': 'قطعی',
};

const Map<String, String> _kCcyFa = <String, String>{
  'USD': 'دلار',
  'EUR': 'یورو',
  'AED': 'درهم',
  'CNY': 'یوان',
  'TRY': 'لیر',
  'IQD': 'دینار عراق',
  'GBP': 'پوند',
  'RUB': 'روبل',
  'AFN': 'افغانی',
};

/// گروه کلیدهای عملیاتِ جدید/ناشناخته (ستون action فقط ۲۰ نویسه است و ممکن است بریده شده باشد).
const Map<String, String> _kActionGroupFa = <String, String>{
  'voucher.': 'سند حسابداری',
  'fy.': 'سال مالی',
  'fx.': 'ارز',
  'tier.': 'ارتقای نسخه',
  'account.': 'حساب',
  'tafsili.': 'حساب تفصیلی',
  'import.': 'ورود از اکسل',
  'stock_count.': 'انبارگردانی',
  'payments.': 'پرداخت',
};

/// شرح‌های ثابتی که قاعدهٔ عمومی جملهٔ خوبی از آن‌ها نمی‌سازد.
const Map<String, String> _kExactFa = <String, String>{
  'سند اصلاحی (فی/وزن)': 'سند اصلاحی فی یا وزن ثبت کرد',
  'تطبیق خودکار بانک': 'ردیف‌های بانک را به‌طور خودکار تطبیق داد',
  'تطبیق دستی ردیف بانک': 'یک ردیف بانک را دستی تطبیق داد',
  'لغو تطبیق ردیف بانک': 'تطبیق یک ردیف بانک را لغو کرد',
  'نادیده‌گرفتن ردیف بانک': 'یک ردیف بانک را نادیده گرفت',
  'تمرین بازیابی بک‌آپ': 'تمرین بازیابی پشتیبان را انجام داد',
  'انتقال بین انبارها': 'کالا را بین انبارها جابه‌جا کرد',
  'ارسال انبارگردانی برای تأیید': 'انبارگردانی را برای تأیید فرستاد',
  'تبدیل پیش‌فاکتور به فروش': 'پیش‌فاکتور را به فروش تبدیل کرد',
  'اتصال فروش‌های آفلاین به پیش‌فاکتور': 'فروش‌های آفلاین را به پیش‌فاکتور وصل کرد',
  'شکست مجدد نشکن': 'نشکن را دوباره شکست داد',
  'لغو شکست مجدد نشکن': 'شکست مجدد نشکن را لغو کرد',
  'بازکردن عملیات کارگاه برای اصلاح': 'عملیات کارگاه را برای اصلاح دوباره باز کرد',
  'شروع عملیات کارگاه': 'یک عملیات کارگاه را شروع کرد',
  'خروج از سایر دستگاه‌ها': 'از همهٔ دستگاه‌های دیگر خارج شد',
  'ساخت دوبارهٔ کدهای بازیابی': 'کدهای بازیابی ورود دو مرحله‌ای را دوباره ساخت',
  'فعال‌سازی ورود دو مرحله‌ای': 'ورود دو مرحله‌ای را فعال کرد',
  'غیرفعال‌سازی ورود دو مرحله‌ای': 'ورود دو مرحله‌ای را غیرفعال کرد',
  'درخواست پرداخت بالای سقف (در انتظار تأیید مالک)': 'درخواست پرداختِ بالای سقف داد (در انتظار تأیید مالک)',
  'تسویهٔ سررسید': 'یک سررسید را تسویه کرد',
  'تسویهٔ قسط قرض': 'قسط قرض را تسویه کرد',
  'بازیابی پشتیبان': 'اطلاعات را از فایل پشتیبان بازیابی کرد',
  'تغییر رمز': 'رمز عبور را تغییر داد',
  'بازنشانی رمز': 'رمز عبور را بازنشانی کرد',
  'ایجاد پیش‌نویس پذیرش اتاق انس': 'پیش‌نویس پذیرش اتاق انس ساخت',
  'تعریف درصد جدید در پذیرش': 'یک درصد جدید برای پذیرش تعریف کرد',
  'ارتقا به نسخهٔ طلایی کامل شد': 'ارتقا به نسخهٔ طلایی را کامل کرد',
  'بازگشت از نسخهٔ طلایی به سبز': 'از نسخهٔ طلایی به نسخهٔ سبز برگشت',
  'شاخص کیفی لات (رطوبت/ایراد)': 'شاخص کیفی لات (رطوبت و ایراد) را ثبت کرد',
  'سند افتتاحیه سال بعد': 'سند افتتاحیهٔ سال بعد را صادر کرد',
  'تنظیمات جداسازی': 'تنظیمات جداسازی را تغییر داد',
};

/// پیشوند اسمِ عمل ← فعل گذشته. ترتیب مهم است (طولانی‌تر اول).
const List<List<String>> _kPrefixVerb = <List<String>>[
  <String>['ثبت/ویرایش ', 'ثبت یا ویرایش کرد'],
  <String>['ثبت نهایی ', 'به‌طور نهایی ثبت کرد'],
  <String>['ثبت ', 'ثبت کرد'],
  <String>['ایجاد ', 'ایجاد کرد'],
  <String>['ساخت ', 'ساخت'],
  <String>['ویرایش ', 'ویرایش کرد'],
  <String>['حذف ', 'حذف کرد'],
  <String>['تغییر ', 'تغییر داد'],
  <String>['تأیید ', 'تأیید کرد'],
  <String>['رد قطعی ', 'به‌طور قطعی رد کرد'],
  <String>['رد ', 'رد کرد'],
  <String>['بستن ', 'بست'],
  <String>['بازگشایی ', 'بازگشایی کرد'],
  <String>['بازکردن ', 'باز کرد'],
  <String>['ذخیرهٔ ', 'ذخیره کرد'],
  <String>['تسویهٔ ', 'تسویه کرد'],
  <String>['لغو ', 'لغو کرد'],
  <String>['قفل ', 'قفل کرد'],
  <String>['ارسال ', 'ارسال کرد'],
  <String>['تبدیل ', 'تبدیل کرد'],
  <String>['افزودن ', 'اضافه کرد'],
  <String>['شروع ', 'شروع کرد'],
  <String>['ورود ', 'وارد کرد'],
  <String>['قطعی‌سازی ', 'قطعی کرد'],
  <String>['ابطال ', 'باطل کرد'],
];

const Map<String, String> _kVerbFa = <String, String>{'create': 'ایجاد', 'update': 'ویرایش', 'delete': 'حذف'};

/// برچسب فارسی رکورد؛ entity.<name> از رجیستری موجودیت‌ها. ناشناخته ← رشتهٔ خالی (هرگز نام فنی).
String auditEntityFa(String entity) {
  if (entity.startsWith('entity.')) return kEntityRegistry[entity.substring(7)]?.label ?? '';
  return kAuditEntityFa[entity] ?? '';
}

String _s(Object? v) => (v ?? '').toString().trim();

/// «۱۴۰۵/۰۹/۰۸ ساعت ۱۴:۳۵» از created_at سرور (به وقت تهران، `Y-m-d H:i:s`).
String auditWhen(Object? createdAt) {
  final String ts = _s(createdAt);
  final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?').firstMatch(ts);
  if (m == null) return toFaDigits(ts);
  final List<int> j = gregorianToJalali(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  final String d = '${j[0]}/${j[1].toString().padLeft(2, '0')}/${j[2].toString().padLeft(2, '0')}';
  return toFaDigits(m[4] == null ? d : '$d ساعت ${m[4]}:${m[5]}');
}

/// فقط تاریخ شمسی و فقط ساعت (برای ستون‌های جدای Excel).
String auditDate(Object? createdAt) => auditWhen(createdAt).split(' ساعت ').first;
String auditTime(Object? createdAt) {
  final List<String> p = auditWhen(createdAt).split(' ساعت ');
  return p.length > 1 ? p[1] : '';
}

/// نام انجام‌دهنده: «مالک» یا نام کارمند.
String auditActorName(Map<String, dynamic> row) {
  final int sid = int.tryParse(_s(row['staff_id'])) ?? 0;
  final String name = _s(row['staff_name']);
  if (sid <= 0 && name.isEmpty) return 'مالک';
  return name.isEmpty ? 'کارمند' : name;
}

/// نقش انجام‌دهنده: «مالک» برای مالک؛ برای کارمند نام نقش (سرور v96 به بعد) یا [roleOf] (فهرست کاربران) یا خالی.
String auditActorRole(Map<String, dynamic> row, {String Function(int staffId)? roleOf}) {
  final int sid = int.tryParse(_s(row['staff_id'])) ?? 0;
  if (sid <= 0 && _s(row['staff_name']).isEmpty) return 'مالک';
  final String r = _s(row['staff_role']);
  if (r.isNotEmpty) return r;
  return roleOf == null || sid <= 0 ? '' : roleOf(sid).trim();
}

/// «علی (بازاریاب)» یا «مالک».
String auditWho(Map<String, dynamic> row, {String Function(int staffId)? roleOf}) {
  final String name = auditActorName(row);
  if (name == 'مالک') return name;
  final String role = auditActorRole(row, roleOf: roleOf);
  return role.isEmpty ? name : '$name ($role)';
}

String _faDate(String iso) {
  try {
    return jalaliDate(iso);
  } catch (_) {
    return iso;
  }
}

String _faNumStr(String raw) {
  final double? v = double.tryParse(raw.replaceAll(',', ''));
  return v == null ? toFaDigits(raw) : faNum(v, dec: 4);
}

/// تمیز کردن شرح: تاریخ میلادی ← شمسی، «sale#12» ← «فروش شمارهٔ ۱۲»، «#12» ← «شمارهٔ ۱۲»، ارقام فارسی.
String _clean(String s) {
  String t = s.replaceAllMapped(RegExp(r'\b(\d{4}-\d{2}-\d{2})\b'), (Match m) => _faDate(m[1]!));
  t = t.replaceAllMapped(RegExp(r'\b([a-z_]+)#(\d+)'), (Match m) {
    final String? d = kAuditDocTypeFa[m[1]!];
    return d == null ? 'شمارهٔ ${m[2]}' : '$d شمارهٔ ${m[2]}';
  });
  t = t.replaceAllMapped(RegExp(r'#(\d+)'), (Match m) => 'شمارهٔ ${m[1]}');
  t = t.replaceAll('کلید API', 'کلید اتصال').replaceAll('ایمپورت', 'ورود از اکسل');
  return _faDigitsKeepCodes(t.replaceAll(RegExp(r'\s+'), ' ').trim());
}

/// ارقام فارسی، ولی کدهای لاتین (مثل KH-12) همان‌طور که روی برچسب نوشته شده می‌مانند.
String _faDigitsKeepCodes(String s) => s.replaceAllMapped(
    RegExp(r'[A-Za-z][A-Za-z0-9_\-/]*|\d+'), (Match m) => RegExp(r'^[A-Za-z]').hasMatch(m[0]!) ? m[0]! : toFaDigits(m[0]!));

/// اسم‌عمل ← جملهٔ فعلی. «ثبت خرید» ← «خرید را ثبت کرد». بخش بعد از «: » (نام، دلیل، …) با «؛» می‌آید.
String _sentence(String summary) {
  final String exact = _kExactFa[summary] ?? '';
  if (exact.isNotEmpty) return _clean(exact);
  String head = summary;
  String tail = '';
  final int colon = summary.indexOf(': ');
  if (colon > 0) {
    head = summary.substring(0, colon).trim();
    tail = summary.substring(colon + 2).trim();
  }
  if (_kExactFa.containsKey(head)) return _clean('${_kExactFa[head]}${tail.isEmpty ? '' : '؛ $tail'}');
  String out = '';
  for (final List<String> pv in _kPrefixVerb) {
    if (head.startsWith(pv[0])) {
      final String obj = head.substring(pv[0].length).trim();
      if (obj.isEmpty) break;
      out = tail.isNotEmpty && !obj.contains('(') ? '$obj «$tail» را ${pv[1]}' : '$obj را ${pv[1]}${tail.isEmpty ? '' : '؛ $tail'}';
      break;
    }
  }
  if (out.isEmpty) {
    if (head.endsWith(' شد') || head.contains(' شد ') || summary.contains(' شد:')) {
      out = summary; // جملهٔ مجهول خودش خواناست
    } else {
      out = '$head را انجام داد${tail.isEmpty ? '' : '؛ $tail'}';
    }
  }
  return _clean(out);
}

String _byVerb(String verb, String label) {
  final String l = label.isEmpty ? 'مورد' : label;
  switch (verb) {
    case 'create':
      return label.isEmpty ? 'یک مورد جدید ثبت کرد' : 'یک $l جدید ثبت کرد';
    case 'update':
      return 'یک $l را ویرایش کرد';
    case 'delete':
      return 'یک $l را حذف کرد';
  }
  return '';
}

String _importSentence(String summary) {
  final RegExpMatch? m = RegExp(r'^ایمپورت\s+([a-z_]+)\s*:\s*(\d+)\s*جدید،\s*(\d+)\s*ویرایش،\s*(\d+)\s*ردشده').firstMatch(summary);
  if (m == null) return '';
  final String kind = _kImportKindFa[m[1]!] ?? 'اطلاعات';
  final int created = int.parse(m[2]!), updated = int.parse(m[3]!), skipped = int.parse(m[4]!);
  final List<String> parts = <String>[];
  if (created > 0) parts.add('$created $kind از اکسل وارد کرد');
  if (updated > 0) parts.add(created > 0 ? '$updated مورد موجود را به‌روز کرد' : '$updated $kind را از اکسل به‌روز کرد');
  if (parts.isEmpty) parts.add('فایل اکسل $kind را وارد کرد ولی ردیف تازه‌ای اضافه نشد');
  if (skipped > 0) parts.add('$skipped ردیف کنار گذاشته شد');
  return toFaDigits(parts.join('، '));
}

String _voucherStatusSentence(String summary) {
  final RegExpMatch? m = RegExp(r'^تغییر وضعیت سند\s+(\w+)\s*→\s*(\w+)').firstMatch(summary);
  if (m == null) return '';
  final String a = _kVoucherStatusFa[m[1]!] ?? '', b = _kVoucherStatusFa[m[2]!] ?? '';
  if (a.isEmpty || b.isEmpty) return 'وضعیت سند حسابداری را تغییر داد';
  return 'وضعیت سند حسابداری را از «$a» به «$b» تغییر داد';
}

String _fxAdjustSentence(String summary) {
  final RegExpMatch? m = RegExp(r'^تعدیل نرخ\s+([A-Za-z]+)\s*:\s*([\d.]+)\s*←\s*([\d.]+)\s*\(اختلاف\s*(-?[\d.]+)\s*ریال\)').firstMatch(summary);
  if (m == null) return '';
  final String ccy = _kCcyFa[m[1]!.toUpperCase()] ?? 'ارز';
  return 'نرخ $ccy را از ${_faNumStr(m[2]!)} به ${_faNumStr(m[3]!)} ریال اصلاح کرد (اختلاف ${_faNumStr(m[4]!)} ریال)';
}

/// جملهٔ فارسیِ «چه کرد» برای یک ردیف ممیزی؛ هرگز کلید خام، شناسه یا JSON برنمی‌گرداند.
String auditWhat(Map<String, dynamic> row) {
  final String action = _s(row['action']);
  final String entity = _s(row['entity']);
  final String summary = _s(row['summary']);
  final String label = auditEntityFa(entity);
  String out = '';
  if (action.startsWith('import.')) out = _importSentence(summary);
  if (out.isEmpty && action.startsWith('voucher.status')) out = _voucherStatusSentence(summary);
  if (out.isEmpty && action.startsWith('fx.adjust')) out = _fxAdjustSentence(summary);
  if (out.isEmpty && action.startsWith('voucher.unpost') && summary.startsWith('حذف سند خودکار')) {
    out = _clean('${summary.replaceFirst('حذف سند خودکار', 'سند حسابداری خودکارِ').trim()} را حذف کرد');
  }
  if (out.isEmpty && action.startsWith('voucher.copy') && summary.startsWith('رونوشت از سند')) {
    out = _clean('از ${summary.replaceFirst('رونوشت از ', '')} رونوشت گرفت');
  }
  if (out.isEmpty && action.startsWith('fy.open_next') && summary.startsWith('سند افتتاحیه ')) {
    out = _clean('${summary.replaceFirst('سند افتتاحیه ', 'سند افتتاحیهٔ ')} را صادر کرد');
  }
  if (out.isEmpty && summary.startsWith('تسعیر ارز')) {
    final int dash = summary.indexOf(' — ');
    out = dash > 0 ? _clean('${summary.substring(0, dash)} را انجام داد؛ ${summary.substring(dash + 3)}') : _clean('$summary را انجام داد');
  }
  if (out.isEmpty && summary.startsWith('برگشت پذیرش به اتاق انس برای اصلاح')) {
    out = _clean(summary.replaceFirst('برگشت پذیرش به اتاق انس برای اصلاح', 'پذیرش را برای اصلاح به اتاق انس برگرداند').replaceFirst(': ', '؛ دلیل: '));
  }
  if (out.isEmpty && summary.startsWith('برگشت خودکار تسعیر ارز')) {
    out = _clean('${summary.replaceFirst('برگشت خودکار ', '')} را به‌طور خودکار برگرداند');
  }
  if (out.isEmpty && summary.startsWith('قطعی‌سازی پذیرش اتاق انس')) {
    final List<String> p = summary.replaceFirst('قطعی‌سازی ', '').split(' ← ');
    out = _clean('${p.first} را قطعی کرد${p.length > 1 ? ' و ${p[1]} ساخته شد' : ''}');
  }
  if (out.isEmpty && action.startsWith('tafsili.')) out = _sentence(summary.replaceFirst('تفصیلی ', 'حساب تفصیلی '));
  if (out.isEmpty && summary.startsWith('تبدیل پذیرش به نمونه')) {
    out = _clean(summary.replaceFirst('تبدیل پذیرش به نمونه', 'پذیرش را به نمونه تبدیل کرد'));
  }
  if (out.isEmpty && summary.startsWith('رد قطعی پذیرش اتاق انس')) {
    final int c = summary.indexOf(': ');
    final String head = c > 0 ? summary.substring(0, c) : summary;
    out = _clean('${head.replaceFirst('رد قطعی ', '')} را به‌طور قطعی رد کرد${c > 0 ? '؛ دلیل: ${summary.substring(c + 2)}' : ''}');
  }
  if (out.isEmpty && summary.isNotEmpty) out = _sentence(summary);
  if (out.isEmpty) out = _byVerb(action, label);
  if (out.isEmpty) {
    String group = label;
    if (group.isEmpty) {
      for (final MapEntry<String, String> e in _kActionGroupFa.entries) {
        if (action.startsWith(e.key)) {
          group = e.value;
          break;
        }
      }
    }
    out = group.isEmpty ? 'یک تغییر در برنامه ثبت کرد' : 'تغییری در $group ثبت کرد';
  }
  return out;
}

/// کل خط: «۱۴۰۵/۰۹/۰۸ ساعت ۱۴:۳۵ — علی (بازاریاب): خرید را ثبت کرد».
String auditLine(Map<String, dynamic> row, {String Function(int staffId)? roleOf}) =>
    '${auditWhen(row['created_at'])} — ${auditWho(row, roleOf: roleOf)}: ${auditWhat(row)}';

/// نوع عمل به فارسی برای فیلتر (ایجاد/ویرایش/حذف).
String auditVerbFa(String verb) => _kVerbFa[verb] ?? '';

// ───────────── جزئیات تغییر (به‌جای JSON) ─────────────

class AuditChange {
  final String label;
  final String before;
  final String after;
  const AuditChange(this.label, this.before, this.after);
}

/// برچسب فارسی فیلدهای رایج. فیلدی که اینجا (یا در رجیستری موجودیت) نیست نمایش داده نمی‌شود.
const Map<String, String> _kFieldFa = <String, String>{
  'date': 'تاریخ',
  'doc_date': 'تاریخ سند',
  'party': 'طرف حساب',
  'party_name': 'طرف حساب',
  'customer': 'مشتری',
  'seller': 'فروشنده',
  'buyer': 'خریدار',
  'name': 'نام',
  'title': 'عنوان',
  'code': 'کد',
  'category': 'دسته',
  'type': 'نوع',
  'warehouse': 'انبار',
  'ounce': 'انس',
  'weight': 'وزن',
  'net_weight': 'وزن خالص',
  'qty': 'تعداد',
  'price': 'فی',
  'unit_price': 'فی',
  'amount': 'مبلغ',
  'amount_rial': 'مبلغ (ریال)',
  'total': 'جمع',
  'rate': 'نرخ',
  'ccy': 'ارز',
  'pct': 'درصد',
  'note': 'توضیح',
  'description': 'شرح',
  'reason': 'دلیل',
  '_delete_reason': 'دلیل حذف',
  'reject_reason': 'دلیل رد',
  'status': 'وضعیت',
  'phone': 'تلفن',
  'address': 'نشانی',
  'active': 'فعال',
  'ref_gram': 'گرم مرجع',
  'loss_gram': 'گرم پرتی',
  'lots': 'تعداد لات',
  'label': 'عنوان',
  'staff': 'کارمند',
};

const Map<String, String> _kStatusFa = <String, String>{
  'draft': 'پیش‌نویس',
  'temporary': 'موقت',
  'final': 'قطعی',
  'submitted': 'ثبت‌شده',
  'approved': 'تأییدشده',
  'rejected': 'ردشده',
  'open': 'باز',
  'closed': 'بسته',
  'pending': 'در انتظار',
  'done': 'انجام‌شده',
  'cancelled': 'لغوشده',
};

Map<String, dynamic>? _json(Object? v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  final String s = _s(v);
  if (s.isEmpty || !s.startsWith('{')) return null;
  try {
    final Object? d = jsonDecode(s);
    return d is Map ? Map<String, dynamic>.from(d) : null;
  } catch (_) {
    return null; // بریده‌شده با «…» یا خراب
  }
}

String _value(String key, Object? v) {
  if (v == null) return '';
  if (v is bool) return v ? 'بله' : 'خیر';
  if (v is num) return key == 'active' ? (v != 0 ? 'بله' : 'خیر') : faNum(v, dec: 3);
  if (v is Map || v is List) return '';
  final String s = v.toString().trim();
  if (key == 'active' && (s == '0' || s == '1')) return s == '1' ? 'بله' : 'خیر';
  if (key == 'status' || key.endsWith('_status')) return _kStatusFa[s] ?? (RegExp(r'^[a-z_]+$').hasMatch(s) ? '' : s);
  if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) return auditWhen(s);
  if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s)) return _faNumStr(s);
  if (s.length > 120) return '${_faDigitsKeepCodes(s.substring(0, 120))}…';
  return _faDigitsKeepCodes(s);
}

/// تغییرات خوانا (قبل ← بعد) فقط برای فیلدهای شناخته‌شده؛ شناسه‌ها و فیلدهای فنی کنار گذاشته می‌شوند.
List<AuditChange> auditChanges(Map<String, dynamic> row) {
  final Map<String, dynamic> b = _json(row['before']) ?? const <String, dynamic>{};
  final Map<String, dynamic> a = _json(row['after']) ?? const <String, dynamic>{};
  final String entity = _s(row['entity']);
  final Map<String, String> labels = <String, String>{..._kFieldFa};
  if (entity.startsWith('entity.')) {
    for (final f in kEntityRegistry[entity.substring(7)]?.fields ?? const []) {
      labels[f.key] = f.label;
    }
  }
  final List<AuditChange> out = <AuditChange>[];
  final Set<String> seen = <String>{};
  for (final String k in <String>[...b.keys, ...a.keys]) {
    if (!seen.add(k)) continue;
    final String? label = labels[k];
    if (label == null) continue;
    final String vb = _value(k, b[k]), va = _value(k, a[k]);
    if (vb.isEmpty && va.isEmpty) continue;
    if (b.isNotEmpty && a.isNotEmpty && vb == va) continue; // بدون تغییر
    out.add(AuditChange(label, vb, va));
  }
  return out;
}
