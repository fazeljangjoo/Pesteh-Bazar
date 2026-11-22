// فاز ۴ — آینهٔ Dart بهینه‌ساز کوت‌ریزی با کیس‌های مشترک سرور (test/blend_cases.json = کپی بایت‌به‌بایت backend/api/blend_cases.json)
// + اعتبارسنجی مستقل با جست‌وجوی شبکه + ۳۰۰ لات تصادفی با بذر ثابت (مقدار هدف برابر PHP).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/blend_opt_calc.dart';

bool near(Object? a, Object? b, [double tol = 1e-6]) {
  if (a == null || b == null) return a == b;
  final double x = (a as num).toDouble(), y = (b as num).toDouble();
  return (x - y).abs() <= tol * (y.abs() > 1 ? y.abs() : 1);
}

List<Map<String, dynamic>> lotsOf(Object? v) => (v as List<dynamic>).map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList();

void main() {
  final Map<String, dynamic> doc = jsonDecode(File('test/blend_cases.json').readAsStringSync()) as Map<String, dynamic>;

  group('shared cases', () {
    for (final dynamic raw in doc['cases'] as List<dynamic>) {
      final Map<String, dynamic> c = raw as Map<String, dynamic>;
      test(c['name'] as String, () {
        final Map<String, dynamic> r = boSolve(lotsOf(c['lots']), Map<String, dynamic>.from(c['req'] as Map));
        final Map<String, dynamic> e = c['expect'] as Map<String, dynamic>;
        expect(r['status'], e['status']);
        if (e['status'] == 'optimal') {
          expect(near(r['cost_total'], e['cost_total']), isTrue, reason: 'cost ${r['cost_total']} vs ${e['cost_total']}');
          List<List<num>> tk(Object? v) => (v as List<dynamic>).map((dynamic t) => <num>[(t as Map)['id'] as num, boRound((t['kg'] as num).toDouble(), 3)]).toList();
          expect(tk(r['takes']), tk(e['takes']));
          (e['metrics'] as Map<String, dynamic>).forEach((String k, dynamic m) {
            expect(near(((r['metrics'] as Map)[k] as Map)['value'], (m as Map)['value']), isTrue, reason: 'metric $k');
          });
          expect(r['warnings'], e['warnings']);
          expect(near(r['saving'], e['saving']), isTrue, reason: 'saving');
          expect(r['lots_count'], e['lots_count']);
        } else if (e['status'] == 'infeasible') {
          expect((r['blocking'] as List).map((dynamic b) => (b as Map)['text']).toList(), (e['blocking'] as List).map((dynamic b) => (b as Map)['text']).toList());
          if (e['nearest'] != null) {
            ((e['nearest'] as Map)['metrics'] as Map).forEach((dynamic k, dynamic m) {
              expect(near((((r['nearest'] as Map)['metrics'] as Map)[k] as Map)['value'], (m as Map)['value']), isTrue, reason: 'nearest $k');
            });
          }
        } else {
          expect(r['message'], e['message']);
        }
      });
    }
  });

  test('300 random lots: same generator, same objective as PHP, < 1 s', () {
    final Map<String, dynamic> rd = doc['random'] as Map<String, dynamic>;
    final List<Map<String, dynamic>> lots = boRandomLots(rd['n'] as int, rd['seed'] as int);
    expect(jsonEncode(lots.first), jsonEncode(rd['first_lot']));
    final Stopwatch sw = Stopwatch()..start();
    final Map<String, dynamic> r = boSolve(lots, Map<String, dynamic>.from(rd['req'] as Map));
    sw.stop();
    final Map<String, dynamic> e = rd['expect'] as Map<String, dynamic>;
    expect(r['status'], e['status']);
    expect(near(r['cost_total'], e['cost_total'], 1e-9), isTrue, reason: '${r['cost_total']} vs ${e['cost_total']}');
    expect(r['total_kg'], e['total_kg']);
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('grid search never beats the LP (small instances)', () {
    final BoLcg g = BoLcg(777);
    int compared = 0;
    for (int k = 0; k < 20; k++) {
      final List<Map<String, dynamic>> lots = <Map<String, dynamic>>[
        for (int i = 1; i <= 3; i++)
          <String, dynamic>{
            'id': i, 'kg': boRound(200 + g.next() * 600), 'cost': boRound(100 + g.next() * 100), 'date': '2026-01-0$i',
            'q': <String, dynamic>{'ounce': boRound(24 + g.next() * 8, 1), 'khandan_pct': boRound(75 + g.next() * 20, 1)},
          },
      ];
      final double umax = boRound(26 + g.next() * 4, 1), kmin = boRound(80 + g.next() * 8, 1);
      final Map<String, dynamic> req = <String, dynamic>{
        'target_kg': 600, 'objective': 'cost', 'min_take_kg': 0,
        'bounds': <String, dynamic>{'ounce': <double?>[null, umax], 'khandan_pct': <double?>[kmin, null]},
      };
      double? best;
      const int steps = 100;
      for (int a = 0; a <= steps; a++) {
        for (int b = 0; b <= steps - a; b++) {
          final List<double> x = <double>[600.0 * a / steps, 600.0 * b / steps, 600.0 * (steps - a - b) / steps];
          bool ok = true;
          double cost = 0, ou = 0, kh = 0;
          for (int i = 0; i < 3; i++) {
            if (x[i] > (lots[i]['kg'] as double) + 1e-9) ok = false;
            cost += x[i] * (lots[i]['cost'] as double);
            ou += x[i] * ((lots[i]['q'] as Map)['ounce'] as double);
            kh += x[i] * ((lots[i]['q'] as Map)['khandan_pct'] as double);
          }
          if (!ok || ou / 600 > umax + 1e-9 || kh / 600 < kmin - 1e-9) continue;
          if (best == null || cost < best) best = cost;
        }
      }
      final Map<String, dynamic> r = boSolve(lots, req);
      if (best != null) {
        compared++;
        expect(r['status'], 'optimal');
        expect((r['cost_total'] as num) <= best * 1.002, isTrue, reason: 'LP ${r['cost_total']} > grid $best');
        int sum = 0;
        for (final dynamic t in r['takes'] as List) {
          sum += (((t as Map)['kg'] as num) * 1000).round();
        }
        expect(sum, 600000);
      }
    }
    expect(compared, greaterThan(3));
  });

  test('number formatting like PHP', () {
    expect(boNumStr(33.0), '33');
    expect(boNumStr(27.5), '27.5');
    expect(boRound(2.675, 2), 2.68);
  });
}
