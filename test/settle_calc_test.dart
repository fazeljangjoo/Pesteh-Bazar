// v92 — آزمون محاسبهٔ شناسنامه: همان اعداد backend/api/settle_selftest.php (مثال بخش ۱۰ DESIGN_v92_accounting_FA.md).
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/settle_calc.dart';
import 'package:pesteh_bazar/xch_calc.dart';

StlDoc _doc(String t, int id, String party, String date, double amt, double rate, {String ccy = 'USD'}) =>
    StlDoc(t: t, id: id, party: party, ccy: ccy, rate: rate, date: date, total4: stlQ4(amt), book: (amt * rate).round());

void main() {
  const String alef = 'شرکت الف';
  final Map<String, StlDoc> docs = <String, StlDoc>{
    for (final StlDoc d in <StlDoc>[
      _doc('sale', 101, alef, '2026-10-01', 4000, 600000),
      _doc('sale', 108, alef, '2026-10-08', 6000, 610000),
      _doc('sale', 120, alef, '2026-10-20', 5000, 605000),
    ])
      d.key: d,
  };
  final Settlement r1 = Settlement(
    uid: 'u-r1',
    order: 1,
    date: '2026-11-02',
    dir: 'recv',
    party: alef,
    ccy: 'USD',
    amt4: stlQ4(12000),
    refNo: 'و-1405-0001',
    alloc: <(String, int)>[('s101', stlQ4(4000)), ('s108', stlQ4(6000)), ('s120', stlQ4(2000))],
    legs: const <StlLeg>[
      StlLeg(lid: 'l1', k: 'direct', settle4: 30000000, ccy: 'USD', amount: 3000, rate: 615000),
      StlLeg(lid: 'l2', k: 'xch', exchanger: 'صرافی امین', settle4: 70000000, ccy: 'USD', amount: 7000, rate: 615000),
      StlLeg(lid: 'l3', k: 'xch', exchanger: 'صرافی نور', settle4: 20000000, ccy: 'AED', amount: 7350, rate: 167500),
    ],
  );

  test('stage 1: carry, per-leg realized, open documents (design §10)', () {
    final StlMatch m = stlMatch(docs, <Settlement>[r1]);
    final StlRes s = m.stl['u-r1']!;
    expect(s.carry, 7270000000);
    expect(s.adv4, 0);
    expect(s.legs['l1']!.carry, 1800000000);
    expect(s.legs['l1']!.realized, 45000000);
    expect(s.legs['l2']!.carry, 4260000000);
    expect(s.legs['l2']!.realized, 45000000);
    expect(s.legs['l3']!.carry, 1210000000);
    expect(s.legs['l3']!.realized, 21125000);
    expect(s.realized, 111125000);
    expect(m.docs['s101']!.open4, 0);
    expect(m.docs['s120']!.open4, stlQ4(3000));
    expect(m.docs['s108']!.carry, 3660000000);
  });

  test('FIFO allocation', () {
    final StlMatch empty = stlMatch(docs, <Settlement>[]);
    expect(stlFifo(docs, empty, alef, 'USD', 'recv', '2026-11-02', stlQ4(12000)), <(String, int)>[('s101', 40000000), ('s108', 60000000), ('s120', 20000000)]);
    expect(stlFifo(docs, empty, alef, 'USD', 'recv', '2026-10-10', stlQ4(12000)), <(String, int)>[('s101', 40000000), ('s108', 60000000)]);
  });

  test('exchangers settle later ⇒ trail complete, total realized 87,000,000', () {
    final List<XchMove> moves = <XchMove>[
      const XchMove(uid: 'm-amin', date: '2026-11-10', kind: 'xch_paid_us', exchanger: 'صرافی امین', ccy: 'USD', amountCcy: 7000, payCcy: 'IRR', payAmount: 4284000000, payRate: 1),
      const XchMove(uid: 'm-noor', date: '2026-11-12', kind: 'xch_paid_us', exchanger: 'صرافی نور', ccy: 'AED', amountCcy: 7350, payCcy: 'USD', payAmount: 2000, payRate: 614000),
    ];
    final StlState st = StlState.build(docs, <Settlement>[r1], moves);
    expect(st.legRes('u-r1', 'l2')!.db, 4305000000);
    final Trail t = stlTrail(st, 'u-r1')!;
    expect(t.complete, isTrue);
    expect(t.realized, 87000000);
    expect(t.stages[1].next.single.realized, -21000000);
    expect(t.stages[1].next.single.no, '2-1');
    expect(t.stages[1].from, alef);
    expect(t.stages[1].to, 'صرافی امین');
    expect(t.stages[2].next.single.payAmount, 2000);
    expect(t.stages[2].next.single.realized, -3125000);
    for (final XchPosition p in st.xrun.positions.values) {
      expect(p.q4, 0);
      expect(p.book, 0);
      expect(p.lots, isEmpty);
    }
  });

  test('exchanger still holding a deposit ⇒ trail open', () {
    final StlState st = StlState.build(docs, <Settlement>[r1], const <XchMove>[]);
    final Trail t = stlTrail(st, 'u-r1')!;
    expect(t.complete, isFalse);
    expect(t.stages[1].openAtExchanger, 7000);
    expect(t.stages[2].openAtExchanger, 7350);
  });

  test('advance consumed by a later invoice (loss 10,000,000)', () {
    final Map<String, StlDoc> d2 = <String, StlDoc>{...docs};
    final StlDoc s130 = _doc('sale', 130, alef, '2026-11-25', 2000, 625000);
    d2[s130.key] = s130;
    final Settlement r2 = Settlement(
      uid: 'u-r2', order: 2, date: '2026-11-20', dir: 'recv', party: alef, ccy: 'USD', amt4: stlQ4(5000),
      alloc: <(String, int)>[('s120', stlQ4(3000))],
      legs: const <StlLeg>[StlLeg(lid: 'x', k: 'direct', settle4: 50000000, ccy: 'USD', amount: 5000, rate: 620000)],
    );
    final StlMatch m = stlMatch(d2, <Settlement>[r1, r2]);
    expect(m.stl['u-r2']!.adv4, stlQ4(2000));
    expect(m.stl['u-r2']!.advB, 1240000000);
    expect(m.stl['u-r2']!.realized, 45000000);
    final StlCons c = m.docs['s130']!.cons.single;
    expect(c.carryAdv, 1240000000);
    expect(c.carryDoc, 1250000000);
    expect(c.realized, -10000000);
    expect(m.docs['s130']!.open4, 0);
  });

  test('pay through an exchanger, then we pay the exchanger in USD ⇒ loss 73,200,000', () {
    final Map<String, StlDoc> d = <String, StlDoc>{'p55': _doc('purchase', 55, 'تأمین‌کننده ب', '2026-10-12', 50000, 165000, ccy: 'AED')};
    final Settlement p1 = Settlement(
      uid: 'u-p1', order: 1, date: '2026-10-15', dir: 'pay', party: 'تأمین‌کننده ب', ccy: 'AED', amt4: stlQ4(50000),
      alloc: <(String, int)>[('p55', stlQ4(50000))],
      legs: const <StlLeg>[StlLeg(lid: 'a', k: 'xch', exchanger: 'صرافی پارس', settle4: 500000000, ccy: 'AED', amount: 50000, rate: 166000)],
    );
    final StlState st = StlState.build(d, <Settlement>[p1], const <XchMove>[
      XchMove(uid: 'w', date: '2026-11-03', kind: 'we_paid_xch', exchanger: 'صرافی پارس', ccy: 'AED', amountCcy: 50000, payCcy: 'USD', payAmount: 13600, payRate: 612000),
    ]);
    expect(st.match.stl['u-p1']!.realized, -50000000);
    final Trail t = stlTrail(st, 'u-p1')!;
    expect(t.stages.single.from, 'صرافی پارس');
    expect(t.realized, -73200000);
    expect(t.complete, isTrue);
  });

  test('exchanger lots: manual link closes the linked lot first; FIFO across lots', () {
    XchMove leg(String uid, int v) => XchMove(uid: uid, date: '2026-01-01', kind: 'leg_in', exchanger: 'X', ccy: 'USD', amountCcy: 1000, value: v, stlUid: uid, lid: '1');
    final XchRun lk = xchRun(<XchMove>[
      leg('a', 600000000),
      leg('b', 620000000),
      const XchMove(uid: 'p', date: '2026-01-03', kind: 'xch_paid_us', exchanger: 'X', ccy: 'USD', amountCcy: 1000, payCcy: 'IRR', payAmount: 630000000, links: <XchLink>[XchLink('s:b:1')]),
    ]);
    expect(lk.results[2].realized, 10000000);
    expect(lk.results[2].closed.single.lot, 's:b:1');
    expect(lk.positions['X\u001fUSD']!.lots.single.id, 's:a:1');
    final XchRun ff = xchRun(<XchMove>[
      leg('a', 600000000),
      leg('b', 620000000),
      const XchMove(uid: 'p', date: '2026-01-03', kind: 'xch_paid_us', exchanger: 'X', ccy: 'USD', amountCcy: 1500, payCcy: 'IRR', payAmount: 945000000),
    ]);
    expect(ff.results[2].realized, 35000000);
    expect(ff.results[2].closed.length, 2);
    expect(ff.results[2].closed[1].carry, 310000000);
  });

  test('Settlement.fromRow parses the entity row (JSON strings or lists)', () {
    final Settlement s = Settlement.fromRow(<String, dynamic>{
      'uid': 'x', 'date': '2026-11-02', 'dir': 'recv', 'party': ' شرکت  الف', 'ccy': 'usd', 'amount_ccy': '12000.0000',
      'alloc': '[{"t":"sale","id":101,"amt":4000}]',
      'legs': <dynamic>[<String, dynamic>{'lid': 'l1', 'k': 'xch', 'exchanger': 'صرافي امين', 'settle': 12000, 'ccy': 'USD', 'amount': 12000, 'rate': 615000}],
      'ref_no': 'و-1405-0001',
    }, 3);
    expect(s.party, alef);
    expect(s.ccy, 'USD');
    expect(s.amt4, stlQ4(12000));
    expect(s.alloc.single, ('s101', 40000000));
    expect(s.legs.single.exchanger, 'صرافی امین');
    expect(s.legs.single.v, 7380000000);
  });
}
