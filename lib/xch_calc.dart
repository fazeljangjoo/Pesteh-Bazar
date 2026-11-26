// v91 p5 — صراف: محاسبهٔ خالص (بدون پایگاه داده) — آینهٔ دقیق `pb_xch_run` سرور (backend/api/xch.php).
//
// هر «حرکت صراف» یکی از چهار نوع است:
//   cust_paid   مشتری به صراف پرداخت کرد   ⇒ فاکتور فروش تسویه، صراف به ما بدهکار (+)
//   paid_seller صراف به فروشندهٔ ما پرداخت کرد ⇒ فاکتور خرید تسویه، ما به صراف بدهکار (−)
//   xch_paid_us صراف به ما پرداخت کرد        ⇒ از طلب ما از صراف کم می‌شود
//   we_paid_xch ما به صراف پرداخت کردیم       ⇒ از بدهی ما به صراف کم می‌شود
// v92: مانده هر (صراف، ارز) «لات به لات» (FIFO؛ یا پیوند دستی links) نگه داشته می‌شود؛ تسویه به نرخ دیگر ⇒ سود/زیان تحقق‌یافته (حساب ۵۲۰۷).
// با یک لات دقیقاً همان میانگین موزون v91 است. مراحل «از طریق صراف» شناسنامه‌ها (settle_calc.dart) با kind = leg_in / leg_out وارد همین محاسبه می‌شوند.
// واحدها: مبلغ ارزی به همان ارز (برای IRR = ریال، نه تومان)؛ نرخ‌ها ریال بر واحد؛ نتیجه‌ها ریال صحیح.

import 'dart:convert';

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

  /// v92: مرحلهٔ صرافیِ یک شناسنامه (kind leg_in / leg_out): ارزش ریالی مرحله، شناسهٔ شناسنامه و مرحله، شمارهٔ شناسنامه
  final int value;
  final String stlUid;
  final String lid;
  final String? refNo;

  /// v92: لات‌هایی که این تسویه اول می‌بندد (به ترتیب؛ amt = 0 یعنی تا جای ممکن)
  final List<XchLink> links;

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
    this.value = 0,
    this.stlUid = '',
    this.lid = '',
    this.refNo,
    this.links = const <XchLink>[],
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
      links: XchLink.listFrom(m['links']),
    );
  }

  bool get isSettle => kind == 'cust_paid' || kind == 'paid_seller';

  /// v92: مرحلهٔ صرافیِ شناسنامه
  bool get isLeg => kind == 'leg_in' || kind == 'leg_out';

  /// v92: شناسهٔ لاتی که این ردیف (در صورت باز کردن موقعیت) می‌سازد — همان سرور
  String get lotId => isLeg ? 's:$stlUid:$lid' : 'm:$uid';
  String get key => '$exchanger\u001f$ccy';

  /// [dq4, dr]: تغییر مانده (ده‌هزارم ارز، علامت‌دار) و ارزش ریالی خود حرکت (ریال صحیح، علامت‌دار)
  (int, int) get delta {
    if (isLeg) return kind == 'leg_in' ? (_q4(amountCcy), value) : (-_q4(amountCcy), -value);
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

/// v92: پیوند دستی یک تسویه به یک لات
class XchLink {
  final String lot;
  final double amt;
  const XchLink(this.lot, [this.amt = 0]);
  Map<String, dynamic> toJson() => <String, dynamic>{'lot': lot, 'amt': amt};
  static List<XchLink> listFrom(Object? raw) {
    Object? v = raw;
    if (v is String) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        v = null;
      }
    }
    if (v is! List) return const <XchLink>[];
    return <XchLink>[
      for (final Object? x in v)
        if (x is Map && x['lot'] is String) XchLink(x['lot'] as String, _d(x['amt'])),
    ];
  }
}

/// v92: یک لات باز (واریز/پرداختی که هنوز با صراف تسویه نشده)
class XchLot {
  final String id;
  final String date;
  int q; // ده‌هزارم ارز، علامت‌دار (+ صراف به ما بدهکار)
  int b; // ریال دفتری، علامت‌دار
  XchLot(this.id, this.date, this.q, this.b);
  double get amount => q / kXchScale;
}

/// v92: سهم بسته‌شدهٔ یک لات توسط یک ردیف
class XchClosed {
  final String lot;
  final int q4;
  final int carry;
  final int dr;
  final int realized;
  const XchClosed(this.lot, this.q4, this.carry, this.dr, this.realized);
}

/// نتیجهٔ یک حرکت پس از محاسبهٔ موقعیت
class XchResult {
  final int dq4;
  final int dr; // ارزش ریالی حرکت به نرخ خودش
  final int db; // تغییر ماندهٔ دفتری ریالی صراف (بدهکار +)
  final int realized; // سود (+) / زیان (−) تحقق‌یافته
  final int q4After;
  final int bAfter;
  final String lot; // v92: لات این ردیف
  final List<XchClosed> closed; // v92: لات‌هایی که بست
  const XchResult(this.dq4, this.dr, this.db, this.realized, this.q4After, this.bAfter, [this.lot = '', this.closed = const <XchClosed>[]]);
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
  final List<XchLot> lots = <XchLot>[]; // v92: لات‌های باز (قدیمی‌ترین اول)
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

/// مرتب‌سازی استاندارد حرکت‌ها (تاریخ، v92: مراحل شناسنامه قبل از حرکت‌ها، بعد ترتیب ورود) — ورودی xchRun باید همین ترتیب را داشته باشد
List<XchMove> xchSorted(List<XchMove> moves) {
  final List<(int, XchMove)> ix = <(int, XchMove)>[for (int i = 0; i < moves.length; i++) (i, moves[i])];
  ix.sort(((int, XchMove) a, (int, XchMove) b) {
    int c = a.$2.date.compareTo(b.$2.date);
    if (c != 0) return c;
    c = (a.$2.isLeg ? 0 : 1).compareTo(b.$2.isLeg ? 0 : 1);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return <XchMove>[for (final (int, XchMove) e in ix) e.$2];
}

/// v92: حسابداری موقعیت با «لات»ها — همان الگوریتم سرور pb_xch_run (ریال صحیح، گرد کردن معمولی).
/// حرکت هم‌جهت ⇒ لات تازه؛ حرکت خلاف جهت ⇒ اول لات‌های پیوندشده (links)، بعد قدیمی‌ترین‌ها بسته می‌شوند، هرکدام به ارزش دفتری خودش.
XchRun xchRun(List<XchMove> moves) {
  final Map<String, XchPosition> g = <String, XchPosition>{};
  final List<XchResult> out = <XchResult>[];
  for (final XchMove m in moves) {
    final XchPosition p = g.putIfAbsent(m.key, () => XchPosition(m.exchanger, m.ccy));
    final (int dq, int dr) = m.delta;
    final String lotId = m.lotId;
    int q = p.q4, b = p.book, db = 0, real = 0;
    final List<XchClosed> closed = <XchClosed>[];
    if (dq == 0) {
      db = dr;
      b += dr;
      if (p.lots.isNotEmpty) {
        p.lots.first.b += dr;
      } else if (dr != 0) {
        p.lots.add(XchLot(lotId, m.date, 0, dr));
      }
    } else if (q == 0 || (q > 0) == (dq > 0)) {
      q += dq;
      b += dr;
      db = dr;
      p.lots.add(XchLot(lotId, m.date, dq, dr));
    } else {
      final int need = dq.abs() < q.abs() ? dq.abs() : q.abs();
      final List<(int, int)> plan = <(int, int)>[];
      const int inf = 1 << 62;
      for (final XchLink ln in m.links) {
        for (int li = 0; li < p.lots.length; li++) {
          if (p.lots[li].id == ln.lot) {
            plan.add((li, ln.amt > 0 ? _q4(ln.amt) : inf));
            break;
          }
        }
      }
      for (int li = 0; li < p.lots.length; li++) {
        plan.add((li, inf));
      }
      int done = 0, drCum = 0, carryTot = 0;
      for (final (int li, int cap) in plan) {
        if (done >= need) break;
        final XchLot l = p.lots[li];
        final int avail = l.q.abs();
        int c = avail < need - done ? avail : need - done;
        if (cap < c) c = cap;
        if (c <= 0) continue;
        final int carry = c == avail ? l.b : (l.b.toDouble() * c / avail).round();
        done += c;
        final int drPart = (done == dq.abs() ? dr : (dr.toDouble() * done / dq.abs()).round()) - drCum;
        drCum += drPart;
        l.q += l.q > 0 ? -c : c;
        l.b -= carry;
        final int r = -(drPart + carry);
        real += r;
        carryTot += carry;
        closed.add(XchClosed(l.id, c, carry, drPart, r));
      }
      p.lots.removeWhere((XchLot l) => l.q == 0);
      final int drOpen = dr - drCum;
      q += dq;
      b = b - carryTot + drOpen;
      db = -carryTot + drOpen;
      if (dq.abs() > need) p.lots.add(XchLot(lotId, m.date, dq > 0 ? dq.abs() - need : -(dq.abs() - need), drOpen));
    }
    p
      ..q4 = q
      ..book = b
      ..realized += real
      ..moves += 1;
    out.add(XchResult(dq, dr, db, real, q, b, lotId, closed));
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
