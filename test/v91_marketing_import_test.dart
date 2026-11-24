// v91 — خطاهای واقعی ورود مشتری‌های بازاریابی از اکسل (گزارش کاربر: ۸۶۰ ردیف سالم، ۸۴ ردیف خطادار، هیچ‌چیز ثبت نشد).
// کشورهای بیرون از فهرست ۷۰تایی، منبع آزاد (نام نمایشگاه)، تلفن بیش از ۴۰ نویسه و نام تکراری در فایل.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/import_engine.dart';
import 'package:pesteh_bazar/marketing_calc.dart';

Uint8List _csv(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  final ImpKind k = kMkLeadImportKind;

  test('every country from the user report resolves (Persian, misspellings, English, ISO)', () {
    const Map<String, String> cases = <String, String>{
      'ارژانتین': 'AR', 'آرژانتین': 'AR', 'اسرائیل': 'IL', 'جمهوری چک': 'CZ', 'اسلوانی': 'SI', 'اسلوونی': 'SI', 'فلسطین': 'PS',
      'کلمبیا': 'CO', 'زیمباوه': 'ZW', 'زیمبابوه': 'ZW', 'دانمارک': 'DK', 'یمن': 'YE', 'امارات': 'AE', 'امارات متحده عربی': 'AE',
      'Argentina': 'AR', 'czech republic': 'CZ', 'UAE': 'AE', 'ae': 'AE', 'Türkiye': 'TR', 'کره جنوبی': 'KR', 'هنگ کنگ': 'HK',
      'هنگ‌کنگ': 'HK', 'عربستان سعودی': 'SA', 'كويت': 'KW', 'United Kingdom': 'GB', 'آمریکا': 'US', 'امریکا': 'US',
    };
    cases.forEach((String raw, String iso) => expect(mkCountryKey(raw), iso, reason: raw));
    expect(mkCountryKey('Atlantis'), isNull);
    expect(mkCountryKey(''), isNull);
    expect(mkCountryName('DK'), 'دانمارک'); // بیرون از فهرست پرکاربرد هم نام فارسی دارد
    expect(kMkCountryChoices.length, kMkCountryNames.length);
    expect(kMkCountryChoices.first.key, 'CN'); // پرکاربردها اول
  });

  test('free-text source: categorised, original text kept in source_detail', () {
    expect(mkSourceKey('Gulfood 2026'), 'expo');
    expect(mkSourceKey('نمایشگاه استانبول 2025'), 'expo');
    expect(mkSourceKey('نمایشگاه'), 'expo');
    expect(mkSourceKey('LinkedIn'), 'linkedin');
    expect(mkSourceKey('Alibaba.com'), 'b2b');
    expect(mkSourceKey('معرفی آقای احمدی'), 'referral');
    expect(mkSourceKey('اینستاگرام'), 'social');
    expect(mkSourceKey('سایت شرکت'), 'website');
    expect(mkSourceKey('چیز ناشناخته'), 'other');
    final ImpSheet s = ImportEngine.parse('l.csv', _csv('نام,منبع آشنایی\nA,Gulfood 2026\nB,نمایشگاه\nC,نمایشگاه استانبول 2025\n'));
    final List<ImpRow> rows = ImportEngine.validate(k, s, ImportEngine.autoMap(k, s.headers));
    expect(rows.every((ImpRow r) => r.ok), isTrue);
    expect(rows[0].values['source'], 'expo');
    expect(rows[0].values['source_detail'], 'Gulfood 2026');
    expect(rows[1].values.containsKey('source_detail'), isFalse); // برچسب دقیق ⇒ جزئیاتی لازم نیست
    expect(rows[2].values['source_detail'], 'نمایشگاه استانبول 2025');
  });

  test('phone up to 200 chars; duplicate company rows merge (phones and notes joined)', () {
    final String longPhone = List<String>.filled(5, '+971 50 123 4567').join(' / '); // ۸۸ نویسه
    final ImpSheet s = ImportEngine.parse(
        'l.csv',
        _csv('نام,تلفن,ایمیل,یادداشت,کشور\n'
            'Al Noor,"$longPhone",,اول,\n'
            'Kevin,+86 10 1111,,,\n'
            'al  noor,+971 4 999 0000,a@n.example,دوم,امارات\n'
            'AL NOOR,+971 4 999 0000,,,\n'));
    final List<ImpRow> rows = ImportEngine.validate(k, s, ImportEngine.autoMap(k, s.headers));
    expect(rows.every((ImpRow r) => r.ok), isTrue, reason: rows.map((ImpRow r) => r.errors).toString());
    expect(rows[2].mergedInto, 2);
    expect(rows[3].mergedInto, 2);
    expect(rows[0].values['phone'], '$longPhone / +971 4 999 0000'); // شمارهٔ تکراری دو بار نمی‌آید
    expect(rows[0].values['email'], 'a@n.example');
    expect(rows[0].values['note'], 'اول\nدوم');
    expect(rows[0].values['country'], 'AE');
    final List<dynamic> sent = ImportEngine.payload(k, rows, batchId: 'b', dryRun: true)['rows'] as List<dynamic>;
    expect(sent.length, 2); // ردیف‌های ادغام‌شده جدا فرستاده نمی‌شوند
  });

  test('good rows are sent even when other rows have errors (no all-or-nothing block)', () {
    final ImpSheet s = ImportEngine.parse('l.csv', _csv('نام,کشور,مرحله\nGood 1,دانمارک,\nBad,Atlantis,\nGood 2,یمن,فروش\nGood 3,فلسطین,مذاکره\n'));
    final List<ImpRow> rows = ImportEngine.validate(k, s, ImportEngine.autoMap(k, s.headers));
    expect(rows.where((ImpRow r) => !r.ok).length, 2); // کشور ناشناخته + مرحلهٔ «فروش»
    expect(rows[1].errors.single, contains('Atlantis'));
    final List<dynamic> sent = ImportEngine.payload(k, rows, batchId: 'b', dryRun: false, allOrNothing: false)['rows'] as List<dynamic>;
    expect(sent.map((dynamic r) => (r as Map)['name']), <String>['Good 1', 'Good 3']);
  });
}
