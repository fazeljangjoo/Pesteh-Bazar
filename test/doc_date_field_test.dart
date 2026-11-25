import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/utils.dart';
import 'package:pesteh_bazar/widgets.dart';

/// v91: تاریخ دستی در فرم خرید و فروش (تایپ شمسی یا تقویم، پیش‌فرض امروز).
void main() {
  test('parseJalaliInput: Persian/Latin digits, separators, short year, invalid', () {
    expect(parseJalaliInput('۱۴۰۵/۰۹/۰۴'), DateTime(2026, 11, 25));
    expect(parseJalaliInput('1405-9-4'), DateTime(2026, 11, 25));
    expect(parseJalaliInput('05/9/4'), DateTime(2026, 11, 25));
    expect(parseJalaliInput('1405/01/01'), DateTime(2026, 3, 21));
    expect(parseJalaliInput('1405/07/31'), isNull); // مهر ۳۰ روز
    expect(parseJalaliInput('1405/13/01'), isNull);
    expect(parseJalaliInput('abc'), isNull);
  });

  testWidgets('DocDateField: shows date, typing a valid date reports it, invalid fails validation', (WidgetTester t) async {
    DateTime v = DateTime(2026, 11, 25);
    final GlobalKey<FormState> form = GlobalKey<FormState>();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Form(
          key: form,
          child: StatefulBuilder(builder: (BuildContext c, StateSetter set) => DocDateField(label: 'تاریخ فروش', value: v, onChanged: (DateTime d) => set(() => v = d))),
        ),
      ),
    ));
    expect(find.text(jalaliDateFromDt(DateTime(2026, 11, 25))), findsOneWidget);
    await t.enterText(find.byType(TextFormField), '1405/08/15');
    await t.pump();
    expect(v, DateTime(2026, 11, 6));
    expect(form.currentState!.validate(), isTrue);
    await t.enterText(find.byType(TextFormField), '1405/08');
    await t.pump();
    expect(form.currentState!.validate(), isFalse);
    expect(v, DateTime(2026, 11, 6)); // ورودی ناقص مقدار را عوض نمی‌کند
  });
}
