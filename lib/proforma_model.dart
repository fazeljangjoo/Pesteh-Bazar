import 'dart:convert';
import 'dart:typed_data';

/// v96 — پیش‌فاکتور صادراتی (بازاریابی بین‌المللی): مدل مشترک قالب و پیش‌فاکتور.
/// قالب = تنظیمات ثابت شرکت (سربرگ، رنگ‌ها، فروشنده، بانک، مشخصات کیفی، شرایط، مدارک و ردیف‌های پیش‌فرض)؛
/// هر پیش‌فاکتور یک کپی از قالب است که اطلاعات همان فروش (خریدار، اقلام، مبالغ...) در آن پر و ویرایش می‌شود.

const int kPfMaxRows = 20;

class PfItem {
  String type, grade, ounce, unit;
  double qty, price;
  PfItem({this.type = '', this.grade = '', this.ounce = '', this.qty = 0, this.unit = 'MT', this.price = 0});

  /// کیلوگرم هر واحد (MT = ۱۰۰۰)
  double get kg => qty * (unit == 'MT' ? 1000 : 1);
  double get total => kg * price;

  Map<String, dynamic> toJson() => <String, dynamic>{'type': type, 'grade': grade, 'ounce': ounce, 'qty': qty, 'unit': unit, 'price': price};
  factory PfItem.fromJson(Map<dynamic, dynamic> m) => PfItem(
        type: '${m['type'] ?? ''}',
        grade: '${m['grade'] ?? ''}',
        ounce: '${m['ounce'] ?? ''}',
        qty: _num(m['qty']),
        unit: '${m['unit'] ?? 'MT'}' == 'kg' ? 'kg' : 'MT',
        price: _num(m['price']),
      );
}

/// ردیف «عنوان | مقدار» (شرایط پرداخت، بسته‌بندی/HS/تحویل، بانک، مشخصات کیفی)
class PfPair {
  String label, value;
  PfPair(this.label, this.value);
  Map<String, dynamic> toJson() => <String, dynamic>{'label': label, 'value': value};
  factory PfPair.fromJson(Object? m) => m is Map ? PfPair('${m['label'] ?? ''}', '${m['value'] ?? ''}') : PfPair('', '');
}

class PfData {
  // ---- سربرگ و رنگ‌ها ----
  String company, tagline, title, logo; // logo = data URL یا ''
  String cPrimary, cAccent, cLight, cTagline; // hex بدون #
  // ---- اطلاعات کلی ----
  String seller, buyer, footer, ccy, signLeft, signRight;
  String number, date; // date = yyyy-MM-dd (میلادی)
  int nextNo; // فقط قالب: شمارهٔ پیشنهادی بعدی
  List<PfItem> items;
  List<PfPair> payment, info, bank, quality;
  List<String> conditions, documents;

  PfData({
    this.company = '',
    this.tagline = '',
    this.title = 'PROFORMA INVOICE',
    this.logo = '',
    this.cPrimary = '2F4A2B',
    this.cAccent = 'B08D3C',
    this.cLight = 'F1F5EC',
    this.cTagline = 'E6D9AE',
    this.seller = '',
    this.buyer = '',
    this.footer = '',
    this.ccy = 'USD',
    this.signLeft = 'Seller',
    this.signRight = 'Buyer',
    this.number = '',
    this.date = '',
    this.nextNo = 1,
    List<PfItem>? items,
    List<PfPair>? payment,
    List<PfPair>? info,
    List<PfPair>? bank,
    List<PfPair>? quality,
    List<String>? conditions,
    List<String>? documents,
  })  : items = items ?? <PfItem>[],
        payment = payment ?? <PfPair>[],
        info = info ?? <PfPair>[],
        bank = bank ?? <PfPair>[],
        quality = quality ?? <PfPair>[],
        conditions = conditions ?? <String>[],
        documents = documents ?? <String>[];

  double get total => items.fold<double>(0, (double s, PfItem i) => s + i.total);

  Uint8List? get logoBytes {
    final int i = logo.indexOf('base64,');
    if (i < 0) return null;
    try {
      return base64Decode(logo.substring(i + 7));
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson({bool withLogo = true}) => <String, dynamic>{
        'company': company, 'tagline': tagline, 'title': title, if (withLogo) 'logo': logo,
        'c_primary': cPrimary, 'c_accent': cAccent, 'c_light': cLight, 'c_tagline': cTagline,
        'seller': seller, 'buyer': buyer, 'footer': footer, 'ccy': ccy, 'sign_left': signLeft, 'sign_right': signRight,
        'number': number, 'date': date, 'next_no': nextNo,
        'items': <Map<String, dynamic>>[for (final PfItem i in items.take(kPfMaxRows)) i.toJson()],
        'payment': <Map<String, dynamic>>[for (final PfPair p in payment.take(kPfMaxRows)) p.toJson()],
        'info': <Map<String, dynamic>>[for (final PfPair p in info.take(kPfMaxRows)) p.toJson()],
        'bank': <Map<String, dynamic>>[for (final PfPair p in bank.take(kPfMaxRows)) p.toJson()],
        'quality': <Map<String, dynamic>>[for (final PfPair p in quality.take(kPfMaxRows)) p.toJson()],
        'conditions': conditions.take(kPfMaxRows).toList(),
        'documents': documents.take(kPfMaxRows).toList(),
      };

  factory PfData.fromJson(Object? raw) {
    final Map<dynamic, dynamic> m = raw is Map ? raw : (raw is String ? (_tryJson(raw) ?? <dynamic, dynamic>{}) : <dynamic, dynamic>{});
    String s(String k, String d) => m[k] == null ? d : '${m[k]}';
    List<PfPair> pairs(String k) => <PfPair>[for (final Object? e in (m[k] as List?) ?? const <Object?>[]) PfPair.fromJson(e)];
    List<String> strs(String k) => <String>[for (final Object? e in (m[k] as List?) ?? const <Object?>[]) '${e ?? ''}'];
    return PfData(
      company: s('company', ''),
      tagline: s('tagline', ''),
      title: s('title', 'PROFORMA INVOICE'),
      logo: s('logo', ''),
      cPrimary: _hex(s('c_primary', ''), '2F4A2B'),
      cAccent: _hex(s('c_accent', ''), 'B08D3C'),
      cLight: _hex(s('c_light', ''), 'F1F5EC'),
      cTagline: _hex(s('c_tagline', ''), 'E6D9AE'),
      seller: s('seller', ''),
      buyer: s('buyer', ''),
      footer: s('footer', ''),
      ccy: s('ccy', 'USD'),
      signLeft: s('sign_left', 'Seller'),
      signRight: s('sign_right', 'Buyer'),
      number: s('number', ''),
      date: s('date', ''),
      nextNo: _num(m['next_no']).toInt() < 1 ? 1 : _num(m['next_no']).toInt(),
      items: <PfItem>[for (final Object? e in (m['items'] as List?) ?? const <Object?>[]) if (e is Map) PfItem.fromJson(e)],
      payment: pairs('payment'),
      info: pairs('info'),
      bank: pairs('bank'),
      quality: pairs('quality'),
      conditions: strs('conditions'),
      documents: strs('documents'),
    );
  }

  PfData copy() => PfData.fromJson(jsonDecode(jsonEncode(toJson())));

  /// قالب آماده (همان چیدمان و رنگ‌های نمونه)؛ اطلاعات شرکت را مدیر جایگزین می‌کند.
  factory PfData.sample() => PfData(
        company: 'YOUR COMPANY NAME',
        tagline: 'Premium Iranian Pistachio Exporter',
        seller: 'Company name\nAddress ...\nPhone +98 ...  Email ...',
        footer: 'Factory address ...  -  Tel: +98 ...\nwww.example.com',
        nextNo: 1001,
        items: <PfItem>[PfItem(type: 'Akbari', grade: 'AA', ounce: '22-24', qty: 10, unit: 'MT', price: 0)],
        payment: <PfPair>[PfPair('Deposit', ''), PfPair('Upon Preparation', '')],
        info: <PfPair>[PfPair('Packing', '50-kg plastic bags'), PfPair('HS Code', '08025100'), PfPair('Delivery Terms', 'FCA Rafsanjan Customs')],
        bank: <PfPair>[PfPair('Bank Name', ''), PfPair('Swift Code (BIC)', ''), PfPair('Branch Name', ''), PfPair('USD Account', ''), PfPair('EUR Account', '')],
        quality: <PfPair>[
          PfPair('Natural Open', 'Min 85%'), PfPair('Closed-Shell', 'Max 5%'),
          PfPair('Foreign Materials', 'Max 0.05%'), PfPair('Shell Pieces', 'Max 0.02%'),
          PfPair('Dark Stains', 'Max 7%'), PfPair('Insect Damage', 'Max 0.0%'),
          PfPair('Crinkled Shells', 'Max 2%'), PfPair('Adhering Hulls', 'Max 2%'),
          PfPair('Moisture Content', 'Max 6.0%'), PfPair('Kernel Yield', '52 gr ± 0.5 gr'),
        ],
        conditions: <String>[
          'If the prepayment is not received within a maximum of ... working days of the issuance date, this Proforma Invoice will be automatically cancelled.',
          'The goods shall be delivered within a maximum of ten (10) working days from the date of receipt of the advance payment.',
          'The goods shall be handed over to the Buyer\'s nominated carrier only after receipt of the full outstanding balance in cleared funds.',
        ],
        documents: <String>[
          'Certificate of Origin', 'Phytosanitary Certificate', 'Aflatoxin Test Report', 'Health Certificate', 'Microbiology Test Report',
          'Export customs declaration and related documents', 'Commercial Invoice and packing list', 'Shipping document (Original BL or ...)',
          'Certificate of analysis',
        ],
      );
}

double _num(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}'.replaceAll(',', '')) ?? 0);
Map<dynamic, dynamic>? _tryJson(String s) {
  try {
    final Object? o = jsonDecode(s);
    return o is Map ? o : null;
  } catch (_) {
    return null;
  }
}

String _hex(String v, String d) {
  final String h = v.replaceAll('#', '').trim().toUpperCase();
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(h) ? h : d;
}

// ---------------- قالب‌بندی متن ----------------

String pfCcySymbol(String ccy) => switch (ccy.toUpperCase()) { 'USD' => r'$', 'EUR' => '€', 'GBP' => '£', 'AED' => 'AED ', 'CNY' => '¥', _ => '${ccy.toUpperCase()} ' };

String _group(String intPart) {
  final StringBuffer b = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) b.write(',');
    b.write(intPart[i]);
  }
  return b.toString();
}

/// 170000 ⇒ "$170,000.00"
String pfMoney(double v, String ccy, {int decimals = 2}) {
  final bool neg = v < 0;
  final List<String> parts = v.abs().toStringAsFixed(decimals).split('.');
  final String s = _group(parts[0]) + (parts.length > 1 ? '.${parts[1]}' : '');
  return '${neg ? '-' : ''}${pfCcySymbol(ccy)}$s';
}

/// قیمت هر کیلو بدون صفرهای اضافه: 17 ⇒ "$17"، 17.5 ⇒ "$17.50"
String pfUnitPrice(double v, String ccy) => v == v.roundToDouble() ? '${pfCcySymbol(ccy)}${_group(v.toStringAsFixed(0))}' : pfMoney(v, ccy);

/// عدد بدون صفر اضافه: 10.0 ⇒ "10"، 2.5 ⇒ "2.5"
String pfQty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

/// yyyy-MM-dd ⇒ dd/MM/yyyy
String pfDate(String iso) {
  final List<String> p = iso.split('-');
  if (p.length != 3) return iso;
  return '${p[2].padLeft(2, '0')}/${p[1].padLeft(2, '0')}/${p[0]}';
}

/// مقدار عددی «شرایط پرداخت»: اگر عدد باشد با ارز قالب‌بندی می‌شود، وگرنه همان متن.
String pfPayValue(String v, String ccy) {
  final double? n = double.tryParse(v.replaceAll(',', '').trim());
  return n == null ? v : pfMoney(n, ccy);
}
