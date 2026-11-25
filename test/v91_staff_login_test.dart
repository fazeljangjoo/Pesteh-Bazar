// v91 p2: ورود مالک/کارمند، ورود کارمند فقط با نام کاربری، و قاعدهٔ نام کاربری.
// درخواست‌ها با MockClient گرفته می‌شوند (هیچ درخواستی به سرور واقعی نمی‌رود).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pesteh_bazar/access_catalog.dart';
import 'package:pesteh_bazar/access_ui.dart';
import 'package:pesteh_bazar/license_gate_screen.dart';
import 'package:pesteh_bazar/license_service.dart';
import 'package:pesteh_bazar/staff_login_logic.dart';

void main() {
  group('validateStaffUsername', () {
    test('new usernames follow ^[A-Za-z0-9]{3,30}\$', () {
      expect(validateStaffUsername('Reza2026'), isNull);
      expect(validateStaffUsername('abc'), isNull);
      expect(validateStaffUsername('a' * 30), isNull);
      expect(validateStaffUsername('a' * 31), kStaffUsernameRuleMsg);
      expect(validateStaffUsername('ab'), kStaffUsernameRuleMsg);
      expect(validateStaffUsername('ali.r'), kStaffUsernameRuleMsg);
      expect(validateStaffUsername('ali_r'), kStaffUsernameRuleMsg);
      expect(validateStaffUsername('علی'), kStaffUsernameRuleMsg);
      expect(validateStaffUsername('a b c'), kStaffUsernameRuleMsg);
      expect(validateStaffUsername('  '), 'نام کاربری را وارد کنید');
    });
    test('grandfathered: unchanged legacy username is accepted, changed one must be valid', () {
      expect(validateStaffUsername('sara.m', original: 'sara.m'), isNull);
      expect(validateStaffUsername('x1', original: 'x1'), isNull);
      expect(validateStaffUsername('sara.mm', original: 'sara.m'), kStaffUsernameRuleMsg);
      expect(validateStaffUsername('Sara2', original: 'sara.m'), isNull);
    });
  });

  test('server asks for owner phone only with 409 + need_owner_phone', () {
    expect(responseNeedsOwnerPhone(409, <String, dynamic>{'code': kNeedOwnerPhoneCode}), isTrue);
    expect(responseNeedsOwnerPhone(401, <String, dynamic>{'code': kNeedOwnerPhoneCode}), isFalse);
    expect(responseNeedsOwnerPhone(409, <String, dynamic>{'error': 'x'}), isFalse);
  });

  test('owner phone for a staff session comes from the server response', () {
    final s = LicenseService.I;
    String r(Object? srv, String sent) => resolveStaffOwnerPhone(srv, sent, normalize: s.normalizePhone, isValid: s.isValidPhone);
    expect(r('989121111111', ''), '989121111111'); // ورود فقط با نام کاربری
    expect(r('09121111111', ''), '989121111111');
    expect(r(null, '989123333333'), '989123333333'); // پاسخ بدون phone ⇒ شمارهٔ فرستاده‌شده
    expect(r('bad', ''), ''); // نامعتبر
  });

  testWidgets('staff form validates username live (grandfathered legacy name ok until changed)', (WidgetTester t) async {
    t.view.physicalSize = const Size(1200, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final AccessData data = AccessData(kAccessSections, <AccessRole>[], <String>{}, true);
    await t.pumpWidget(MaterialApp(
        home: StaffAccessScreen(data: data, staff: const <String, dynamic>{'id': 5, 'name': 'سارا', 'username': 'sara.m', 'active': true})));
    await t.pumpAndSettle();
    final Finder f = find.byKey(const ValueKey<String>('staff_username'));
    expect(f, findsOneWidget);
    expect(find.text(kStaffUsernameRuleMsg), findsNothing); // نام قدیمی بدون تغییر
    await t.enterText(f, 'sara.mm');
    await t.pump();
    expect(find.text(kStaffUsernameRuleMsg), findsOneWidget);
    await t.enterText(f, 'Sara2');
    await t.pump();
    expect(find.text(kStaffUsernameRuleMsg), findsNothing);
  });

  group('LoginScreen', () {
    Future<void> waitIdle(WidgetTester t) async {
      for (int i = 0; i < 40; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await t.pump(const Duration(milliseconds: 50));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      await t.pump();
    }

    Future<void> pump(WidgetTester t) async {
      t.view.physicalSize = const Size(900, 2000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: LoginScreen(onSuccess: () {})));
      await t.pumpAndSettle();
    }

    testWidgets('step 1: choose owner or staff', (WidgetTester t) async {
      await pump(t);
      expect(find.byKey(const ValueKey('login_role_owner')), findsOneWidget);
      expect(find.byKey(const ValueKey('login_role_staff')), findsOneWidget);
      expect(find.text('کارمند'), findsOneWidget);
      expect(find.byKey(const ValueKey('login_phone')), findsNothing);
      expect(find.byKey(const ValueKey('login_submit')), findsNothing);

      // مالک: شماره + پیش‌فرض کد پیامکی + گزینهٔ «ورود با رمز عبور»
      await t.tap(find.byKey(const ValueKey('login_role_owner')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('login_phone')), findsOneWidget);
      expect(find.text('دریافت کد ورود'), findsOneWidget);
      expect(find.byKey(const ValueKey('login_pass')), findsNothing);
      await t.tap(find.text('ورود با رمز عبور'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('login_phone')), findsOneWidget);
      expect(find.byKey(const ValueKey('login_pass')), findsOneWidget);
      expect(find.byKey(const ValueKey('login_user')), findsNothing);

      // بازگشت ⇒ کارمند: فقط نام کاربری + رمز، بدون شمارهٔ مالک، با «رمز را فراموش کرده‌ام»
      await t.tap(find.byKey(const ValueKey('login_change_role')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('login_role_staff')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('login_user')), findsOneWidget);
      expect(find.byKey(const ValueKey('login_pass')), findsOneWidget);
      expect(find.byKey(const ValueKey('login_phone')), findsNothing);
      expect(find.byKey(const ValueKey('login_mode_toggle')), findsNothing);
      expect(find.byKey(const ValueKey('login_staff_forgot')), findsOneWidget);
      expect(find.text('ورود کارمند: نام کاربری و رمز عبور'), findsOneWidget);
    });

    testWidgets('staff: username only; ambiguous legacy username ⇒ asks owner phone', (WidgetTester t) async {
      final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
      final client = MockClient((http.Request req) async {
        expect(req.url.path.endsWith('/staff_login.php'), isTrue);
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        sent.add(body);
        if (!body.containsKey('phone')) {
          return http.Response(jsonEncode(<String, dynamic>{'error': 'این نام کاربری در بیش از یک مجموعه ثبت شده است', 'code': 'need_owner_phone'}), 409,
              headers: <String, String>{'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response(jsonEncode(<String, dynamic>{'error': 'نام کاربری یا رمز اشتباه است.'}), 401,
            headers: <String, String>{'content-type': 'application/json; charset=utf-8'});
      });
      await http.runWithClient(() async {
        await pump(t);
        await t.tap(find.byKey(const ValueKey('login_role_staff')));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const ValueKey('login_user')), 'mina');
        await t.enterText(find.byKey(const ValueKey('login_pass')), 'secret1');
        await t.tap(find.byKey(const ValueKey('login_submit')));
        await waitIdle(t);

        expect(sent.length, 1);
        expect(sent.first['username'], 'mina');
        expect(sent.first.containsKey('phone'), isFalse); // بدون شمارهٔ مالک
        expect(find.byKey(const ValueKey('login_phone')), findsOneWidget); // حالا شمارهٔ مالک پرسیده می‌شود
        expect(find.text('شمارهٔ موبایل مالک مجموعه'), findsOneWidget);

        await t.enterText(find.byKey(const ValueKey('login_phone')), '09123333333');
        await t.tap(find.byKey(const ValueKey('login_submit')));
        await waitIdle(t);
        expect(sent.length, 2);
        expect(sent[1]['phone'], '989123333333');
        expect(sent[1]['username'], 'mina');
        expect(find.text('نام کاربری یا رمز اشتباه است.'), findsOneWidget);
      }, () => client);
    });
  });
}
