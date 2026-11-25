import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/sale_lot_picker.dart';

/// v91: انتخاب لات فروش با پنجرهٔ جست‌وجو (به‌جای فهرست کشویی بلند).
void main() {
  final List<Map<String, dynamic>> lots = <Map<String, dynamic>>[
    for (int i = 1; i <= 300; i++)
      <String, dynamic>{
        'id': i,
        'code': 'K$i',
        'seller': i == 137 ? 'حسینی رفسنجان' : 'فروشنده $i',
        'category_name': 'خندان',
        'type_name': i.isEven ? 'اکبری' : 'فندقی',
        'remaining': 100.0 + i,
        'ounce': 28,
        'gram': 45,
        'is_mix': 0,
      },
  ];

  Future<int?> pump(WidgetTester t) async {
    int? picked;
    await t.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext c, StateSetter set) => SaleLotPicker(lots: lots, selectedId: picked, onSelect: (int v) => set(() => picked = v)),
          ),
        ),
      ),
    ));
    await t.tap(find.byType(InputDecorator));
    await t.pumpAndSettle();
    return picked;
  }

  testWidgets('300 lots: compact dialog, search narrows, tap selects', (WidgetTester t) async {
    await pump(t);
    expect(t.takeException(), isNull);
    expect(find.text('۳۰۰ لات از ۳۰۰'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'حسینی');
    await t.pumpAndSettle();
    expect(find.text('۱ لات از ۳۰۰'), findsOneWidget);
    await t.tap(find.textContaining('حسینی رفسنجان'));
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.textContaining('K137'), findsWidgets); // کادر انتخاب و مشخصات لات
  });

  testWidgets('search by code with Persian digits', (WidgetTester t) async {
    await pump(t);
    await t.enterText(find.byType(TextField), 'k۲۹۹');
    await t.pumpAndSettle();
    expect(find.text('۱ لات از ۳۰۰'), findsOneWidget);
  });
}
