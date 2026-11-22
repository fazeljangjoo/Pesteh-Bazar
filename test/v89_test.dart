import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/access_catalog.dart';
import 'package:pesteh_bazar/db.dart';

void main() {
  test('v89: unpriced purchase is held out of stock; foreign-currency docs are not', () {
    expect(AppDb.purchaseUnpriced(<String, dynamic>{'price': 0}), isTrue);
    expect(AppDb.purchaseUnpriced(<String, dynamic>{'price': null}), isTrue);
    expect(AppDb.purchaseUnpriced(<String, dynamic>{'price': 2600000}), isFalse);
    expect(AppDb.purchaseUnpriced(<String, dynamic>{'price': 0, 'ccy': 'USD'}), isFalse);
  });

  test('v89: purchase form has separate base / quality / price parts; ounce-room intake perms are gone', () {
    final AccessSection p = accessSectionOf('purchases')!;
    final List<String> keys = p.fields.map((AccessOption o) => o.key).toList();
    expect(keys, containsAll(<String>['purchase.base', 'purchase.quality', 'purchase.price', 'purchase.pct']));
    final AccessSection o = accessSectionOf('ounce')!;
    expect(o.perms.map((AccessOption x) => x.key), isNot(contains('ounce.intake')));
  });

  test('v89: sale form has a separate price part', () {
    final List<String> keys = accessSectionOf('sales')!.fields.map((AccessOption o) => o.key).toList();
    expect(keys.first, 'sale.price');
    expect(keys, containsAll(<String>['sale.buyer', 'sale.costs', 'sale.fin', 'sale.note']));
  });
}
