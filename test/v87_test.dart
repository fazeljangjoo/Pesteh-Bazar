import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/workshop_calc.dart';

void main() {
  test('crack sheet: ناشکن is not part of the kernel breakdown, but counts in real loss', () {
    final CrackCalc c = crackCalc(inputKg: 1000, kernelKg: 400, hullKg: 500, soilKg: 20, soundKg: 300, splitKg: 100, unbreakableKg: 50);
    expect(c.subSumKg, 400); // 300 + 100 (بدون ناشکن)
    expect(c.subMismatch, isFalse);
    expect(c.realLossKg, closeTo(30, 1e-9)); // 1000 − (400 + 500 + 20 + 50)
  });

  test('crack op: uncracked stays out of received gram', () {
    final WsCrackResult r = wsCrackResult(inKg: 1000, gram: 50, kernelKg: 380, uncrackedKg: 200);
    expect(r.crackedKg, 800);
    expect(r.recvGram, closeTo(47.5, 1e-9));
  });

  test('abkhandan estimated gram = gram in ± weight %', () {
    expect(wsAbEstimatedGram(47, wsMoisture(1000, 986.8)), closeTo(45.68, 1e-9));
    expect(wsAbEstimatedGram(47, wsMoisture(1000, 1013.2)), closeTo(48.32, 1e-9));
    expect(wsAbEstimatedGram(null, wsMoisture(1000, 990)), isNull);
  });
}
