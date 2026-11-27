// v95 — کوت‌ریزی مرحله‌ای: همان اعداد mix_staged_selftest.php سرور (DESIGN_v95_mix_sep_FA.md بخش ۲).
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/mix_staged_ui.dart';

void main() {
  test('1,000 kg in worth 2,000,000,000, cost 50,000/kg, 950 kg out ⇒ 2,157,894.74 per kg', () {
    final MixStagedCost c = mixStagedCost(1000, 2000000000, 950, 50000);
    expect(c.unit, closeTo(2157894.74, 0.01));
    expect(c.base, closeTo(2000000, 0.01));
    expect(c.wasteShare, closeTo(105263.16, 0.01));
    expect(c.costShare, closeTo(52631.58, 0.01));
    expect(c.base + c.wasteShare + c.costShare, closeTo(c.unit, 0.0001));
    expect(c.waste, closeTo(50, 1e-9));
  });

  test('no waste and no cost ⇒ the input price', () {
    final MixStagedCost c = mixStagedCost(1000, 2000000000, 1000, 0);
    expect(c.unit, closeTo(2000000, 0.01));
    expect(c.wasteShare, 0);
  });

  test('v96: extra total cost X ⇒ (V + c×I + X) ÷ O, same as the server', () {
    final MixStagedCost c = mixStagedCost(1000, 2000000000, 950, 30000, 15000000);
    expect(c.unit, closeTo((2000000000 + 30000000 + 15000000) / 950, 0.01));
    expect(c.costShare, closeTo(45000000 / 950, 0.01));
    expect(mixStagedCost(590, 1180000000, 580, 10000, 3000000).unit, closeTo((1180000000 + 5900000 + 3000000) / 580, 0.01));
  });

  test('recalc example: input value 2,060,000,000 ⇒ 2,221,052.63', () {
    expect(mixStagedCost(1000, 2060000000, 950, 50000).unit, closeTo(2110000000 / 950, 0.01));
  });
}
