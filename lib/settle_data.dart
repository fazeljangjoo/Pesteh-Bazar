// v92 — «شناسنامهٔ پرداخت/وصول»: خواندن دادهٔ محلی (فاکتورها، ردیف‌های پرداخت، شناسنامه‌ها، حرکت‌های صراف) و اثر روی حساب طرف‌ها.
// همان قواعد سرور (settle.php: pb_stl_docs، pb_stl_apply_sums). محاسبهٔ خالص در settle_calc.dart.
import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import 'db.dart';
import 'entity_store.dart';
import 'ledger.dart';
import 'loan_calc.dart'; // v92 فاز ج
import 'settle_calc.dart';
import 'xch_calc.dart';
import 'cheque_ui.dart' show ChequeStore; // v92 فاز د

double _n(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

int get stlRialPerStored => AppDb.I.moneyUnit == 'rial' ? 1 : 10;

/// همان قاعدهٔ سرور: کدام جدول ردیف در این نوع پرداخت حساب می‌شود (پرداخت‌شده و برنامه‌ریزی‌شده)
bool _counts(String table, String? type, String? staged) {
  final bool lump = table.endsWith('lump_tx');
  final bool credit = table.endsWith('credit_inst');
  if (type == 'mixed') return true;
  if (lump) return type == 'lump';
  if (type != 'staged') return false;
  return credit ? staged == 'credit' : staged == 'cheque';
}

/// فاکتورهای محلی به‌صورت سند تخصیص (pre4 = بخش مصرف‌شده با ردیف‌های قبلی + تسویهٔ صراف v91). فاکتورهای همگام‌نشده (شناسهٔ منفی) هم هستند
/// تا مانده درست باشد، ولی در فرم قابل انتخاب نیستند.
Future<Map<String, StlDoc>> loadStlDocs({DatabaseExecutor? db, List<XchMove>? xchMoves}) async {
  final DatabaseExecutor d = db ?? await AppDb.I.db;
  final int mult = stlRialPerStored;
  final Map<String, StlDoc> docs = <String, StlDoc>{};
  Future<void> add(String t, String sql) async {
    List<Map<String, Object?>> rows;
    try {
      rows = await d.rawQuery(sql);
    } catch (_) {
      return;
    }
    for (final Map<String, Object?> r in rows) {
      final String ccy = xchNormCcy(r['ccy']);
      final double rate = _n(r['fx_rate']);
      final bool foreign = ccy != 'IRR' && rate > 0;
      final int book = (_n(r['stored']) * mult).round();
      final int total4 = foreign ? stlQ4(_n(r['amt'])) : book * kQ;
      if (total4 <= 0) continue;
      final StlDoc doc = StlDoc(
        t: t,
        id: (r['id'] as num).toInt(),
        party: xchPartyKey(r['party']),
        ccy: foreign ? ccy : 'IRR',
        rate: foreign ? rate : 1.0,
        date: '${r['date'] ?? ''}'.length >= 10 ? '${r['date']}'.substring(0, 10) : '${r['date'] ?? ''}',
        total4: total4,
        book: book,
        label: t == 'sale' ? 'فروش #${r['id']}' : 'خرید #${r['id']}${(r['label'] ?? '') == '' ? '' : ' (${r['label']})'}',
      );
      docs[doc.key] = doc;
    }
  }

  await add('sale', 'SELECT id, buyer AS party, date, ccy, fx_rate, total_ccy AS amt, net_weight*price AS stored, NULL AS label FROM sales');
  await add('purchase', 'SELECT id, seller AS party, date, ccy, fx_rate, price_ccy*net_weight AS amt, net_weight*price AS stored, type_name AS label FROM purchases WHERE is_mix = 0');
  if (docs.isEmpty) return docs;
  const List<(String, String, String, String, String, String)> src = <(String, String, String, String, String, String)>[
    ('lump_tx', 'payments', 'payment_id', 'purchase_id', 'pay_type', 'purchase'),
    ('credit_inst', 'payments', 'payment_id', 'purchase_id', 'pay_type', 'purchase'),
    ('cheque_inst', 'payments', 'payment_id', 'purchase_id', 'pay_type', 'purchase'),
    ('receipt_lump_tx', 'receipts', 'receipt_id', 'sale_id', 'recv_type', 'sale'),
    ('receipt_credit_inst', 'receipts', 'receipt_id', 'sale_id', 'recv_type', 'sale'),
    ('receipt_cheque_inst', 'receipts', 'receipt_id', 'sale_id', 'recv_type', 'sale'),
  ];
  for (final (String tx, String h, String fk, String docCol, String typeCol, String t) in src) {
    List<Map<String, Object?>> rows;
    try {
      rows = await d.rawQuery('SELECT h.$docCol AS doc, h.$typeCol AS tp, h.staged_type AS st, x.amount AS amount, x.ccy AS ccy, x.ccy_amount AS ca, x.doc_ccy_amount AS dca FROM $tx x JOIN $h h ON h.id = x.$fk');
    } catch (_) {
      try { // پایگاه بدون ستون v93
        rows = await d.rawQuery('SELECT h.$docCol AS doc, h.$typeCol AS tp, h.staged_type AS st, x.amount AS amount, x.ccy AS ccy, x.ccy_amount AS ca FROM $tx x JOIN $h h ON h.id = x.$fk');
      } catch (_) {
        continue;
      }
    }
    for (final Map<String, Object?> r in rows) {
      if (!_counts(tx, r['tp'] as String?, r['st'] as String?)) continue;
      final StlDoc? doc = docs[stlDocKey(t, (r['doc'] as num?)?.toInt() ?? 0)];
      if (doc == null) continue;
      final String lc = xchNormCcy(r['ccy']);
      if (doc.ccy != 'IRR' && lc == doc.ccy && r['ca'] != null) {
        doc.pre4 += stlQ4(_n(r['ca']));
      } else if (doc.ccy != 'IRR' && _n(r['dca']) > 0) { // v93: سهم به ارز فاکتور
        doc.pre4 += stlQ4(_n(r['dca']));
      } else if (doc.ccy != 'IRR') {
        doc.pre4 += stlQ4(_n(r['amount']) * mult / doc.rate);
      } else {
        doc.pre4 += stlQ4(_n(r['amount']) * mult);
      }
    }
  }
  // v92 فاز ج: قرض‌ها هم سند تخصیص‌اند (قرض دادیم ⇐ وصول، قرض گرفتیم ⇐ پرداخت)؛ بازپرداخت‌های ثبت‌شده = pre4
  final List<LoanRow> loanRows = await loadLoanRows(db: d);
  final Map<String, int> loanIds = <String, int>{for (final LoanRow r in loanRows) r.uid: r.id}; // شناسهٔ محلی (منفی = همگام‌نشده)
  final LoanMatch lm = loanMatch(loanRows, mult);
  for (final LoanLot l in lm.loans.values) {
    if (l.q4 <= 0) continue;
    final StlDoc doc = StlDoc(t: 'loan', id: loanIds[l.uid] ?? 0, uid: l.uid, kind: l.kind, party: l.party, ccy: l.ccy, rate: l.b / (l.q4 / kQ), date: l.date,
        total4: l.q4, book: l.b, pre4: l.q4 - l.open4);
    docs[doc.key] = doc;
  }
  for (final XchMove m in xchMoves ?? await loadXchMoves()) {
    if (!m.isSettle || m.docId == null) continue;
    final StlDoc? doc = docs[stlDocKey(m.docType == 'sale' ? 'sale' : 'purchase', m.docId!)];
    if (doc != null) doc.pre4 += stlQ4(m.amountCcy);
  }
  return docs;
}

/// v92 فاز ج: ردیف‌های دفتر قرض (با ستون‌های ارزی، اگر ستون‌ها هنوز نیامده باشند ریالی)
Future<List<LoanRow>> loadLoanRows({DatabaseExecutor? db}) async {
  final DatabaseExecutor d = db ?? await AppDb.I.db;
  try {
    return <LoanRow>[for (final Map<String, Object?> r in await d.query('loan_entries')) LoanRow.fromRow(r)];
  } catch (_) {
    return <LoanRow>[];
  }
}

/// شناسنامه‌های محلی به ترتیب ثبت
Future<List<Settlement>> loadSettlements() async {
  try {
    final List<Map<String, dynamic>> rows = await EntityStore.I.list('settlements');
    final List<Map<String, dynamic>> ordered = rows.reversed.toList(); // list(): جدیدترین اول ⇒ برعکس = ترتیب ثبت
    return <Settlement>[for (int i = 0; i < ordered.length; i++) Settlement.fromRow(ordered[i], i + 1)];
  } catch (_) {
    return <Settlement>[];
  }
}

/// کل وضعیت محلی (اختیاری: بدون یک شناسنامه / با یک شناسنامهٔ پیش‌نمایش)
Future<StlState> loadStlState({List<XchMove>? xchMoves, String excludeUid = '', Settlement? candidate}) async {
  final List<XchMove> xm = xchMoves ?? await loadXchMoves();
  final Map<String, StlDoc> docs = await loadStlDocs(xchMoves: xm);
  final List<Settlement> stls = <Settlement>[
    for (final Settlement s in await loadSettlements())
      if (s.uid != excludeUid) s,
    if (candidate != null) candidate,
  ];
  final Map<int, String> cheques = <int, String>{};
  try { // v92 فاز د: وضعیت چک‌های مرحله‌ای از حافظهٔ «مدیریت چک» (آخرین دریافت از سرور)
    for (final Map<String, dynamic> c in await ChequeStore.cached()) {
      if (c['source_table'] == 'settlements' && c['source_id'] is num) cheques[(c['source_id'] as num).toInt()] = '${c['status'] ?? ''}';
    }
  } catch (_) {}
  return StlState.build(docs, stls, xm, cheques: cheques);
}

/// اثر شناسنامه‌ها روی حساب طرف‌ها — آینهٔ pb_stl_apply_sums سرور (و مانده به ارز مثل موتور رویداد سرور).
void applySettlements(StlState st, PartyAccount Function(String?) acc, {int rialPerStored = 1}) {
  for (final Settlement s in st.stls) {
    final StlRes? m = st.match.stl[s.uid];
    if (m == null) continue;
    final PartyAccount p = acc(s.party);
    final DateTime dt = DateTime.tryParse(s.date) ?? DateTime(2000);
    p.dates.add(dt);
    final int rial = m.carry + m.advB;
    final double amt = rial / rialPerStored;
    final double ccyAmt = s.ccy == 'IRR' ? amt : s.amt4 / kQ;
    if (s.isRecv) {
      p.received += amt;
      p.addCcy(s.ccy, -ccyAmt);
    } else {
      p.paid += amt;
      p.addCcy(s.ccy, ccyAmt);
    }
    p.settlementUids.add(s.uid);
    for (final StlLeg l in s.legs) {
      if (l.isCheque && st.chequeStatus(s.uid, l.lid) == 'bounced') { // v92 فاز د: چک برگشتی ⇒ دوباره بدهکار/بستانکار (همان سرور)
        if (s.isRecv) {
          p.received -= l.v / rialPerStored;
        } else {
          p.paid -= l.v / rialPerStored;
        }
        p.addCcy(l.ccy, (s.isRecv ? 1 : -1) * (l.ccy == 'IRR' ? l.v / rialPerStored : l.amount));
        continue;
      }
      if (!l.isXch) continue;
      final XchResult? x = st.legRes(s.uid, l.lid);
      if (x == null) continue;
      final PartyAccount e = acc(l.exchanger);
      e.types.add('exchanger');
      final double db = x.db / rialPerStored;
      if (db >= 0) {
        e.sold += db;
      } else {
        e.bought += -db;
      }
    }
  }
  st.match.docs.forEach((String k, StlDocRes d) {
    final StlDoc doc = st.docs[k]!;
    if (d.carry == 0 && d.cons.isEmpty) return;
    final PartyAccount p = acc(doc.party);
    if (doc.isLoan) { // v92 فاز ج: بخش تسویه‌شدهٔ قرض = بازپرداخت قرض (نه دریافت/پرداخت فاکتور)
      final double c = d.carry / rialPerStored;
      if (doc.dir == 'recv') {
        p.received -= c;
        p.repaidToUs += c;
      } else {
        p.paid -= c;
        p.repaidByUs += c;
      }
      return;
    }
    if (d.carry != 0) {
      for (final PartyEntry en in p.entries) {
        if (en.isPurchase == (doc.t == 'purchase') && en.id == doc.id) {
          en.settled += d.carry / rialPerStored;
          if (doc.ccy != 'IRR') en.settledCcy += d.settled4 / kQ;
          break;
        }
      }
    }
    int diff = 0;
    for (final StlCons c in d.cons) {
      diff += c.carryDoc - c.carryAdv;
    }
    if (diff != 0) {
      if (doc.t == 'sale') {
        p.received += diff / rialPerStored;
      } else {
        p.paid += diff / rialPerStored;
      }
      if (doc.ccy == 'IRR') p.addCcy('IRR', (doc.t == 'sale' ? -diff : diff) / rialPerStored);
    }
  });
}

/// ذخیرهٔ شناسنامه (محلی + صف همگام‌سازی). خطای اعتبارسنجی محلی ⇒ ArgumentError با پیام فارسی.
Future<String> saveSettlement(Map<String, dynamic> data, {String? uid}) => EntityStore.I.save('settlements', data, uid: uid);

Future<void> deleteSettlement(String uid) => EntityStore.I.delete('settlements', uid);
