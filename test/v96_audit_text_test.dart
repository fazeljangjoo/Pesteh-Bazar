// v96: گزارش ممیزی به فارسیِ ساده (چه کسی، با چه نقشی، کی، چه کرد) — بدون کلید خام، شناسه یا JSON.
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/audit_text.dart';

Map<String, dynamic> row(String action, String entity, String summary, {int staffId = 3, String name = 'علی', String? role = 'بازاریاب', Object? before, Object? after}) =>
    <String, dynamic>{
      'id': 77,
      'staff_id': staffId,
      'staff_name': name,
      if (role != null) 'staff_role': role,
      'action': action,
      'entity': entity,
      'entity_id': 'a1b2c3d4-uid',
      'summary': summary,
      'before': before,
      'after': after,
      'ip': '1.2.3.4',
      'created_at': '2026-11-28 14:35:10',
    };

/// متن خروجی نباید هیچ چیز فنی داشته باشد.
void expectPlain(String s) {
  expect(s, isNot(contains('uid')));
  expect(s, isNot(contains('{')));
  expect(s, isNot(contains('_')));
  expect(s, isNot(matches(RegExp(r'\b[a-z]+\.[a-z_]+\b')))); // import.commit, voucher.status, …
  expect(s, isNot(matches(RegExp(r'[0-9]')))); // ارقام لاتین (کدهای لات جداگانه بررسی می‌شوند)
}

void main() {
  test('خط کامل: تاریخ شمسی، ساعت، نام و نقش، جملهٔ فارسی', () {
    final r = row('import.commit', 'import', 'ایمپورت mk_leads: 12 جدید، 0 ویرایش، 0 ردشده');
    expect(auditLine(r), '۱۴۰۵/۰۹/۰۷ ساعت ۱۴:۳۵ — علی (بازاریاب): ۱۲ مشتری بازاریابی از اکسل وارد کرد');
  });

  test('مالک و کارمند بدون نقش (سرور قدیمی) با نقش از فهرست کاربران', () {
    final owner = row('create', 'sale', 'ثبت فروش', staffId: 0, name: '', role: null);
    expect(auditWho(owner), 'مالک');
    expect(auditLine(owner), '۱۴۰۵/۰۹/۰۷ ساعت ۱۴:۳۵ — مالک: فروش را ثبت کرد');
    final old = row('delete', 'purchase', 'حذف خرید', role: null);
    expect(auditWho(old), 'علی');
    expect(auditWho(old, roleOf: (int id) => id == 3 ? 'انباردار' : ''), 'علی (انباردار)');
  });

  test('همهٔ کلیدهای شناخته‌شده جملهٔ فارسی بی‌متن فنی می‌دهند', () {
    final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
      row('update', 'stock_count', 'ارسال انبارگردانی برای تأیید'),
      row('create', 'purchase', 'ثبت خرید'),
      row('update', 'payment', 'ثبت/ویرایش پرداخت'),
      row('voucher.status', 'voucher', 'تغییر وضعیت سند draft → final'),
      row('voucher.unpost', 'voucher', 'حذف سند خودکار sale#12'),
      row('voucher.copy', 'voucher', 'رونوشت از سند 45'),
      row('fx.adjust', 'sale', 'تعدیل نرخ USD: 500000 ← 520000 (اختلاف 2000000 ریال)'),
      row('fx.reval', 'fx_reval', 'تسعیر ارز تا 2026-11-20 — پایان ماه'),
      row('fx.reval_auto_revers', 'fx_reval', 'برگشت خودکار تسعیر ارز #7'),
      row('fy.open_next', 'fiscal_year', 'سند افتتاحیه 1405 از 1404'),
      row('tafsili.save', 'tafsili', 'ثبت/ویرایش تفصیلی بانک ملت'),
      row('create', 'api_keys', 'ساخت کلید API: حسابدار'),
      row('create', 'entity.warehouses', ''),
      row('delete', 'entity.mk_leads', ''),
      row('update', 'entity.unknown_table', ''),
      row('tier.upgrade_rollbac', 'upgrade_run', ''),
      row('weird.new_key', 'weird_entity', ''),
      row('', '', ''),
    ];
    for (final r in rows) {
      final String line = auditLine(r);
      expectPlain(line);
      expect(line, startsWith('۱۴۰۵/۰۹/۰۷ ساعت ۱۴:۳۵ — علی (بازاریاب): '));
    }
  });

  test('جمله‌های مشخص', () {
    expect(auditWhat(row('voucher.status', 'voucher', 'تغییر وضعیت سند draft → final')), 'وضعیت سند حسابداری را از «پیش‌نویس» به «قطعی» تغییر داد');
    expect(auditWhat(row('voucher.unpost', 'voucher', 'حذف سند خودکار sale#12')), 'سند حسابداری خودکارِ فروش شمارهٔ ۱۲ را حذف کرد');
    expect(auditWhat(row('fx.adjust', 'sale', 'تعدیل نرخ USD: 500000 ← 520000 (اختلاف 2000000 ریال)')),
        'نرخ دلار را از ۵۰۰٬۰۰۰ به ۵۲۰٬۰۰۰ ریال اصلاح کرد (اختلاف ۲٬۰۰۰٬۰۰۰ ریال)');
    expect(auditWhat(row('create', 'entity.warehouses', '')), 'یک انبار جدید ثبت کرد');
    expect(auditWhat(row('update', 'entity.unknown_table', '')), 'یک مورد را ویرایش کرد');
    expect(auditWhat(row('weird.new_key', 'weird_entity', '')), 'یک تغییر در برنامه ثبت کرد');
    expect(auditWhat(row('import.commit', 'import', 'ایمپورت parties: 0 جدید، 3 ویرایش، 1 ردشده')), '۳ طرف حساب را از اکسل به‌روز کرد، ۱ ردیف کنار گذاشته شد');
  });

  test('کد لات لاتین می‌ماند و دلیل رد خوانا است', () {
    final String s = auditWhat(row('update', 'intake', 'رد قطعی پذیرش اتاق انس (KH-12): رطوبت بالا'));
    expect(s, 'پذیرش اتاق انس (KH-12) را به‌طور قطعی رد کرد؛ دلیل: رطوبت بالا');
  });

  test('تاریخ و ساعت', () {
    expect(auditWhen('2026-03-21 08:05:00'), '۱۴۰۵/۰۱/۰۱ ساعت ۰۸:۰۵');
    expect(auditDate('2026-03-21 08:05:00'), '۱۴۰۵/۰۱/۰۱');
    expect(auditTime('2026-03-21 08:05:00'), '۰۸:۰۵');
  });

  test('تغییرات: فقط فیلدهای شناخته‌شده، بدون شناسه و JSON', () {
    final List<AuditChange> c = auditChanges(row('update', 'sale', 'ویرایش فروش',
        before: '{"id":5,"uid":"x-1","customer_id":9,"weight":"100.5","date":"2026-11-20","status":"draft","note":"a"}',
        after: '{"id":5,"uid":"x-1","customer_id":9,"weight":"120","date":"2026-11-20","status":"final","note":"a"}'));
    expect(c.map((AuditChange e) => e.label), <String>['وزن', 'وضعیت']);
    expect(c.first.before, '۱۰۰٫۵');
    expect(c.first.after, '۱۲۰');
    expect(c[1].after, 'قطعی');
    expect(auditChanges(row('update', 'sale', 'x', before: '{"a":1…', after: null)), isEmpty);
  });
}
