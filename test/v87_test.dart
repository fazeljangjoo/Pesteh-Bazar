import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/workshop_calc.dart';

void main() {
  test('crack sheet: ناشکن is not part of the kernel breakdown, but counts in real loss', () {
    final CrackCalc c = crackCalc(inputKg: 1000, kernelKg: 400, hullKg: 500, soilKg: 20, soundKg: 300, splitKg: 100, unbreakableKg: 50);
    expect(c.subSumKg, 400); // 300 + 100 (بدون ناشکن)
    expect(c.subMismatch, isFalse);
    expect(c.realLossKg, closeTo(30, 1e-9)); // 1000 − (400 + 500 + 20 + 50)
  });

  test('crack op (v88): uncracked is only recorded; gram and loss use the full input', () {
    // ۵۰۰ کیلو، گرم ۴۵، پرتی خط ۰٫۷، مغز ۲۲۱، نشکن ۳۰ ⇒ مغز مورد انتظار = برآورد بالای فرم = ۲۲۱٫۵
    final WsCrackResult r = wsCrackResult(inKg: 500, gram: 45, kernelKg: 221, lineLoss: 0.7, uncrackedKg: 30, outKg: 251);
    expect(r.expectedKernelKg, closeTo(221.5, 1e-9));
    expect(r.recvGram, closeTo(44.2, 1e-9));
    expect(r.lossGram, closeTo(0.8, 1e-9));
    expect(r.lossKg, closeTo(4, 1e-9));
    expect(r.expectedLossKg, closeTo(3.5, 1e-9));
    expect(r.gramVsLine, closeTo(0.1, 1e-9));
    expect(r.crackedKg, 470);
  });

  test('crack op (v88): kernel cost = whole input value / kernel; hull and uncracked do not affect it', () {
    // ۵۰۰ کیلو × ۲٬۶۰۰٬۰۰۰ ریال، مغز ۲۲۷ ⇒ ۵٬۷۲۶٬۸۷۲ ریال (پوست و نشکن هر مقداری باشند)
    final WsCrackResult a = wsCrackResult(inKg: 500, gram: 47, kernelKg: 227, buyPerKg: 2600000, lineLoss: 0.7, uncrackedKg: 50, hullValue: 9999999);
    expect(a.unitCost!.round(), 5726872);
    expect(a.expectedKernelKg, closeTo(231.5, 1e-9));
    final WsCrackResult b = wsCrackResult(inKg: 500, gram: 47, kernelKg: 227, buyPerKg: 2600000, crackCost: 100000);
    expect(b.unitCost!.round(), 5826872);
  });

  test('abkhandan estimated gram = gram in ± weight %', () {
    expect(wsAbEstimatedGram(47, wsMoisture(1000, 986.8)), closeTo(45.68, 1e-9));
    expect(wsAbEstimatedGram(47, wsMoisture(1000, 1013.2)), closeTo(48.32, 1e-9));
    expect(wsAbEstimatedGram(null, wsMoisture(1000, 990)), isNull);
  });
}
