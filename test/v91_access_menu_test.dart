// v91 — بازاریاب/مدیر بازاریابی فقط بخش خودشان؛ منوی کناری قابل تنظیم (پین، پوشهٔ «سایر»).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/menu_layout.dart';
import 'package:pesteh_bazar/perms.dart';

Map<String, dynamic> _staff(List<String> perms) => <String, dynamic>{'id': 9, 'name': 'تست', 'perms': perms};

ListTile _t(String s) => ListTile(leading: const Icon(Icons.circle), title: Text(s));

String? _title(Widget w) => w is ListTile && w.title is Text ? (w.title as Text).data : (w is ExpansionTile && w.title is Text ? (w.title as Text).data : null);

void main() {
  tearDown(() => StaffPerms.I.current.value = null);

  test('marketing-only detection covers the two system roles (and settings/users extras), nothing else', () {
    StaffPerms.I.current.value = null;
    expect(StaffPerms.I.isMarketingOnly, isFalse); // مالک
    StaffPerms.I.current.value = _staff(<String>['marketing.entry']); // بازاریاب
    expect(StaffPerms.I.isMarketingOnly, isTrue);
    StaffPerms.I.current.value = _staff(<String>['marketing.entry', 'marketing.manage', 'marketing.reports', 'users.manage']); // مدیر بازاریابی
    expect(StaffPerms.I.isMarketingOnly, isTrue);
    StaffPerms.I.current.value = _staff(<String>['marketing.entry', 'marketing.manage', 'users.manage', 'settings.manage']); // بخش «مدیریت» کامل
    expect(StaffPerms.I.isMarketingOnly, isTrue);
    StaffPerms.I.current.value = _staff(<String>['marketing.entry', 'sales.view']); // نقش ترکیبی ⇒ پوستهٔ عادی
    expect(StaffPerms.I.isMarketingOnly, isFalse);
    StaffPerms.I.current.value = _staff(<String>['users.manage']); // بدون بازاریابی
    expect(StaffPerms.I.isMarketingOnly, isFalse);
    StaffPerms.I.current.value = _staff(<String>[]);
    expect(StaffPerms.I.isMarketingOnly, isFalse);
  });

  test('menu layout JSON round trip; pinned items cannot also be in «سایر»', () {
    final MenuLayout l = MenuLayout.fromJson(<String, dynamic>{'pinned': <String>['الف', 'ب', 'الف'], 'other': <String>['ب', 'ج']});
    expect(l.pinned, <String>['الف', 'ب']);
    expect(l.other, <String>{'ج'});
    final MenuLayout r = MenuLayout.fromJson(l.toJson());
    expect(r.pinned, l.pinned);
    expect(r.other, l.other);
    expect(MenuLayout.fromJson('junk').isEmpty, isTrue);
  });

  testWidgets('arrangeMenu: pinned on top in chosen order, «سایر» folder, edit entry, logout stays last', (WidgetTester t) async {
    late List<Widget> out;
    final List<Widget> items = <Widget>[
      const Padding(padding: EdgeInsets.all(8), child: Text('سرتیتر')),
      _t('فراوری'),
      _t('سررسیدها'),
      const Divider(),
      _t('حقوق و دستمزد'),
      _t('طرف‌حساب‌ها'),
      _t('تنظیمات چاپ'),
      const Divider(height: 1),
      _t('خروج از حساب'),
    ];
    await t.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext c) {
      out = arrangeMenu(c, items, const MenuLayout(pinned: <String>['طرف‌حساب‌ها', 'فراوری'], other: <String>{'تنظیمات چاپ', 'خروج از حساب'}), onEdit: () {});
      return const SizedBox();
    })));
    final List<String?> titles = out.map(_title).toList();
    expect(out.first, isA<Padding>()); // سرتیتر بالای پین‌شده‌ها
    final List<String> named = titles.whereType<String>().toList();
    expect(named, <String>['طرف‌حساب‌ها', 'فراوری', 'سررسیدها', 'حقوق و دستمزد', 'سایر (1)', 'ویرایش منو', 'خروج از حساب']);
    final ExpansionTile folder = out.whereType<ExpansionTile>().single;
    expect(folder.children.map(_title), <String>['تنظیمات چاپ']);
    // «خروج از حساب» قابل جابه‌جایی نیست
    expect(menuEditableItems(items).map(((String, Widget?) e) => e.$1), <String>['فراوری', 'سررسیدها', 'حقوق و دستمزد', 'طرف‌حساب‌ها', 'تنظیمات چاپ']);
  });

  testWidgets('a pinned item the user lost access to simply disappears (layout never grants access)', (WidgetTester t) async {
    late List<Widget> out;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext c) {
      out = arrangeMenu(c, <Widget>[_t('سررسیدها')], const MenuLayout(pinned: <String>['حقوق و دستمزد']), onEdit: () {});
      return const SizedBox();
    })));
    expect(out.map(_title).whereType<String>(), <String>['سررسیدها', 'ویرایش منو']);
  });
}
