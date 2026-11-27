// v93 — سهم ارز فاکتور روی ردیف پرداخت/دریافت به ارز دیگر: «طبق نرخ روز» یا «مبلغ توافقی».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/fx_tx_fields.dart';

void main() {
  tearDown(() => FxTxController.docCcy = null);

  test('AED received on a USD invoice: share at the day rates, agreed share is kept', () {
    FxTxController.docCcy = 'USD';
    final FxTxController c = FxTxController(TextEditingController());
    c.ccy = 'AED';
    expect(c.needsShare, isTrue);
    c.docRate = 610000;
    c.docRateDate = '2026-11-01';
    c.ccyAmount.text = '3700';
    c.rate.text = '165000';
    c.recompute();
    expect(double.parse(c.share.text), closeTo(1000.8197, 0.00005)); // 3,700 × 165,000 ÷ 610,000
    final Map<String, dynamic> f = c.fields();
    expect(f['doc_ccy_mode'], 'rate');
    expect(f['doc_ccy_amount'], closeTo(1000.8197, 0.00005));
    c.shareMode = 'agreed';
    c.share.text = '1000';
    c.ccyAmount.text = '3750';
    c.recompute();
    expect(c.share.text, '1000'); // agreed amount is not overwritten
    expect(c.fields()['doc_ccy_mode'], 'agreed');
  });

  test('same currency as the invoice or a rial invoice ⇒ no share', () {
    FxTxController.docCcy = 'USD';
    final FxTxController c = FxTxController(TextEditingController());
    c.ccy = 'USD';
    expect(c.needsShare, isFalse);
    expect(c.fields()['doc_ccy_amount'], isNull); // cleared on the line
    FxTxController.docCcy = null;
    final FxTxController r = FxTxController(TextEditingController());
    r.ccy = 'AED';
    expect(r.needsShare, isFalse);
    expect(r.fields().containsKey('doc_ccy_amount'), isFalse); // rial invoice: nothing sent (old behaviour)
  });

  test('rial line on a USD invoice needs a share and is validated', () {
    FxTxController.docCcy = 'USD';
    final FxTxController c = FxTxController(TextEditingController());
    expect(c.needsShare, isTrue); // ccy null = rial
    expect(c.validate(), contains('USD'));
    c.share.text = '483.871';
    expect(c.validate(), isNull);
    expect(c.fields()['doc_ccy_amount'], 483.871);
  });
}
