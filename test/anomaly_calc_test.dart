// فاز ۱ — آینهٔ Dart تشخیص ناهنجاری با کیس‌های مشترک سرور (test/anomaly_cases.json = کپی بایت‌به‌بایت backend/api/anomaly_cases.json).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/anomaly_calc.dart';

void near(Object? got, Object? want, String what) {
  if (want == null || got == null) {
    expect(got, want, reason: what);
    return;
  }
  if (want is num) {
    expect((got as num).toDouble(), closeTo(want.toDouble(), 1e-6), reason: what);
    return;
  }
  expect(got, want, reason: what);
}

void main() {
  final Map<String, dynamic> doc = jsonDecode(File('test/anomaly_cases.json').readAsStringSync()) as Map<String, dynamic>;
  group('anEval', () {
    for (final dynamic c in doc['eval'] as List<dynamic>) {
      final Map<String, dynamic> m = c as Map<String, dynamic>;
      test(m['name'] as String, () {
        final AnEval r = anEval(m['x'], (m['history'] as List<dynamic>).cast<Object?>(), m['dir'] as String);
        final Map<String, Object?> got = r.toMap();
        (m['expect'] as Map<String, dynamic>).forEach((String k, dynamic v) => near(got[k], v, '${m['name']} $k'));
      });
    }
  });
  group('anEvaluate', () {
    for (final dynamic c in doc['evaluate'] as List<dynamic>) {
      final Map<String, dynamic> m = c as Map<String, dynamic>;
      test(m['name'] as String, () {
        final Map<String, List<Object?>> hs = (m['histories'] as Map<String, dynamic>)
            .map((String k, dynamic v) => MapEntry<String, List<Object?>>(k, (v as List<dynamic>).cast<Object?>()));
        final List<AnRow> rows = anEvaluate(m['source'] as String, (m['values'] as Map<String, dynamic>).cast<String, Object?>(), hs, 'کارگاه داخلی');
        final Map<String, dynamic> e = m['expect'] as Map<String, dynamic>;
        expect(anWorst(rows), e['worst']);
        expect(rows.map((AnRow r) => r.eval.level).toList(), e['levels']);
        expect(rows.map((AnRow r) => r.text).toList(), e['texts']);
      });
    }
  });
  test('fa number format', () {
    expect(anFa(2.30, 1), '۲٫۳');
    expect(anFa(12, 0), '۱۲');
    expect(anFa(4.0, 2), '۴');
  });
}
