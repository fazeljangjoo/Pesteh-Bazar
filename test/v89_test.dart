import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/perms.dart';
import 'package:pesteh_bazar/staff_reset_screen.dart';
import 'package:pesteh_bazar/user_badge.dart';
import 'package:pesteh_bazar/access_catalog.dart';
import 'package:pesteh_bazar/db.dart';

void main() {
  test('v89: unpriced purchase is held out of stock; foreign-currency docs are not', () {
    expect(AppDb.purchaseUnpriced(<String, dynamic>{'price': 0}), isTrue);
    expect(AppDb.purchaseUnpriced(<String, dynamic>{'price': null}), isTrue);
    expect(AppDb.purchaseUnpriced(<String, dynamic>{'price': 2600000}), isFalse);
    expect(AppDb.purchaseUnpriced(<String, dynamic>{'price': 0, 'ccy': 'USD'}), isFalse);
  });

  test('v89: purchase form has separate base / quality / price parts; ounce-room intake perms are gone', () {
    final AccessSection p = accessSectionOf('purchases')!;
    final List<String> keys = p.fields.map((AccessOption o) => o.key).toList();
    expect(keys, containsAll(<String>['purchase.base', 'purchase.quality', 'purchase.price', 'purchase.pct']));
    final AccessSection o = accessSectionOf('ounce')!;
    expect(o.perms.map((AccessOption x) => x.key), isNot(contains('ounce.intake')));
  });

  test('v89: sale form has a separate price part', () {
    final List<String> keys = accessSectionOf('sales')!.fields.map((AccessOption o) => o.key).toList();
    expect(keys.first, 'sale.price');
    expect(keys, containsAll(<String>['sale.buyer', 'sale.costs', 'sale.fin', 'sale.note']));
  });

  testWidgets('v89: name and role line under the badge; owner shows «مالک»', (WidgetTester t) async {
    StaffPerms.I.current.value = <String, dynamic>{'name': 'علی رضایی', 'role': 'اتاق انس + انباردار', 'perms': <String>[]};
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: UserRoleLine())));
    expect(find.text('علی رضایی — اتاق انس + انباردار'), findsOneWidget);
    StaffPerms.I.current.value = null;
    await t.pump();
    expect(find.text('مالک'), findsOneWidget);
  });

  testWidgets('v89: staff password reset screen starts with owner phone, username and send button', (WidgetTester t) async {
    await t.pumpWidget(const MaterialApp(home: StaffResetScreen(ownerPhone: '09120000000', username: 'ali')));
    expect(find.text('09120000000'), findsOneWidget);
    expect(find.text('ali'), findsOneWidget);
    expect(find.text('ارسال کد پیامکی'), findsOneWidget);
  });
}
