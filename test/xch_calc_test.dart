// v91 p5 — صراف: همان مثال عددی CHANGES_v91_p5.md (آینهٔ backend/api/xch_selftest.php).
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/ledger.dart';
import 'package:pesteh_bazar/xch_calc.dart';

XchMove _m(String date, String kind, String ex, String ccy, double amt,
        {double docRate = 0, String? party, int? docId, String? docType, String? payCcy, double pay = 0, double payRate = 0, String uid = ''}) =>
    XchMove(
        uid: uid,
        date: date,
        kind: kind,
        exchanger: ex,
        ccy: ccy,
        amountCcy: amt,
        docRate: docRate,
        party: party,
        docId: docId,
        docType: docType,
        payCcy: payCcy,
        payAmount: pay,
        payRate: payRate);

void main() {
  final List<XchMove> moves = <XchMove>[
    _m('2026-10-05', 'cust_paid', 'صرافی امین', 'USD', 10000, docRate: 600000, party: 'شرکت الف', docType: 'sale', docId: 101),
    _m('2026-10-10', 'xch_paid_us', 'صرافی امین', 'USD', 4000, payCcy: 'IRR', pay: 2460000000),
    _m('2026-10-15', 'paid_seller', 'صرافی نور', 'AED', 50000, docRate: 165000, party: 'تأمین‌کننده ب', docType: 'purchase', docId: 55),
    _m('2026-11-03', 'we_paid_xch', 'صرافی نور', 'AED', 50000, payCcy: 'USD', pay: 13600, payRate: 612000),
    _m('2026-11-05', 'xch_paid_us', 'صرافی امین', 'USD', 6000, payCcy: 'AED', pay: 22100, payRate: 167000),
  ];

  test('worked example: realized FX per move and in total (= PHP selftest)', () {
    final XchRun r = xchRun(moves);
    expect(r.results[0].db, 6000000000);
    expect(r.results[0].realized, 0);
    expect(r.results[1].db, -2400000000);
    expect(r.results[1].realized, 60000000);
    expect(r.results[1].q4After, 6000 * kXchScale);
    expect(r.results[1].bAfter, 3600000000);
    expect(r.results[2].db, -8250000000);
    expect(r.results[3].dr, 8323200000);
    expect(r.results[3].realized, -73200000);
    expect(r.results[4].dr, -3690700000);
    expect(r.results[4].realized, 90700000);
    expect(r.realizedTotal, 77500000);
    for (final XchPosition p in r.positions.values) {
      expect(p.q4, 0);
      expect(p.book, 0);
    }
  });

  test('balances at month end (2026-10-31): Amin +6,000 USD avg 600,000; Noor −50,000 AED', () {
    final XchRun r = xchRun(moves.where((XchMove m) => m.date.compareTo('2026-10-31') <= 0).toList());
    final XchPosition amin = r.positions['صرافی امین\u001fUSD']!;
    final XchPosition noor = r.positions['صرافی نور\u001fAED']!;
    expect(amin.amount, 6000);
    expect(amin.book, 3600000000);
    expect(amin.avgRate, 600000);
    expect(amin.theyOwe, isTrue);
    expect(noor.amount, -50000);
    expect(noor.book, -8250000000);
    expect(noor.weOwe, isTrue);
    // unrealized at 620,000 / 168,000 (what the server revaluation posts)
    expect((amin.amount * 620000).round() - amin.book, 120000000);
    expect((noor.amount * 168000).round() - noor.book, -150000000);
  });

  test('crossing zero and rounding (thirds) behave like the server', () {
    final XchRun x = xchRun(<XchMove>[
      _m('2026-01-01', 'cust_paid', 'X', 'USD', 10, docRate: 600000),
      _m('2026-01-02', 'xch_paid_us', 'X', 'USD', 15, payCcy: 'USD', pay: 15, payRate: 610000),
    ]);
    expect(x.results[1].realized, 100000);
    expect(x.results[1].db, -9050000);
    expect(x.results[1].bAfter, -3050000);
    final XchRun t = xchRun(<XchMove>[
      _m('2026-01-01', 'cust_paid', 'Y', 'EUR', 3, docRate: 333333.333333),
      _m('2026-01-02', 'xch_paid_us', 'Y', 'EUR', 1, payCcy: 'IRR', pay: 333333),
      _m('2026-01-03', 'xch_paid_us', 'Y', 'EUR', 1, payCcy: 'IRR', pay: 333333),
      _m('2026-01-04', 'xch_paid_us', 'Y', 'EUR', 1, payCcy: 'IRR', pay: 333334),
    ]);
    final XchPosition p = t.positions.values.single;
    expect(p.q4, 0);
    expect(p.book, 0);
    expect(p.realized, 0);
  });

  test('preview of a new move uses the earlier moves of the same exchanger + ccy only', () {
    final XchResult pv = xchPreview(moves.take(3).toList(), _m('2026-10-20', 'xch_paid_us', 'صرافی امین', 'USD', 1000, payCcy: 'IRR', pay: 610000000));
    expect(pv.realized, 10000000); // 1,000 × (610,000 − 600,000)
    expect(pv.balanceAfter, 5000);
  });

  test('fromRow normalizes names / currencies and parses decimals from strings', () {
    final XchMove m = XchMove.fromRow(<String, dynamic>{
      'uid': 'u1', 'date': '2026-10-05', 'kind': 'xch_paid_us', 'exchanger': ' صرافي  امین ', 'ccy': 'usd',
      'amount_ccy': '4000.0000', 'pay_ccy': null, 'pay_amount': '4000', 'pay_rate': '615000.000000',
    });
    expect(m.exchanger, 'صرافی امین');
    expect(m.ccy, 'USD');
    expect(m.payCcy, 'USD');
    expect(m.delta, (-4000 * kXchScale, -2460000000));
  });

  test('party accounts per currency (applyXchMoves): customer, supplier and exchangers settle to zero', () {
    final Map<String, PartyAccount> map = <String, PartyAccount>{};
    PartyAccount acc(String? n) => map.putIfAbsent(partyKey(n), () => PartyAccount(partyKey(n)));
    // documents: sale 10,000 USD (6,000,000,000 rial), purchase 50,000 AED (8,250,000,000 rial) — rial tenant
    final PartyAccount alef = acc('شرکت الف')
      ..sold = 6000000000
      ..addCcy('USD', 10000);
    alef.entries.add(PartyEntry(isPurchase: false, id: 101, date: DateTime(2026, 10, 2), label: 'فروش', weight: 1000, total: 6000000000, settled: 0, ccy: 'USD', totalCcy: 10000));
    final PartyAccount be = acc('تأمین‌کننده ب')
      ..bought = 8250000000
      ..addCcy('AED', -50000);
    be.entries.add(PartyEntry(isPurchase: true, id: 55, date: DateTime(2026, 10, 12), label: 'خرید', weight: 1000, total: 8250000000, settled: 0, ccy: 'AED', totalCcy: 50000));

    applyXchMoves(map, moves.where((XchMove m) => m.date.compareTo('2026-10-31') <= 0).toList(), acc);
    expect(alef.openByCcy, isEmpty);
    expect(alef.net, 0);
    expect(alef.entries.single.remainingCcy, 0);
    expect(be.openByCcy, isEmpty);
    expect(be.net, 0);
    expect(map['صرافی امین']!.openByCcy, <String, double>{'USD': 6000});
    expect(map['صرافی امین']!.net, 3600000000); // book rial
    expect(map['صرافی امین']!.isExchanger, isTrue);
    expect(map['صرافی امین']!.xchRealized, 60000000);
    expect(map['صرافی نور']!.openByCcy, <String, double>{'AED': -50000});
    expect(map['صرافی نور']!.net, -8250000000);

    final Map<String, PartyAccount> all = <String, PartyAccount>{};
    PartyAccount acc2(String? n) => all.putIfAbsent(partyKey(n), () => PartyAccount(partyKey(n)));
    applyXchMoves(all, moves, acc2);
    expect(all['صرافی امین']!.openByCcy, isEmpty);
    expect(all['صرافی نور']!.openByCcy, isEmpty);
    expect(all['صرافی امین']!.xchRealized + all['صرافی نور']!.xchRealized, 77500000);
  });

  test('toman tenant: rial (IRR) moves are converted to the stored unit', () {
    final Map<String, PartyAccount> map = <String, PartyAccount>{};
    PartyAccount acc(String? n) => map.putIfAbsent(partyKey(n), () => PartyAccount(partyKey(n)));
    applyXchMoves(map, <XchMove>[_m('2026-01-01', 'cust_paid', 'ص', 'IRR', 5000000, party: 'م', docType: 'sale', docId: 1)], acc, rialPerStored: 10);
    expect(map['ص']!.byCcy['IRR'], 500000);
    expect(map['م']!.byCcy['IRR'], -500000);
    expect(map['م']!.received, 500000);
  });

  test('party types from the JSON column', () {
    expect(partyTypesOf('["customer","exchanger"]'), <String>{'customer', 'exchanger'});
    expect(partyTypesOf(null), isEmpty);
    expect(partyTypesOf('bad'), isEmpty);
  });
}
