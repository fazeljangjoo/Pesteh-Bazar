import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/workshop_calc.dart';
import 'package:pesteh_bazar/ws_recrack_ui.dart';
import 'package:pesteh_bazar/ws_shifts_ui.dart';

// v91 p4 — شکست مجدد نشکن در همان فرم عملیات شکست: کادر WsRecrackCard (اعتبارسنجی وزن، دورها، لغو) + برچسب دور شیفت‌ها.
// محاسبات و قواعد وضعیت در test/workshop_flow_cases.json و test/workshop_v81_cases.json (مشترک با PHP) آزموده می‌شوند.
void main() {
  Map<String, dynamic> open0() => <String, dynamic>{
        'status': 'open',
        'op_type': 'crack',
        'inputs': <Map<String, dynamic>>[<String, dynamic>{'uid': 'i1', 'kg': 1000}],
        'outputs': <Map<String, dynamic>>[
          <String, dynamic>{'uid': 'k0', 'grade': 'kernel', 'kg': 400},
          <String, dynamic>{'uid': 'h0', 'grade': 'hull', 'kg': 450},
          <String, dynamic>{'uid': 'u0a', 'grade': 'uncracked', 'kg': 70},
          <String, dynamic>{'uid': 'u0b', 'grade': 'uncracked', 'kg': 50},
        ],
      };

  Future<void> pump(WidgetTester t, Widget w) async {
    t.view.physicalSize = const Size(1000, 1800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))));
    await t.pumpAndSettle();
  }

  testWidgets('شکست مجدد: بیش از نشکن موجود رد می‌شود؛ وزن مجاز ارسال و روی مدل اعمال می‌شود', (WidgetTester t) async {
    Map<String, dynamic> d = open0();
    final List<double> sent = <double>[];
    late StateSetter setOuter;
    await pump(
      t,
      StatefulBuilder(builder: (BuildContext c, StateSetter set) {
        setOuter = set;
        return WsRecrackCard(
          detail: d,
          onRecrack: (double kg, String date) async {
            sent.add(kg);
            final WsFlowStep r = wsFlowApply(d, 'recrack', <String, dynamic>{'uid': 'rc-1', 'kg': kg, 'date': date});
            expect(r.error, isNull);
            setOuter(() => d = r.state);
          },
          onUndo: (int round) async {
            final WsFlowStep r = wsFlowApply(d, 'recrack_undo', <String, dynamic>{'round': round});
            setOuter(() => d = r.state);
          },
        );
      }),
    );
    expect(WsRecrackCard.shown(d), isTrue);
    expect(find.text('شکست مجدد نشکن'), findsWidgets);
    expect(find.text('۱۲۰ کیلو'), findsOneWidget); // نشکن موجود = ۷۰ + ۵۰

    await t.tap(find.widgetWithText(FilledButton, 'شکست مجدد نشکن'));
    await t.pumpAndSettle();
    expect(find.text('شکست مجدد نشکن — شکست مجدد ۱'), findsOneWidget);

    await t.enterText(find.byKey(const ValueKey<String>('ws-recrack-kg')), '130');
    await t.tap(find.text('ثبت شکست مجدد'));
    await t.pumpAndSettle();
    expect(find.text(kWsFlowErrors['over_recrack']!), findsOneWidget);
    expect(sent, isEmpty);

    await t.enterText(find.byKey(const ValueKey<String>('ws-recrack-kg')), '0');
    await t.tap(find.text('ثبت شکست مجدد'));
    await t.pumpAndSettle();
    expect(find.text(kWsFlowErrors['recrack_kg']!), findsOneWidget);

    await t.enterText(find.byKey(const ValueKey<String>('ws-recrack-kg')), '۱۰۰');
    await t.tap(find.text('ثبت شکست مجدد'));
    await t.pumpAndSettle();
    expect(sent, <double>[100]);
    // LIFO: ۵۰ کامل + ۵۰ از ۷۰ ⇒ ۲۰ کیلو نشکن می‌ماند؛ ورودی همان ۱۰۰۰
    expect(find.text('۲۰ کیلو'), findsOneWidget);
    expect(find.textContaining('شکست مجدد ۱'), findsWidgets);
    expect(wsFlowTotals(d).inputKg, 1000);
    expect(wsFlowTotals(d).lossKg, 130);

    // دور ۱ خروجی دارد ⇒ لغو رد می‌شود
    d = wsFlowApply(d, 'output_save', <String, dynamic>{'uid': 'k1', 'grade': 'kernel', 'kg': 45, 'round': 1}).state;
    setOuter(() {});
    await t.pumpAndSettle();
    await t.tap(find.text('لغو شکست مجدد ۱'));
    await t.pumpAndSettle();
    expect(find.text(kWsFlowErrors['recrack_busy']!), findsOneWidget);

    // بی‌خروجی ⇒ لغو ⇒ نشکن ۱۲۰ برمی‌گردد
    d = wsFlowApply(d, 'output_delete', <String, dynamic>{'uid': 'k1'}).state;
    setOuter(() {});
    await t.pumpAndSettle();
    ScaffoldMessenger.of(t.element(find.byType(WsRecrackCard))).clearSnackBars();
    await t.pumpAndSettle();
    await t.tap(find.text('لغو شکست مجدد ۱'));
    await t.pumpAndSettle();
    await t.tap(find.text('لغو دور'));
    await t.pumpAndSettle();
    expect((d['recracks'] as List<dynamic>).length, 0);
    expect(find.text('۱۲۰ کیلو'), findsOneWidget);
  });

  testWidgets('عملیات بسته: کادر فقط‌خواندنی؛ بی‌نشکن و بی‌دور: کادر نمایش داده نمی‌شود', (WidgetTester t) async {
    final Map<String, dynamic> d = <String, dynamic>{...open0(), 'status': 'done'};
    await pump(t, WsRecrackCard(detail: d, onRecrack: (double kg, String date) async {}, onUndo: (int r) async {}));
    expect(find.text('۱۲۰ کیلو'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'شکست مجدد نشکن'), findsNothing);
    final Map<String, dynamic> none = <String, dynamic>{
      ...open0(),
      'outputs': <Map<String, dynamic>>[<String, dynamic>{'uid': 'k0', 'grade': 'kernel', 'kg': 400}],
    };
    expect(WsRecrackCard.shown(none), isFalse);
    expect(WsRecrackCard.shown(<String, dynamic>{...open0(), 'op_type': 'dehull'}), isFalse);
  });

  testWidgets('شیفت‌ها: برچسب دور شکست مجدد', (WidgetTester t) async {
    await pump(
      t,
      WsShiftsCard(
        round: 1,
        shifts: const <Map<String, dynamic>>[
          <String, dynamic>{'shift': 'morning', 'date': '2026-11-25', 'start': '08:00', 'end': '12:00'},
          <String, dynamic>{'shift': 'evening', 'date': '2026-11-25', 'start': '14:00', 'end': '18:00', 'round': 1},
        ],
        onSave: (List<Map<String, dynamic>> v) async {},
      ),
    );
    expect(find.textContaining('شکست مجدد ۱'), findsOneWidget);
    final List<List<String>> rows = wsShiftReportRows(<Map<String, dynamic>>[
      <String, dynamic>{'shift': 'evening', 'date': '2026-11-25', 'start': '14:00', 'end': '18:00', 'round': 2},
    ]);
    expect(rows.first.first, contains('شکست مجدد ۲'));
  });
}
