// v92 فاز ج — آزمون قرض چندارزی: همان اعداد backend/api/loans_selftest.php.
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/loan_calc.dart';
import 'package:pesteh_bazar/settle_calc.dart';

LoanRow _r(int id, String uid, String kind, String date, double amt, double rate, {String ccy = 'USD', String? ref, String party = 'آقای ب'}) =>
    LoanRow(id: id, uid: uid, party: party, kind: kind, date: date, amount: 0, ccy: ccy, ccyAmount: amt, fxRate: rate, loanRef: ref);

void main() {
  test('repayments of a foreign loan: book carry and realized FX (= PHP selftest)', () {
    final LoanMatch m = loanMatch(<LoanRow>[
      _r(1, 'g1', 'given', '2026-09-01', 1000, 600000),
      _r(2, 'r1', 'repay_in', '2026-10-01', 400, 615000),
      _r(3, 'r2', 'repay_in', '2026-11-01', 600, 590000),
      _r(4, 't1', 'taken', '2026-09-05', 2000, 165000, ccy: 'AED'),
      _r(5, 'r3', 'repay_out', '2026-10-05', 2000, 166000, ccy: 'AED'),
    ], 1);
    expect(m.entries['g1']!.rial, 600000000);
    expect(m.entries['r1']!.rial, 246000000);
    expect(m.entries['r1']!.carry, 240000000);
    expect(m.entries['r1']!.realized, 6000000);
    expect(m.entries['r2']!.carry, 360000000);
    expect(m.entries['r2']!.realized, -6000000);
    expect(m.loans['g1']!.open4, 0);
    expect(m.loans['g1']!.openb, 0);
    expect(m.entries['r3']!.carry, 330000000);
    expect(m.entries['r3']!.realized, -2000000);
  });

  test('loan_ref closes the chosen loan first', () {
    final LoanMatch m = loanMatch(<LoanRow>[
      _r(1, 'a', 'given', '2026-01-01', 100, 600000),
      _r(2, 'b', 'given', '2026-01-02', 100, 620000),
      _r(3, 'c', 'repay_in', '2026-02-01', 100, 630000, ref: 'b'),
    ], 1);
    expect(m.entries['c']!.carry, 62000000);
    expect(m.loans['a']!.open4, 1000000);
    expect(m.loans['b']!.open4, 0);
  });

  test('rial loan on a toman tenant: no FX result, over-repayment kept at its value', () {
    final LoanMatch m = loanMatch(const <LoanRow>[
      LoanRow(id: 1, uid: 'x', party: 'ج', kind: 'given', date: '2026-01-01', amount: 500000),
      LoanRow(id: 2, uid: 'y', party: 'ج', kind: 'repay_in', date: '2026-01-05', amount: 700000),
    ], 10);
    expect(m.entries['x']!.rial, 5000000);
    expect(m.entries['y']!.carry, 7000000);
    expect(m.entries['y']!.realized, 0);
    expect(m.entries['y']!.excess4, 20000000000);
  });

  test('a settlement allocated to a loan: carry = loan book, realized at the leg rate', () {
    final StlDoc loan = StlDoc(t: 'loan', id: 9, uid: 'g1', kind: 'given', party: 'آقای ب', ccy: 'USD', rate: 600000, date: '2026-09-01',
        total4: stlQ4(1000), book: 600000000, pre4: stlQ4(400));
    expect(loan.key, 'lg1');
    expect(loan.dir, 'recv');
    final Settlement s = Settlement(
      uid: 'u', order: 1, date: '2026-11-01', dir: 'recv', party: 'آقای ب', ccy: 'USD', amt4: stlQ4(600), allocMode: 'manual',
      alloc: <(String, int)>[('lg1', stlQ4(600))],
      legs: const <StlLeg>[StlLeg(lid: 'x', k: 'xch', exchanger: 'صرافی امین', settle4: 6000000, ccy: 'USD', amount: 600, rate: 620000)],
    );
    final StlMatch m = stlMatch(<String, StlDoc>{loan.key: loan}, <Settlement>[s]);
    expect(m.stl['u']!.carry, 360000000);
    expect(m.stl['u']!.carryLoan, 360000000);
    expect(m.stl['u']!.realized, 12000000);
    expect(m.docs['lg1']!.open4, 0);
    // a collection cannot settle a taken loan
    final StlDoc taken = StlDoc(t: 'loan', id: 3, uid: 't1', kind: 'taken', party: 'آقای ب', ccy: 'USD', rate: 600000, date: '2026-09-01', total4: stlQ4(10), book: 6000000);
    final StlMatch m2 = stlMatch(<String, StlDoc>{taken.key: taken}, <Settlement>[
      Settlement(uid: 'v', order: 1, date: '2026-11-01', dir: 'recv', party: 'آقای ب', ccy: 'USD', amt4: stlQ4(10), alloc: <(String, int)>[('lt1', stlQ4(10))],
          legs: const <StlLeg>[StlLeg(lid: 'y', k: 'direct', settle4: 100000, ccy: 'USD', amount: 10, rate: 600000)]),
    ]);
    expect(m2.stl['v']!.adv4, stlQ4(10)); // not allocated ⇒ on account
  });

  test('LoanRow.fromRow reads the local row (rial rows keep working)', () {
    final LoanRow r = LoanRow.fromRow(<String, Object?>{'id': 4, 'uid': 'q', 'party': ' آقاي  ب', 'kind': 'given', 'date': '2026-01-01', 'amount': 1000, 'ccy': null});
    expect(r.party, 'آقای ب');
    expect(r.isForeign, isFalse);
    expect(loanQ(r, 10), ('IRR', 100000000, 10000));
    expect(kLoanKindFa['given'], 'قرض دادیم');
  });
}
