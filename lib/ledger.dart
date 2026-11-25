import 'dart:convert';

import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import 'db.dart';
import 'entity_store.dart'; // v91 p5: xch_moves
import 'return_calc.dart';
import 'xch_calc.dart'; // v91 p5

/// یکسان‌سازی نام طرف حساب: «ي/ك» عربی، فاصله‌های اضافه
String partyKey(String? name) {
  if (name == null) return '';
  return name
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

// ======================= سررسیدها =======================

/// یک تراکنش پرداخت‌نشده (یکجا/قسط/چک) از خرید (پرداختی) یا فروش (دریافتی)
class DueItem {
  final String table; // نام جدول برای علامت‌گذاری «انجام شد»
  final int id;
  final bool receivable; // true = باید از خریدار بگیریم، false = باید به فروشنده بدهیم
  final String kind; // یکجا | قسط | چک
  final String party;
  final String label;
  final String? ref; // شماره چک
  final String? bank;
  final double amount;
  final DateTime date;
  final bool paid;
  DueItem({
    required this.table,
    required this.id,
    required this.receivable,
    required this.kind,
    required this.party,
    required this.label,
    required this.ref,
    required this.bank,
    required this.amount,
    required this.date,
    required this.paid,
  });
}

/// منبع‌های شش‌گانهٔ سررسید: (جدول، ستون طرف‌حساب، join، شرط، دریافتنی؟) — همان شرط‌های loadDues / سرور `pb_dues_credit_meta`.
const List<(String, String, String, String, bool)> _kDueSources = <(String, String, String, String, bool)>[
  ('lump_tx', 'p.seller', 'JOIN payments pay ON pay.id = x.payment_id JOIN purchases p ON p.id = pay.purchase_id',
      "pay.pay_type IN ('lump', 'mixed')", false),
  ('credit_inst', 'p.seller', 'JOIN payments pay ON pay.id = x.payment_id JOIN purchases p ON p.id = pay.purchase_id',
      "(pay.pay_type = 'mixed' OR (pay.pay_type = 'staged' AND pay.staged_type = 'credit'))", false),
  ('cheque_inst', 'p.seller', 'JOIN payments pay ON pay.id = x.payment_id JOIN purchases p ON p.id = pay.purchase_id',
      "(pay.pay_type = 'mixed' OR (pay.pay_type = 'staged' AND pay.staged_type = 'cheque'))", false),
  ('receipt_lump_tx', 's.buyer', 'JOIN receipts rec ON rec.id = x.receipt_id JOIN sales s ON s.id = rec.sale_id',
      "rec.recv_type = 'lump'", true),
  ('receipt_credit_inst', 's.buyer', 'JOIN receipts rec ON rec.id = x.receipt_id JOIN sales s ON s.id = rec.sale_id',
      "rec.recv_type = 'staged' AND rec.staged_type = 'credit'", true),
  ('receipt_cheque_inst', 's.buyer', 'JOIN receipts rec ON rec.id = x.receipt_id JOIN sales s ON s.id = rec.sale_id',
      "rec.recv_type = 'staged' AND rec.staged_type = 'cheque'", true),
];

/// Σ credit_used ردیف‌های «پرداخت‌شدهٔ» هر طرف‌حساب (کلید = partyKey) به تفکیک سمت — اعتباری که قبلاً مصرف شده است.
Future<({Map<String, double> receivable, Map<String, double> payable})> loadCreditUsed() async {
  final d = await AppDb.I.db;
  final r = <String, double>{};
  final p = <String, double>{};
  for (final (String t, String pcol, String join, String cond, bool recv) in _kDueSources) {
    final rows = await d.rawQuery('SELECT $pcol AS party, SUM(COALESCE(x.credit_used, 0)) AS u FROM $t x $join '
        'WHERE x.paid = 1 AND COALESCE(x.credit_used, 0) > 0 AND $cond GROUP BY $pcol');
    for (final row in rows) {
      final k = partyKey(row['party'] as String?);
      final m = recv ? r : p;
      m[k] = (m[k] ?? 0) + ((row['u'] as num?) ?? 0).toDouble();
    }
  }
  return (receivable: r, payable: p);
}

/// اعتبار برگشت هر طرف‌حساب = Σ ارزش برگشت − Σ مبلغ بازپرداخت‌شده − Σ credit_used ردیف‌های پرداخت‌شدهٔ همان طرف
/// (کلید = partyKey؛ هرگز منفی نمی‌شود). receivable: برگشت از فروش، payable: برگشت از خرید.
Future<({Map<String, double> receivable, Map<String, double> payable})> loadReturnCredits() async {
  final d = await AppDb.I.db;
  Future<Map<String, double>> sums(String tbl, String itbl) async {
    final m = <String, double>{};
    final rows = await d.rawQuery('''
        SELECT r.party AS party, COALESCE(r.refund_amount, 0) AS refund,
               COALESCE((SELECT SUM(i.kg * i.unit_price) FROM $itbl i WHERE i.return_id = r.id), 0) AS total
        FROM $tbl r''');
    for (final r in rows) {
      final k = partyKey(r['party'] as String?);
      m[k] = (m[k] ?? 0) + (r['total'] as num).toDouble() - (r['refund'] as num).toDouble();
    }
    return m;
  }

  final recv = await sums('sale_returns', 'sale_return_items');
  final pay = await sums('purchase_returns', 'purchase_return_items');
  final used = await loadCreditUsed();
  used.receivable.forEach((k, v) => recv[k] = (recv[k] ?? 0) - v);
  used.payable.forEach((k, v) => pay[k] = (pay[k] ?? 0) - v);
  recv.removeWhere((k, v) => v <= 0);
  pay.removeWhere((k, v) => v <= 0);
  return (receivable: recv, payable: pay);
}

/// سررسیدها بدون اعمال اعتبار برگشت (مبلغ‌ها همان مبلغ ذخیره‌شده‌اند).
Future<List<DueItem>> _loadDuesRaw({bool includePaid = false}) async {
  final d = await AppDb.I.db;
  final out = <DueItem>[];

  Future<void> add(String sql, String table, bool receivable, String kind) async {
    final rows = await d.rawQuery(sql);
    for (final r in rows) {
      final paid = ((r['paid'] as num?) ?? 0) == 1;
      if (paid && !includePaid) continue;
      out.add(DueItem(
        table: table,
        id: r['id'] as int,
        receivable: receivable,
        kind: kind,
        party: partyKey(r['party'] as String?),
        label: (r['label'] as String?) ?? '',
        ref: r['ref'] as String?,
        bank: r['bank'] as String?,
        amount: (r['amount'] as num).toDouble(),
        date: DateTime.parse(r['date'] as String),
        paid: paid,
      ));
    }
  }

  // ---- پرداختی‌ها (خرید) ----
  const payBase = 'FROM %T% x JOIN payments pay ON pay.id = x.payment_id '
      'JOIN purchases p ON p.id = pay.purchase_id ';
  await add(
      'SELECT x.id AS id, x.amount AS amount, x.date AS date, x.paid AS paid, '
      'p.seller AS party, p.type_name AS label, NULL AS ref, NULL AS bank '
      '${payBase.replaceAll('%T%', 'lump_tx')} WHERE pay.pay_type IN (\'lump\', \'mixed\')',
      'lump_tx',
      false,
      'یکجا');
  await add(
      'SELECT x.id AS id, x.amount AS amount, x.due_date AS date, x.paid AS paid, '
      'p.seller AS party, p.type_name AS label, NULL AS ref, NULL AS bank '
      '${payBase.replaceAll('%T%', 'credit_inst')} '
      'WHERE (pay.pay_type = \'mixed\' OR (pay.pay_type = \'staged\' AND pay.staged_type = \'credit\'))',
      'credit_inst',
      false,
      'قسط');
  await add(
      'SELECT x.id AS id, x.amount AS amount, x.due_date AS date, x.paid AS paid, '
      'p.seller AS party, p.type_name AS label, x.cheque_no AS ref, x.bank_name AS bank '
      '${payBase.replaceAll('%T%', 'cheque_inst')} '
      'WHERE (pay.pay_type = \'mixed\' OR (pay.pay_type = \'staged\' AND pay.staged_type = \'cheque\'))',
      'cheque_inst',
      false,
      'چک');

  // ---- دریافتی‌ها (فروش) ----
  const recBase = 'FROM %T% x JOIN receipts rec ON rec.id = x.receipt_id '
      'JOIN sales s ON s.id = rec.sale_id ';
  await add(
      'SELECT x.id AS id, x.amount AS amount, x.date AS date, x.paid AS paid, '
      's.buyer AS party, \'فروش\' AS label, NULL AS ref, NULL AS bank '
      '${recBase.replaceAll('%T%', 'receipt_lump_tx')} WHERE rec.recv_type = \'lump\'',
      'receipt_lump_tx',
      true,
      'یکجا');
  await add(
      'SELECT x.id AS id, x.amount AS amount, x.due_date AS date, x.paid AS paid, '
      's.buyer AS party, \'فروش\' AS label, NULL AS ref, NULL AS bank '
      '${recBase.replaceAll('%T%', 'receipt_credit_inst')} '
      'WHERE rec.recv_type = \'staged\' AND rec.staged_type = \'credit\'',
      'receipt_credit_inst',
      true,
      'قسط');
  await add(
      'SELECT x.id AS id, x.amount AS amount, x.due_date AS date, x.paid AS paid, '
      's.buyer AS party, \'فروش\' AS label, x.cheque_no AS ref, x.bank_name AS bank '
      '${recBase.replaceAll('%T%', 'receipt_cheque_inst')} '
      'WHERE rec.recv_type = \'staged\' AND rec.staged_type = \'cheque\'',
      'receipt_cheque_inst',
      true,
      'چک');

  // ---- سررسید قرض و وام (اعطای قرض = دریافتی ما، دریافت قرض = پرداختیِ ما) ----
  for (final r in await AppDb.I.loanDueRows(includePaid: includePaid)) {
    final given = r['kind'] == 'given';
    out.add(DueItem(
      table: 'loan_dues',
      id: r['id'] as int,
      receivable: given,
      kind: 'قرض',
      party: partyKey(r['party'] as String?),
      label: given ? 'قرض اعطایی' : 'قرض دریافتی',
      ref: null,
      bank: null,
      amount: (r['amount'] as num).toDouble(),
      date: DateTime.parse(r['due_date'] as String),
      paid: ((r['paid'] as num?) ?? 0) == 1,
    ));
  }

  return out;
}

List<DueRow> _creditRows(List<DueItem> out) => <DueRow>[
      for (final x in out)
        (
          party: x.party,
          receivable: x.receivable,
          paid: x.paid,
          eligible: x.table != 'loan_dues',
          date: x.date,
          amount: x.amount,
        ),
    ];

/// اعتباری که این ردیفِ پرداخت‌نشده همین الان مصرف می‌کند (0 اگر اعتباری نباشد/ردیف پرداخت‌شده باشد).
/// همان تخصیص loadDues: نزدیک‌ترین سررسید اول، با استخرِ بعد از کسر credit_used ردیف‌های پرداخت‌شده.
Future<double> dueCreditTake(String table, int id) async {
  if (table == 'loan_dues') return 0;
  final credits = await loadReturnCredits();
  if (credits.receivable.isEmpty && credits.payable.isEmpty) return 0;
  final raw = await _loadDuesRaw();
  final takes = allocateReturnCredit(
      rows: _creditRows(raw), receivableCredit: credits.receivable, payableCredit: credits.payable);
  for (final e in takes.entries) {
    if (raw[e.key].table == table && raw[e.key].id == id) return e.value;
  }
  return 0;
}

/// «پرداخت/دریافت شد» با حسابداری اعتبار برگشت (معادل `dues.mark_paid` سرور).
/// [shownAmount] = مبلغ کاهش‌یافتهٔ نمایش‌داده‌شده در لیست سررسید؛ اگر ندهید و [paid] درست باشد، از تخصیص فعلی حساب می‌شود.
/// [paid]=false مبلغ اصلی (قبل از کاهش) را برمی‌گرداند.
Future<void> setPaidWithCredit(String table, int id, bool paid, {double? shownAmount}) async {
  if (!paid || table == 'loan_dues') {
    await AppDb.I.setPaid(table, id, paid);
    return;
  }
  double? shown = shownAmount;
  if (shown == null) {
    final take = await dueCreditTake(table, id);
    if (take > 0.004) {
      final stored = await AppDb.I.lineAmount(table, id);
      if (stored != null) shown = stored - take;
    }
  }
  await AppDb.I.setPaid(table, id, true, shownAmount: shown);
}

/// ذخیرهٔ ویرایش یک ردیف از فرم: اگر در این ویرایش ردیف از «پرداخت‌نشده» به «پرداخت‌شده» رسید، اول بدون پرداخت ذخیره می‌شود
/// و بعد با [setPaidWithCredit] علامت می‌خورد تا اعتبار برگشت مصرف شود (فرم نباید از دور اعتبار خارج کند).
/// بقیهٔ حالت‌ها (از جمله برگرداندن به پرداخت‌نشده) همان [update] است که خودش `credit_used` را برمی‌گرداند.
Future<void> updateLineWithCredit(String table, int id, Map<String, dynamic> row, bool wasPaid,
    Future<void> Function(int id, Map<String, dynamic> row) update) async {
  final nowPaid = row['paid'] == 1 || row['paid'] == true;
  if (nowPaid && !wasPaid) {
    await update(id, <String, dynamic>{...row, 'paid': 0});
    await setPaidWithCredit(table, id, true);
  } else {
    await update(id, row);
  }
}

Future<List<DueItem>> loadDues({bool includePaid = false}) async {
  final out = await _loadDuesRaw(includePaid: includePaid);
  // برگشت‌ها: اعتبار برگشت هر طرف‌حساب (ارزش − بازپرداخت‌شده) از سررسیدهای پرداخت‌نشدهٔ همان طرف کم می‌شود (نزدیک‌ترین سررسید اول).
  final credits = await loadReturnCredits();
  if (credits.receivable.isNotEmpty || credits.payable.isNotEmpty) {
    final amounts = applyReturnCredit(
      rows: _creditRows(out),
      receivableCredit: credits.receivable,
      payableCredit: credits.payable,
    );
    final adjusted = <DueItem>[];
    for (var i = 0; i < out.length; i++) {
      final x = out[i];
      if (amounts[i] == x.amount) {
        adjusted.add(x);
      } else if (amounts[i] >= 0.5) {
        adjusted.add(DueItem(
          table: x.table, id: x.id, receivable: x.receivable, kind: x.kind, party: x.party, label: x.label,
          ref: x.ref, bank: x.bank, amount: amounts[i], date: x.date, paid: x.paid,
        ));
      } // else: کاملاً با اعتبار برگشت پوشش داده شده ⇒ در سررسیدها نمی‌آید
    }
    out
      ..clear()
      ..addAll(adjusted);
  }

  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

// ======================= حساب طرف‌ها =======================

class PartyEntry {
  final bool isPurchase; // true = خرید از او، false = فروش به او
  final int id;
  final DateTime date;
  final String label;
  final double weight;
  final double total;
  double settled; // v91 p5: تسویه از طریق صراف هم اضافه می‌شود

  /// v91 p5: ارز سند (null = ریالی)، مبلغ ارزی و تسویه‌شده به همان ارز (ردیف‌های هم‌ارز + تسویه از طریق صراف)
  final String? ccy;
  final double totalCcy;
  double settledCcy;
  PartyEntry({
    required this.isPurchase,
    required this.id,
    required this.date,
    required this.label,
    required this.weight,
    required this.total,
    required this.settled,
    this.ccy,
    this.totalCcy = 0,
    this.settledCcy = 0,
  });
  double get remaining => total - settled;
  double get remainingCcy => totalCcy - settledCcy;
  bool get isForeign => ccy != null;
}

/// نام‌های رسمی انواع تراکنش دفتر قرض و وام
const Map<String, String> kLoanKindLabel = {
  'given': 'قرض اعطایی',
  'taken': 'قرض دریافتی',
  'repay_in': 'بازپرداخت دریافتی',
  'repay_out': 'بازپرداخت پرداختی',
};

/// آیا این نوع تراکنش پول به حساب ما وارد می‌کند؟ (قرض دریافتی / بازپرداخت دریافتی)
bool loanKindIsIn(String kind) => kind == 'taken' || kind == 'repay_in';

class LoanEntry {
  final int id;
  final String uid;
  final String kind; // given | taken | repay_in | repay_out
  final double amount;
  final DateTime date;
  final String? note;
  LoanEntry({
    required this.id,
    required this.uid,
    required this.kind,
    required this.amount,
    required this.date,
    required this.note,
  });
  String get label => kLoanKindLabel[kind] ?? kind;
  bool get isIn => loanKindIsIn(kind);
}

class PartyAccount {
  final String key;
  double bought = 0; // جمع خرید از او
  double paid = 0; // پرداخت‌شده به او
  double sold = 0; // جمع فروش به او
  double received = 0; // دریافت‌شده از او
  final List<PartyEntry> entries = [];

  // ---- دفتر قرض و وام (جدا از خرید/فروش؛ در سود و زیان حساب نمی‌شود) ----
  double loanGiven = 0; // قرض اعطایی
  double loanTaken = 0; // قرض دریافتی
  double repaidToUs = 0; // بازپرداخت دریافتی (او به ما پس داده)
  double repaidByUs = 0; // بازپرداخت پرداختی (ما به او پس داده‌ایم)
  final List<LoanEntry> loans = [];

  PartyAccount(this.key);

  // ---- v91 p5: مانده به ارز سند ----
  /// کلید = کد ارز؛ 'IRR' = رویدادهای ریالیِ بدون ارز (به واحد ذخیره). مثبت = او به ما بدهکار است، منفی = ما بدهکاریم.
  final Map<String, double> byCcy = <String, double>{};

  /// نوع‌های طرف‌حساب (customer, supplier, …, exchanger) از جدول parties
  final Set<String> types = <String>{};

  /// تاریخ همهٔ رویدادها (برای فیلتر بازهٔ تاریخ)
  final List<DateTime> dates = <DateTime>[];

  /// موقعیت‌های صراف (وقتی این طرف‌حساب صراف است) و سود/زیان تحقق‌یافتهٔ آن (ریال)
  final List<XchPosition> xchPositions = <XchPosition>[];
  int xchRealized = 0;

  void addCcy(String? ccy, double v) {
    final String c = xchNormCcy(ccy);
    byCcy[c] = (byCcy[c] ?? 0) + v;
  }

  /// مانده‌های غیرصفر به ارز (ریال: |v| ≥ ۰٫۵، ارز: ≥ ۰٫۰۰۵)
  Map<String, double> get openByCcy => <String, double>{
        for (final MapEntry<String, double> e in byCcy.entries)
          if (e.value.abs() >= (e.key == 'IRR' ? 0.5 : 0.005)) e.key: e.value,
      };

  bool get isExchanger => types.contains('exchanger') || xchPositions.isNotEmpty;

  /// آخرین تاریخ فعالیت (یا null)
  DateTime? get lastDate => dates.isEmpty ? null : dates.reduce((DateTime a, DateTime b) => a.isAfter(b) ? a : b);

  /// مانده طلب قرضی: چقدر از قرضِ اعطایی هنوز به ما برنگشته
  double get loanReceivable => loanGiven - repaidToUs;

  /// مانده بدهی قرضی: چقدر از قرضِ دریافتی هنوز پس نداده‌ایم
  double get loanPayable => loanTaken - repaidByUs;

  /// مثبت = او بابت قرض به ما بدهکار است، منفی = ما بدهکاریم
  double get loanNet => loanReceivable - loanPayable;

  bool get hasLoans => loans.isNotEmpty;

  /// تراز کل (خرید/فروش + قرض)
  double get totalNet => net + loanNet;

  String get name => key.isEmpty ? 'بدون نام' : key;

  /// بدهی ما به او
  double get weOwe => bought - paid;

  /// طلب ما از او
  double get theyOwe => sold - received;

  /// مثبت = او به ما بدهکار است، منفی = ما به او بدهکاریم
  double get net => theyOwe - weOwe;
}

double _settledOf(String? type, String? staged, num lump, num credit, num cheque) {
  if (type == 'lump') return lump.toDouble();
  if (type == 'staged' && staged == 'credit') return credit.toDouble();
  if (type == 'staged' && staged == 'cheque') return cheque.toDouble();
  if (type == 'mixed') return (lump + credit + cheque).toDouble();
  return 0;
}

/// v91 p5: کد ارز سند خارجی یا null (ریالی / IRT)
String? _fxCcy(Object? v) {
  final String c = xchNormCcy(v);
  return c == 'IRR' ? null : c;
}

/// v91 p5: نوع‌های طرف‌حساب از ستون JSON `types`
Set<String> partyTypesOf(Object? raw) {
  if (raw == null || '$raw'.isEmpty) return <String>{};
  try {
    final Object? j = jsonDecode('$raw');
    if (j is List) return <String>{for (final Object? t in j) if (t is String && t.isNotEmpty) t};
  } catch (_) {}
  return <String>{};
}

/// v91 p5: ردیف‌های پرداخت‌شدهٔ هر سند (کلید p<id> / s<id>) با نوع جدول، ارز و مبلغ
Future<Map<String, List<Map<String, Object?>>>> _paidLinesByDoc(DatabaseExecutor d) async {
  final out = <String, List<Map<String, Object?>>>{};
  const src = <(String, String, String, String, String)>[
    ('lump_tx', 'payments', 'payment_id', 'purchase_id', 'p'),
    ('credit_inst', 'payments', 'payment_id', 'purchase_id', 'p'),
    ('cheque_inst', 'payments', 'payment_id', 'purchase_id', 'p'),
    ('receipt_lump_tx', 'receipts', 'receipt_id', 'sale_id', 's'),
    ('receipt_credit_inst', 'receipts', 'receipt_id', 'sale_id', 's'),
    ('receipt_cheque_inst', 'receipts', 'receipt_id', 'sale_id', 's'),
  ];
  for (final (String t, String h, String fk, String doc, String pre) in src) {
    try {
      final rows = await d.rawQuery('SELECT h.$doc AS did, x.amount AS amount, x.ccy AS ccy, x.ccy_amount AS ca FROM $t x JOIN $h h ON h.id = x.$fk WHERE x.paid = 1');
      for (final Map<String, Object?> r in rows) {
        (out['$pre${r['did']}'] ??= <Map<String, Object?>>[]).add(<String, Object?>{...r, 't': t});
      }
    } catch (_) {/* ستون ارز در پایگاه خیلی قدیمی */}
  }
  return out;
}

/// v91 p5: همان قاعدهٔ _settledOf: کدام جدول ردیف در این نوع پرداخت حساب می‌شود
bool _lineCounts(String table, String? type, String? staged) {
  final bool lump = table.endsWith('lump_tx');
  final bool credit = table.endsWith('credit_inst');
  if (type == 'mixed') return true;
  if (type == 'lump') return lump;
  if (type == 'staged' && staged == 'credit') return credit;
  if (type == 'staged' && staged == 'cheque') return !lump && !credit;
  return false;
}

void _applyLines(PartyAccount a, PartyEntry e, List<Map<String, Object?>>? lines, String? type, String? staged) {
  if (lines == null) return;
  final double sign = e.isPurchase ? 1 : -1; // پرداخت به فروشنده بدهی ما را کم می‌کند (+)، دریافت از خریدار طلب را (−)
  for (final Map<String, Object?> l in lines) {
    if (!_lineCounts(l['t'] as String, type, staged)) continue;
    final String? lc = _fxCcy(l['ccy']);
    if (lc == null) {
      a.addCcy('IRR', sign * ((l['amount'] as num?) ?? 0).toDouble());
    } else {
      final double ca = ((l['ca'] as num?) ?? 0).toDouble();
      a.addCcy(lc, sign * ca);
      if (lc == e.ccy) e.settledCcy += ca;
    }
  }
}

/// v91 p5: حرکت‌های صراف از موجودیت محلی (مرتب: تاریخ، ترتیب ثبت)
Future<List<XchMove>> loadXchMoves() async {
  try {
    final rows = await EntityStore.I.list('xch_moves');
    // list() جدیدترین را اول می‌دهد (rowid DESC) ⇒ برعکس تا ترتیب ثبت حفظ شود، بعد مرتب‌سازی پایدار بر اساس تاریخ
    return xchSorted(<XchMove>[for (final Map<String, dynamic> r in rows.reversed) XchMove.fromRow(r)]);
  } catch (_) {
    return <XchMove>[];
  }
}

/// v91 p5 (خالص): اثر حرکت‌های صراف روی حساب طرف‌ها — آینهٔ pb_xch_apply_sums سرور.
/// [rialPerStored] = ۱ برای مستأجر ریالی، ۱۰ برای تومانی (مبالغ IRR حرکت‌ها ریال‌اند).
void applyXchMoves(Map<String, PartyAccount> map, List<XchMove> moves, PartyAccount Function(String?) acc, {int rialPerStored = 1}) {
  if (moves.isEmpty) return;
  final XchRun run = xchRun(moves);
  for (int i = 0; i < moves.length; i++) {
    final XchMove m = moves[i];
    final XchResult r = run.results[i];
    final DateTime dt = DateTime.tryParse(m.date) ?? DateTime(2000);
    final PartyAccount e = acc(m.exchanger);
    e.types.add('exchanger');
    e.dates.add(dt);
    if (m.isSettle) {
      final double amt = r.dr.abs() / rialPerStored;
      final PartyAccount p = acc(m.party);
      p.dates.add(dt);
      final bool sale = m.kind == 'cust_paid';
      final double ccyAmt = m.ccy == 'IRR' ? m.amountCcy / rialPerStored : m.amountCcy;
      if (sale) {
        p.received += amt;
        e.sold += amt;
        p.addCcy(m.ccy, -ccyAmt);
      } else {
        p.paid += amt;
        e.bought += amt;
        p.addCcy(m.ccy, ccyAmt);
      }
      for (final PartyEntry en in p.entries) {
        if (en.isPurchase == !sale && en.id == m.docId) {
          en.settled += amt;
          if (m.ccy != 'IRR') en.settledCcy += m.amountCcy;
          break;
        }
      }
    } else {
      final double db = r.db / rialPerStored;
      if (db < 0) {
        e.received += -db;
      } else {
        e.paid += db;
      }
    }
  }
  for (final XchPosition p in run.positions.values) {
    final PartyAccount e = acc(p.exchanger);
    e.xchPositions.add(p);
    e.xchRealized += p.realized;
    e.addCcy(p.ccy, p.ccy == 'IRR' ? p.book / rialPerStored : p.amount);
  }
}

Future<List<PartyAccount>> loadParties() async {
  final d = await AppDb.I.db;
  final map = <String, PartyAccount>{};
  PartyAccount acc(String? name) => map.putIfAbsent(partyKey(name), () => PartyAccount(partyKey(name)));

  final purchases = await d.rawQuery('''
      SELECT p.id AS id, p.seller AS party, p.date AS date, p.type_name AS label,
             p.net_weight AS net, p.price AS price, p.ccy AS ccy, p.price_ccy AS pccy,
             pay.pay_type AS pt, pay.staged_type AS st,
             COALESCE((SELECT SUM(amount) FROM lump_tx WHERE payment_id = pay.id AND paid = 1), 0) AS lp,
             COALESCE((SELECT SUM(amount) FROM credit_inst WHERE payment_id = pay.id AND paid = 1), 0) AS cp,
             COALESCE((SELECT SUM(amount) FROM cheque_inst WHERE payment_id = pay.id AND paid = 1), 0) AS hp
      FROM purchases p LEFT JOIN payments pay ON pay.purchase_id = p.id
      WHERE p.is_mix = 0''');
  final lines = await _paidLinesByDoc(d); // v91 p5: ردیف‌های پرداخت‌شده با ارزشان
  for (final r in purchases) {
    final net = (r['net'] as num).toDouble();
    final total = net * (r['price'] as num).toDouble();
    final settled = _settledOf(r['pt'] as String?, r['st'] as String?, r['lp'] as num,
        r['cp'] as num, r['hp'] as num);
    final a = acc(r['party'] as String?);
    a.bought += total;
    a.paid += settled;
    final String? ccy = _fxCcy(r['ccy']);
    final double totalCcy = ccy == null ? 0 : net * ((r['pccy'] as num?) ?? 0).toDouble();
    final e = PartyEntry(
      isPurchase: true,
      id: r['id'] as int,
      date: DateTime.parse(r['date'] as String),
      label: (r['label'] as String?) ?? '',
      weight: net,
      total: total,
      settled: settled,
      ccy: ccy,
      totalCcy: totalCcy,
    );
    a.entries.add(e);
    a.dates.add(e.date);
    if (ccy == null) {
      a.addCcy('IRR', -total);
    } else {
      a.addCcy(ccy, -totalCcy);
    }
    _applyLines(a, e, lines['p${e.id}'], r['pt'] as String?, r['st'] as String?);
  }

  final sales = await d.rawQuery('''
      SELECT s.id AS id, s.buyer AS party, s.date AS date,
             s.net_weight AS net, s.price AS price, s.ccy AS ccy, s.total_ccy AS tccy,
             rec.recv_type AS rt, rec.staged_type AS st,
             COALESCE((SELECT SUM(amount) FROM receipt_lump_tx WHERE receipt_id = rec.id AND paid = 1), 0) AS lp,
             COALESCE((SELECT SUM(amount) FROM receipt_credit_inst WHERE receipt_id = rec.id AND paid = 1), 0) AS cp,
             COALESCE((SELECT SUM(amount) FROM receipt_cheque_inst WHERE receipt_id = rec.id AND paid = 1), 0) AS hp
      FROM sales s LEFT JOIN receipts rec ON rec.sale_id = s.id''');
  for (final r in sales) {
    final net = (r['net'] as num).toDouble();
    final total = net * (r['price'] as num).toDouble();
    final settled = _settledOf(r['rt'] as String?, r['st'] as String?, r['lp'] as num,
        r['cp'] as num, r['hp'] as num);
    final a = acc(r['party'] as String?);
    a.sold += total;
    a.received += settled;
    final String? ccy = _fxCcy(r['ccy']);
    final double totalCcy = ccy == null ? 0 : ((r['tccy'] as num?) ?? 0).toDouble();
    final e = PartyEntry(
      isPurchase: false,
      id: r['id'] as int,
      date: DateTime.parse(r['date'] as String),
      label: 'فروش',
      weight: net,
      total: total,
      settled: settled,
      ccy: ccy,
      totalCcy: totalCcy,
    );
    a.entries.add(e);
    a.dates.add(e.date);
    if (ccy == null) {
      a.addCcy('IRR', total);
    } else {
      a.addCcy(ccy, totalCcy);
    }
    _applyLines(a, e, lines['s${e.id}'], r['rt'] as String?, r['st'] as String?);
  }

  // برگشت از فروش: ارزش کالای برگشتی (V) از طلب ما کم می‌شود؛ مبلغی که نقد/چکی به خریدار پس داده‌ایم (R) دوباره به طلب اضافه می‌شود.
  // اثر روی تراز = −(V − R) (همان منطق سرور: sold −= V، received −= R). قبلاً برگشت‌ها اینجا اصلاً حساب نمی‌شد و خریدار بعد از برگشت هم بدهکار می‌ماند.
  final saleReturns = await d.rawQuery('''
      SELECT r.party AS party, COALESCE(r.refund_amount, 0) AS refund,
             COALESCE((SELECT SUM(i.kg * i.unit_price) FROM sale_return_items i WHERE i.return_id = r.id), 0) AS total
      FROM sale_returns r''');
  for (final r in saleReturns) {
    final a = acc(r['party'] as String?);
    a.sold -= (r['total'] as num).toDouble();
    a.received -= (r['refund'] as num).toDouble();
    a.addCcy('IRR', -((r['total'] as num).toDouble() - (r['refund'] as num).toDouble())); // v91 p5
  }

  // برگشت از خرید (قرینهٔ برگشت از فروش؛ همان منطق سرور returns.php: bought −= V، paid −= R).
  // ارزش کالای برگشتی (V) از بدهی ما به فروشنده کم می‌شود؛ مبلغی که فروشنده نقد/چکی به ما پس داده (R) دوباره به بدهی اضافه می‌شود.
  // قبلاً برگشت از خرید اینجا حساب نمی‌شد و فروشنده بعد از برگشت هم طلبکار می‌ماند.
  final purchaseReturns = await d.rawQuery('''
      SELECT r.party AS party, COALESCE(r.refund_amount, 0) AS refund,
             COALESCE((SELECT SUM(i.kg * i.unit_price) FROM purchase_return_items i WHERE i.return_id = r.id), 0) AS total
      FROM purchase_returns r''');
  for (final r in purchaseReturns) {
    final a = acc(r['party'] as String?);
    a.bought -= (r['total'] as num).toDouble();
    a.paid -= (r['refund'] as num).toDouble();
    a.addCcy('IRR', (r['total'] as num).toDouble() - (r['refund'] as num).toDouble()); // v91 p5
  }

  // طرف‌حساب‌هایی که دستی تعریف شده‌اند (حتی اگر هنوز خرید/فروشی نداشته باشند)
  for (final r in await d.query('parties')) {
    acc(r['name'] as String?).types.addAll(partyTypesOf(r['types'])); // v91 p5: نوع‌ها (ستون types از سرور)
  }

  // دفتر قرض و وام
  for (final r in await d.query('loan_entries', orderBy: 'date DESC, id DESC')) {
    final a = acc(r['party'] as String?);
    final kind = (r['kind'] as String?) ?? '';
    final amount = (r['amount'] as num).toDouble();
    switch (kind) {
      case 'given':
        a.loanGiven += amount;
        break;
      case 'taken':
        a.loanTaken += amount;
        break;
      case 'repay_in':
        a.repaidToUs += amount;
        break;
      case 'repay_out':
        a.repaidByUs += amount;
        break;
      default:
        continue;
    }
    a.addCcy('IRR', loanKindIsIn(kind) ? -amount : amount); // v91 p5: قرض در ماندهٔ ریالی
    a.dates.add(DateTime.parse(r['date'] as String));
    a.loans.add(LoanEntry(
      id: (r['id'] as num).toInt(),
      uid: (r['uid'] as String?) ?? '',
      kind: kind,
      amount: amount,
      date: DateTime.parse(r['date'] as String),
      note: r['note'] as String?,
    ));
  }

  // v91 p5: حرکت‌های صراف (همان ارقام سرور: pb_xch_apply_sums)
  applyXchMoves(map, await loadXchMoves(), acc, rialPerStored: AppDb.I.moneyUnit == 'rial' ? 1 : 10);

  final list = map.values.toList();
  for (final a in list) {
    a.entries.sort((x, y) => y.date.compareTo(x.date));
  }
  list.sort((a, b) => b.totalNet.abs().compareTo(a.totalNet.abs()));
  return list;
}

// ======================= گردش واریزی و برداشت =======================

/// یک حرکت واقعیِ پول: واریزی (به حساب ما) یا برداشت (از حساب ما)
class CashFlow {
  final DateTime date;
  final double amount;
  final bool isIn; // true = واریزی، false = برداشت
  final String party;
  final bool isLoan;
  CashFlow(this.date, this.amount, this.isIn, this.party, this.isLoan);
}

/// فقط تراکنش‌های «انجام‌شده» (تسویه‌شده) در بازهٔ [from, to] (هر دو شامل).
/// واریزی = دریافت از خریدارها (+ قرض دریافتی و بازپرداخت دریافتی در صورت [includeLoans])
/// برداشت = پرداخت به فروشنده‌ها (+ قرض اعطایی و بازپرداخت پرداختی در صورت [includeLoans])
Future<List<CashFlow>> loadCashFlows({
  required DateTime from,
  required DateTime to,
  String? partyKeyFilter,
  bool includeLoans = false,
}) async {
  final out = <CashFlow>[];
  final start = DateTime(from.year, from.month, from.day);
  final endEx = DateTime(to.year, to.month, to.day + 1);
  bool inRange(DateTime d) => !d.isBefore(start) && d.isBefore(endEx);
  bool matches(String name) => partyKeyFilter == null || partyKey(name) == partyKeyFilter;

  final db = AppDb.I;
  for (final r in await db.allReceiptTransactions()) {
    if (((r['paid'] as num?) ?? 0) != 1) continue;
    final dt = DateTime.parse(r['date'] as String);
    final name = '${r['name'] ?? ''}';
    if (!inRange(dt) || !matches(name == '-' ? '' : name)) continue;
    out.add(CashFlow(dt, (r['amount'] as num).toDouble(), true, name, false));
  }
  for (final r in await db.allPaymentTransactions()) {
    if (((r['paid'] as num?) ?? 0) != 1) continue;
    final dt = DateTime.parse(r['date'] as String);
    final name = '${r['name'] ?? ''}';
    if (!inRange(dt) || !matches(name == '-' ? '' : name)) continue;
    out.add(CashFlow(dt, (r['amount'] as num).toDouble(), false, name, false));
  }
  if (includeLoans) {
    for (final r in await db.loanEntries()) {
      final dt = DateTime.parse(r['date'] as String);
      final name = '${r['party'] ?? ''}';
      if (!inRange(dt) || !matches(name)) continue;
      out.add(CashFlow(dt, (r['amount'] as num).toDouble(), loanKindIsIn('${r['kind']}'), name, true));
    }
  }
  return out;
}
