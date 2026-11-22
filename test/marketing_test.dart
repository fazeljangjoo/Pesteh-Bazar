import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/marketing_calc.dart';
import 'package:pesteh_bazar/marketing_dashboard_ui.dart';
import 'package:pesteh_bazar/marketing_ui.dart';

void main() {
  group('v90 marketing score (shared cases with the server)', () {
    final Map<String, dynamic> cases = jsonDecode(File('test/marketing_cases.json').readAsStringSync()) as Map<String, dynamic>;
    for (final dynamic c in cases['score'] as List<dynamic>) {
      final Map<String, dynamic> m = c as Map<String, dynamic>;
      test('${m['name']}', () {
        final MkScore s = mkScore(MkCounts.fromJson(m['in'] as Map<String, dynamic>));
        expect(s.total, closeTo((m['total'] as num).toDouble(), 1e-6));
        expect(s.finalScore, closeTo((m['final'] as num).toDouble(), 1e-6));
      });
    }

    test('custom weights from settings', () {
      final MkWeights w = MkWeights.fromSettings(<String, dynamic>{'w_sale': 100, 'per_sale_deduct': 0});
      final MkScore s = mkScore(const MkCounts(sales: 2), w);
      expect(s.total, 200);
      expect(s.finalScore, 200);
    });

    test('safe rate and flags', () {
      expect(mkRate(3, 0), isNull);
      expect(mkRate(1, 4), 0.25);
      expect(mkFlag('tr'), '🇹🇷');
      expect(mkFlag(''), '🌐');
      expect(mkCountryName('CN'), 'چین');
      expect(mkCountryName('--'), 'نامشخص');
    });
  });

  group('v90 marketing dashboard renders server reports', () {
    final Map<String, dynamic> sample = jsonDecode(File('test/marketing_report_sample.json').readAsStringSync()) as Map<String, dynamic>;

    Future<void> pump(WidgetTester t, Map<String, dynamic> r, {double width = 1400}) async {
      t.view.physicalSize = Size(width, 6000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: MarketingDashboard(debugReport: r)))));
      await t.pump(const Duration(milliseconds: 600));
    }

    testWidgets('full report: KPIs, funnel, board, countries, lists', (WidgetTester t) async {
      await pump(t, sample['full'] as Map<String, dynamic>);
      expect(t.takeException(), isNull);
      expect(find.text('قیف تبدیل مشتری‌های این دوره'), findsOneWidget);
      expect(find.text('رتبه و امتیاز بازاریاب‌ها'), findsOneWidget);
      expect(find.text('Ali'), findsWidgets);
      expect(find.textContaining('ترکیه'), findsWidgets);
      expect(find.text('Kevin'), findsWidgets); // پیگیری عقب‌افتاده
      expect(find.textContaining('فروش منتظر تأیید'), findsOneWidget);
    });

    testWidgets('phone width: no overflow', (WidgetTester t) async {
      await pump(t, sample['full'] as Map<String, dynamic>, width: 390);
      expect(t.takeException(), isNull);
      expect(find.text('رتبه و امتیاز بازاریاب‌ها'), findsOneWidget);
    });

    testWidgets('empty period: no crash, friendly empty states', (WidgetTester t) async {
      await pump(t, sample['empty'] as Map<String, dynamic>);
      expect(t.takeException(), isNull);
      expect(find.text('در این دوره مشتری تازه‌ای ثبت نشده'), findsWidgets);
      expect(find.text('در این دوره فعالیتی ثبت نشده'), findsOneWidget);
    });
  });

  testWidgets('v90 lead tile shows flag, stage and overdue follow-up', (WidgetTester t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MkLeadTile(lead: <String, dynamic>{
          'uid': 'a', 'name': 'Jiangmen Boshi Foods', 'country': 'CN', 'city': 'Jiangmen', 'stage': 'negotiation', 'next_followup_at': '2020-01-01 10:00:00',
        }),
      ),
    ));
    expect(find.text('Jiangmen Boshi Foods'), findsOneWidget);
    expect(find.text('مذاکره'), findsOneWidget);
    expect(find.textContaining('پیگیری عقب‌افتاده'), findsOneWidget);
  });
}
