// v92 فاز د — آزمون مرحلهٔ چک در شناسنامه و طرف‌های تازهٔ تسعیر در مدل اپ.
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/fx_reval_models.dart';
import 'package:pesteh_bazar/settle_calc.dart';

void main() {
  test('cheque source id = PHP crc32("uid:lid") & 0x7fffffff + 1', () {
    expect(stlChequeSrcId('u', 'l'), 1289126052);
    expect(stlChequeSrcId('00000000-0000-4000-8000-000000000102', 'abc-lid'), 274082835);
  });

  final StlDoc sale = StlDoc(t: 'sale', id: 501, party: 'آقای چ', ccy: 'IRR', rate: 1, date: '2026-10-01', total4: 50000000 * kQ, book: 50000000);
  final Settlement s = Settlement(
    uid: 'u1', order: 1, date: '2026-10-10', dir: 'recv', party: 'آقای چ', ccy: 'IRR', amt4: 50000000 * kQ,
    alloc: <(String, int)>[('s501', 50000000 * kQ)],
    legs: const <StlLeg>[StlLeg(lid: 'c1', k: 'cheque', settle4: 50000000 * kQ, ccy: 'IRR', amount: 50000000, rate: 1, cheque: <String, String>{'no': '123456', 'due': '2026-12-01'})],
  );

  test('cheque stage keeps the trail open until it is cleared', () {
    final StlState unknown = StlState.build(<String, StlDoc>{sale.key: sale}, <Settlement>[s], const []);
    final Trail t0 = stlTrail(unknown, 'u1')!;
    expect(t0.complete, isFalse);
    expect(t0.stages.single.open, isTrue);
    expect(t0.res.carry, 50000000);
    final int src = stlChequeSrcId('u1', 'c1');
    final Trail t1 = stlTrail(StlState.build(<String, StlDoc>{sale.key: sale}, <Settlement>[s], const [], cheques: <int, String>{src: 'cleared'}), 'u1')!;
    expect(t1.complete, isTrue);
    expect(t1.stages.single.chequeStatus, 'cleared');
    final Trail t2 = stlTrail(StlState.build(<String, StlDoc>{sale.key: sale}, <Settlement>[s], const [], cheques: <int, String>{src: 'bounced'}), 'u1')!;
    expect(t2.complete, isFalse);
    expect(kChequeStatusFa[t2.stages.single.chequeStatus], 'برگشتی');
  });

  test('cheque leg survives the JSON round trip', () {
    final StlLeg l = StlLeg.fromJson(<String, dynamic>{'lid': 'c1', 'k': 'cheque', 'settle': 10, 'ccy': 'IRR', 'amount': 10, 'rate': 1, 'cheque': <String, dynamic>{'no': '9', 'due': '2026-12-01', 'bank': 'ملت'}});
    expect(l.isCheque, isTrue);
    expect(l.toJson()['cheque'], <String, String>{'no': '9', 'due': '2026-12-01', 'bank': 'ملت'});
  });

  test('revaluation preview: new book sides are labelled and summed like exchangers', () {
    final FxRevalPreview p = FxRevalPreview.fromJson(<String, dynamic>{
      'as_of': '2026-11-30', 'ai_down': 10000000, 'ao_up': 3000000, 'lg_up': 15000000, 'lt_down': 6000000, 'tc_up': 30000000, 'tb_up': 1000000,
      'docs': <dynamic>[], 'items': <dynamic>[], 'parties': <dynamic>[], 'net_delta': 33000000,
    });
    expect(p.xrUp, 49000000);
    expect(p.xrDown, 16000000);
    expect(p.hasChanges, isTrue);
    expect(p.netGain, 33000000);
    expect(fxRevalSideOf('tc'), 'tc');
    expect(fxRevalSideLabel('lt'), 'قرض گرفتیم');
    expect(fxRevalSideLabel('ai'), 'پیش‌دریافت (علی‌الحساب)');
  });
}
