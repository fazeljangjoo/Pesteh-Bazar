// v92 فاز ج — قرض چندارزی: محاسبهٔ خالص — آینهٔ دقیق pb_loan_match سرور (backend/api/loans_fx.php).
// هر قرض (given = قرض دادیم / taken = قرض گرفتیم) یک «لات» به ارز خودش است؛ بازپرداخت (repay_in / repay_out) اول قرضِ loan_ref و بعد
// قدیمی‌ترین قرض همان طرف و همان ارز را می‌بندد. ارزش دفتری بخش بسته‌شده (carry) به نسبت از ریالِ همان قرض؛ سود/زیان تحقق‌یافته:
// repay_in = V − carry، repay_out = carry − V (V = مبلغ ارزی × نرخ روز). قرض ریالی: V = carry ⇒ بدون سود/زیان، دقیقاً مثل قبل.
import 'xch_calc.dart' show xchNormCcy, xchPartyKey;

/// نام‌های تازه و روشن (v92)
const Map<String, String> kLoanKindFa = <String, String>{
  'given': 'قرض دادیم',
  'taken': 'قرض گرفتیم',
  'repay_in': 'قرض ما را پس داد',
  'repay_out': 'قرضش را پس دادیم',
};

/// توضیح یک‌خطی هر نوع
const Map<String, String> kLoanKindHelp = <String, String>{
  'given': 'پول از ما به او رفت؛ او به ما بدهکار شد.',
  'taken': 'پول از او به ما آمد؛ ما به او بدهکار شدیم.',
  'repay_in': 'او بخشی یا همهٔ قرضی را که به او داده بودیم پس داد.',
  'repay_out': 'ما بخشی یا همهٔ قرضی را که از او گرفته بودیم پس دادیم.',
};

double _d(Object? v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

/// یک ردیف دفتر قرض (از جدول محلی loan_entries)
class LoanRow {
  final int id;
  final String uid;
  final String party;
  final String kind;
  final String date;
  final double amount; // معادل ریالی به واحد ذخیره
  final String ccy; // IRR = ریالی
  final double ccyAmount;
  final double fxRate;
  final String? accountUid;
  final String? loanRef;
  final String? note;
  const LoanRow({required this.id, required this.uid, required this.party, required this.kind, required this.date, required this.amount, this.ccy = 'IRR', this.ccyAmount = 0, this.fxRate = 0, this.accountUid, this.loanRef, this.note});

  factory LoanRow.fromRow(Map<String, Object?> r) => LoanRow(
        id: (r['id'] as num?)?.toInt() ?? 0,
        uid: '${r['uid'] ?? ''}',
        party: xchPartyKey(r['party']),
        kind: '${r['kind'] ?? ''}',
        date: '${r['date'] ?? ''}'.length >= 10 ? '${r['date']}'.substring(0, 10) : '${r['date'] ?? ''}',
        amount: _d(r['amount']),
        ccy: xchNormCcy(r['ccy']),
        ccyAmount: _d(r['ccy_amount']),
        fxRate: _d(r['fx_rate']),
        accountUid: r['account_uid'] as String?,
        loanRef: r['loan_ref'] as String?,
        note: r['note'] as String?,
      );

  bool get isForeign => ccy != 'IRR' && ccyAmount > 0 && fxRate > 0;
  bool get isRepay => kind == 'repay_in' || kind == 'repay_out';
}

/// [ccy, q4, rial] یک ردیف — همان pb_loan_q
(String, int, int) loanQ(LoanRow r, int mult) {
  if (r.isForeign) return (r.ccy, (r.ccyAmount * 10000).round(), (r.ccyAmount * r.fxRate).round());
  final int rial = (r.amount * mult).round();
  return ('IRR', rial * 10000, rial);
}

class LoanLot {
  final String uid, party, ccy, kind, date;
  final int q4, b;
  int open4, openb;
  LoanLot(this.uid, this.party, this.ccy, this.kind, this.date, this.q4, this.b)
      : open4 = q4,
        openb = b;
  double get open => open4 / 10000;
  double get amount => q4 / 10000;
}

class LoanClosed {
  final String loan;
  final int q4, carry;
  const LoanClosed(this.loan, this.q4, this.carry);
}

class LoanRes {
  final String kind, party, ccy;
  final int q4, rial, carry, realized, excess4;
  final List<LoanClosed> closed;
  const LoanRes(this.kind, this.party, this.ccy, this.q4, this.rial, this.carry, this.realized, this.closed, this.excess4);
  double get amountCcy => q4 / 10000;
}

class LoanMatch {
  final Map<String, LoanRes> entries;
  final Map<String, LoanLot> loans; // به ترتیب تاریخ
  const LoanMatch(this.entries, this.loans);
}

/// آینهٔ pb_loan_match ([mult] = ریال بر واحد ذخیره)
LoanMatch loanMatch(List<LoanRow> rows, int mult) {
  final List<LoanRow> sorted = <LoanRow>[...rows]..sort((LoanRow a, LoanRow b) {
      final int c = a.date.compareTo(b.date);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  final Map<String, LoanLot> loans = <String, LoanLot>{};
  final Map<String, LoanRes> ent = <String, LoanRes>{};
  for (final LoanRow r in sorted) {
    if (!kLoanKindFa.containsKey(r.kind)) continue;
    final (String ccy, int q4, int rial) = loanQ(r, mult);
    if (!r.isRepay) {
      loans[r.uid] = LoanLot(r.uid, r.party, ccy, r.kind, r.date, q4, rial);
      ent[r.uid] = LoanRes(r.kind, r.party, ccy, q4, rial, rial, 0, const <LoanClosed>[], 0);
      continue;
    }
    final String side = r.kind == 'repay_in' ? 'given' : 'taken';
    final List<String> order = <String>[];
    final String ref = r.loanRef ?? '';
    final LoanLot? rl = loans[ref];
    if (ref.isNotEmpty && rl != null && rl.kind == side && rl.party == r.party && rl.ccy == ccy) order.add(ref);
    for (final LoanLot l in loans.values) {
      if (l.uid != ref && l.kind == side && l.party == r.party && l.ccy == ccy) order.add(l.uid);
    }
    int left = q4, carry = 0;
    final List<LoanClosed> closed = <LoanClosed>[];
    for (final String lu in order) {
      if (left <= 0) break;
      final LoanLot l = loans[lu]!;
      if (l.open4 <= 0) continue;
      final int c = left < l.open4 ? left : l.open4;
      final int cb = c == l.open4 ? l.openb : (l.openb.toDouble() * c / l.open4).round();
      l.open4 -= c;
      l.openb -= cb;
      left -= c;
      carry += cb;
      closed.add(LoanClosed(lu, c, cb));
    }
    final int vClosed = left > 0 ? (q4 > 0 ? (rial.toDouble() * (q4 - left) / q4).round() : 0) : rial;
    final int real = side == 'given' ? vClosed - carry : carry - vClosed;
    carry += rial - vClosed;
    ent[r.uid] = LoanRes(r.kind, r.party, ccy, q4, rial, carry, real, closed, left);
  }
  return LoanMatch(ent, loans);
}
