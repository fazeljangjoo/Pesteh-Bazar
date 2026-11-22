import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/access_catalog.dart';
import 'package:pesteh_bazar/access_ui.dart';

void main() {
  testWidgets('section editor: pick sections, options, price and form parts', (WidgetTester t) async {
    AccessDraft draft = AccessDraft(<String>{}, <String, String>{});
    final AccessData data = AccessData(kAccessSections, <AccessRole>[], <String>{}, true);
    Future<void> tap(Finder f) async {
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
    }

    t.view.physicalSize = const Size(1200, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (BuildContext c, StateSetter set) => SingleChildScrollView(
            child: SectionAccessEditor(data: data, draft: draft, onChanged: (AccessDraft d) => set(() => draft = d)),
          ),
        ),
      ),
    ));
    expect(find.text('هنوز بخشی انتخاب نشده؛ این کاربر به هیچ قسمتی دسترسی ندارد.'), findsOneWidget);
    await tap(find.widgetWithText(FilterChip, 'خرید'));
    expect(draft.perms, <String>{'purchases.view'}); // اولین گزینهٔ بخش
    await tap(find.widgetWithText(SwitchListTile, 'ثبت و ویرایش خرید'));
    expect(draft.perms.contains('purchases.create'), isTrue);
    await tap(find.widgetWithText(SwitchListTile, 'نمایش قیمت‌ها و مبالغ در این بخش'));
    expect(draft.perms.contains('price.purchases'), isTrue);
    await t.tap(find.text('پنهان').at(5)); // ششمین قسمت فرم (v89: پایه، گرم/انس، فی، فروشنده، درصدها، هزینه): هزینهٔ کارگر و حمل
    await t.pumpAndSettle();
    expect(draft.fields, <String, String>{'purchase.costs': 'hide'});
    await tap(find.widgetWithText(FilterChip, 'خرید'));
    expect(draft.perms, isEmpty); // خاموش‌کردن بخش ⇒ گزینه‌ها، قیمت و قسمت‌های فرم پاک
    expect(draft.fields, isEmpty);
  });
}
