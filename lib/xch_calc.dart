// v91 p5 — صراف: محاسبهٔ خالص (بدون پایگاه داده) — آینهٔ دقیق `pb_xch_run` سرور (backend/api/xch.php).
//
// هر «حرکت صراف» یکی از چهار نوع است:
//   cust_paid   مشتری به صراف پرداخت کرد   ⇒ فاکتور فروش تسویه، صراف به ما بدهکار (+)
//   paid_seller صراف به فروشندهٔ ما پرداخت کرد ⇒ فاکتور خرید تسویه، ما به صراف بدهکار (−)
//   xch_paid_us صراف به ما پرداخت کرد        ⇒ از طلب ما از صراف کم می‌شود
//   we_paid_xch ما به صراف پرداخت کردیم       ⇒ از بدهی ما به صراف کم می‌شود
// مانده هر (صراف، ارز) با «نرخ میانگین دفتری» نگه داشته می‌شود؛ تسویه به نرخ دیگر ⇒ سود/زیان تحقق‌یافته (حساب ۵۲۰۷).
// واحدها: مبلغ ارزی به همان ارز (برای IRR = ریال، نه تومان)؛ نرخ‌ها ریال بر واحد؛ نتیجه‌ها ریال صحیح.

/// انواع چهارگانهٔ حرکت و برچسب فارسی‌شان
const Map<String, String> kXchKindsFa = <String, String>{
  'cust_paid': 'مشتری به صراف پرداخت کرد',
  'paid_seller': 'صراف به فروشنده پرداخت کرد',
  'xch_paid_us': 'صراف به ما پرداخت کرد',
  'we_paid_xch': 'ما به صراف پرداخت کردیم',
};

/// توضیح یک‌خطی هر نوع حرکت (برای فرم)
const Map<String, String> kXchKindsHelp = <String, String>{
  'cust_paid': 'فاکتور فروش مشتری (به ارز خودش) تسویه می‌شود و صراف همان مبلغ را به ما بدهکار می‌شود.',
  'paid_seller': 'فاکتور خرید فروشنده (به ارز خودش) تسویه می‌شود و ما همان مبلغ را به صراف بدهکار می‌شویم.',
  'xch_paid_us': 'صراف بخشی از بدهی‌اش را (به هر ارزی) به ما داد. اگر ارز یا نرخ فرق کند، سود/زیان تفاوت نرخ حساب می‌شود.',
  'we_paid_xch': 'ما بخشی از بدهی‌مان را (به هر ارزی) به صراف دادیم. اگر ارز یا نرخ فرق کند، سود/زیان تفاوت نرخ حساب می‌شود.',
};

const int kXchScale = 10000; // مبلغ ارزی به ده‌هزارم واحد (عدد صحیح)

/// '' / IRT / RIAL ⇒ IRR
String xchNormCcy(Object? c) {
  final String s = (c ?? '').toString().trim().toUpperCase();
  return (s.isEmpty || s == 'IRT' || s == 'RIAL') ? 'IRR' : s;
}

String xchPartyKey(Object? name) => (name ?? '')
    .toString()
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

double _d(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

int _q4(double v) => (v * kXchScale).round();

/// یک حرکت صراف (از ردیف موجودیت `xch_moves`)
class XchMove {
  final String uid;
  final String date; // YYYY-MM-DD
  final String kind;
  final String exchanger;
  final String? party;
  final String? docType; // sale | purchase
  final int? docId;
  final String ccy;
  final double amountCcy;
  final double docRate;
  final String payCcy;
  final double payAmount;
  final double payRate;
  final String? cashBox;
  final String? bankAccount;
  final String? note;

  const XchMove({
    this.uid = '',
    required this.date,
    required this.kind,
    required this.exchanger,
    this.party,
    this.docType,
    this.docId,
    required this.ccy,
    required this.amountCcy,
    this.docRate = 0,
    String? payCcy,
    this.payAmount = 0,
    this.payRate = 0,
    this.cashBox,
    this.bankAccount,
    this.note,
  }) : payCcy = payCcy ?? ccy;

  factory XchMove.fromRow(Map<String, dynamic> m) {
    final String ccy = xchNormCcy(m['ccy']);
    final Object? pc = m['pay_ccy'];
    return XchMove(
      uid: (m['uid'] ?? '').toString(),
      date: (m['date'] ?? '').toString(),
      kind: (m['kind'] ?? '').toString(),
      exchanger: xchPartyKey(m['exchanger']),
      party: m['party'] == null ? null : xchPartyKey(m['party']),
      docType: m['doc_type'] as String?,
      docId: m['doc_id'] is num ? (m['doc_id'] as num).toInt() : int.tryParse('${m['doc_id'] ?? ''}'),
      ccy: ccy,
      amountCcy: _d(m['amount_ccy']),
      docRate: _d(m['doc_rate']),
      payCcy: (pc == null || '$pc'.trim().isEmpty) ? ccy : xchNormCcy(pc),
      payAmount: _d(m['pay_amount']),
      payRate: _d(m['pay_rate']),
      cashBox: m['cash_box'] as String?,
      bankAccount: m['bank_account'] as String?,
      note: m['note'] as String?,
    );
  }

  bool get isSettle => kind == 'cust_paid' || kind == 'paid_seller';
  String get key => '$exchanger\u001f$ccy';

  /// [dq4, dr]: تغییر مانده (ده‌هزارم ارز، علامت‌دار) و ارزش ریالی خود حرکت (ریال صحیح، علامت‌دار)
  (int, int) get delta {
    if (isSettle) {
      final double rate = ccy == 'IRR' ? 1.0 : docRate;
      final int r = (amountCcy * rate).round();
      return kind == 'cust_paid' ? (_q4(amountCcy), r) : (-_q4(amountCcy), -r);
    }
    final double rate = payCcy == 'IRR' ? 1.0 : payRate;
    final int v = (payAmount * rate).round();
    return kind == 'xch_paid_us' ? (-_q4(amountCcy), -v) : (_q4(amountCcy), v);
  }
}

/// نتیجهٔ یک حرکت پس از محاسبهٔ موقعیت
class XchResult {
  final int dq4;
  final int dr; // ارزش ریالی حرکت به نرخ خودش
  final int db; // تغییر ماندهٔ دفتری ریالی صراف (بدهکار +)
  final int realized; // سود (+) / زیان (−) تحقق‌یافته
  final int q4After;
  final int bAfter;
  const XchResult(this.dq4, this.dr, this.db, this.realized, this.q4After, this.bAfter);
  double get balanceAfter => q4After / kXchScale;
}

/// موقعیت یک صراف در یک ارز
class XchPosition {
  final String exchanger;
  final String ccy;
  int q4 = 0;
  int book = 0; // ریال دفتری (علامت‌دار)
  int realized = 0;
  int moves = 0;
  XchPosition(this.exchanger, this.ccy);
  double get amount => q4 / kXchScale;

  /// نرخ میانگین دفتری (ریال بر واحد) یا null وقتی مانده صفر است
  double? get avgRate => q4 == 0 ? null : (book / amount).abs();
  bool get theyOwe => q4 > 0;
  bool get weOwe => q4 < 0;
}

class XchRun {
  final List<XchResult> results; // هم‌ترتیب با ورودی
  final Map<String, XchPosition> positions; // کلید: صراف \u001f ارز
  const XchRun(this.results, this.positions);

  /// سود/زیان تحقق‌یافتهٔ کل
  int get realizedTotal => positions.values.fold(0, (int s, XchPosition p) => s + p.realized);
}

/// مرتب‌سازی استاندارد حرکت‌ها (تاریخ، بعد ترتیب ورود) — ورودی xchRun باید همین ترتیب را داشته باشد
List<XchMove> xchSorted(List<XchMove> moves) {
  final List<(int, XchMove)> ix = <(int, XchMove)>[for (int i = 0; i < moves.length; i++) (i, moves[i])];
  ix.sort(((int, XchMove) a, (int, XchMove) b) {
    final int c = a.$2.date.compareTo(b.$2.date);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return <XchMove>[for (final (int, XchMove) e in ix) e.$2];
}

/// حسابداری موقعیت با میانگین موزون — همان الگوریتم سرور (ریال صحیح، گرد کردن معمولی).
XchRun xchRun(List<XchMove> moves) {
  final Map<String, XchPosition> g = <String, XchPosition>{};
  final List<XchResult> out = <XchResult>[];
  for (final XchMove m in moves) {
    final XchPosition p = g.putIfAbsent(m.key, () => XchPosition(m.exchanger, m.ccy));
    final (int dq, int dr) = m.delta;
    int q = p.q4, b = p.book, db = 0, real = 0;
    if (dq == 0) {
      db = dr;
      b += dr;
    } else if (q == 0 || (q > 0) == (dq > 0)) {
      q += dq;
      b += dr;
      db = dr;
    } else {
      final int close = dq.abs() < q.abs() ? dq.abs() : q.abs();
      final int drClose = close == dq.abs() ? dr : (dr.toDouble() * close / dq.abs()).round();
      final int drOpen = dr - drClose;
      final int carry = close == q.abs() ? b : (b.toDouble() * close / q.abs()).round();
      real = -(drClose + carry);
      q += dq;
      b = b - carry + drOpen;
      db = -carry + drOpen;
    }
    p
      ..q4 = q
      ..book = b
      ..realized += real
      ..moves += 1;
    out.add(XchResult(dq, dr, db, real, q, b));
  }
  return XchRun(out, g);
}

/// پیش‌نمایش سود/زیان یک حرکت تازه (یا ویرایش‌شده) روی حرکت‌های موجود همان صراف و ارز.
XchResult xchPreview(List<XchMove> existing, XchMove candidate) {
  final List<XchMove> all = xchSorted(<XchMove>[
    for (final XchMove m in existing)
      if (m.key == candidate.key && (candidate.uid.isEmpty || m.uid != candidate.uid)) m,
    candidate,
  ]);
  final XchRun r = xchRun(all);
  return r.results[all.indexOf(candidate)];
}
