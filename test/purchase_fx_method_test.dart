import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/buy_mode_ui.dart' show BuyMode;
import 'package:pesteh_bazar/purchase_pct_ui.dart';

/// v91: روش خرید ارزی — همان موتور قیمت‌گذاری روی قیمت ارزی (اعشاری).
void main() {
  test('base50 in USD: 5.50 per 50 g, gram 45 ⇒ 4.95 USD/kg', () {
    final PurchasePctCtl c = PurchasePctCtl()
      ..baseMode = BuyMode.base50
      ..gramSource = () => 45;
    c.syncFx('USD', 2);
    final r = c.blend(5.5, 100)!;
    expect(r.ok, isTrue);
    expect(r.avgPerKg, closeTo(4.95, 1e-6));
    expect(c.money(4.95), contains('USD'));
  });

  test('separate pct price in USD is read as a decimal and blended', () {
    final PurchasePctCtl c = PurchasePctCtl();
    final PurchasePctRow row = PurchasePctRow(defKey: 'dombest', pct: '20')..separate = true;
    c.rows.add(row);
    c.syncFx('USD', 2);
    row.q.text = '3.25';
    expect(c.qOf(row), 3.25);
    final r = c.blend(5.0, 100)!; // ۸۰٪ با ۵ دلار + ۲۰٪ با ۳٫۲۵ دلار
    expect(r.ok, isTrue);
    expect(r.avgPerKg, closeTo(0.8 * 5.0 + 0.2 * 3.25, 1e-6));
  });

  test('switching document currency clears separate prices (no rial read as USD)', () {
    final PurchasePctCtl c = PurchasePctCtl();
    final PurchasePctRow row = PurchasePctRow(defKey: 'dombest', pct: '20')..separate = true;
    c.rows.add(row);
    row.q.text = '1,250,000';
    expect(c.syncFx('USD', 2), isTrue);
    expect(row.q.text, isEmpty);
    expect(c.syncFx('USD', 2), isFalse);
  });
}
