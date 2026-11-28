import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import 'db.dart';

/// Bump when [kEntityRegistry] changes in a way the server must know about (informational; the server
/// stays the authority: only entities it exports/lists are shown, see [EntityStore.visibleNames]).
const int kEntityRegistryVersion = 7; // v94: mix_processes (کوت در جریان، همگام بین دستگاه‌ها) // v92: settlements (شناسنامهٔ پرداخت/وصول) + xch_moves.links // v91 p5: xch_moves (صراف) // v90: mk_* (بازاریابی بین‌المللی) // S5.T1: lot_intakes / lot_intake_pcts / pct_defs (اتاق انس)؛ v79: crack_lines

/// One field of an entity (mirrors a column spec of `server/backend/api/entities.php`).
/// type: string | text | int | bigint | decimal | bool | date | datetime | enum | ref | json
class EntityField {
  final String key;
  final String label;
  final String type;
  final bool required;
  final int? max;
  final num? vmin;
  final num? vmax;
  final int scale;
  final List<String> values;
  final Map<String, String> valueLabels;
  final String? ref;
  final Object? defaultValue;

  /// UI hint only: format with thousands separators (stored as plain integer, unit = toman).
  final bool money;

  /// UI hint only: a string field that holds a party name (autocomplete from existing parties).
  final bool party;

  const EntityField(
    this.key,
    this.label,
    this.type, {
    this.required = false,
    this.max,
    this.vmin,
    this.vmax,
    this.scale = 4,
    this.values = const <String>[],
    this.valueLabels = const <String, String>{},
    this.ref,
    this.defaultValue,
    this.money = false,
    this.party = false,
  });

  bool get isNumeric => type == 'int' || type == 'bigint' || type == 'decimal';
  bool get isLong => type == 'text';
}

class EntitySpec {
  final String name;
  final String label;
  final List<EntityField> fields;
  final List<String> search;

  /// column used for ordering in lists ('' = newest first)
  final String orderCol;
  final bool orderDesc;

  /// permission keys (client hides only; the server enforces)
  final String? permCreate;
  final String? permEdit;
  final String? permDelete;

  /// fields shown in the list tile: first = title, second = subtitle, rest = trailing text
  final List<String> listFields;

  const EntitySpec(
    this.name,
    this.label,
    this.fields, {
    this.search = const <String>[],
    this.orderCol = '',
    this.orderDesc = true,
    this.permCreate,
    this.permEdit,
    this.permDelete,
    this.listFields = const <String>[],
  });

  EntityField? field(String key) {
    for (final f in fields) {
      if (f.key == key) return f;
    }
    return null;
  }
}

/// Bundled static registry (same names/types as the server registry). Later stages append entries.
/// Never rename/remove a released entry or field.
const Map<String, EntitySpec> kEntityRegistry = <String, EntitySpec>{
  // کارگاه داخلی — خطوط شکست (mirror of server `crack_lines`): نام خط + گرم پرتی؛ در شروع عملیات «شکست» انتخاب می‌شود.
  'crack_lines': EntitySpec(
    'crack_lines',
    'خط شکست',
    <EntityField>[
      EntityField('name', 'نام خط', 'string', required: true, max: 100),
      EntityField('loss_gram', 'گرم پرتی', 'decimal', required: true, vmin: 0, vmax: 1000, scale: 2),
      EntityField('active', 'فعال', 'bool', defaultValue: true),
    ],
    search: <String>['name'],
    listFields: <String>['name', 'loss_gram'],
    orderCol: 'name',
    orderDesc: false,
    permCreate: 'workshop.manage',
    permEdit: 'workshop.manage',
    permDelete: 'workshop.manage',
  ),
  // S01.T01.1 (mirror of server `warehouses`)
  'warehouses': EntitySpec(
    'warehouses',
    'انبار',
    <EntityField>[
      EntityField('name', 'نام انبار', 'string', required: true, max: 100),
      EntityField('type', 'نوع', 'enum',
          values: <String>['main', 'consignment', 'processing', 'virtual'],
          valueLabels: <String, String>{
            'main': 'اصلی',
            'consignment': 'امانی',
            'processing': 'فراوری',
            'virtual': 'مجازی'
          },
          defaultValue: 'main'),
      EntityField('active', 'فعال', 'bool', defaultValue: true),
      EntityField('address', 'نشانی', 'string', max: 250),
      EntityField('is_default', 'پیش‌فرض', 'bool', defaultValue: false),
    ],
    search: <String>['name', 'address'],
    listFields: <String>['name', 'address'],
    permCreate: 'warehouses.manage',
    permEdit: 'warehouses.manage',
    permDelete: 'warehouses.manage',
  ),
  // S01.T01.1 (mirror of server `ounces`)
  'ounces': EntitySpec(
    'ounces',
    'درجه‌بندی اونس',
    <EntityField>[
      EntityField('code', 'کد', 'string', required: true, max: 40),
      EntityField('from_val', 'از', 'decimal', scale: 3, vmin: 0),
      EntityField('to_val', 'تا', 'decimal', scale: 3, vmin: 0),
      EntityField('note', 'توضیح', 'string', max: 250),
    ],
    search: <String>['code', 'note'],
    listFields: <String>['code', 'note'],
    permCreate: 'ounces.manage',
    permEdit: 'ounces.manage',
    permDelete: 'ounces.manage',
  ),
  // S03.T03.3/T03.4 (mirror of server `crm_notes` / `crm_tasks`)
  'crm_notes': EntitySpec(
    'crm_notes',
    'یادداشت ارتباط با طرف‌حساب',
    <EntityField>[
      EntityField('party', 'طرف‌حساب', 'string', required: true, max: 150, party: true),
      EntityField('kind', 'نوع', 'enum',
          values: <String>['call', 'visit', 'message', 'other'],
          valueLabels: <String, String>{'call': 'تماس', 'visit': 'بازدید', 'message': 'پیام', 'other': 'سایر'},
          defaultValue: 'other'),
      EntityField('text', 'متن', 'text', required: true, max: 5000),
      EntityField('date', 'تاریخ', 'date'),
    ],
    search: <String>['party', 'text'],
    listFields: <String>['party', 'text'],
    permCreate: 'crm.edit',
    permEdit: 'crm.edit',
    permDelete: 'crm.edit',
  ),
  'crm_tasks': EntitySpec(
    'crm_tasks',
    'پیگیری طرف‌حساب',
    <EntityField>[
      EntityField('party', 'طرف‌حساب', 'string', required: true, max: 150, party: true),
      EntityField('due_at', 'موعد پیگیری', 'datetime'),
      EntityField('text', 'شرح', 'string', required: true, max: 500),
      EntityField('done', 'انجام شد', 'bool', defaultValue: false),
      EntityField('assignee_staff', 'مسئول', 'string', max: 100),
    ],
    search: <String>['party', 'text'],
    listFields: <String>['party', 'text'],
    permCreate: 'crm.edit',
    permEdit: 'crm.edit',
    permDelete: 'crm.edit',
  ),
  // S12.T12.1 (mirror of server `company_profile` / `doc_sequences`)
  'company_profile': EntitySpec(
    'company_profile',
    'مشخصات شرکت',
    <EntityField>[
      EntityField('name', 'نام شرکت', 'string', required: true, max: 150),
      EntityField('logo', 'لوگو', 'text', max: 120000),
      EntityField('address', 'نشانی', 'string', max: 300),
      EntityField('phones', 'تلفن‌ها', 'string', max: 150),
      EntityField('economic_code', 'کد اقتصادی', 'string', max: 30),
      EntityField('national_id', 'شناسه ملی', 'string', max: 30),
      EntityField('postal_code', 'کد پستی', 'string', max: 20),
      EntityField('registration_no', 'شمارهٔ ثبت', 'string', max: 30),
      EntityField('footer_text', 'متن پای فاکتور', 'string', max: 300),
    ],
    search: <String>['name'],
    listFields: <String>['name', 'address'],
    permCreate: 'settings.manage',
    permEdit: 'settings.manage',
    permDelete: 'settings.manage',
  ),
  // S15.T15.3/T15.5 gold entities (mirror of server treasury.php; visible only to gold accounts)
  'cost_centers': EntitySpec(
    'cost_centers',
    'مراکز هزینه',
    <EntityField>[
      EntityField('code', 'کد', 'string', required: true, max: 20),
      EntityField('name', 'نام', 'string', required: true, max: 120),
      EntityField('parent', 'والد', 'ref', ref: 'cost_centers'),
      EntityField('active', 'فعال', 'bool', defaultValue: true),
    ],
    search: <String>['code', 'name'],
    orderCol: 'code',
    orderDesc: false,
    listFields: <String>['code', 'name'],
    permCreate: 'settings.manage',
    permEdit: 'settings.manage',
    permDelete: 'settings.manage',
  ),
  'cash_boxes': EntitySpec(
    'cash_boxes',
    'صندوق‌ها',
    <EntityField>[
      EntityField('name', 'نام صندوق', 'string', required: true, max: 100),
      EntityField('active', 'فعال', 'bool', defaultValue: true),
      EntityField('note', 'توضیح', 'string', max: 250),
    ],
    search: <String>['name'],
    listFields: <String>['name', 'note'],
    permCreate: 'settings.manage',
    permEdit: 'settings.manage',
    permDelete: 'settings.manage',
  ),
  'bank_accounts': EntitySpec(
    'bank_accounts',
    'حساب‌های بانکی',
    <EntityField>[
      EntityField('name', 'عنوان حساب', 'string', required: true, max: 100),
      EntityField('bank_name', 'بانک', 'string', max: 100),
      EntityField('branch', 'شعبه', 'string', max: 100),
      EntityField('account_no', 'شمارهٔ حساب', 'string', max: 40),
      EntityField('iban', 'شبا', 'string', max: 34),
      EntityField('ccy', 'ارز', 'string', max: 8, defaultValue: 'IRR'),
      EntityField('opening_balance', 'مانده اول دوره', 'bigint', money: true, defaultValue: 0),
      EntityField('active', 'فعال', 'bool', defaultValue: true),
    ],
    search: <String>['name', 'bank_name', 'account_no', 'iban'],
    listFields: <String>['name', 'bank_name', 'account_no'],
    permCreate: 'settings.manage',
    permEdit: 'settings.manage',
    permDelete: 'settings.manage',
  ),
  'expenses': EntitySpec(
    'expenses',
    'هزینه‌های عمومی',
    <EntityField>[
      EntityField('date', 'تاریخ', 'date', required: true),
      EntityField('amount', 'مبلغ', 'bigint', required: true, vmin: 1, money: true),
      EntityField('category', 'دسته', 'string', max: 100),
      EntityField('account_code', 'کد حساب هزینه', 'string', max: 20),
      EntityField('cost_center', 'مرکز هزینه', 'ref', ref: 'cost_centers'),
      EntityField('payer', 'پرداخت از', 'enum',
          values: <String>['cash', 'bank', 'credit'],
          valueLabels: <String, String>{'cash': 'صندوق', 'bank': 'بانک', 'credit': 'نسیه'},
          defaultValue: 'cash'),
      EntityField('cash_box', 'صندوق', 'ref', ref: 'cash_boxes'),
      EntityField('bank_account', 'حساب بانکی', 'ref', ref: 'bank_accounts'),
      EntityField('party', 'طرف‌حساب', 'string', max: 150),
      EntityField('note', 'توضیح', 'string', max: 500),
    ],
    search: <String>['category', 'party', 'note'],
    listFields: <String>['date', 'category', 'amount'],
    permCreate: 'accounting.post',
    permEdit: 'accounting.post',
    permDelete: 'accounting.post',
  ),
  'owner_draws': EntitySpec(
    'owner_draws',
    'برداشت/آورده صاحب سرمایه',
    <EntityField>[
      EntityField('date', 'تاریخ', 'date', required: true),
      EntityField('amount', 'مبلغ', 'bigint', required: true, vmin: 1, money: true),
      EntityField('kind', 'نوع', 'enum',
          values: <String>['draw', 'contribution'],
          valueLabels: <String, String>{'draw': 'برداشت', 'contribution': 'آورده'},
          defaultValue: 'draw'),
      EntityField('payer', 'از/به', 'enum',
          values: <String>['cash', 'bank'],
          valueLabels: <String, String>{'cash': 'صندوق', 'bank': 'بانک'},
          defaultValue: 'cash'),
      EntityField('cash_box', 'صندوق', 'ref', ref: 'cash_boxes'),
      EntityField('bank_account', 'حساب بانکی', 'ref', ref: 'bank_accounts'),
      EntityField('note', 'توضیح', 'string', max: 500),
    ],
    search: <String>['note'],
    listFields: <String>['date', 'kind', 'amount'],
    permCreate: 'accounting.post',
    permEdit: 'accounting.post',
    permDelete: 'accounting.post',
  ),
  // v91 p5 — صراف: حرکت‌های صراف (آینهٔ موجودیت سرور `xch_moves`؛ صفحهٔ خودش در xch_ui.dart). مبالغ به ارز خودشان (IRR = ریال)؛ هیچ‌کدام ×۱۰ نمی‌شود.
  'xch_moves': EntitySpec(
    'xch_moves',
    'حرکت صراف',
    <EntityField>[
      EntityField('date', 'تاریخ', 'date', required: true),
      EntityField('kind', 'نوع', 'enum', required: true, values: <String>['cust_paid', 'paid_seller', 'xch_paid_us', 'we_paid_xch'], valueLabels: <String, String>{
        'cust_paid': 'مشتری به صراف پرداخت کرد',
        'paid_seller': 'صراف به فروشنده پرداخت کرد',
        'xch_paid_us': 'صراف به ما پرداخت کرد',
        'we_paid_xch': 'ما به صراف پرداخت کردیم',
      }),
      EntityField('exchanger', 'صراف', 'string', required: true, max: 150, party: true),
      EntityField('party', 'طرف‌حساب', 'string', max: 150, party: true),
      EntityField('doc_type', 'نوع فاکتور', 'enum', values: <String>['sale', 'purchase']),
      EntityField('doc_id', 'شمارهٔ فاکتور', 'bigint', vmin: 1),
      EntityField('ccy', 'ارز', 'string', required: true, max: 8),
      EntityField('amount_ccy', 'مبلغ ارزی', 'decimal', vmin: 0, scale: 4),
      EntityField('doc_rate', 'نرخ فاکتور', 'decimal', vmin: 0, scale: 6),
      EntityField('pay_ccy', 'ارز پرداخت', 'string', max: 8),
      EntityField('pay_amount', 'مبلغ پرداخت', 'decimal', vmin: 0, scale: 4),
      EntityField('pay_rate', 'نرخ ریالی پرداخت', 'decimal', vmin: 0, scale: 6),
      EntityField('cash_box', 'صندوق', 'ref', ref: 'cash_boxes'),
      EntityField('bank_account', 'حساب بانکی', 'ref', ref: 'bank_accounts'),
      EntityField('note', 'توضیح', 'string', max: 500),
      EntityField('links', 'پیوند به واریزها', 'json', max: 20000), // v92: [{lot, amt}] لات‌هایی که اول بسته می‌شوند
    ],
    search: <String>['exchanger', 'party', 'note'],
    listFields: <String>['date', 'exchanger', 'amount_ccy'],
    orderCol: 'date',
    permCreate: 'receipts.save',
    permEdit: 'receipts.save',
    permDelete: 'receipts.save',
  ),
  // v94 — «کوت در جریان» (آینهٔ موجودیت سرور `mix_processes`؛ صفحه‌اش همان فرم کوت‌ریزی). data = دادهٔ فرم.
  'mix_processes': EntitySpec(
    'mix_processes',
    'کوت در جریان',
    <EntityField>[
      EntityField('pkey', 'کلید', 'string', required: true, max: 60),
      EntityField('title', 'عنوان', 'string', max: 200),
      EntityField('data', 'داده', 'json', required: true, max: 500000),
    ],
    search: <String>['title'],
    listFields: <String>['title'],
    permCreate: 'mixes.create',
    permEdit: 'mixes.create',
    permDelete: 'mixes.create',
  ),
  // v92 — شناسنامهٔ پرداخت/وصول (آینهٔ موجودیت سرور `settlements`؛ صفحهٔ خودش در settle_ui.dart). مبالغ به ارز خودشان (IRR = ریال)؛ هیچ‌کدام ×۱۰ نمی‌شود.
  'settlements': EntitySpec(
    'settlements',
    'شناسنامهٔ پرداخت/وصول',
    <EntityField>[
      EntityField('date', 'تاریخ', 'date', required: true),
      EntityField('dir', 'جهت', 'enum', required: true, values: <String>['recv', 'pay'], valueLabels: <String, String>{'recv': 'وصول', 'pay': 'پرداخت'}),
      EntityField('party', 'طرف‌حساب', 'string', required: true, max: 150, party: true),
      EntityField('ccy', 'ارز', 'string', required: true, max: 8),
      EntityField('amount_ccy', 'مبلغ', 'decimal', vmin: 0, scale: 4),
      EntityField('alloc_mode', 'روش تخصیص', 'enum', values: <String>['fifo', 'manual'], defaultValue: 'fifo'),
      EntityField('alloc', 'تخصیص', 'json', max: 60000),
      EntityField('legs', 'مراحل', 'json', required: true, max: 60000),
      EntityField('ref_no', 'شماره', 'string', max: 20),
      EntityField('note', 'توضیح', 'string', max: 500),
    ],
    search: <String>['party', 'ref_no', 'note'],
    listFields: <String>['date', 'party', 'amount_ccy'],
    orderCol: 'date',
    permCreate: 'receipts.save',
    permEdit: 'receipts.save',
    permDelete: 'receipts.save',
  ),
  'doc_sequences': EntitySpec(
    'doc_sequences',
    'شمارندهٔ اسناد',
    <EntityField>[
      EntityField('doc_type', 'نوع سند', 'string', required: true, max: 20),
      EntityField('fy', 'سال مالی', 'int', vmin: 0, vmax: 9999, defaultValue: 0),
      EntityField('prefix', 'پیشوند', 'string', max: 12),
      EntityField('next_no', 'شمارهٔ بعدی', 'int', vmin: 1, defaultValue: 1),
      EntityField('padding', 'تعداد ارقام', 'int', vmin: 0, vmax: 12, defaultValue: 5),
    ],
    search: <String>['doc_type', 'prefix'],
    listFields: <String>['doc_type', 'prefix'],
    permDelete: 'settings.manage',
  ),
  'dev_notes': EntitySpec(
    'dev_notes',
    'یادداشت آزمایشی',
    <EntityField>[
      EntityField('title', 'عنوان', 'string', required: true, max: 120),
      EntityField('body', 'متن', 'text', max: 5000),
      EntityField('kind', 'نوع', 'enum',
          values: <String>['note', 'todo'],
          valueLabels: <String, String>{'note': 'یادداشت', 'todo': 'کار'},
          defaultValue: 'note'),
      EntityField('done', 'انجام شد', 'bool', defaultValue: false),
      EntityField('due', 'سررسید', 'date'),
      EntityField('amount', 'مبلغ', 'bigint', vmin: 0, money: true),
    ],
    search: <String>['title', 'body'],
    listFields: <String>['title', 'body', 'amount'],
    permCreate: 'dev_notes.create',
    permEdit: 'dev_notes.edit',
    permDelete: 'dev_notes.delete',
  ),
  // S5.T1 (mirror of server `lot_intakes`; فیلدهای server-only مثل status/code فقط نمایش‌اند)
  'lot_intakes': EntitySpec(
    'lot_intakes',
    'پذیرش اتاق انس',
    <EntityField>[
      EntityField('category_id', 'دسته', 'int', vmin: 1),
      EntityField('type_name', 'نوع', 'string', max: 120),
      EntityField('gross_kg', 'وزن کل (کیلو)', 'decimal', scale: 3, vmin: 0, vmax: 100000000),
      EntityField('small_sacks', 'گونی کوچک', 'int', vmin: 0, vmax: 1000000, defaultValue: 0),
      EntityField('large_sacks', 'گونی بزرگ', 'int', vmin: 0, vmax: 1000000, defaultValue: 0),
      EntityField('ounce', 'انس', 'decimal', scale: 3, vmin: 0, vmax: 100000),
      EntityField('gram', 'گرم', 'decimal', scale: 3, vmin: 0, vmax: 100),
      EntityField('owner_name', 'نام صاحب پسته', 'string', max: 150),
      EntityField('is_sample', 'نمونه', 'bool', defaultValue: false),
      EntityField('status', 'وضعیت', 'enum',
          values: <String>['draft', 'submitted', 'returned', 'confirmed', 'rejected', 'sample_only'],
          valueLabels: <String, String>{
            'draft': 'پیش‌نویس',
            'submitted': 'ثبت‌شده',
            'returned': 'برگشتی برای اصلاح',
            'confirmed': 'قطعی‌شده',
            'rejected': 'ردشده',
            'sample_only': 'نمونه'
          },
          defaultValue: 'draft'),
      EntityField('code', 'کد پسته', 'string', max: 40),
      EntityField('note', 'یادداشت', 'string', max: 500),
      EntityField('purchase_id', 'شناسهٔ خرید', 'bigint', vmin: 1),
      EntityField('created_by_staff_id', 'ثبت‌کننده', 'int', vmin: 0),
      EntityField('created_by_name', 'نام ثبت‌کننده', 'string', max: 120),
      EntityField('confirmed_by_staff_id', 'قطعی‌کننده', 'int', vmin: 0),
      EntityField('confirmed_by_name', 'نام قطعی‌کننده', 'string', max: 120),
      EntityField('confirmed_at', 'زمان قطعی‌سازی', 'datetime'),
      EntityField('submitted_at', 'زمان ثبت', 'datetime'),
      EntityField('reject_reason', 'دلیل رد', 'string', max: 250),
    ],
    search: <String>['code', 'owner_name', 'type_name', 'note'],
    listFields: <String>['code', 'owner_name', 'type_name', 'gross_kg'],
    permCreate: 'ounce.intake',
    permEdit: 'ounce.edit_own',
    permDelete: 'ounce.edit_own',
  ),
  // S5.T1 (mirror of server `lot_intake_pcts`)
  'lot_intake_pcts': EntitySpec(
    'lot_intake_pcts',
    'درصد پذیرش',
    <EntityField>[
      EntityField('intake_id', 'پذیرش', 'ref', ref: 'lot_intakes', required: true),
      EntityField('def_key', 'نوع درصد', 'string', required: true, max: 32),
      EntityField('pct', 'درصد', 'decimal', scale: 3, required: true, vmin: 0, vmax: 100),
      EntityField('kernel_g', 'گرم مغز در ۱۰۰ گرم', 'decimal', scale: 3, vmin: 0, vmax: 100),
    ],
    search: <String>['def_key'],
    listFields: <String>['def_key', 'pct'],
    permCreate: 'ounce.intake',
    permEdit: 'ounce.edit_own',
    permDelete: 'ounce.edit_own',
  ),
  // S5.T1 (mirror of server `pct_defs`; خواندنی برای فرم — مدیریت آن در مرحلهٔ بعد)
  'pct_defs': EntitySpec(
    'pct_defs',
    'تعریف درصدها', // v89
    <EntityField>[
      EntityField('key', 'کلید', 'string', max: 32),
      EntityField('label', 'عنوان', 'string', required: true, max: 80),
      EntityField('active', 'فعال', 'bool', defaultValue: true),
      EntityField('sort', 'ترتیب', 'int', vmin: 0, vmax: 100000),
      EntityField('pricing_allowed', 'قابل قیمت‌گذاری', 'bool', defaultValue: false),
    ],
    search: <String>['key', 'label'],
    listFields: <String>['label', 'key'],
    orderCol: 'sort',
    orderDesc: false,
    permCreate: 'ounce.intake',
    permEdit: 'intake.confirm',
    permDelete: 'intake.confirm',
  ),
  // v90 — بازاریابی بین‌المللی (آینهٔ marketing.php). فیلدهای staff_id/owner/status را سرور مهر می‌زند.
  'mk_leads': EntitySpec(
    'mk_leads',
    'مشتری بازاریابی',
    <EntityField>[
      EntityField('name', 'نام شرکت/مشتری', 'string', required: true, max: 150),
      EntityField('contact', 'شخص رابط', 'string', max: 120),
      EntityField('country', 'کشور', 'string', max: 2),
      EntityField('city', 'شهر', 'string', max: 80),
      EntityField('phone', 'تلفن/واتساپ', 'string', max: 200), // v91: چند شماره در یک خانه
      EntityField('email', 'ایمیل', 'string', max: 120),
      EntityField('source', 'منبع', 'enum', values: <String>['expo', 'website', 'linkedin', 'b2b', 'referral', 'cold', 'social', 'other'], defaultValue: 'other'),
      EntityField('source_detail', 'جزئیات منبع', 'string', max: 150), // v91: مثل «Gulfood 2026»
      EntityField('products', 'محصول مورد علاقه', 'string', max: 200),
      EntityField('est_tons', 'حجم تخمینی (تن)', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('stage', 'مرحله', 'enum', values: <String>['lead', 'contacted', 'negotiation', 'proforma', 'won', 'lost'], defaultValue: 'lead'),
      EntityField('lost_reason', 'دلیل از دست رفتن', 'enum', values: <String>['price', 'quality', 'competitor', 'no_reply', 'payment', 'shipping', 'other']),
      EntityField('owner_staff_id', 'مسئول', 'int', vmin: 0),
      EntityField('owner_name', 'نام مسئول', 'string', max: 120),
      EntityField('prev_owner_staff_id', 'مسئول قبلی', 'int', vmin: 0),
      EntityField('creator_staff_id', 'سازنده', 'int', vmin: 0),
      EntityField('next_followup_at', 'پیگیری بعدی', 'datetime'),
      EntityField('stage_at', 'زمان آخرین تغییر مرحله', 'datetime'),
      EntityField('note', 'یادداشت', 'text', max: 3000),
    ],
    search: <String>['name', 'contact', 'city', 'phone', 'email', 'products'],
    listFields: <String>['name', 'country', 'stage'],
    permCreate: 'marketing.entry',
    permEdit: 'marketing.entry',
    permDelete: 'marketing.manage',
  ),
  'mk_activities': EntitySpec(
    'mk_activities',
    'پیگیری بازاریابی',
    <EntityField>[
      EntityField('lead_uid', 'مشتری', 'ref', ref: 'mk_leads', required: true),
      EntityField('staff_id', 'بازاریاب', 'int', vmin: 0),
      EntityField('staff_name', 'نام بازاریاب', 'string', max: 120),
      EntityField('at', 'زمان', 'datetime', required: true),
      EntityField('kind', 'نوع', 'enum', values: <String>['call', 'message', 'email', 'meeting', 'sample', 'proforma', 'note', 'stage'], defaultValue: 'call'),
      EntityField('from_stage', 'از مرحله', 'enum', values: <String>['lead', 'contacted', 'negotiation', 'proforma', 'won', 'lost']),
      EntityField('to_stage', 'به مرحله', 'enum', values: <String>['lead', 'contacted', 'negotiation', 'proforma', 'won', 'lost']),
      EntityField('result', 'نتیجه', 'string', max: 500),
    ],
    search: <String>['result'],
    orderCol: 'at',
    listFields: <String>['kind', 'at', 'result'],
    permCreate: 'marketing.entry',
    permEdit: 'marketing.entry',
    permDelete: 'marketing.entry',
  ),
  'mk_sales': EntitySpec(
    'mk_sales',
    'فروش بازاریابی',
    <EntityField>[
      EntityField('lead_uid', 'مشتری', 'ref', ref: 'mk_leads', required: true),
      EntityField('staff_id', 'بازاریاب', 'int', vmin: 0),
      EntityField('staff_name', 'نام بازاریاب', 'string', max: 120),
      EntityField('date', 'تاریخ فروش', 'date', required: true),
      EntityField('tons', 'تناژ', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('deal_value', 'مبلغ قرارداد', 'decimal', scale: 2, vmin: 0, vmax: 1e13),
      EntityField('ccy', 'ارز', 'string', max: 3),
      EntityField('product', 'محصول', 'string', max: 120),
      EntityField('collected', 'وصول شد', 'bool', defaultValue: false),
      EntityField('collected_at', 'تاریخ وصول', 'date'),
      EntityField('status', 'وضعیت', 'enum', values: <String>['pending', 'confirmed', 'rejected'], defaultValue: 'pending'),
      EntityField('confirmed_by', 'تأییدکننده', 'string', max: 120),
      EntityField('confirmed_at', 'زمان تأیید', 'datetime'),
      EntityField('note', 'یادداشت', 'string', max: 500),
    ],
    search: <String>['product', 'note'],
    orderCol: 'date',
    listFields: <String>['date', 'tons', 'status'],
    permCreate: 'marketing.entry',
    permEdit: 'marketing.entry',
    permDelete: 'marketing.entry',
  ),
  'mk_targets': EntitySpec(
    'mk_targets',
    'هدف بازاریابی',
    <EntityField>[
      EntityField('staff_id', 'بازاریاب', 'int', vmin: 0, required: true),
      EntityField('month', 'ماه', 'string', max: 7, required: true),
      EntityField('follow_ups', 'پیگیری', 'decimal', scale: 2, vmin: 0, vmax: 100000),
      EntityField('new_leads', 'لید جدید', 'decimal', scale: 2, vmin: 0, vmax: 100000),
      EntityField('negotiations', 'مذاکره', 'decimal', scale: 2, vmin: 0, vmax: 100000),
      EntityField('proformas', 'پیش‌فاکتور', 'decimal', scale: 2, vmin: 0, vmax: 100000),
      EntityField('sales', 'فروش', 'decimal', scale: 2, vmin: 0, vmax: 100000),
      EntityField('tons', 'تناژ', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
    ],
    search: <String>['month'],
    orderCol: 'month',
    listFields: <String>['month', 'staff_id'],
    permCreate: 'marketing.manage',
    permEdit: 'marketing.manage',
    permDelete: 'marketing.manage',
  ),
  'mk_settings': EntitySpec(
    'mk_settings',
    'تنظیمات بازاریابی',
    <EntityField>[
      EntityField('w_lead', 'w_lead', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('w_negotiation', 'w_negotiation', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('w_proforma', 'w_proforma', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('w_sale', 'w_sale', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('w_ton', 'w_ton', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('w_collection', 'w_collection', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('no_sale_factor', 'no_sale_factor', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('per_sale_deduct', 'per_sale_deduct', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('stale_days', 'stale_days', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('p_lead', 'p_lead', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('p_contacted', 'p_contacted', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('p_negotiation', 'p_negotiation', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('p_proforma', 'p_proforma', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('t_follow_ups', 't_follow_ups', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('t_new_leads', 't_new_leads', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('t_negotiations', 't_negotiations', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('t_proformas', 't_proformas', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('t_sales', 't_sales', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
      EntityField('t_tons', 't_tons', 'decimal', scale: 3, vmin: 0, vmax: 1000000),
    ],
    permCreate: 'marketing.manage',
    permEdit: 'marketing.manage',
    permDelete: 'marketing.manage',
  ),
  // v96 — پیش‌فاکتور صادراتی (آینهٔ marketing.php): قالب شرکت + پیش‌فاکتور هر فروش. data = JSON کامل (proforma_model.dart).
  'mk_pf_templates': EntitySpec(
    'mk_pf_templates',
    'قالب پیش‌فاکتور',
    <EntityField>[
      EntityField('title', 'نام قالب', 'string', required: true, max: 100),
      EntityField('data', 'تنظیمات قالب', 'json', required: true, max: 400000),
    ],
    search: <String>['title'],
    orderCol: 'title',
    orderDesc: false,
    listFields: <String>['title'],
    permCreate: 'marketing.manage',
    permEdit: 'marketing.manage',
    permDelete: 'marketing.manage',
  ),
  'mk_proformas': EntitySpec(
    'mk_proformas',
    'پیش‌فاکتور صادراتی',
    <EntityField>[
      EntityField('lead_uid', 'مشتری', 'ref', ref: 'mk_leads'),
      EntityField('template_uid', 'قالب', 'string', max: 36),
      EntityField('number', 'شماره', 'string', required: true, max: 40),
      EntityField('date', 'تاریخ', 'date', required: true),
      EntityField('buyer', 'خریدار', 'string', max: 150),
      EntityField('total', 'جمع', 'decimal', scale: 2, vmin: 0, vmax: 1e13),
      EntityField('ccy', 'ارز', 'string', max: 3),
      EntityField('staff_id', 'بازاریاب', 'int', vmin: 0),
      EntityField('staff_name', 'نام بازاریاب', 'string', max: 120),
      EntityField('data', 'محتوا', 'json', required: true, max: 400000),
    ],
    search: <String>['number', 'buyer'],
    orderCol: 'date',
    listFields: <String>['number', 'buyer', 'date'],
    permCreate: 'marketing.entry',
    permEdit: 'marketing.entry',
    permDelete: 'marketing.entry',
  ),
};

/// v90: کلیدهای تنظیمات بازاریابی (آینهٔ pb_mk_default_settings)
const List<String> kMkSettingKeys = <String>[
  'w_lead', 'w_negotiation', 'w_proforma', 'w_sale', 'w_ton', 'w_collection', 'no_sale_factor', 'per_sale_deduct', 'stale_days',
  'p_lead', 'p_contacted', 'p_negotiation', 'p_proforma', 't_follow_ups', 't_new_leads', 't_negotiations', 't_proformas', 't_sales', 't_tons',
];

/// Local mirror of generic entities (table `entity_rows`, one JSON blob per row) + offline queue hooks.
///
/// * Rows are identified by `uid` (client UUID). `rev` = server revision (0 = never confirmed by the server).
/// * Writes are applied locally at once and queued as `entity.save` / `entity.delete` ops in `sync_ops`
///   (the same queue/idempotency/retry as every other op). The server is the authority: a full pull
///   (`backup.export` -> `entities`) replaces local rows when the queue is empty.
/// * Conflict policy: last write wins (no expected_rev is sent).
class EntityStore {
  EntityStore._();
  static final EntityStore I = EntityStore._();

  static const String table = 'entity_rows';
  static const String _kVisibleKey = 'entity_visible';

  static final math.Random _rng = math.Random.secure();

  /// Creates the table (idempotent). Called from AppDb `_onCreate` and `_onUpgrade`.
  static Future<void> createTable(DatabaseExecutor d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS $table(
        entity TEXT NOT NULL,
        uid TEXT NOT NULL,
        rev INTEGER NOT NULL DEFAULT 0,
        data TEXT NOT NULL,
        created_at TEXT,
        updated_at TEXT,
        PRIMARY KEY(entity, uid)
      )''');
  }

  /// RFC-4122 v4 UUID (lowercase), accepted by the server (`pb_is_uid`).
  static String newUid() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  // ======================= visibility =======================

  /// Entities this account may use: those the server last reported (export keys) that the app also knows.
  Future<List<String>> visibleNames() async {
    final raw = await AppDb.I.metaGet(_kVisibleKey);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final l = jsonDecode(raw);
      if (l is! List) return <String>[];
      final out = <String>[];
      for (final x in l) {
        if (x is String && kEntityRegistry.containsKey(x)) out.add(x);
      }
      return out;
    } catch (_) {
      return <String>[];
    }
  }

  Future<bool> isVisible(String entity) async => (await visibleNames()).contains(entity);

  // ======================= read =======================

  Map<String, dynamic> _decode(Map<String, Object?> r) {
    Map<String, dynamic> m = <String, dynamic>{};
    try {
      final j = jsonDecode(r['data'] as String);
      if (j is Map) m = Map<String, dynamic>.from(j);
    } catch (_) {}
    m['uid'] = r['uid'];
    m['rev'] = (r['rev'] as num?)?.toInt() ?? 0;
    m['created_at'] = r['created_at'];
    m['updated_at'] = r['updated_at'];
    return m;
  }

  Future<Map<String, dynamic>?> get(String entity, String uid) async {
    final d = await AppDb.I.db;
    final r = await d.query(table, where: 'entity=? AND uid=?', whereArgs: [entity, uid], limit: 1);
    return r.isEmpty ? null : _decode(r.first);
  }

  /// All rows of [entity], filtered by [q] over the spec's search fields, ordered per the spec.
  Future<List<Map<String, dynamic>>> list(String entity, {String q = ''}) async {
    final spec = kEntityRegistry[entity];
    if (spec == null) return <Map<String, dynamic>>[];
    final d = await AppDb.I.db;
    final rows = await d.query(table, where: 'entity=?', whereArgs: [entity], orderBy: 'rowid DESC');
    var out = rows.map(_decode).toList();
    final needle = q.trim().toLowerCase();
    if (needle.isNotEmpty && spec.search.isNotEmpty) {
      out = out.where((m) {
        for (final k in spec.search) {
          final v = m[k];
          if (v != null && v.toString().toLowerCase().contains(needle)) return true;
        }
        return false;
      }).toList();
    }
    final oc = spec.orderCol;
    if (oc.isNotEmpty) {
      int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
        final x = a[oc];
        final y = b[oc];
        if (x == null && y == null) return 0;
        if (x == null) return -1;
        if (y == null) return 1;
        if (x is num && y is num) return x.compareTo(y);
        return x.toString().compareTo(y.toString());
      }

      out.sort((a, b) => spec.orderDesc ? cmp(b, a) : cmp(a, b));
    }
    return out;
  }

  // ======================= write (local + queue) =======================

  /// Client-side validation mirroring the server rules. Returns a Persian message or null when OK.
  /// [existing] = stored row when [data] is a partial update: a required field that [data] does not touch is
  /// checked against the stored value (like the server's pb_entity_validate). Clearing it is still an error.
  String? validate(EntitySpec spec, Map<String, dynamic> data, {Map<String, dynamic>? existing}) {
    bool blank(Object? v) => v == null || (v is String && v.trim().isEmpty);
    for (final f in spec.fields) {
      final v = data[f.key];
      final empty = blank(v);
      if (empty) {
        if (f.required && !(existing != null && !data.containsKey(f.key) && !blank(existing[f.key]))) return '«${f.label}» الزامی است';
        continue;
      }
      if (f.type == 'string' || f.type == 'text') {
        final mx = f.max ?? (f.type == 'string' ? 255 : 20000);
        if (v.toString().trim().length > mx) return '«${f.label}» حداکثر $mx حرف می‌تواند باشد';
      } else if (f.isNumeric) {
        if (v is! num) return '«${f.label}» باید عدد باشد';
        if (f.vmin != null && v < f.vmin!) return '«${f.label}» نمی‌تواند کمتر از ${f.vmin} باشد';
        if (f.vmax != null && v > f.vmax!) return '«${f.label}» نمی‌تواند بیشتر از ${f.vmax} باشد';
        if (f.type != 'decimal' && v is double && v != v.roundToDouble()) return '«${f.label}» باید عدد صحیح باشد';
      } else if (f.type == 'enum') {
        if (!f.values.contains(v)) return '«${f.label}» نامعتبر است';
      }
    }
    return null;
  }

  /// Keeps only known fields, normalizes types and drops empty values (null = cleared).
  Map<String, dynamic> _clean(EntitySpec spec, Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    for (final f in spec.fields) {
      if (!data.containsKey(f.key)) continue;
      var v = data[f.key];
      if (v is String) {
        v = v.trim();
        if (v == '') v = null;
      }
      if (v != null) {
        switch (f.type) {
          case 'int':
          case 'bigint':
            if (v is num) v = v.round();
            break;
          case 'decimal':
            if (v is num) v = v.toDouble();
            break;
          case 'bool':
            v = (v == true || v == 1 || v == '1');
            break;
        }
      }
      out[f.key] = v;
    }
    return out;
  }

  /// Save (create when [uid] is null). Returns the row uid. Throws [ArgumentError] with a Persian message
  /// when validation fails. The row is stored locally at once and queued for the server.
  /// [patch] = true ⇒ فقط همین فیلدها برای سرور فرستاده می‌شوند (نه کل ردیف محلی)؛ برای تغییر یک وضعیت بدون بازنویسی تغییرات تازه‌تر دیگران.
  Future<String> save(String entity, Map<String, dynamic> data, {String? uid, bool patch = false}) async {
    final spec = kEntityRegistry[entity];
    if (spec == null) throw ArgumentError('بخش نامعتبر است');
    final clean = _clean(spec, data);
    final id = uid ?? newUid();
    final d = await AppDb.I.db;
    final now = DateTime.now().toIso8601String();
    await d.transaction((t) async {
      final ex = await t.query(table, where: 'entity=? AND uid=?', whereArgs: [entity, id], limit: 1);
      var merged = <String, dynamic>{};
      var rev = 0;
      String? created = now;
      if (ex.isNotEmpty) {
        merged = Map<String, dynamic>.from(jsonDecode(ex.first['data'] as String) as Map);
        rev = (ex.first['rev'] as num?)?.toInt() ?? 0;
        created = ex.first['created_at'] as String?;
      } else {
        // defaults on create (the server applies the same defaults)
        for (final f in spec.fields) {
          if (f.defaultValue != null) merged[f.key] = f.defaultValue;
        }
      }
      // v90: یک ردیف موجود با چند فیلد (تغییر مرحله، تأیید فروش، سپردن) ⇒ فیلدهای الزامیِ دست‌نخورده از ردیف ذخیره‌شده؛ خطا ⇒ تراکنش برمی‌گردد
      final err = validate(spec, clean, existing: ex.isNotEmpty ? merged : null);
      if (err != null) throw ArgumentError(err);
      merged.addAll(clean);
      await t.insert(
          table,
          {
            'entity': entity,
            'uid': id,
            'rev': rev,
            'data': jsonEncode(merged),
            'created_at': created,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      // send the full merged state (last write wins) · v90: patch ⇒ فقط فیلدهای تغییرکرده
      final payload = <String, dynamic>{'entity': entity, 'uid': id, 'data': merged};
      await _upsertSaveOp(t, id, payload, patch: (patch && ex.isNotEmpty) ? <String, dynamic>{'entity': entity, 'uid': id, 'data': clean} : null);
    });
    AppDb.I.version.value++;
    return id;
  }

  Future<void> delete(String entity, String uid) async {
    final d = await AppDb.I.db;
    await d.transaction((t) async {
      final ex = await t.query(table, columns: ['rev'], where: 'entity=? AND uid=?', whereArgs: [entity, uid], limit: 1);
      if (ex.isEmpty) return;
      final rev = (ex.first['rev'] as num?)?.toInt() ?? 0;
      await t.delete(table, where: 'entity=? AND uid=?', whereArgs: [entity, uid]);
      await t.delete('sync_ops',
          where: "action='entity.save' AND state='pending' AND payload LIKE ?", whereArgs: ['%"uid":"$uid"%']);
      // rev 0 = the server never confirmed it; an in-flight save is handled in [onSaved]
      if (rev > 0) {
        await AppDb.I.entityEnqueue(t, 'entity.delete', {'entity': entity, 'uid': uid});
      }
    });
    AppDb.I.version.value++;
  }

  /// S5.T1: ثبت نهایی پذیرش. کلاینت فقط uid می‌فرستد؛ کد را سرور می‌دهد (idempotent روی سرور).
  /// ترتیب صف FIFO است، پس درصدهایی که قبلاً ذخیره شده‌اند قبل از این عملیات به سرور می‌رسند.
  Future<void> submitIntake(String uid) async {
    final d = await AppDb.I.db;
    await d.transaction((t) async {
      await AppDb.I.entityEnqueue(t, 'intake.submit', {'uid': uid});
    });
    AppDb.I.version.value++;
  }

  /// آیا `intake.submit` این پذیرش هنوز در صف ارسال است؟ (برای نمایش «در انتظار ارسال»)
  Future<bool> isSubmitPending(String uid) async {
    final d = await AppDb.I.db;
    final r = await d.query('sync_ops',
        columns: ['seq'],
        where: "action='intake.submit' AND state='pending' AND payload LIKE ?",
        whereArgs: ['%"uid":"$uid"%'],
        limit: 1);
    return r.isNotEmpty;
  }

  /// [patch]: فقط وقتی عملیات ذخیرهٔ دیگری برای همین ردیف در صف نیست فرستاده می‌شود (وگرنه کل ردیف تا داده‌های آن عملیات گم نشود).
  Future<void> _upsertSaveOp(DatabaseExecutor t, String uid, Map<String, dynamic> payload, {Map<String, dynamic>? patch}) async {
    final ex = await t.query('sync_ops',
        columns: ['seq'],
        where: "action='entity.save' AND state='pending' AND payload LIKE ?",
        whereArgs: ['%"uid":"$uid"%'],
        limit: 1);
    if (ex.isNotEmpty) {
      await AppDb.I.entityUpdateOp(t, (ex.first['seq'] as num).toInt(), payload);
    } else {
      await AppDb.I.entityEnqueue(t, 'entity.save', patch ?? payload);
    }
  }

  // ======================= sync hooks =======================

  /// Called by SyncService after the server accepted an `entity.save`. Stores the server revision.
  /// If the user deleted the row meanwhile, a delete op is queued so the server copy goes too.
  Future<void> onSaved(Map<String, dynamic> payload, Map<String, dynamic>? response) async {
    final entity = payload['entity'];
    final uid = payload['uid'];
    if (entity is! String || uid is! String) return;
    final item = response == null ? null : response['item'];
    final srvRev = item is Map ? (item['rev'] as num?)?.toInt() : null;
    final d = await AppDb.I.db;
    await d.transaction((t) async {
      final ex = await t.query(table, columns: ['rev'], where: 'entity=? AND uid=?', whereArgs: [entity, uid], limit: 1);
      if (ex.isEmpty) {
        await AppDb.I.entityEnqueue(t, 'entity.delete', {'entity': entity, 'uid': uid});
        return;
      }
      if (srvRev != null) {
        await t.update(table, {'rev': srvRev}, where: 'entity=? AND uid=?', whereArgs: [entity, uid]);
      }
    });
  }

  /// Replaces local rows with the server snapshot (`backup.export` -> `entities`), inside the caller's
  /// transaction. [entities] = {entity: [rawRow,...]}. Only entities present in the map are replaced
  /// (all local rows are dropped first when [discardAll]). Records which entities the server exposes.
  static Future<void> applySnapshot(DatabaseExecutor t, Map<String, dynamic> entities, {bool discardAll = false}) async {
    if (discardAll) {
      await t.delete(table);
    }
    final visible = <String>[];
    for (final e in entities.entries) {
      final name = e.key;
      visible.add(name);
      final spec = kEntityRegistry[name];
      if (spec == null) continue; // newer server entity this app version does not know: ignore
      await t.delete(table, where: 'entity=?', whereArgs: [name]);
      final rows = e.value;
      if (rows is! List) continue;
      final b = t.batch();
      var maxRev = 0; // S7: مکان‌نمای دلتا = بیشترین rev دیده‌شده (حتی ردیف‌های حذف‌شده)
      for (final raw in rows) {
        if (raw is! Map) continue;
        final rv = int.tryParse('${raw['rev']}') ?? 0;
        if (rv > maxRev) maxRev = rv;
        final uid = raw['uid'];
        if (uid is! String || uid.isEmpty) continue;
        if (raw['deleted_at'] != null) continue; // soft-deleted on the server
        final data = <String, dynamic>{};
        for (final f in spec.fields) {
          data[f.key] = _fromServer(f, raw[f.key]);
        }
        b.insert(
            table,
            {
              'entity': name,
              'uid': uid,
              'rev': int.tryParse('${raw['rev']}') ?? 0,
              'data': jsonEncode(data),
              'created_at': raw['created_at']?.toString(),
              'updated_at': raw['updated_at']?.toString(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await b.commit(noResult: true);
      await t.insert('meta', {'k': '$_kCursorPrefix$name', 'v': '$maxRev'}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await t.insert('meta', {'k': _kVisibleKey, 'v': jsonEncode(visible)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ======================= S7: دلتا (entity.changes) =======================

  static const String _kCursorPrefix = 'ent_cur:';

  /// آخرین `rev` سروری که برای این entity اعمال شده (برای `since_rev`). اگر نیست: بیشترین rev ردیف‌های محلی.
  Future<int> cursorOf(String entity) async {
    final raw = await AppDb.I.metaGet('$_kCursorPrefix$entity');
    final v = int.tryParse(raw ?? '');
    if (v != null) return v;
    final d = await AppDb.I.db;
    final r = await d.rawQuery('SELECT MAX(rev) AS m FROM $table WHERE entity=?', [entity]);
    return r.isEmpty ? 0 : ((r.first['m'] as num?)?.toInt() ?? 0);
  }

  /// ردیف‌های تغییرکردهٔ سرور ([items] از `entity.changes`) را در آینهٔ محلی اعمال می‌کند:
  /// حذف نرم ⇒ حذف محلی؛ در غیر این صورت جایگزینی (مگر ردیف محلی از نسخهٔ سرور جدیدتر باشد).
  /// فقط وقتی صف ارسال خالی است صدا زده می‌شود (SyncService). مکان‌نما را تا [maxRev] جلو می‌برد.
  Future<int> applyDelta(String entity, List<dynamic> items, int maxRev) async {
    final spec = kEntityRegistry[entity];
    if (spec == null) return 0;
    final d = await AppDb.I.db;
    var changed = 0;
    await d.transaction((t) async {
      var top = maxRev;
      for (final raw in items) {
        if (raw is! Map) continue;
        final uid = raw['uid'];
        if (uid is! String || uid.isEmpty) continue;
        final rv = int.tryParse('${raw['rev']}') ?? 0;
        if (rv > top) top = rv;
        if (raw['deleted_at'] != null || raw['deleted'] == true) { // v90: entity.changes کلید «deleted» (بولی) می‌فرستد، نه deleted_at
          changed += await t.delete(table, where: 'entity=? AND uid=?', whereArgs: [entity, uid]);
          continue;
        }
        final ex = await t.query(table, columns: ['rev'], where: 'entity=? AND uid=?', whereArgs: [entity, uid], limit: 1);
        if (ex.isNotEmpty && ((ex.first['rev'] as num?)?.toInt() ?? 0) > rv) continue; // محلیِ جدیدتر (تازه ذخیره‌شده)
        final data = <String, dynamic>{};
        for (final f in spec.fields) {
          data[f.key] = _fromServer(f, raw[f.key]);
        }
        await t.insert(
            table,
            {
              'entity': entity,
              'uid': uid,
              'rev': rv,
              'data': jsonEncode(data),
              'created_at': raw['created_at']?.toString(),
              'updated_at': raw['updated_at']?.toString(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        changed++;
      }
      await t.insert('meta', {'k': '$_kCursorPrefix$entity', 'v': '$top'}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    if (changed > 0) AppDb.I.version.value++;
    return changed;
  }

  /// S6: یک ردیف تازه از پاسخ سرور (مثلاً `item` در `intake.confirm`) را فوراً در آینهٔ محلی جایگزین می‌کند
  /// (بدون صف؛ سرور مرجع است). ردیف ناشناخته/بدون uid نادیده گرفته می‌شود.
  Future<void> applyServerItem(String entity, Object? raw) async {
    final spec = kEntityRegistry[entity];
    if (spec == null || raw is! Map) return;
    final uid = raw['uid'];
    if (uid is! String || uid.isEmpty) return;
    final d = await AppDb.I.db;
    final data = <String, dynamic>{};
    for (final f in spec.fields) {
      data[f.key] = _fromServer(f, raw[f.key]);
    }
    await d.insert(
        table,
        {
          'entity': entity,
          'uid': uid,
          'rev': int.tryParse('${raw['rev']}') ?? 0,
          'data': jsonEncode(data),
          'created_at': raw['created_at']?.toString(),
          'updated_at': raw['updated_at']?.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    AppDb.I.version.value++;
  }

  /// Raw server value (PDO may give strings) -> typed client value.
  static Object? _fromServer(EntityField f, Object? v) {
    if (v == null) return null;
    switch (f.type) {
      case 'int':
      case 'bigint':
        if (v is num) return v.toInt();
        return int.tryParse(v.toString());
      case 'decimal':
        if (v is num) return v.toDouble();
        return double.tryParse(v.toString());
      case 'bool':
        return v == true || v == 1 || v == '1' || v == 'true';
      case 'json':
        if (v is String) {
          try {
            return jsonDecode(v);
          } catch (_) {
            return null;
          }
        }
        return v;
      case 'date':
        final s = v.toString();
        return s.length >= 10 ? s.substring(0, 10) : s;
      default:
        return v.toString();
    }
  }
}
