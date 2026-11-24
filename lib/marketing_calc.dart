// v90 — بازاریابی بین‌المللی: برچسب‌ها، فهرست کشورها و امتیاز ارزیابی (آینهٔ marketing_calc.php؛ تست مشترک marketing_cases.json).
import 'package:flutter/material.dart';

import 'mk_countries.dart';

export 'mk_countries.dart' show kMkCountryNames, mkCountryKey, mkCountryNorm;

const List<String> kMkStages = <String>['lead', 'contacted', 'negotiation', 'proforma', 'won', 'lost'];
const List<String> kMkOpenStages = <String>['lead', 'contacted', 'negotiation', 'proforma'];

const Map<String, String> kMkStageLabels = <String, String>{
  'lead': 'لید جدید',
  'contacted': 'ارتباط گرفته',
  'negotiation': 'مذاکره',
  'proforma': 'پیش‌فاکتور',
  'won': 'فروش',
  'lost': 'از دست رفت',
};

const Map<String, Color> kMkStageColors = <String, Color>{
  'lead': Color(0xFF64748B),
  'contacted': Color(0xFF0EA5E9),
  'negotiation': Color(0xFF8B5CF6),
  'proforma': Color(0xFFF59E0B),
  'won': Color(0xFF16A34A),
  'lost': Color(0xFFDC2626),
};

const Map<String, IconData> kMkStageIcons = <String, IconData>{
  'lead': Icons.person_add_alt_1_outlined,
  'contacted': Icons.forum_outlined,
  'negotiation': Icons.handshake_outlined,
  'proforma': Icons.request_quote_outlined,
  'won': Icons.emoji_events_outlined,
  'lost': Icons.block_outlined,
};

const Map<String, String> kMkSourceLabels = <String, String>{
  'expo': 'نمایشگاه',
  'website': 'وب‌سایت',
  'linkedin': 'لینکدین',
  'b2b': 'علی‌بابا / B2B',
  'referral': 'معرفی',
  'cold': 'تماس سرد',
  'social': 'شبکهٔ اجتماعی',
  'other': 'سایر',
};

const Map<String, String> kMkLostLabels = <String, String>{
  'price': 'قیمت',
  'quality': 'کیفیت',
  'competitor': 'رقیب',
  'no_reply': 'عدم پاسخ',
  'payment': 'تحریم / انتقال پول',
  'shipping': 'حمل',
  'other': 'سایر',
};

const Map<String, String> kMkKindLabels = <String, String>{
  'call': 'تماس',
  'message': 'واتساپ / پیام',
  'email': 'ایمیل',
  'meeting': 'جلسه / نمایشگاه',
  'sample': 'ارسال نمونه',
  'proforma': 'ارسال پیش‌فاکتور',
  'note': 'یادداشت',
  'stage': 'تغییر مرحله',
};

const Map<String, IconData> kMkKindIcons = <String, IconData>{
  'call': Icons.call_outlined,
  'message': Icons.chat_outlined,
  'email': Icons.alternate_email,
  'meeting': Icons.groups_outlined,
  'sample': Icons.inventory_2_outlined,
  'proforma': Icons.request_quote_outlined,
  'note': Icons.sticky_note_2_outlined,
  'stage': Icons.trending_up,
};

const List<String> kMkProducts = <String>['خندان', 'دهن‌بست', 'مغز', 'کال', 'سبز (مغز سبز)', 'آرد پسته', 'پوست'];
const List<String> kMkCurrencies = <String>['USD', 'EUR', 'AED', 'CNY', 'TRY', 'INR', 'RUB', 'IRR'];

/// کشورهای پرکاربرد بازار پسته (کد ISO دوحرفی ⇒ نام فارسی). ترتیب = ترتیب نمایش.
const Map<String, String> kMkCountries = <String, String>{
  'CN': 'چین', 'HK': 'هنگ‌کنگ', 'IN': 'هند', 'TR': 'ترکیه', 'AE': 'امارات', 'IQ': 'عراق', 'AF': 'افغانستان', 'PK': 'پاکستان',
  'RU': 'روسیه', 'KZ': 'قزاقستان', 'UZ': 'ازبکستان', 'TM': 'ترکمنستان', 'AZ': 'آذربایجان', 'AM': 'ارمنستان', 'GE': 'گرجستان',
  'SA': 'عربستان', 'QA': 'قطر', 'KW': 'کویت', 'OM': 'عمان', 'BH': 'بحرین', 'JO': 'اردن', 'LB': 'لبنان', 'SY': 'سوریه', 'EG': 'مصر',
  'DE': 'آلمان', 'IT': 'ایتالیا', 'ES': 'اسپانیا', 'FR': 'فرانسه', 'NL': 'هلند', 'BE': 'بلژیک', 'GB': 'انگلستان', 'PL': 'لهستان',
  'GR': 'یونان', 'AT': 'اتریش', 'CH': 'سوئیس', 'SE': 'سوئد', 'UA': 'اوکراین', 'BY': 'بلاروس', 'RS': 'صربستان', 'XK': 'کوزوو',
  'AL': 'آلبانی', 'BG': 'بلغارستان', 'RO': 'رومانی', 'US': 'آمریکا', 'CA': 'کانادا', 'BR': 'برزیل', 'MX': 'مکزیک', 'AU': 'استرالیا',
  'VN': 'ویتنام', 'TH': 'تایلند', 'MY': 'مالزی', 'ID': 'اندونزی', 'SG': 'سنگاپور', 'KR': 'کره جنوبی', 'JP': 'ژاپن', 'TW': 'تایوان',
  'BD': 'بنگلادش', 'LK': 'سری‌لانکا', 'NP': 'نپال', 'TJ': 'تاجیکستان', 'KG': 'قرقیزستان', 'MA': 'مراکش', 'DZ': 'الجزایر', 'TN': 'تونس',
  'LY': 'لیبی', 'ZA': 'آفریقای جنوبی', 'KE': 'کنیا', 'NG': 'نیجریه', 'IR': 'ایران',
};

/// پرچم ایموجی از کد ISO دوحرفی (کد نامعتبر ⇒ کرهٔ زمین).
String mkFlag(String? iso) {
  final String c = (iso ?? '').trim().toUpperCase();
  if (c.length != 2 || c.codeUnits.any((int u) => u < 65 || u > 90)) return '🌐';
  return String.fromCharCodes(c.codeUnits.map((int u) => 0x1F1E6 + u - 65));
}

String mkCountryName(String? iso) {
  final String c = (iso ?? '').trim().toUpperCase();
  if (c.isEmpty || c == '--') return 'نامشخص';
  return kMkCountries[c] ?? kMkCountryNames[c]?.first ?? c;
}

/// v91: همهٔ کشورها برای انتخاب در فرم — پرکاربردها اول (ترتیب kMkCountries)، بعد بقیه به ترتیب الفبای فارسی.
final List<MapEntry<String, String>> kMkCountryChoices = <MapEntry<String, String>>[
  ...kMkCountries.entries,
  ...(kMkCountryNames.entries.where((MapEntry<String, List<String>> e) => !kMkCountries.containsKey(e.key)).map((MapEntry<String, List<String>> e) => MapEntry<String, String>(e.key, e.value.first)).toList()
    ..sort((MapEntry<String, String> a, MapEntry<String, String> b) => a.value.compareTo(b.value))),
];

/// v91: متن آزاد «منبع آشنایی» (مثلاً «Gulfood 2026» یا «نمایشگاه استانبول 2025») ⇒ کلید دسته‌بندی.
/// برچسب یا کلید دقیق ⇒ همان؛ وگرنه از روی کلمه‌های کلیدی؛ ناشناخته ⇒ 'other'. متن اصلی جدا در source_detail می‌ماند.
String mkSourceKey(String raw) {
  final String t = mkCountryNorm(raw);
  if (t.isEmpty) return 'other';
  for (final MapEntry<String, String> e in kMkSourceLabels.entries) {
    if (t == mkCountryNorm(e.key) || t == mkCountryNorm(e.value)) return e.key;
  }
  bool has(List<String> words) => words.any((String w) => t.contains(mkCountryNorm(w)));
  if (has(<String>['نمایشگاه', 'expo', 'exhibition', 'fair', 'gulfood', 'sial', 'anuga', 'foodex', 'worldfood', 'همایش', 'summit'])) return 'expo';
  if (has(<String>['لینکدین', 'linkedin'])) return 'linkedin';
  if (has(<String>['علی‌بابا', 'علی بابا', 'alibaba', 'b2b', 'tradekey', 'made-in-china', 'indiamart', 'ec21'])) return 'b2b';
  if (has(<String>['معرفی', 'معرف', 'referral', 'refer', 'دوست', 'همکار'])) return 'referral';
  if (has(<String>['تماس سرد', 'cold'])) return 'cold';
  if (has(<String>['اینستاگرام', 'instagram', 'تلگرام', 'telegram', 'واتساپ', 'whatsapp', 'facebook', 'فیسبوک', 'شبکه', 'social', 'youtube', 'یوتیوب', 'tiktok'])) return 'social';
  if (has(<String>['سایت', 'وب', 'website', 'web', 'google', 'گوگل', 'سرچ', 'search', 'www', 'http'])) return 'website';
  return 'other';
}

/// وزن‌ها و ضریب‌های امتیاز (پیش‌فرض = شیت ارزیابی).
class MkWeights {
  const MkWeights({
    this.lead = 5,
    this.negotiation = 15,
    this.proforma = 30,
    this.sale = 70,
    this.ton = 7,
    this.collection = 100,
    this.noSaleFactor = 0.4,
    this.perSaleDeduct = 50,
  });
  final double lead, negotiation, proforma, sale, ton, collection, noSaleFactor, perSaleDeduct;

  static MkWeights fromSettings(Map<String, dynamic>? s) {
    double g(String k, double d) {
      final Object? v = s?[k];
      if (v is num) return v.toDouble();
      return double.tryParse('${v ?? ''}') ?? d;
    }

    return MkWeights(
      lead: g('w_lead', 5),
      negotiation: g('w_negotiation', 15),
      proforma: g('w_proforma', 30),
      sale: g('w_sale', 70),
      ton: g('w_ton', 7),
      collection: g('w_collection', 100),
      noSaleFactor: g('no_sale_factor', 0.4),
      perSaleDeduct: g('per_sale_deduct', 50),
    );
  }
}

/// شمارش‌های یک دوره (همان ستون‌های شیت ارزیابی).
class MkCounts {
  const MkCounts({this.followUps = 0, this.newLeads = 0, this.negotiations = 0, this.proformas = 0, this.sales = 0, this.tons = 0, this.collections = 0});
  final double followUps, newLeads, negotiations, proformas, sales, tons, collections;

  static MkCounts fromJson(Map<String, dynamic>? j) {
    double g(String k) => ((j?[k] as num?) ?? 0).toDouble();
    return MkCounts(
        followUps: g('follow_ups'), newLeads: g('new_leads'), negotiations: g('negotiations'), proformas: g('proformas'), sales: g('sales'), tons: g('tons'), collections: g('collections'));
  }
}

class MkScore {
  const MkScore(this.points, this.total, this.finalScore);
  final Map<String, double> points;
  final double total;
  final double finalScore;
}

/// امتیاز: لید×5 + مذاکره×15 + پیش‌فاکتور×30 + فروش×70 + تن×7 + وصول×100 ؛ نهایی: بدون فروش ⇒ ×0.4 ، وگرنه − 50 × فروش.
MkScore mkScore(MkCounts m, [MkWeights w = const MkWeights()]) {
  final Map<String, double> p = <String, double>{
    'new_leads': m.newLeads * w.lead,
    'negotiations': m.negotiations * w.negotiation,
    'proformas': m.proformas * w.proforma,
    'sales': m.sales * w.sale,
    'tons': m.tons * w.ton,
    'collections': m.collections * w.collection,
  };
  final double total = p.values.fold(0, (double a, double b) => a + b);
  final double fin = m.sales <= 0 ? total * w.noSaleFactor : total - m.sales * w.perSaleDeduct;
  return MkScore(p, total, fin);
}

/// نسبت امن (b = 0 ⇒ null)
double? mkRate(num a, num b) => b > 0 ? a / b : null;
