// v94 — نحوهٔ قیمت‌گذاری فرم فروش (همان فرمول فرم خرید).
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/buy_mode_ui.dart';
import 'package:pesteh_bazar/sale_price_mode.dart';

void main() {
  test('one fee: the entered fee is the per-kg price', () {
    expect(salePriceFromMode(BuyMode.fixed, 2500000, null), 2500000);
  });
  test('50-gram base: fee ÷ 50 × gram', () {
    expect(salePriceFromMode(BuyMode.base50, 2500000, 46), 2300000);
    expect(salePriceFromMode(BuyMode.base50, 2500000, null), isNull); // gram needed
  });
  test('per gram: fee per gram × gram', () {
    expect(salePriceFromMode(BuyMode.perGram, 50000, 46.5), 2325000);
    expect(salePriceFromMode(BuyMode.perGram, 50000, 120), isNull); // gram out of range
  });
}
