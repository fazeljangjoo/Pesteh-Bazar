import 'package:flutter/material.dart';

import 'perms.dart';

/// v87 — دسترسی بخش‌محور (فایل مشترک اندروید و ویندوز). آینهٔ backend/api/access_catalog.php (کاتالوگ سرور در roles.list.sections هم می‌آید).
///   بخش = گزینه‌ها (کلیدهای مجوز) + «نمایش قیمت در این بخش» + قسمت‌های فرم (نمایش / قفل / پنهان).
///   price.view = قیمت در همهٔ بخش‌ها (رفتار قدیمی)؛ price.<بخش> = فقط همان بخش.

class AccessOption {
  const AccessOption(this.key, this.label);
  final String key;
  final String label;
}

class AccessSection {
  const AccessSection({required this.key, required this.label, required this.price, required this.perms, required this.fields});
  final String key;
  final String label;
  final String? price;
  final List<AccessOption> perms;
  final List<AccessOption> fields;

  Set<String> get permKeys => <String>{for (final AccessOption o in perms) o.key};

  static AccessSection fromJson(Map<String, dynamic> j) => AccessSection(
        key: '${j['key']}',
        label: '${j['label']}',
        price: j['price'] as String?,
        perms: <AccessOption>[for (final dynamic o in (j['perms'] as List<dynamic>? ?? const <dynamic>[])) if (o is Map) AccessOption('${o['key']}', '${o['label']}')],
        fields: <AccessOption>[for (final dynamic o in (j['fields'] as List<dynamic>? ?? const <dynamic>[])) if (o is Map) AccessOption('${o['key']}', '${o['label']}')],
      );
}

/// آینهٔ PB_ACCESS_SECTIONS (اگر سرور قدیمی sections نفرستاد).
const List<AccessSection> kAccessSections = <AccessSection>[
  AccessSection(key: 'purchases', label: 'خرید', price: 'price.purchases', perms: <AccessOption>[
    AccessOption('purchases.view', 'مشاهدهٔ فهرست خرید'),
    AccessOption('purchases.create', 'ثبت و ویرایش خرید'),
    AccessOption('purchases.delete', 'حذف خرید'),
    AccessOption('purchases.return', 'برگشت از خرید'),
    AccessOption('payments.save', 'ثبت پرداخت به فروشنده'),
  ], fields: <AccessOption>[
    AccessOption('purchase.base', 'اطلاعات پایه (تاریخ، دسته، نوع، وزن، تعداد گونی/عدل، انبار)'), // v89
    AccessOption('purchase.quality', 'گرم، انس و مشخصات'),
    AccessOption('purchase.price', 'فی خرید، درجه‌بندی قیمت، بلوک مالی، مالیات و دلالی'),
    AccessOption('purchase.seller', 'فروشنده'),
    AccessOption('purchase.pct', 'درصدها و قیمت‌گذاری درصدها'),
    AccessOption('purchase.costs', 'هزینهٔ کارگر و حمل'),
    AccessOption('purchase.weigh', 'توزین (تارا، کسر کیفیت، قبض باسکول)'),
    AccessOption('purchase.photo', 'عکس'),
    AccessOption('purchase.note', 'توضیحات'),
  ]),
  AccessSection(key: 'sales', label: 'فروش', price: 'price.sales', perms: <AccessOption>[
    AccessOption('sales.view', 'مشاهدهٔ فهرست فروش'),
    AccessOption('sales.create', 'ثبت فروش'),
    AccessOption('sales.update', 'ویرایش فروش'),
    AccessOption('sales.delete', 'حذف فروش'),
    AccessOption('sales.return', 'برگشت از فروش'),
    AccessOption('pos.use', 'صندوق فروش (POS)'),
    AccessOption('receipts.save', 'ثبت دریافت از خریدار'),
  ], fields: <AccessOption>[
    AccessOption('sale.price', 'فی فروش، درجه‌بندی قیمت، مالیات، دلالی و دریافت'), // v89
    AccessOption('sale.buyer', 'خریدار'),
    AccessOption('sale.costs', 'هزینهٔ کارگر و حمل'),
    AccessOption('sale.fin', 'بلوک مالی (تخفیف، هزینهٔ باسکول)'),
    AccessOption('sale.note', 'توضیحات'),
  ]),
  AccessSection(key: 'stock', label: 'انبار و موجودی', price: 'price.stock', perms: <AccessOption>[
    AccessOption('stock.view', 'مشاهدهٔ موجودی انبار'),
    AccessOption('cartex.view', 'کارتکس لات'),
    AccessOption('stock.transfer', 'انتقال بین انبارها'),
    AccessOption('stock.count', 'انبارگردانی'),
    AccessOption('warehouses.view', 'مشاهدهٔ انبارها'),
    AccessOption('warehouses.manage', 'تعریف و ویرایش انبارها'),
    AccessOption('catalog.manage', 'دسته‌ها و انواع پسته'),
  ], fields: <AccessOption>[]),
  AccessSection(key: 'mixing', label: 'کوت‌ریزی و تفکیک', price: 'price.mixing', perms: <AccessOption>[
    AccessOption('mixes.create', 'ثبت کوت‌ریزی'),
    AccessOption('mixes.update', 'ویرایش کوت‌ریزی'),
    AccessOption('mixes.delete', 'حذف کوت‌ریزی'),
    AccessOption('separations.create', 'ثبت تفکیک'),
    AccessOption('separations.update', 'ویرایش تفکیک'),
    AccessOption('separations.delete', 'حذف تفکیک'),
  ], fields: <AccessOption>[AccessOption('mix.note', 'توضیحات کوت')]),
  AccessSection(key: 'consign', label: 'امانی (کالای دیگران)', price: 'price.consign', perms: <AccessOption>[
    AccessOption('consignments.create', 'ثبت امانی'),
    AccessOption('consignments.manage', 'مدیریت، برگشت و تسویهٔ امانی'),
  ], fields: <AccessOption>[]),
  AccessSection(key: 'processing', label: 'فراوری (برون‌سپاری و امانی)', price: 'price.processing', perms: <AccessOption>[
    AccessOption('processing.create', 'ثبت سفارش فراوری'),
    AccessOption('processing.manage', 'دریافت خروجی، تحویل، ویرایش و حذف'),
  ], fields: <AccessOption>[
    AccessOption('proc.fee', 'اجرت و هزینه‌ها'),
    AccessOption('proc.receipt', 'قبض فراوری‌کننده'),
    AccessOption('proc.shifts', 'شیفت‌های شکست امانی'),
    AccessOption('proc.chain', 'ارسال به تولید (سورت)'),
  ]),
  AccessSection(key: 'workshop', label: 'کارگاه داخلی', price: 'price.workshop', perms: <AccessOption>[
    AccessOption('workshop.view', 'مشاهدهٔ عملیات کارگاه'),
    AccessOption('workshop.operate', 'شروع عملیات و ثبت ورودی و خروجی'),
    AccessOption('workshop.manage', 'بستن، بازکردن و حذف عملیات'),
    AccessOption('workshop.crack', 'گزارش خط شکست'),
    AccessOption('workshop.feed', 'موجودی پستهٔ خرجی'),
    AccessOption('workshop.cost', 'بهای تمام‌شدهٔ کارگاه'),
  ], fields: <AccessOption>[
    AccessOption('ws.shifts', 'شیفت‌های شکست'),
    AccessOption('ws.chain', 'ارسال به تولید (سورت)'),
    AccessOption('ws.costs', 'ثبت هزینه (اجرت، هزینهٔ شکست)'),
  ]),
  AccessSection(key: 'ounce', label: 'اتاق انس', price: 'intake.price', perms: <AccessOption>[
    AccessOption('ounces.view', 'مشاهدهٔ درجه‌بندی انس'), // v89: پذیرش اتاق انس غیرفعال (اتاق انس روی خود خرید کار می‌کند)
    AccessOption('ounces.manage', 'تعریف درجه‌بندی انس'),
  ], fields: <AccessOption>[]),
  AccessSection(key: 'parties', label: 'طرف‌حساب‌ها و پیگیری', price: 'price.parties', perms: <AccessOption>[
    AccessOption('parties.view', 'مشاهدهٔ طرف‌حساب‌ها'),
    AccessOption('parties.create', 'ثبت و ویرایش طرف‌حساب'),
    AccessOption('crm.view', 'مشاهدهٔ پیگیری مشتریان'),
    AccessOption('crm.edit', 'ثبت یادداشت و پیگیری'),
    AccessOption('dues.view', 'سررسیدها و چک‌ها'),
    AccessOption('dues.mark_paid', 'تسویهٔ سررسید و وضعیت چک'),
  ], fields: <AccessOption>[]),
  AccessSection(key: 'finance', label: 'مالی و حسابداری', price: 'price.finance', perms: <AccessOption>[
    AccessOption('loans.create', 'ثبت وام و قرض'),
    AccessOption('loans.delete', 'ویرایش و حذف وام'),
    AccessOption('loans.due_paid', 'بازپرداخت وام'),
    AccessOption('accounting.view', 'مشاهدهٔ حسابداری'),
    AccessOption('accounting.post', 'ثبت سند'),
    AccessOption('accounting.edit', 'ویرایش سند'),
    AccessOption('accounting.close', 'بستن سال و اسناد'),
    AccessOption('accounting.fx_reval.apply', 'اعمال تسعیر ارز'),
    AccessOption('accounting.fx_reval.reverse', 'ابطال تسعیر ارز'),
    AccessOption('fy.manage', 'سال‌های مالی'),
    AccessOption('tax.view', 'گزارش‌های مالیاتی'),
  ], fields: <AccessOption>[]),
  AccessSection(key: 'payroll', label: 'حقوق و دستمزد', price: 'price.payroll', perms: <AccessOption>[
    AccessOption('payroll.view', 'مشاهده'),
    AccessOption('payroll.manage', 'ثبت و مدیریت'),
  ], fields: <AccessOption>[]),
  AccessSection(key: 'orchards', label: 'باغ‌ها', price: 'price.orchards', perms: <AccessOption>[
    AccessOption('orchards.view', 'مشاهده'),
    AccessOption('orchards.manage', 'ثبت و مدیریت'),
  ], fields: <AccessOption>[]),
  AccessSection(key: 'reports', label: 'گزارش‌ها', price: 'price.reports', perms: <AccessOption>[
    AccessOption('reports.view', 'گزارش‌ها'),
    AccessOption('profit.view', 'سود و زیان'),
    AccessOption('audit.view', 'گزارش ممیزی'),
  ], fields: <AccessOption>[]),
  AccessSection(key: 'marketing', label: 'بازاریابی بین‌المللی', price: null, perms: <AccessOption>[ // v90
    AccessOption('marketing.entry', 'ثبت مشتری، پیگیری و فروش خود'),
    AccessOption('marketing.manage', 'مدیریت همهٔ مشتری‌ها، سپردن، تأیید فروش، هدف‌ها و امتیاز'),
    AccessOption('marketing.reports', 'دیدن گزارش‌ها و داشبورد همهٔ بازاریاب‌ها'),
  ], fields: <AccessOption>[]),
  AccessSection(key: 'admin', label: 'مدیریت', price: null, perms: <AccessOption>[
    AccessOption('settings.manage', 'تنظیمات'),
    AccessOption('users.manage', 'کارکنان، نقش‌ها و دسترسی‌ها'),
  ], fields: <AccessOption>[]),
];

AccessSection? accessSectionOf(String key, [List<AccessSection> sections = kAccessSections]) {
  for (final AccessSection s in sections) {
    if (s.key == key) return s;
  }
  return null;
}

/// حالت قسمت فرم: show | lock | hide.
const List<String> kFieldModes = <String>['show', 'lock', 'hide'];
const Map<String, String> kFieldModeLabels = <String, String>{'show': 'نمایش', 'lock': 'قفل', 'hide': 'پنهان'};

/// آینهٔ pb_field_rules_merge (v89 «فقط آنچه باز شده»): هر نقش فقط قسمت‌های باز (show/lock)؛ بازترین حالت بین نقش‌ها؛ نبودِ کلید = پنهان.
Map<String, String> accessMergeFields(List<Map<String, String>> lists) {
  final Map<String, String> o = <String, String>{};
  for (final Map<String, String> l in lists) {
    l.forEach((String k, String v) {
      if (v != 'show' && v != 'lock') return;
      if (!o.containsKey(k) || v == 'show') o[k] = v;
    });
  }
  return o;
}

/// آینهٔ pb_access_effective: اجتماع مجوز نقش‌ها + اضافه − کم‌شده؛ قسمت‌ها: ادغام نقش‌ها و سپس قاعدهٔ کارکن (hide = بستن؛ خروجی فقط show/lock).
({Set<String> perms, Map<String, String> fields}) accessEffective(
    List<Set<String>> rolePerms, List<Map<String, String>> roleFields, Set<String> grants, Set<String> denies, Map<String, String> userFields) {
  final Set<String> p = <String>{for (final Set<String> l in rolePerms) ...l, ...grants}..removeAll(denies);
  final Map<String, String> f = accessMergeFields(roleFields);
  userFields.forEach((String k, String v) {
    if (v == 'hide') {
      f.remove(k);
    } else {
      f[k] = v;
    }
  });
  return (perms: p, fields: f);
}

/// v87: قسمت فرمی که برای کارکن قفل یا پنهان است (مالک ⇒ همیشه نمایش). hide ⇒ چیزی نمایش داده نمی‌شود؛ lock ⇒ دیده می‌شود ولی قابل تغییر نیست.
class FieldGate extends StatelessWidget {
  const FieldGate({super.key, required this.field, required this.child, this.lockedNote = true});
  final String field;
  final Widget child;
  final bool lockedNote;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: StaffPerms.I.current,
      builder: (BuildContext c, Map<String, dynamic>? _, Widget? __) {
        final String m = StaffPerms.I.fieldMode(field);
        if (m == 'hide') return const SizedBox.shrink();
        if (m == 'lock') {
          return Stack(children: <Widget>[
            AbsorbPointer(child: Opacity(opacity: 0.55, child: child)),
            if (lockedNote)
              PositionedDirectional(
                top: 2,
                end: 2,
                child: Tooltip(message: 'این قسمت برای شما قفل است', child: Icon(Icons.lock_outline, size: 16, color: Theme.of(context).hintColor)),
              ),
          ]);
        }
        return child;
      },
    );
  }
}
