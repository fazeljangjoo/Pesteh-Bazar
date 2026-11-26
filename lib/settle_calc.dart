// v92 — «شناسنامهٔ پرداخت/وصول»: محاسبهٔ خالص (بدون پایگاه داده) — آینهٔ دقیق settle.php سرور (pb_stl_match، pb_stl_fifo، pb_stl_trail_of).
//
// هر شناسنامه = یک مبلغ به «ارز بدهی» برای یک طرف‌حساب (وصول از او یا پرداخت به او):
//   تخصیص (alloc): روی کدام فاکتورها نشست (FIFO یا دستی)؛ باقی‌مانده = علی‌الحساب (پیش‌دریافت/پیش‌پرداخت) که فاکتورهای بعدی مصرفش می‌کنند.
//   مراحل (legs): مستقیم (صندوق/بانک) یا از طریق صراف؛ هر مرحله به هر ارزی. Σ سهم مراحل = مبلغ.
// هر مرحله: V = round(مبلغ × نرخ)؛ carry = ارزش دفتری بخش تسویه‌شدهٔ فاکتورها؛ سود/زیان تحقق‌یافته = V − carry (وصول) یا carry − V (پرداخت).
// مقادیر ارزی = عدد صحیح ده‌هزارم (q4)؛ ریال صحیح؛ گرد کردن «نیمه به دور از صفر» با همان ترتیب عملیات اعشاری سرور.
import 'dart:convert';

import 'xch_calc.dart';

const int kQ = 10000;

int stlQ4(num v) => (v * kQ).round();

double _d(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

/// round(total × part / whole) — همان pb_stl_share
int stlShare(int total, int part, int whole) {
  if (whole == 0 || part == 0) return 0;
  if (part == whole) return total;
  return (total.toDouble() * part / whole).round();
}

/// کلید سند: s<id> فروش، p<id> خرید، l<uid> قرض (v92 فاز ج)
String stlDocKey(String t, Object id) => t == 'loan' ? 'l$id' : '${t == 'sale' ? 's' : 'p'}$id';

String stlFmt4(int q4) {
  final String s = (q4 / kQ).toStringAsFixed(4);
  return s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
}

/// یک فاکتور (فروش یا خرید) برای تخصیص
class StlDoc {
  final String key; // s<id> / p<id> / l<uid>
  final String t; // sale | purchase | loan
  final int id; // قرض: 0 (شناسه = uid)
  final String uid; // فقط قرض
  final String dir; // recv (فروش، قرض دادیم) | pay (خرید، قرض گرفتیم)
  final String? kind; // قرض: given | taken
  final String party;
  final String ccy; // IRR برای ریالی
  final double rate; // ریال بر واحد (IRR = 1)
  final String date;
  final int total4;
  final int book; // ریال دفتری کل
  int pre4; // بخش مصرف‌شده با ردیف‌های قبلی پرداخت/دریافت و تسویهٔ صراف v91
  final String label;
  StlDoc({required this.t, required this.id, required this.party, required this.ccy, required this.rate, required this.date, required this.total4, required this.book, this.pre4 = 0, String? label, this.uid = '', String? dir, this.kind})
      : key = t == 'loan' ? stlDocKey('loan', uid) : stlDocKey(t, id),
        dir = dir ?? (t == 'sale' || (t == 'loan' && kind == 'given') ? 'recv' : 'pay'),
        label = label ?? (t == 'loan' ? '${kind == 'taken' ? 'قرض گرفتیم' : 'قرض دادیم'} ($date)' : '${t == 'sale' ? 'فروش' : 'خرید'} #$id');
  bool get isLoan => t == 'loan';
}

/// یک مرحله
class StlLeg {
  final String lid;
  final String k; // direct | xch
  final int settle4; // سهم از بدهی (به ارز شناسنامه)
  final String ccy; // ارز پول جابه‌جاشده
  final double amount;
  final double rate; // ریال بر واحد (IRR = 1)
  final String? exchanger;
  final String? accountUid;
  final String? date;
  final String? ref;
  final String? note;

  /// v92 فاز د: مرحلهٔ «چک»: {no, bank, sayad, due}
  final Map<String, String>? cheque;
  const StlLeg({required this.lid, required this.k, required this.settle4, required this.ccy, required this.amount, required this.rate, this.exchanger, this.accountUid, this.date, this.ref, this.note, this.cheque});
  bool get isCheque => k == 'cheque';

  int get v => (amount * (ccy == 'IRR' ? 1.0 : rate)).round();
  bool get isXch => k == 'xch';

  factory StlLeg.fromJson(Map<String, dynamic> m) => StlLeg(
        lid: '${m['lid'] ?? ''}',
        k: '${m['k'] ?? 'direct'}',
        settle4: stlQ4(_d(m['settle'])),
        ccy: xchNormCcy(m['ccy']),
        amount: _d(m['amount']),
        rate: _d(m['rate']),
        exchanger: m['exchanger'] == null ? null : xchPartyKey(m['exchanger']),
        accountUid: m['account_uid'] as String?,
        date: (m['date'] as String?)?.isEmpty ?? true ? null : m['date'] as String?,
        ref: m['ref'] as String?,
        note: m['note'] as String?,
        cheque: m['cheque'] is Map ? <String, String>{for (final MapEntry<dynamic, dynamic> e in (m['cheque'] as Map).entries) '${e.key}': '${e.value ?? ''}'} : null,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'lid': lid,
        'k': k,
        'settle': double.parse(stlFmt4(settle4)),
        'ccy': ccy,
        'amount': amount,
        'rate': rate,
        if (exchanger != null) 'exchanger': exchanger,
        if (accountUid != null && accountUid!.isNotEmpty) 'account_uid': accountUid,
        if (date != null && date!.isNotEmpty) 'date': date,
        if (ref != null && ref!.isNotEmpty) 'ref': ref,
        if (note != null && note!.isNotEmpty) 'note': note,
        if (cheque != null) 'cheque': cheque,
      };
}

/// v92 فاز د: شناسهٔ منبع مرحلهٔ چک در دفتر چک سرور (source_table = settlements) — همان pb_stl_cheque_src_id: crc32("uid:lid") & 0x7fffffff + 1
int stlChequeSrcId(String uid, String lid) => (_crc32('$uid:$lid') & 0x7fffffff) + 1;

final List<int> _crcTable = List<int>.generate(256, (int n) {
  int c = n;
  for (int k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(String s) {
  int c = 0xFFFFFFFF;
  for (final int b in utf8.encode(s)) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// برچسب فارسی وضعیت چک (همان سرور)
const Map<String, String> kChequeStatusFa = <String, String>{
  'in_hand': 'نزد ما', 'deposited': 'در جریان وصول', 'cleared': 'پاس‌شده', 'bounced': 'برگشتی',
  'endorsed': 'خرج‌شده', 'returned_to_payer': 'عودت به صادرکننده', 'pending': 'صادرشده (در انتظار)', 'cancelled': 'ابطال‌شده',
};

/// یک شناسنامه
class Settlement {
  final String uid;
  final int order; // ترتیب ثبت (جای شناسهٔ سرور)
  final String date;
  final String dir; // recv | pay
  final String party;
  final String ccy;
  final int amt4;
  final String allocMode;
  final List<(String, int)> alloc; // [(کلید فاکتور، q4)]
  final List<StlLeg> legs;
  final String refNo;
  final String? note;
  const Settlement({required this.uid, required this.order, required this.date, required this.dir, required this.party, required this.ccy, required this.amt4, this.allocMode = 'fifo', this.alloc = const <(String, int)>[], required this.legs, this.refNo = '', this.note});

  bool get isRecv => dir == 'recv';
  String get docSide => isRecv ? 'sale' : 'purchase';
  String get label => '${isRecv ? 'وصول' : 'پرداخت'} — شناسنامهٔ ${refNo.isEmpty ? 'تازه' : refNo}';

  static Object? _json(Object? v) {
    if (v is String) {
      try {
        return jsonDecode(v);
      } catch (_) {
        return null;
      }
    }
    return v;
  }

  factory Settlement.fromRow(Map<String, dynamic> m, int order) {
    final Object? a = _json(m['alloc']);
    final Object? l = _json(m['legs']);
    return Settlement(
      uid: '${m['uid'] ?? ''}',
      order: order,
      date: '${m['date'] ?? ''}',
      dir: '${m['dir'] ?? 'recv'}',
      party: xchPartyKey(m['party']),
      ccy: xchNormCcy(m['ccy']),
      amt4: stlQ4(_d(m['amount_ccy'])),
      allocMode: '${m['alloc_mode'] ?? 'fifo'}',
      alloc: <(String, int)>[
        if (a is List)
          for (final Object? x in a)
            if (x is Map && x['t'] == 'loan') (stlDocKey('loan', '${x['uid'] ?? ''}'), stlQ4(_d(x['amt'])))
            else if (x is Map && (x['t'] == 'sale' || x['t'] == 'purchase')) (stlDocKey('${x['t']}', (x['id'] as num?)?.toInt() ?? int.tryParse('${x['id']}') ?? 0), stlQ4(_d(x['amt']))),
      ],
      legs: <StlLeg>[
        if (l is List)
          for (final Object? x in l)
            if (x is Map) StlLeg.fromJson(Map<String, dynamic>.from(x)),
      ],
      refNo: '${m['ref_no'] ?? ''}',
      note: m['note'] as String?,
    );
  }
}

class StlPiece {
  final String k; // کلید فاکتور یا 'adv'
  final int q4;
  final int carry;
  final int v;
  const StlPiece(this.k, this.q4, this.carry, this.v);
}

class StlLegRes {
  final String lid;
  final int settle4;
  final int v;
  int carry = 0, vDocs = 0, adv4 = 0, advV = 0, realized = 0;
  final List<StlPiece> pieces = <StlPiece>[];
  StlLegRes(this.lid, this.settle4, this.v);
}

class StlRes {
  final Settlement s;
  final Map<String, int> alloc; // کلید فاکتور ⇒ q4 (به ترتیب)
  final Map<String, StlLegRes> legs;
  final int carry, adv4, advB, realized;
  final int carryLoan; // v92 فاز ج: بخش carry روی قرض‌ها
  const StlRes(this.s, this.alloc, this.legs, this.carry, this.adv4, this.advB, this.realized, [this.carryLoan = 0]);
}

class StlBy {
  final String uid, lid, date;
  final int q4, carry;
  const StlBy(this.uid, this.lid, this.q4, this.carry, this.date);
}

class StlCons {
  final String uid; // شناسنامهٔ علی‌الحساب
  final int q4, carryDoc, carryAdv, realized;
  const StlCons(this.uid, this.q4, this.carryDoc, this.carryAdv, this.realized);
}

class StlDocRes {
  int settled4 = 0, carry = 0, cum4 = 0, open4 = 0;
  final List<StlBy> by = <StlBy>[];
  final List<StlCons> cons = <StlCons>[];
}

class StlAdvUse {
  final String k, date;
  final int q4, carryAdv, carryDoc, realized;
  const StlAdvUse(this.k, this.q4, this.carryAdv, this.carryDoc, this.realized, this.date);
}

class StlAdvLot {
  final String uid, date, party, ccy, dir;
  int q4, b;
  final int q0, b0;
  final List<StlAdvUse> used = <StlAdvUse>[];
  StlAdvLot(this.uid, this.date, this.party, this.ccy, this.dir, this.q4, this.b)
      : q0 = q4,
        b0 = b;
}

class StlMatch {
  final Map<String, StlRes> stl;
  final Map<String, StlDocRes> docs;
  final List<StlAdvLot> adv;
  const StlMatch(this.stl, this.docs, this.adv);
}

List<Settlement> stlSorted(List<Settlement> s) => <Settlement>[...s]..sort((Settlement a, Settlement b) {
      final int c = a.date.compareTo(b.date);
      return c != 0 ? c : a.order.compareTo(b.order);
    });

/// موتور اصلی — آینهٔ pb_stl_match
StlMatch stlMatch(Map<String, StlDoc> docs, List<Settlement> settlements) {
  final List<Settlement> stls = stlSorted(settlements);
  final Map<String, int> cum = <String, int>{};
  final Map<String, StlDocRes> dout = <String, StlDocRes>{};
  docs.forEach((String k, StlDoc d) {
    cum[k] = d.pre4 < d.total4 ? d.pre4 : d.total4;
    dout[k] = StlDocRes();
  });
  int take(String k, int q) {
    final StlDoc d = docs[k]!;
    final int a = cum[k]!;
    cum[k] = a + q;
    return stlShare(d.book, a + q, d.total4) - stlShare(d.book, a, d.total4);
  }

  final Map<String, StlRes> out = <String, StlRes>{};
  final List<StlAdvLot> lots = <StlAdvLot>[];
  for (final Settlement s in stls) {
    final int amt = s.amt4;
    final Map<String, int> pieces = <String, int>{};
    int used = 0;
    for (final (String k, int q0) in s.alloc) {
      int q = q0;
      if (q <= 0 || used >= amt) continue;
      final StlDoc? d = docs[k];
      if (d == null || d.dir != s.dir || d.party != s.party || d.ccy != s.ccy) continue;
      final int room = d.total4 - cum[k]! - (pieces[k] ?? 0);
      q = <int>[q, amt - used, room < 0 ? 0 : room].reduce((int x, int y) => x < y ? x : y);
      if (q <= 0) continue;
      pieces[k] = (pieces[k] ?? 0) + q;
      used += q;
    }
    final List<(String, int)> seq = <(String, int)>[for (final MapEntry<String, int> e in pieces.entries) (e.key, e.value)];
    if (amt - used > 0) seq.add(('adv', amt - used));
    final Map<String, StlLegRes> legs = <String, StlLegRes>{};
    int pi = 0;
    int pLeft = seq.isEmpty ? 0 : seq[0].$2;
    final List<(String, String, int, int)> sub = <(String, String, int, int)>[];
    for (final StlLeg l in s.legs) {
      int need = l.settle4;
      final int v = l.v;
      legs[l.lid] = StlLegRes(l.lid, l.settle4, v);
      int got = 0;
      while (need > 0 && pi < seq.length) {
        final int q = need < pLeft ? need : pLeft;
        final int vBefore = stlShare(v, got, l.settle4);
        got += q;
        final int vPart = stlShare(v, got, l.settle4) - vBefore;
        sub.add((seq[pi].$1, l.lid, q, vPart));
        need -= q;
        pLeft -= q;
        if (pLeft == 0) {
          pi++;
          pLeft = pi < seq.length ? seq[pi].$2 : 0;
        }
      }
    }
    int carryAll = 0, carryLoan = 0, advQ = 0, advB = 0, real = 0;
    final Map<String, int> alloc = <String, int>{};
    for (final (String k, String lid, int q, int vPart) in sub) {
      final StlLegRes lr = legs[lid]!;
      if (k == 'adv') {
        lr.adv4 += q;
        lr.advV += vPart;
        advQ += q;
        advB += vPart;
        lr.pieces.add(StlPiece('adv', q, vPart, vPart));
        continue;
      }
      final int c = take(k, q);
      final int r = s.isRecv ? vPart - c : c - vPart;
      lr.carry += c;
      lr.vDocs += vPart;
      lr.realized += r;
      lr.pieces.add(StlPiece(k, q, c, vPart));
      dout[k]!.settled4 += q;
      dout[k]!.carry += c;
      dout[k]!.by.add(StlBy(s.uid, lid, q, c, s.date));
      carryAll += c;
      real += r;
      if (docs[k]!.isLoan) carryLoan += c;
      alloc[k] = (alloc[k] ?? 0) + q;
    }
    if (advQ > 0) lots.add(StlAdvLot(s.uid, s.date, s.party, s.ccy, s.dir, advQ, advB));
    out[s.uid] = StlRes(s, alloc, legs, carryAll, advQ, advB, real, carryLoan);
  }
  final List<String> order = docs.keys.toList()
    ..sort((String a, String b) {
      final StlDoc x = docs[a]!, y = docs[b]!;
      int c = x.date.compareTo(y.date);
      if (c != 0) return c;
      c = x.id.compareTo(y.id);
      return c != 0 ? c : x.t.compareTo(y.t);
    });
  for (final String k in order) {
    final StlDoc d = docs[k]!;
    if (d.isLoan) continue; // علی‌الحساب فقط روی فاکتورها مصرف می‌شود
    final String dir = d.dir;
    for (final StlAdvLot l in lots) {
      final int open = d.total4 - cum[k]!;
      if (open <= 0) break;
      if (l.q4 <= 0 || l.dir != dir || l.party != d.party || l.ccy != d.ccy || l.date.compareTo(d.date) > 0) continue;
      final int q = open < l.q4 ? open : l.q4;
      final int cAdv = q == l.q4 ? l.b : stlShare(l.b, q, l.q4);
      l.q4 -= q;
      l.b -= cAdv;
      final int cDoc = take(k, q);
      final int r = dir == 'recv' ? cAdv - cDoc : cDoc - cAdv;
      dout[k]!.cons.add(StlCons(l.uid, q, cDoc, cAdv, r));
      dout[k]!.settled4 += q;
      dout[k]!.carry += cDoc;
      l.used.add(StlAdvUse(k, q, cAdv, cDoc, r, d.date));
    }
  }
  dout.forEach((String k, StlDocRes x) {
    x.cum4 = cum[k]!;
    final int o = docs[k]!.total4 - cum[k]!;
    x.open4 = o > 0 ? o : 0;
  });
  return StlMatch(out, dout, lots);
}

/// تخصیص FIFO برای شناسنامهٔ تازه — آینهٔ pb_stl_fifo
List<(String, int)> stlFifo(Map<String, StlDoc> docs, StlMatch state, String party, String ccy, String dir, String date, int amt4) {
  final String side = dir == 'recv' ? 'sale' : 'purchase';
  final List<StlDoc> c = <StlDoc>[
    for (final StlDoc d in docs.values)
      if (d.t == side && d.party == party && d.ccy == ccy && d.date.compareTo(date) <= 0 && (state.docs[d.key]?.open4 ?? 0) > 0) d,
  ]..sort((StlDoc a, StlDoc b) {
      final int x = a.date.compareTo(b.date);
      return x != 0 ? x : a.id.compareTo(b.id);
    });
  final List<(String, int)> res = <(String, int)>[];
  int left = amt4;
  for (final StlDoc d in c) {
    if (left <= 0) break;
    final int open = state.docs[d.key]!.open4;
    final int q = left < open ? left : open;
    res.add((d.key, q));
    left -= q;
  }
  return res;
}

/// مراحل صرافی شناسنامه‌ها به‌صورت ردیف‌های صراف (برای xchRun)
List<XchMove> stlLegMoves(List<Settlement> stls) => <XchMove>[
      for (final Settlement s in stlSorted(stls))
        for (final StlLeg l in s.legs)
          if (l.isXch)
            XchMove(
              uid: s.uid,
              date: (l.date ?? '').isNotEmpty ? l.date! : s.date,
              kind: s.isRecv ? 'leg_in' : 'leg_out',
              exchanger: xchPartyKey(l.exchanger),
              party: s.party,
              ccy: l.ccy,
              amountCcy: l.amount,
              value: l.v,
              stlUid: s.uid,
              lid: l.lid,
              refNo: s.refNo,
              note: l.note,
            ),
    ];

/// کل وضعیت: فاکتورها، شناسنامه‌ها، تخصیص، و موقعیت صرافان (حرکت‌ها + مراحل صرافی)
class StlState {
  final Map<String, StlDoc> docs;
  final List<Settlement> stls;
  final StlMatch match;
  final List<XchMove> xmoves; // مرتب
  final XchRun xrun;

  /// v92 فاز د: وضعیت چک‌های مرحله‌ای (شناسهٔ منبع ⇒ وضعیت) از حافظهٔ «مدیریت چک»؛ نبودن = نامعلوم
  final Map<int, String> cheques;
  const StlState(this.docs, this.stls, this.match, this.xmoves, this.xrun, [this.cheques = const <int, String>{}]);

  factory StlState.build(Map<String, StlDoc> docs, List<Settlement> stls, List<XchMove> xchMoves, {Map<int, String> cheques = const <int, String>{}}) {
    final StlMatch m = stlMatch(docs, stls);
    final List<XchMove> xm = xchSorted(<XchMove>[...xchMoves.where((XchMove x) => !x.isLeg), ...stlLegMoves(stls)]);
    return StlState(docs, stls, m, xm, xchRun(xm), cheques);
  }

  String? chequeStatus(String uid, String lid) => cheques[stlChequeSrcId(uid, lid)];

  /// نتیجهٔ یک مرحلهٔ صرافی در محاسبهٔ صراف
  XchResult? legRes(String uid, String lid) {
    for (int i = 0; i < xmoves.length; i++) {
      final XchMove x = xmoves[i];
      if (x.isLeg && x.stlUid == uid && x.lid == lid) return xrun.results[i];
    }
    return null;
  }

  Settlement? byUid(String uid) {
    for (final Settlement s in stls) {
      if (s.uid == uid) return s;
    }
    return null;
  }

  String docLabel(String k) => docs[k]?.label ?? k;
}

// ======================= شناسنامه (مراحل) =======================

/// یک مرحلهٔ بعدی (تسویهٔ صراف با ما یا مرحلهٔ دیگری که لات را بست)
class TrailNext {
  final String no;
  final String date;
  final String kind; // xch_paid_us / we_paid_xch / leg_in / leg_out / cust_paid / paid_seller
  final String uid;
  final String exchanger;
  final double closed; // به ارز لات
  final String closedCcy;
  final String? payCcy;
  final double? payAmount;
  final double? payRate;
  final int value; // ریال (قدرمطلق)
  final int carry;
  final int realized;
  final String? cashBox, bankAccount, note, refNo;
  const TrailNext({required this.no, required this.date, required this.kind, required this.uid, required this.exchanger, required this.closed, required this.closedCcy, this.payCcy, this.payAmount, this.payRate, required this.value, required this.carry, required this.realized, this.cashBox, this.bankAccount, this.note, this.refNo});
}

/// یک مرحله از شناسنامه
class TrailStage {
  final String no;
  final StlLeg leg;
  final String date;
  final String from, to;
  final StlLegRes res;
  int realized; // سود/زیان این مرحله (طرف + بستن لات صراف هنگام واریز)
  final List<TrailNext> next = <TrailNext>[];
  double openAtExchanger = 0;
  String? chequeStatus; // v92 فاز د
  TrailStage(this.no, this.leg, this.date, this.from, this.to, this.res, this.realized);
  bool get open => openAtExchanger.abs() > 0.00005 || (leg.isCheque && chequeStatus != 'cleared' && chequeStatus != 'endorsed');
}

class TrailAlloc {
  final StlDoc doc;
  final int q4;
  final int openAfter4;
  const TrailAlloc(this.doc, this.q4, this.openAfter4);
}

class Trail {
  final Settlement s;
  final StlRes res;
  final List<TrailAlloc> alloc;
  final List<TrailStage> stages;
  final List<StlAdvUse> advUse;
  final int advOpen4;
  final int realized;
  final bool complete;
  const Trail(this.s, this.res, this.alloc, this.stages, this.advUse, this.advOpen4, this.realized, this.complete);
}

/// شناسنامهٔ کامل یک ثبت — آینهٔ pb_stl_trail_of
Trail? stlTrail(StlState st, String uid) {
  final Settlement? s = st.byUid(uid);
  final StlRes? m = st.match.stl[uid];
  if (s == null || m == null) return null;
  final List<TrailAlloc> alloc = <TrailAlloc>[
    for (final MapEntry<String, int> e in m.alloc.entries)
      if (st.docs[e.key] != null) TrailAlloc(st.docs[e.key]!, e.value, st.match.docs[e.key]!.open4),
  ];
  int realTot = m.realized;
  bool complete = true;
  final List<TrailStage> stages = <TrailStage>[];
  int n = 0;
  for (final StlLeg l in s.legs) {
    n++;
    final StlLegRes r = m.legs[l.lid]!;
    String from = s.isRecv ? s.party : 'ما';
    String to = l.isXch ? (l.exchanger ?? '') : (s.isRecv ? 'ما' : s.party);
    if (l.isXch && !s.isRecv) {
      from = l.exchanger ?? '';
      to = s.party;
    }
    final TrailStage ts = TrailStage('$n', l, (l.date ?? '').isNotEmpty ? l.date! : s.date, from, to, r, r.realized);
    if (l.isCheque) { // v92 فاز د: تا پاس نشود شناسنامه باز است
      ts.chequeStatus = st.chequeStatus(uid, l.lid);
      if (ts.chequeStatus != 'cleared' && ts.chequeStatus != 'endorsed') complete = false;
    }
    if (l.isXch) {
      final String lot = 's:$uid:${l.lid}';
      final XchResult? x = st.legRes(uid, l.lid);
      if (x != null) {
        realTot += x.realized;
        ts.realized += x.realized;
      }
      int sub = 0;
      for (int i = 0; i < st.xmoves.length; i++) {
        final XchResult res = st.xrun.results[i];
        final XchMove row = st.xmoves[i];
        for (final XchClosed c in res.closed) {
          if (c.lot != lot) continue;
          sub++;
          realTot += c.realized;
          ts.next.add(TrailNext(
            no: '$n-$sub',
            date: row.date,
            kind: row.kind,
            uid: row.uid,
            exchanger: row.exchanger,
            closed: c.q4 / kXchScale,
            closedCcy: row.ccy,
            payCcy: row.isLeg ? null : row.payCcy,
            payAmount: row.isLeg ? null : double.parse((row.payAmount * c.q4 / (res.dq4.abs() == 0 ? 1 : res.dq4.abs())).toStringAsFixed(4)),
            payRate: row.isLeg ? null : row.payRate,
            value: c.dr.abs(),
            carry: c.carry.abs(),
            realized: c.realized,
            cashBox: row.cashBox,
            bankAccount: row.bankAccount,
            note: row.note,
            refNo: row.refNo,
          ));
        }
      }
      int fin = 0;
      for (final XchPosition p in st.xrun.positions.values) {
        for (final XchLot lt in p.lots) {
          if (lt.id == lot) fin = lt.q;
        }
      }
      ts.openAtExchanger = fin / kXchScale;
      if (fin != 0) complete = false;
    }
    stages.add(ts);
  }
  final List<StlAdvUse> advUse = <StlAdvUse>[];
  int advOpen = 0;
  for (final StlAdvLot l in st.match.adv) {
    if (l.uid != uid) continue;
    for (final StlAdvUse u in l.used) {
      realTot += u.realized;
      advUse.add(u);
    }
    advOpen += l.q4;
    if (l.q4 > 0) complete = false;
  }
  return Trail(s, m, alloc, stages, advUse, advOpen, realTot, complete);
}
