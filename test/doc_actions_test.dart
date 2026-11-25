// v91 p3 — جزئیات خرید/فروش در فرم اصلی به حالت قفل + کارهای سند + قواعد ویرایش بدون محدودیت.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pesteh_bazar/doc_actions_ui.dart';
import 'package:pesteh_bazar/edit_recalc.dart';

bool Function(String) _perms(Set<String>? allowed) => (String k) => allowed == null || allowed.contains(k);

void main() {
  group('purchase actions', () {
    test('owner sees every action, in order', () {
      expect(purchaseActionKeys(isMix: false, can: _perms(null)),
          <String>['payment', 'cartex', 'weigh_slip', 'waybill', 'invoice', 'broker', 'return', 'correction', 'delete']);
    });
    test('mix: no broker / return', () {
      final keys = purchaseActionKeys(isMix: true, can: _perms(null));
      expect(keys.contains('broker'), isFalse);
      expect(keys.contains('return'), isFalse);
      expect(keys.contains('delete'), isTrue);
    });
    test('view-only staff: prints only', () {
      expect(purchaseActionKeys(isMix: false, can: _perms(<String>{'purchases.view'})), <String>['cartex', 'weigh_slip', 'waybill', 'invoice']);
    });
    test('staff with payments + return but no delete', () {
      final keys = purchaseActionKeys(isMix: false, can: _perms(<String>{'payments.save', 'purchases.return'}));
      expect(keys, containsAll(<String>['payment', 'return']));
      expect(keys.contains('delete'), isFalse);
      expect(keys.contains('correction'), isFalse);
    });
    test('unlock needs purchases.create', () {
      expect(canUnlockPurchase(_perms(<String>{'purchases.view'})), isFalse);
      expect(canUnlockPurchase(_perms(<String>{'purchases.create'})), isTrue);
    });
  });

  group('sale actions', () {
    test('owner, rial plan: no export', () {
      expect(saleActionKeys(can: _perms(null)), <String>['receipt', 'invoice', 'weigh_slip', 'waybill', 'broker', 'return', 'correction', 'delete']);
    });
    test('fx plan adds export (needs sales.view)', () {
      expect(saleActionKeys(can: _perms(null), isFx: true).contains('export'), isTrue);
      expect(saleActionKeys(can: _perms(<String>{'sales.create'}), isFx: true).contains('export'), isFalse);
    });
    test('staff without sales.update: no correction, cannot unlock', () {
      final keys = saleActionKeys(can: _perms(<String>{'sales.view', 'receipts.save'}));
      expect(keys.contains('correction'), isFalse);
      expect(keys.contains('receipt'), isTrue);
      expect(canUnlockSale(_perms(<String>{'sales.view'})), isFalse);
      expect(canUnlockSale(_perms(<String>{'sales.update'})), isTrue);
    });
  });

  group('edit rules (mirror of pb_recalc.php)', () {
    test('weight: new net may not go below consumed', () {
      expect(weightRuleError(900, 1000, 150), isNull); // مصرف‌شده ۸۵۰
      final String? e = weightRuleError(800, 1000, 150);
      expect(e, isNotNull);
      expect(e, contains('850'));
      expect(weightRuleError(10, 1000, 1000), isNull); // هیچ مصرفی ⇒ آزاد
    });
    test('mix price = Σ(w×p) ÷ Σw, or ÷ net with waste', () {
      expect(mixPriceOf(<({double w, double price})>[(w: 300, price: 120000), (w: 200, price: 80000)], mixNet: 500), 104000);
      expect(mixPriceOf(<({double w, double price})>[(w: 300, price: 100000)], waste: 20, mixNet: 280), closeTo(107142.86, 0.01));
      expect(mixPriceOf(<({double w, double price})>[], mixNet: 0), isNull);
    });
  });

  group('locked form mode', () {
    testWidgets('fields absorb taps while locked; «ویرایش» unlocks', (WidgetTester t) async {
      int taps = 0;
      bool locked = true;
      await t.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (BuildContext c, StateSetter set) => Scaffold(
              body: ListView(children: <Widget>[
                if (locked) LockedFormBanner(canEdit: true, onEdit: () => set(() => locked = false)),
                LockedFields(locked: locked, child: TextButton(key: const ValueKey<String>('field'), onPressed: () => taps++, child: const Text('فیلد'))),
              ]),
            ),
          ),
        ),
      ));
      await t.tap(find.byKey(const ValueKey<String>('field')), warnIfMissed: false);
      expect(taps, 0, reason: 'locked ⇒ no edits');
      expect(find.text('ویرایش'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('unlock_edit')));
      await t.pump();
      expect(find.byType(LockedFormBanner), findsNothing);
      await t.tap(find.byKey(const ValueKey<String>('field')));
      expect(taps, 1, reason: 'unlocked ⇒ editable');
    });
    testWidgets('no edit permission ⇒ banner without «ویرایش»', (WidgetTester t) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: LockedFormBanner(canEdit: false, onEdit: () {}))));
      expect(find.byKey(const ValueKey<String>('unlock_edit')), findsNothing);
      expect(find.textContaining('فقط‌خواندنی'), findsOneWidget);
    });
  });
}
