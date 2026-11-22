import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/access_catalog.dart';
import 'package:pesteh_bazar/access_ui.dart';
import 'package:pesteh_bazar/perms.dart';

void main() {
  test('several roles: union + grants − denies; most permissive field mode', () {
    final ({Set<String> perms, Map<String, String> fields}) e = accessEffective(
      <Set<String>>[<String>{'ounce.intake'}, <String>{'stock.view', 'purchases.view'}],
      <Map<String, String>>[<String, String>{'purchase.costs': 'hide', 'purchase.note': 'lock'}, <String, String>{'purchase.costs': 'lock'}],
      <String>{'price.stock'},
      <String>{'purchases.view'},
      <String, String>{},
    );
    expect(e.perms, <String>{'ounce.intake', 'stock.view', 'price.stock'});
    expect(e.fields, <String, String>{'purchase.costs': 'lock'});
  });

  test('user field override: show frees a field, hide adds one', () {
    final ({Set<String> perms, Map<String, String> fields}) e = accessEffective(<Set<String>>[<String>{}], <Map<String, String>>[<String, String>{'purchase.costs': 'hide'}],
        <String>{}, <String>{}, <String, String>{'purchase.costs': 'show', 'purchase.seller': 'hide'});
    expect(e.fields, <String, String>{'purchase.seller': 'hide'});
  });

  test('price normalisation: all selected sections priced ⇒ price.view; otherwise per-section keys', () {
    final Set<String> all = accessNormalizePrice(<String>{'purchases.view', 'price.purchases', 'stock.view', 'price.stock'}, kAccessSections);
    expect(all.contains('price.view'), isTrue);
    expect(all.contains('price.purchases'), isFalse);
    final Set<String> some = accessNormalizePrice(<String>{'purchases.view', 'price.purchases', 'stock.view'}, kAccessSections);
    expect(some.contains('price.view'), isFalse);
    expect(some.contains('price.purchases'), isTrue);
    final Set<String> stale = accessNormalizePrice(<String>{'sales.view', 'price.purchases'}, kAccessSections);
    expect(stale.contains('price.purchases'), isFalse); // بخش انتخاب‌نشده کلید قیمت ندارد
    final Set<String> ounce = accessNormalizePrice(<String>{'ounces.view', 'intake.price'}, kAccessSections); // v89: پذیرش حذف شد
    expect(ounce.contains('intake.price'), isTrue);
    expect(ounce.contains('price.view'), isFalse); // قیمت اتاق انس جداست
  });

  test('StaffPerms: field modes and per-section price', () {
    StaffPerms.I.current.value = <String, dynamic>{
      'perms': <String>['purchases.view', 'price.purchases'],
      'fields': <String, String>{'purchase.costs': 'hide', 'ws.shifts': 'lock'},
    };
    expect(StaffPerms.I.fieldMode('purchase.costs'), 'hide');
    expect(StaffPerms.I.fieldEditable('ws.shifts'), isFalse);
    expect(StaffPerms.I.fieldShown('ws.shifts'), isTrue);
    expect(StaffPerms.I.fieldMode('purchase.note'), 'show');
    expect(StaffPerms.I.canPriceIn('purchases'), isTrue);
    expect(StaffPerms.I.canPriceIn('sales'), isFalse);
    StaffPerms.I.current.value = null; // مالک
    expect(StaffPerms.I.fieldMode('purchase.costs'), 'show');
    expect(StaffPerms.I.canPriceIn('sales'), isTrue);
  });

  test('catalog: every option key is unique', () {
    final List<String> keys = <String>[for (final AccessSection s in kAccessSections) ...s.perms.map((AccessOption o) => o.key)];
    expect(keys.toSet().length, keys.length);
    final List<String> fields = <String>[for (final AccessSection s in kAccessSections) ...s.fields.map((AccessOption o) => o.key)];
    expect(fields.toSet().length, fields.length);
  });
}
