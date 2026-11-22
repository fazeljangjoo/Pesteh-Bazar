// v90 — «اضافه کردن از اکسل» در بازاریابی: نوع ایمپورت mk_leads (تطبیق ستون فارسی، کشور/منبع/مرحله، تکراری داخل فایل، بار ارسالی).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/import_engine.dart';
import 'package:pesteh_bazar/marketing_ui.dart' show MkImportScreen;

Uint8List _csv(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  final ImpKind k = kMkLeadImportKind;

  test('mk_leads fields mirror the server spec (import.php)', () {
    expect(k.id, 'mk_leads');
    expect(k.fields.map((ImpField f) => f.key).toList(),
        <String>['name', 'contact', 'country', 'city', 'phone', 'email', 'source', 'products', 'est_tons', 'stage', 'owner', 'next_followup', 'note']);
    expect(k.fields.where((ImpField f) => f.required).map((ImpField f) => f.key), <String>['name']);
    expect(k.keyFields, <String>['name']);
  });

  test('Persian headers auto-match, enums map to stored values', () {
    final ImpSheet s = ImportEngine.parse(
        'leads.csv',
        _csv('﻿نام شرکت / مشتری,شخص رابط,کشور,شهر,تلفن / واتساپ,ایمیل,منبع آشنایی,محصول مورد علاقه,حجم تخمینی خرید (تن),مرحله,مسئول,پیگیری بعدی,یادداشت\n'
            'Al Noor,Khalid,امارات,دبی,+971500000000,a@b.example,نمایشگاه,"خندان، مغز",۲۰,مذاکره,,1405/09/10,نمونه\n'
            'Muze,,tr,,,,علی‌بابا / B2B,,,پیش‌فاکتور,,,\n'
            'Kevin,,CN,,,,linkedin,,,lead,,,\n'));
    final Map<String, int> m = ImportEngine.autoMap(k, s.headers);
    expect(m.values.every((int i) => i >= 0), isTrue, reason: '$m');
    final List<ImpRow> rows = ImportEngine.validate(k, s, m);
    expect(rows.every((ImpRow r) => r.ok), isTrue, reason: rows.map((ImpRow r) => r.errors).toString());
    expect(rows[0].values['country'], 'AE');
    expect(rows[0].values['source'], 'expo');
    expect(rows[0].values['stage'], 'negotiation');
    expect(rows[0].values['est_tons'], 20);
    expect(rows[0].values['products'], 'خندان، مغز');
    expect(rows[0].values.containsKey('owner'), isFalse); // خالی ⇒ ارسال نمی‌شود (سرور = خود کاربر)
    expect(rows[1].values['country'], 'TR');
    expect(rows[1].values['source'], 'b2b');
    expect(rows[1].values['stage'], 'proforma');
    expect(rows[2].values['source'], 'linkedin');
    expect(rows[2].values['stage'], 'lead');
  });

  test('closed stages, unknown country and duplicate names are row errors', () {
    final ImpSheet s = ImportEngine.parse(
        'leads.csv',
        _csv('نام,کشور,مرحله\n'
            'A Co,امارات,فروش\n'
            'B Co,Atlantis,\n'
            'c  co,,\n'
            'C Co,,\n'
            ',ایران,\n'));
    final List<ImpRow> rows = ImportEngine.validate(k, s, ImportEngine.autoMap(k, s.headers));
    expect(rows.length, 5);
    expect(rows[0].ok, isFalse); // فروش با اکسل ثبت نمی‌شود
    expect(rows[1].ok, isFalse); // کشور ناشناخته
    expect(rows[2].ok, isTrue);
    expect(rows[3].errors.single, contains('ردیف 4')); // همان نام (با فاصله/حروف متفاوت)
    expect(rows[4].errors.single, contains('الزامی'));
  });

  test('payload sends only good rows with their sheet row numbers', () {
    final ImpSheet s = ImportEngine.parse('l.csv', _csv('نام,ایمیل\nGood,g@x.example\n,\nBad Row,\n'));
    final List<ImpRow> rows = ImportEngine.validate(k, s, ImportEngine.autoMap(k, s.headers));
    final Map<String, dynamic> p = ImportEngine.payload(k, rows, batchId: 'imp_test_1', dryRun: true);
    expect(p['kind'], 'mk_leads');
    final List<dynamic> sent = p['rows'] as List<dynamic>;
    expect(sent.length, 2);
    expect((sent.first as Map)['_row'], 2);
    expect((sent.last as Map)['_row'], 4);
  });

  testWidgets('«اضافه کردن از اکسل» opens with the marketing kind fixed (no kind picker)', (WidgetTester t) async {
    await t.pumpWidget(const MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: MkImportScreen())));
    await t.pump();
    expect(find.text('اضافه کردن از اکسل'), findsOneWidget);
    expect(find.text('مشتری‌های بازاریابی بین‌المللی'), findsOneWidget);
    expect(find.text('دانلود قالب'), findsOneWidget);
    expect(find.text('انتخاب فایل'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<ImpKind>), findsNothing);
  });
}
