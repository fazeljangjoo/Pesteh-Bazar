import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

const List<String> kPresetTypesNormal = ['اکبری', 'احمدآقایی', 'فندقی', 'کله‌قوچی'];
const List<String> kPresetTypesKernel = ['مغز کال', 'مغز درجه یک', 'مغز درجه دو'];

const int kMaxCustomSpecs = 4;
const int kMaxLumpTx = 10;
const int kMaxStagedTx = 50;

class AppDb {
  AppDb._();
  static final AppDb I = AppDb._();

  /// با هر تغییر داده زیاد می‌شود تا صفحه‌ها بازخوانی شوند
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  /// نسخهٔ ساختار دیتابیس (برای بررسی سازگاری فایل‌های پشتیبان هم استفاده می‌شود)
  static const int schemaVersion = 6;
  static const String _dbName = 'pesteh_bazar_v2.db';

  Database? _db;
  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), _dbName);
    // قبل از اولین باز شدن با ساختار جدید، یک کپی امن از دیتابیس قدیمی نگه می‌داریم
    try {
      final sp = await SharedPreferences.getInstance();
      final f = File(path);
      if ((sp.getInt('db_schema_seen') ?? 0) < schemaVersion && await f.exists()) {
        await f.copy('$path.before_upgrade');
      }
    } catch (_) {}
    final d = await openDatabase(path,
        version: schemaVersion, onCreate: _onCreate, onUpgrade: _onUpgrade);
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt('db_schema_seen', schemaVersion);
    } catch (_) {}
    return d;
  }

  /// نسخهٔ سالم و کامل از فایل دیتابیس در مسیر dest می‌سازد.
  /// کپی داخل یک تراکنش انجام می‌شود تا وسطش هیچ نوشتنی رخ ندهد.
  Future<void> snapshotTo(String dest) async {
    final d = await db;
    try {
      await d.rawQuery('PRAGMA journal_mode=DELETE'); // همه‌چیز داخل خود فایل اصلی باشد
    } catch (_) {}
    await d.transaction((t) async {
      await File(d.path).copy(dest);
    });
  }

  /// فایل دیتابیس را با فایل src (پشتیبان) عوض می‌کند. از وضعیت فعلی یک کپی
  /// با پسوند .before_restore کنار فایل دیتابیس نگه داشته می‌شود.
  Future<void> replaceWith(String src) async {
    final path = join(await getDatabasesPath(), _dbName);
    final cur = File(path);
    if (await cur.exists()) await cur.copy('$path.before_restore');
    await _db?.close();
    _db = null;
    for (final ext in const ['-wal', '-shm', '-journal']) {
      final f = File('$path$ext');
      if (await f.exists()) await f.delete();
    }
    await File(src).copy(path);
    final d = await db; // دوباره باز می‌شود (در صورت قدیمی‌تر بودن، ارتقا هم می‌شود)
    // عکس‌ها داخل پشتیبان نیستند؛ مسیر عکس‌های ناموجود را پاک می‌کنیم
    final rows = await d.query('purchases',
        columns: ['id', 'photo'], where: 'photo IS NOT NULL');
    for (final r in rows) {
      final ph = r['photo'] as String?;
      if (ph != null && !await File(ph).exists()) {
        await d.update('purchases', {'photo': null}, where: 'id=?', whereArgs: [r['id']]);
      }
    }
    version.value++;
  }

  Future<void> _onCreate(Database d, int v) async {
    await d.execute('''
      CREATE TABLE categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        preset_key TEXT
      )''');
    await d.execute('''
      CREATE TABLE types(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL,
        name TEXT NOT NULL
      )''');
    await d.execute('''
      CREATE TABLE purchases(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT UNIQUE,
        category_id INTEGER NOT NULL,
        type_name TEXT NOT NULL,
        date TEXT NOT NULL,
        photo TEXT,
        ounce REAL,
        price REAL NOT NULL,
        total_weight REAL NOT NULL,
        small_sack_count REAL NOT NULL DEFAULT 0,
        large_sack_count REAL NOT NULL DEFAULT 0,
        net_weight REAL NOT NULL,
        remaining REAL NOT NULL,
        gram REAL,
        pct_dombest REAL,
        pct_tuchin REAL,
        pct_crooked REAL,
        pct_khandan REAL,
        custom_specs TEXT,
        seller TEXT,
        note TEXT,
        is_mix INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('''
      CREATE TABLE mix_sources(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        mix_purchase_id INTEGER NOT NULL,
        source_purchase_id INTEGER NOT NULL,
        weight REAL NOT NULL,
        small_sacks REAL,
        large_sacks REAL
      )''');
    await d.execute('''
      CREATE TABLE payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_id INTEGER NOT NULL UNIQUE,
        pay_type TEXT NOT NULL,
        staged_type TEXT
      )''');
    await d.execute('''
      CREATE TABLE lump_tx(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_id INTEGER NOT NULL,
        from_account TEXT,
        payer_name TEXT,
        to_account TEXT,
        seller_name TEXT,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        paid INTEGER NOT NULL DEFAULT 1
      )''');
    await d.execute('''
      CREATE TABLE credit_inst(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_id INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        amount REAL NOT NULL,
        from_account TEXT,
        payer_name TEXT,
        to_account TEXT,
        seller_name TEXT,
        paid INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('''
      CREATE TABLE cheque_inst(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_id INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        amount REAL NOT NULL,
        cheque_no TEXT,
        bank_name TEXT,
        from_account TEXT,
        payer_name TEXT,
        to_account TEXT,
        seller_name TEXT,
        paid INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('''
      CREATE TABLE sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        price REAL NOT NULL,
        total_weight REAL NOT NULL,
        small_sack_count REAL NOT NULL DEFAULT 0,
        large_sack_count REAL NOT NULL DEFAULT 0,
        net_weight REAL NOT NULL,
        buyer TEXT,
        note TEXT
      )''');
    await d.execute('''
      CREATE TABLE sale_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        purchase_id INTEGER NOT NULL,
        weight REAL NOT NULL,
        item_price REAL,
        small_sacks REAL,
        large_sacks REAL
      )''');
    await _createReceiptTables(d);

    final khandanId =
        await d.insert('categories', {'name': 'پسته خندان', 'preset_key': 'khandan'});
    final dombestId =
        await d.insert('categories', {'name': 'پسته دنبست', 'preset_key': 'dombest'});
    final kernelId = await d.insert('categories', {'name': 'مغز', 'preset_key': 'kernel'});
    for (final t in kPresetTypesNormal) {
      await d.insert('types', {'category_id': khandanId, 'name': t});
      await d.insert('types', {'category_id': dombestId, 'name': t});
    }
    for (final t in kPresetTypesKernel) {
      await d.insert('types', {'category_id': kernelId, 'name': t});
    }
  }

  Future<void> _createReceiptTables(Database d) async {
    // ---------- وصول مطالبات (دریافت وجه فروش) ----------
    await d.execute('''
      CREATE TABLE receipts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL UNIQUE,
        recv_type TEXT NOT NULL,
        staged_type TEXT
      )''');
    await d.execute('''
      CREATE TABLE receipt_lump_tx(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL,
        from_account TEXT,
        payer_name TEXT,
        to_account TEXT,
        receiver_name TEXT,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        paid INTEGER NOT NULL DEFAULT 1
      )''');
    await d.execute('''
      CREATE TABLE receipt_credit_inst(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        amount REAL NOT NULL,
        from_account TEXT,
        payer_name TEXT,
        to_account TEXT,
        receiver_name TEXT,
        paid INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('''
      CREATE TABLE receipt_cheque_inst(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        amount REAL NOT NULL,
        cheque_no TEXT,
        bank_name TEXT,
        from_account TEXT,
        payer_name TEXT,
        to_account TEXT,
        receiver_name TEXT,
        paid INTEGER NOT NULL DEFAULT 0
      )''');
  }

  Future<void> _onUpgrade(Database d, int oldV, int newV) async {
    if (oldV < 2) {
      await d.execute('ALTER TABLE lump_tx ADD COLUMN paid INTEGER NOT NULL DEFAULT 1');
      await _createReceiptTables(d);
    }
    if (oldV < 3) {
      // تعداد گونی هر فروش به‌تفکیک جنس (NULL = نامشخص، برآورد تناسبی)
      try {
        await d.execute('ALTER TABLE sale_items ADD COLUMN small_sacks REAL');
      } catch (_) {}
      try {
        await d.execute('ALTER TABLE sale_items ADD COLUMN large_sacks REAL');
      } catch (_) {}
    }
    if (oldV < 4) {
      // مخلوط‌کردن (کوت‌ریزی) چند بار انبار در یک بار جدید
      try {
        await d.execute('ALTER TABLE purchases ADD COLUMN is_mix INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      try {
        await d.execute('''
          CREATE TABLE IF NOT EXISTS mix_sources(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            mix_purchase_id INTEGER NOT NULL,
            source_purchase_id INTEGER NOT NULL,
            weight REAL NOT NULL,
            small_sacks REAL,
            large_sacks REAL
          )''');
      } catch (_) {}
    }
    if (oldV < 5) {
      try {
        await d.execute('ALTER TABLE purchases ADD COLUMN code TEXT');
      } catch (_) {}
      final rows = await d.query('purchases', columns: ['id'], where: 'code IS NULL');
      for (final row in rows) {
        final id = row['id'] as int;
        await d.update('purchases', {'code': _codeFor(id)}, where: 'id=?', whereArgs: [id]);
      }
      try {
        await d.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_purchases_code ON purchases(code)');
      } catch (_) {}
    }
    if (oldV < 6) {
      try {
        await d.execute('ALTER TABLE sale_items ADD COLUMN item_price REAL');
      } catch (_) {}
    }
  }

  static String _codeFor(int id) => 'P${DateTime.now().year % 100}${id.toRadixString(36).toUpperCase()}';

  Future<String> _newCode(DatabaseExecutor executor, int id) async {
    var code = _codeFor(id);
    var suffix = 0;
    while ((await executor.query('purchases', columns: ['id'], where: 'code=?', whereArgs: [code], limit: 1)).isNotEmpty) {
      suffix++;
      code = '${_codeFor(id)}$suffix';
    }
    return code;
  }

  // ---------- دسته‌ها و انواع ----------
  Future<List<Map<String, dynamic>>> categories() async =>
      (await db).query('categories', orderBy: 'id');

  Future<int> addCategory(String name) async {
    final id = await (await db).insert('categories', {'name': name, 'preset_key': null});
    version.value++;
    return id;
  }

  Future<List<Map<String, dynamic>>> typesOf(int categoryId) async =>
      (await db).query('types', where: 'category_id=?', whereArgs: [categoryId], orderBy: 'id');

  Future<int> addType(int categoryId, String name) async {
    final id = await (await db).insert('types', {'category_id': categoryId, 'name': name});
    version.value++;
    return id;
  }

  // ---------- خرید ----------
  /// فقط خریدهای واقعی (بارهای مخلوط/کوت‌ریزی اینجا نمایش داده نمی‌شوند)
  Future<List<Map<String, dynamic>>> purchases() async => (await db).rawQuery('''
        SELECT p.*, c.name AS category_name, c.preset_key AS category_preset
        FROM purchases p JOIN categories c ON c.id = p.category_id
        WHERE p.is_mix = 0
        ORDER BY p.id DESC''');

  Future<Map<String, dynamic>?> purchaseById(int id) async {
    final rows = await (await db).rawQuery('''
        SELECT p.*, c.name AS category_name, c.preset_key AS category_preset
        FROM purchases p JOIN categories c ON c.id = p.category_id
        WHERE p.id = ?''', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> insertPurchase(Map<String, dynamic> p) async {
    final d = await db;
    p['remaining'] = p['net_weight'];
    final id = await d.insert('purchases', p);
    await d.update('purchases', {'code': await _newCode(d, id)}, where: 'id=?', whereArgs: [id]);
    version.value++;
    return id;
  }

  /// ویرایش خرید. اگر بخشی از آن فروخته شده باشد (remaining < net_weight)،
  /// فراخواننده باید فقط فیلدهای غیرمرتبط با وزن/دسته/نوع را در p بگذارد؛
  /// این متد خودش قفل را اعمال نمی‌کند (منطق تصمیم در purchase_form است) اما
  /// اگر net_weight تغییر کند و چیزی فروخته نشده باشد remaining را هم به‌روز می‌کند.
  Future<void> updatePurchase(int id, Map<String, dynamic> p) async {
    final d = await db;
    if (p.containsKey('net_weight')) {
      final cur = await purchaseById(id);
      if (cur != null && (cur['remaining'] as num) == (cur['net_weight'] as num)) {
        p['remaining'] = p['net_weight'];
      }
    }
    await d.update('purchases', p, where: 'id=?', whereArgs: [id]);
    version.value++;
  }

  /// اگر از این خرید فروشی انجام شده یا در ساخت یک مخلوط استفاده شده باشد حذف نمی‌شود؛
  /// اگر خودش نتیجه‌ی یک مخلوط باشد هم باید با deleteMix حذف شود، نه این متد
  Future<bool> deletePurchase(int id) async {
    final d = await db;
    final used = await d.query('sale_items', where: 'purchase_id=?', whereArgs: [id], limit: 1);
    if (used.isNotEmpty) return false;
    final usedAsMixSource =
        await d.query('mix_sources', where: 'source_purchase_id=?', whereArgs: [id], limit: 1);
    if (usedAsMixSource.isNotEmpty) return false;
    final isMixResult =
        await d.query('mix_sources', where: 'mix_purchase_id=?', whereArgs: [id], limit: 1);
    if (isMixResult.isNotEmpty) return false;
    await d.transaction((t) async {
      final pay = await t.query('payments', where: 'purchase_id=?', whereArgs: [id]);
      if (pay.isNotEmpty) {
        final payId = pay.first['id'] as int;
        await t.delete('lump_tx', where: 'payment_id=?', whereArgs: [payId]);
        await t.delete('credit_inst', where: 'payment_id=?', whereArgs: [payId]);
        await t.delete('cheque_inst', where: 'payment_id=?', whereArgs: [payId]);
        await t.delete('payments', where: 'id=?', whereArgs: [payId]);
      }
      await t.delete('purchases', where: 'id=?', whereArgs: [id]);
    });
    version.value++;
    return true;
  }

  static List<Map<String, String>> decodeCustomSpecs(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list
          .map((e) => {'label': (e['label'] ?? '').toString(), 'value': (e['value'] ?? '').toString()})
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String encodeCustomSpecs(List<Map<String, String>> specs) => jsonEncode(specs);

  // ---------- موجودی ----------
  Future<List<Map<String, dynamic>>> lots() async {
    final d = await db;
    final rows = await d.rawQuery('''
        SELECT p.*, c.name AS category_name, c.preset_key AS category_preset
        FROM purchases p JOIN categories c ON c.id = p.category_id
        WHERE p.remaining > 0.0005
        ORDER BY c.name, p.type_name, p.id''');
    return _withSacksLeft(d, rows);
  }

  Future<List<Map<String, dynamic>>> searchLots(String query) async {
    final q = query.trim();
    if (q.isEmpty) return lots();
    final d = await db;
    final rows = await d.rawQuery('''
        SELECT p.*, c.name AS category_name, c.preset_key AS category_preset
        FROM purchases p JOIN categories c ON c.id = p.category_id
        WHERE p.remaining > 0.0005
          AND (p.code LIKE ? OR p.type_name LIKE ? OR c.name LIKE ?)
        ORDER BY c.name, p.type_name, p.id''', ['%$q%', '%$q%', '%$q%']);
    return _withSacksLeft(d, rows);
  }

  /// تعداد گونی باقی‌مانده‌ی هر خرید: گونی‌های خرید منهای گونی‌های فروخته‌شده.
  /// اگر فروشی تعداد گونی نداشته باشد (قدیمی یا وزن گونی به کیلو)، سهم گونی‌ها
  /// به‌نسبت وزن فروخته‌شده برآورد می‌شود و sacks_estimated=true می‌شود.
  Future<List<Map<String, dynamic>>> _withSacksLeft(
      Database d, List<Map<String, Object?>> rows) async {
    // وزن/گونیِ مصرف‌شده از هر بار، هم از محل فروش و هم از محل مخلوط‌کردن (کوت‌ریزی)
    final sums = await d.rawQuery('''
        SELECT purchase_id AS pid,
               SUM(CASE WHEN small_sacks IS NULL AND large_sacks IS NULL THEN weight ELSE 0 END) AS unk_w,
               SUM(COALESCE(small_sacks, 0)) AS ks,
               SUM(COALESCE(large_sacks, 0)) AS kl
        FROM (
          SELECT purchase_id, weight, small_sacks, large_sacks FROM sale_items
          UNION ALL
          SELECT source_purchase_id AS purchase_id, weight, small_sacks, large_sacks FROM mix_sources
        )
        GROUP BY purchase_id''');
    final byId = <int, Map<String, Object?>>{
      for (final r in sums) (r['pid'] as int): r,
    };
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final id = r['id'] as int;
      final net = (r['net_weight'] as num).toDouble();
      final small = (r['small_sack_count'] as num).toDouble();
      final large = (r['large_sack_count'] as num).toDouble();
      var sl = small;
      var ll = large;
      var est = false;
      final s = byId[id];
      if (s != null) {
        final unk = (s['unk_w'] as num?)?.toDouble() ?? 0;
        final ratio = net > 0 ? unk / net : 0.0;
        sl = small - ((s['ks'] as num?)?.toDouble() ?? 0) - small * ratio;
        ll = large - ((s['kl'] as num?)?.toDouble() ?? 0) - large * ratio;
        est = unk > 0.0005;
      }
      if (sl < 0) sl = 0;
      if (ll < 0) ll = 0;
      out.add({
        ...r,
        'small_left': sl.roundToDouble(),
        'large_left': ll.roundToDouble(),
        'sacks_estimated': est,
      });
    }
    return out;
  }

  /// مثل lots() اما برای ویرایش یک فروش موجود: مانده‌ی هر خرید را طوری برمی‌گرداند
  /// که انگار سهم این فروش هنوز کسر نشده (تا بتوان همان مقدار قبلی را هم نشان داد
  /// و هم امکان افزایش/کاهش آن را فراهم کرد). فیلد اضافه‌ی sale_weight مقدار
  /// فعلیِ این فروش از آن خرید را نشان می‌دهد.
  Future<List<Map<String, dynamic>>> lotsForSaleEdit(int saleId) async {
    final d = await db;
    final items = await d.query('sale_items', where: 'sale_id=?', whereArgs: [saleId]);
    final used = <int, double>{};
    for (final it in items) {
      final pid = it['purchase_id'] as int;
      used[pid] = (used[pid] ?? 0) + (it['weight'] as num).toDouble();
    }
    final rows = await d.rawQuery('''
        SELECT p.*, c.name AS category_name, c.preset_key AS category_preset
        FROM purchases p JOIN categories c ON c.id = p.category_id
        ORDER BY c.name, p.type_name, p.id''');
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      final id = r['id'] as int;
      final saleWeight = used[id] ?? 0;
      final adjustedRemaining = (r['remaining'] as num).toDouble() + saleWeight;
      if (adjustedRemaining > 0.0005) {
        out.add({...r, 'remaining': adjustedRemaining, 'sale_weight': saleWeight});
      }
    }
    return out;
  }

  // ---------- مخلوط‌کردن (کوت‌ریزی) ----------
  /// همه‌ی بارهای مخلوط‌شده (برای نمایش در انبار)
  Future<List<Map<String, dynamic>>> mixes() async {
    final d = await db;
    final rows = await d.rawQuery('''
        SELECT p.*, c.name AS category_name, c.preset_key AS category_preset
        FROM purchases p JOIN categories c ON c.id = p.category_id
        WHERE p.is_mix = 1
        ORDER BY p.id DESC''');
    return rows;
  }

  /// ترکیب‌سازها (منابع) یک بار مخلوط: از کدام بارها و چقدر برداشته شده
  Future<List<Map<String, dynamic>>> mixSourcesOf(int mixPurchaseId) async {
    final d = await db;
    return d.rawQuery('''
        SELECT ms.*, p.type_name AS type_name, p.date AS source_date, c.name AS category_name
        FROM mix_sources ms
        JOIN purchases p ON p.id = ms.source_purchase_id
        JOIN categories c ON c.id = p.category_id
        WHERE ms.mix_purchase_id = ?
        ORDER BY ms.id''', [mixPurchaseId]);
  }

  /// یک بار مخلوط (کوت‌ریزی) جدید می‌سازد: وزن دلخواه از چند بار موجود در انبار
  /// کم می‌شود و یک بار تازه با وزن خالص و تعداد گونیِ واردشده به انبار اضافه می‌شود.
  /// فی خرید بار جدید میانگین وزنیِ فی بارهای مبدأ (به نسبت وزن برداشته‌شده) است.
  ///
  /// sources: هرکدام {'purchase_id': int, 'weight': double, 'small_sacks': double?, 'large_sacks': double?}
  Future<int> createMix({
    required int categoryId,
    required String typeName,
    required List<Map<String, dynamic>> sources,
    required double netWeight,
    required double smallSackCount,
    required double largeSackCount,
    String? note,
  }) async {
    if (sources.isEmpty) throw Exception('حداقل یک جنس مبدأ را انتخاب کنید');
    if (netWeight <= 0) throw Exception('وزن نهایی مخلوط را وارد کنید');
    final d = await db;
    late int mixId;
    await d.transaction((t) async {
      double weightedPriceSum = 0;
      double totalTaken = 0;
      for (final s in sources) {
        final pid = s['purchase_id'] as int;
        final w = (s['weight'] as num).toDouble();
        if (w <= 0) continue;
        final rows = await t.rawQuery('''
            SELECT p.remaining, p.price, p.type_name, c.name AS category_name
            FROM purchases p JOIN categories c ON c.id = p.category_id
            WHERE p.id = ?''', [pid]);
        if (rows.isEmpty) throw Exception('خرید مرتبط یافت نشد');
        final rem = (rows.first['remaining'] as num).toDouble();
        final price = (rows.first['price'] as num).toDouble();
        if (w > rem + 1e-6) {
          final label = '${rows.first['type_name']} (${rows.first['category_name']})';
          throw Exception('موجودی «$label» کافی نیست؛ فقط ${_fmt(rem)} کیلو باقی مانده');
        }
        weightedPriceSum += w * price;
        totalTaken += w;
      }
      if (totalTaken <= 0) throw Exception('حداقل از یک جنس مبدأ وزن بردارید');
      final avgPrice = weightedPriceSum / totalTaken;

      mixId = await t.insert('purchases', {
        'code': null,
        'category_id': categoryId,
        'type_name': typeName,
        'date': DateTime.now().toIso8601String(),
        'price': avgPrice,
        'total_weight': netWeight,
        'small_sack_count': smallSackCount,
        'large_sack_count': largeSackCount,
        'net_weight': netWeight,
        'remaining': netWeight,
        'is_mix': 1,
        'note': note,
      });
      await t.update('purchases', {'code': await _newCode(t, mixId)}, where: 'id=?', whereArgs: [mixId]);

      for (final s in sources) {
        final pid = s['purchase_id'] as int;
        final w = (s['weight'] as num).toDouble();
        if (w <= 0) continue;
        await t.rawUpdate('UPDATE purchases SET remaining = remaining - ? WHERE id = ?', [w, pid]);
        await t.insert('mix_sources', {
          'mix_purchase_id': mixId,
          'source_purchase_id': pid,
          'weight': w,
          'small_sacks': s['small_sacks'],
          'large_sacks': s['large_sacks'],
        });
      }
    });
    version.value++;
    return mixId;
  }

  /// حذف یک بار مخلوط: اگر چیزی از آن فروخته نشده باشد، وزن و گونیِ برداشته‌شده
  /// به بارهای مبدأ برمی‌گردد. اگر فروخته شده باشد حذف نمی‌شود.
  Future<bool> deleteMix(int mixPurchaseId) async {
    final d = await db;
    final used = await d.query('sale_items',
        where: 'purchase_id=?', whereArgs: [mixPurchaseId], limit: 1);
    if (used.isNotEmpty) return false;
    await d.transaction((t) async {
      final sources =
          await t.query('mix_sources', where: 'mix_purchase_id=?', whereArgs: [mixPurchaseId]);
      for (final s in sources) {
        await t.rawUpdate('UPDATE purchases SET remaining = remaining + ? WHERE id = ?',
            [s['weight'], s['source_purchase_id']]);
      }
      await t.delete('mix_sources', where: 'mix_purchase_id=?', whereArgs: [mixPurchaseId]);
      await t.delete('purchases', where: 'id=?', whereArgs: [mixPurchaseId]);
    });
    version.value++;
    return true;
  }

  Future<bool> updateMix({
    required int mixPurchaseId,
    required int categoryId,
    required String typeName,
    required List<Map<String, dynamic>> sources,
    required double netWeight,
    required double smallSackCount,
    required double largeSackCount,
    String? note,
  }) async {
    if (sources.isEmpty || netWeight <= 0) throw Exception('مشخصات مخلوط کامل نیست');
    final d = await db;
    var updated = false;
    await d.transaction((t) async {
      final old = await t.query('purchases', where: 'id=? AND is_mix=1', whereArgs: [mixPurchaseId]);
      if (old.isEmpty) return;
      final sold = (old.first['net_weight'] as num).toDouble() - (old.first['remaining'] as num).toDouble();
      if (sold > 0.0005) throw Exception('چون بخشی از مخلوط فروخته شده، ویرایش آن ممکن نیست');
      final oldSources = await t.query('mix_sources', where: 'mix_purchase_id=?', whereArgs: [mixPurchaseId]);
      for (final source in oldSources) {
        await t.rawUpdate('UPDATE purchases SET remaining = remaining + ? WHERE id = ?',
            [source['weight'], source['source_purchase_id']]);
      }
      double weightedPrice = 0;
      double totalTaken = 0;
      for (final source in sources) {
        final weight = (source['weight'] as num).toDouble();
        final rows = await t.query('purchases', columns: ['remaining', 'price'],
            where: 'id=?', whereArgs: [source['purchase_id']]);
        if (rows.isEmpty) throw Exception('جنس مبدأ یافت نشد');
        if (weight <= 0 || weight > (rows.first['remaining'] as num).toDouble() + 1e-6) {
          throw Exception('وزن برداشتی از موجودی بیشتر است');
        }
        weightedPrice += weight * (rows.first['price'] as num).toDouble();
        totalTaken += weight;
      }
      if (totalTaken <= 0) throw Exception('وزن مبدأ باید بیشتر از صفر باشد');
      await t.update('purchases', {
        'category_id': categoryId,
        'type_name': typeName,
        'price': weightedPrice / totalTaken,
        'total_weight': netWeight,
        'small_sack_count': smallSackCount,
        'large_sack_count': largeSackCount,
        'net_weight': netWeight,
        'remaining': netWeight,
        'note': note,
      }, where: 'id=?', whereArgs: [mixPurchaseId]);
      await t.delete('mix_sources', where: 'mix_purchase_id=?', whereArgs: [mixPurchaseId]);
      for (final source in sources) {
        final weight = (source['weight'] as num).toDouble();
        await t.rawUpdate('UPDATE purchases SET remaining = remaining - ? WHERE id = ?',
            [weight, source['purchase_id']]);
        await t.insert('mix_sources', {
          'mix_purchase_id': mixPurchaseId,
          'source_purchase_id': source['purchase_id'],
          'weight': weight,
          'small_sacks': source['small_sacks'],
          'large_sacks': source['large_sacks'],
        });
      }
      updated = true;
    });
    if (updated) version.value++;
    return updated;
  }

  // ---------- پرداخت (خرید) ----------
  Future<Map<String, dynamic>?> paymentOf(int purchaseId) async {
    final rows = await (await db).query('payments', where: 'purchase_id=?', whereArgs: [purchaseId]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> setPaymentType(int purchaseId, String payType, String? stagedType) async {
    final d = await db;
    final existing = await paymentOf(purchaseId);
    int payId;
    if (existing == null) {
      payId = await d.insert('payments',
          {'purchase_id': purchaseId, 'pay_type': payType, 'staged_type': stagedType});
    } else {
      payId = existing['id'] as int;
      await d.update('payments', {'pay_type': payType, 'staged_type': stagedType},
          where: 'id=?', whereArgs: [payId]);
    }
    version.value++;
    return payId;
  }

  Future<List<Map<String, dynamic>>> lumpTxList(int paymentId) async =>
      (await db).query('lump_tx', where: 'payment_id=?', whereArgs: [paymentId], orderBy: 'id');

  Future<int?> addLumpTx(int paymentId, Map<String, dynamic> row) async {
    final d = await db;
    final count = Sqflite.firstIntValue(await d.rawQuery(
            'SELECT COUNT(*) FROM lump_tx WHERE payment_id=?', [paymentId])) ??
        0;
    if (count >= kMaxLumpTx) return null;
    row['payment_id'] = paymentId;
    row.putIfAbsent('paid', () => 1);
    final id = await d.insert('lump_tx', row);
    version.value++;
    return id;
  }

  Future<void> updateLumpTx(int id, Map<String, dynamic> row) async {
    await (await db).update('lump_tx', row, where: 'id=?', whereArgs: [id]);
    version.value++;
  }

  Future<void> deleteLumpTx(int id) async {
    await (await db).delete('lump_tx', where: 'id=?', whereArgs: [id]);
    version.value++;
  }

  Future<List<Map<String, dynamic>>> creditInstList(int paymentId) async =>
      (await db).query('credit_inst', where: 'payment_id=?', whereArgs: [paymentId], orderBy: 'due_date');

  Future<int?> addCreditInst(int paymentId, Map<String, dynamic> row) async {
    final d = await db;
    final count = Sqflite.firstIntValue(await d.rawQuery(
            'SELECT COUNT(*) FROM credit_inst WHERE payment_id=?', [paymentId])) ??
        0;
    if (count >= kMaxStagedTx) return null;
    row['payment_id'] = paymentId;
    final id = await d.insert('credit_inst', row);
    version.value++;
    return id;
  }

  Future<void> updateCreditInst(int id, Map<String, dynamic> row) async {
    await (await db).update('credit_inst', row, where: 'id=?', whereArgs: [id]);
    version.value++;
  }

  Future<void> deleteCreditInst(int id) async {
    await (await db).delete('credit_inst', where: 'id=?', whereArgs: [id]);
    version.value++;
  }

  Future<List<Map<String, dynamic>>> chequeInstList(int paymentId) async =>
      (await db).query('cheque_inst', where: 'payment_id=?', whereArgs: [paymentId], orderBy: 'due_date');

  Future<int?> addChequeInst(int paymentId, Map<String, dynamic> row) async {
    final d = await db;
    final count = Sqflite.firstIntValue(await d.rawQuery(
            'SELECT COUNT(*) FROM cheque_inst WHERE payment_id=?', [paymentId])) ??
        0;
    if (count >= kMaxStagedTx) return null;
    row['payment_id'] = paymentId;
    final id = await d.insert('cheque_inst', row);
    version.value++;
    return id;
  }

  Future<void> updateChequeInst(int id, Map<String, dynamic> row) async {
    await (await db).update('cheque_inst', row, where: 'id=?', whereArgs: [id]);
    version.value++;
  }

  Future<void> deleteChequeInst(int id) async {
    await (await db).delete('cheque_inst', where: 'id=?', whereArgs: [id]);
    version.value++;
  }

  /// همه اقساط/چک‌های پرداخت‌نشده (برای زمان‌بندی نوتیفیکیشن هنگام باز شدن برنامه)
  Future<List<Map<String, dynamic>>> unpaidCreditInst() async =>
      (await db).query('credit_inst', where: 'paid=0');

  Future<List<Map<String, dynamic>>> unpaidChequeInst() async =>
      (await db).query('cheque_inst', where: 'paid=0');

  // ---------- وصول مطالبات (دریافت وجه فروش) ----------
  Future<Map<String, dynamic>?> receiptOf(int saleId) async {
    final rows = await (await db).query('receipts', where: 'sale_id=?', whereArgs: [saleId]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> setReceiptType(int saleId, String recvType, String? stagedType) async {
    final d = await db;
    final existing = await receiptOf(saleId);
    int rid;
    if (existing == null) {
      rid = await d.insert('receipts',
          {'sale_id': saleId, 'recv_type': recvType, 'staged_type': stagedType});
    } else {
      rid = existing['id'] as int;
      await d.update('receipts', {'recv_type': recvType, 'staged_type': stagedType},
          where: 'id=?', whereArgs: [rid]);
    }
    version.value++;
    return rid;
  }

  Future<List<Map<String, dynamic>>> receiptLumpTxList(int receiptId) async => (await db)
      .query('receipt_lump_tx', where: 'receipt_id=?', whereArgs: [receiptId], orderBy: 'id');

  Future<int?> addReceiptLumpTx(int receiptId, Map<String, dynamic> row) async {
    final d = await db;
    final count = Sqflite.firstIntValue(await d.rawQuery(
            'SELECT COUNT(*) FROM receipt_lump_tx WHERE receipt_id=?', [receiptId])) ??
        0;
    if (count >= kMaxLumpTx) return null;
    row['receipt_id'] = receiptId;
    row.putIfAbsent('paid', () => 1);
    final id = await d.insert('receipt_lump_tx', row);
    version.value++;
    return id;
  }

  Future<void> updateReceiptLumpTx(int id, Map<String, dynamic> row) async {
    await (await db).update('receipt_lump_tx', row, where: 'id=?', whereArgs: [id]);
    version.value++;
  }

  Future<void> deleteReceiptLumpTx(int id) async {
    await (await db).delete('receipt_lump_tx', where: 'id=?', whereArgs: [id]);
    version.value++;
  }

  Future<List<Map<String, dynamic>>> receiptCreditInstList(int receiptId) async => (await db).query(
      'receipt_credit_inst', where: 'receipt_id=?', whereArgs: [receiptId], orderBy: 'due_date');

  Future<int?> addReceiptCreditInst(int receiptId, Map<String, dynamic> row) async {
    final d = await db;
    final count = Sqflite.firstIntValue(await d.rawQuery(
            'SELECT COUNT(*) FROM receipt_credit_inst WHERE receipt_id=?', [receiptId])) ??
        0;
    if (count >= kMaxStagedTx) return null;
    row['receipt_id'] = receiptId;
    final id = await d.insert('receipt_credit_inst', row);
    version.value++;
    return id;
  }

  Future<void> updateReceiptCreditInst(int id, Map<String, dynamic> row) async {
    await (await db).update('receipt_credit_inst', row, where: 'id=?', whereArgs: [id]);
    version.value++;
  }

  Future<void> deleteReceiptCreditInst(int id) async {
    await (await db).delete('receipt_credit_inst', where: 'id=?', whereArgs: [id]);
    version.value++;
  }

  Future<List<Map<String, dynamic>>> receiptChequeInstList(int receiptId) async => (await db).query(
      'receipt_cheque_inst', where: 'receipt_id=?', whereArgs: [receiptId], orderBy: 'due_date');

  Future<int?> addReceiptChequeInst(int receiptId, Map<String, dynamic> row) async {
    final d = await db;
    final count = Sqflite.firstIntValue(await d.rawQuery(
            'SELECT COUNT(*) FROM receipt_cheque_inst WHERE receipt_id=?', [receiptId])) ??
        0;
    if (count >= kMaxStagedTx) return null;
    row['receipt_id'] = receiptId;
    final id = await d.insert('receipt_cheque_inst', row);
    version.value++;
    return id;
  }

  Future<void> updateReceiptChequeInst(int id, Map<String, dynamic> row) async {
    await (await db).update('receipt_cheque_inst', row, where: 'id=?', whereArgs: [id]);
    version.value++;
  }

  Future<void> deleteReceiptChequeInst(int id) async {
    await (await db).delete('receipt_cheque_inst', where: 'id=?', whereArgs: [id]);
    version.value++;
  }

  Future<List<Map<String, dynamic>>> unpaidReceiptCreditInst() async =>
      (await db).query('receipt_credit_inst', where: 'paid=0');

  Future<List<Map<String, dynamic>>> unpaidReceiptChequeInst() async =>
      (await db).query('receipt_cheque_inst', where: 'paid=0');

  // ---------- فروش ----------
  Future<List<Map<String, dynamic>>> sales() async {
    final d = await db;
    final rows = await d.query('sales', orderBy: 'id DESC');
    final out = <Map<String, dynamic>>[];
    for (final s in rows) {
      final items = await d.rawQuery('''
        SELECT si.weight, si.item_price, p.price AS cost_price, p.type_name AS type_name, c.name AS category_name
        FROM sale_items si
        JOIN purchases p ON p.id = si.purchase_id
        JOIN categories c ON c.id = p.category_id
        WHERE si.sale_id = ?''', [s['id']]);
      out.add({...s, 'items': items});
    }
    return out;
  }

  Future<Map<String, dynamic>?> saleById(int id) async {
    final rows = await (await db).query('sales', where: 'id=?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  /// در صورت کمبود موجودیِ یکی از اقلام، خطا دقیقاً نام همان جنس را اعلام می‌کند
  Future<void> _applySaleItems(DatabaseExecutor t, int saleId, List<Map<String, dynamic>> items) async {
    for (final it in items) {
      final rows = await t.rawQuery('''
          SELECT p.remaining, p.type_name, c.name AS category_name
          FROM purchases p JOIN categories c ON c.id = p.category_id
          WHERE p.id = ?''', [it['purchase_id']]);
      if (rows.isEmpty) throw Exception('خرید مرتبط یافت نشد');
      final rem = (rows.first['remaining'] as num).toDouble();
      final w = (it['weight'] as num).toDouble();
      if (w > rem + 1e-6) {
        final label = '${rows.first['type_name']} (${rows.first['category_name']})';
        throw Exception('موجودی «$label» کافی نیست؛ فقط ${_fmt(rem)} کیلو باقی مانده');
      }
      await t.insert('sale_items', {
        'sale_id': saleId,
        'purchase_id': it['purchase_id'],
        'weight': w,
        'item_price': it['item_price'],
        'small_sacks': it['small_sacks'],
        'large_sacks': it['large_sacks'],
      });
      await t.update('purchases', {'remaining': math.max(0.0, rem - w)},
          where: 'id=?', whereArgs: [it['purchase_id']]);
    }
  }

  static String _fmt(double v) {
    var s = v.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    return s;
  }

  Future<void> insertSale(Map<String, dynamic> sale, List<Map<String, dynamic>> items) async {
    final d = await db;
    await d.transaction((t) async {
      final sid = await t.insert('sales', sale);
      await _applySaleItems(t, sid, items);
    });
    version.value++;
  }

  /// ویرایش فروش: تخصیص‌های قبلی به انبار برمی‌گردد، سپس ترکیب جدید اعمال می‌شود
  Future<void> updateSale(
      int saleId, Map<String, dynamic> sale, List<Map<String, dynamic>> items) async {
    final d = await db;
    await d.transaction((t) async {
      final oldItems = await t.query('sale_items', where: 'sale_id=?', whereArgs: [saleId]);
      for (final it in oldItems) {
        await t.rawUpdate('UPDATE purchases SET remaining = remaining + ? WHERE id = ?',
            [it['weight'], it['purchase_id']]);
      }
      await t.delete('sale_items', where: 'sale_id=?', whereArgs: [saleId]);
      await _applySaleItems(t, saleId, items);
      if (sale.isNotEmpty) {
        await t.update('sales', sale, where: 'id=?', whereArgs: [saleId]);
      }
    });
    version.value++;
  }

  /// حذف فروش و برگرداندن وزن‌ها به انبار
  Future<void> deleteSale(int id) async {
    final d = await db;
    await d.transaction((t) async {
      final items = await t.query('sale_items', where: 'sale_id=?', whereArgs: [id]);
      for (final it in items) {
        await t.rawUpdate('UPDATE purchases SET remaining = remaining + ? WHERE id = ?',
            [it['weight'], it['purchase_id']]);
      }
      await t.delete('sale_items', where: 'sale_id=?', whereArgs: [id]);
      await t.delete('sales', where: 'id=?', whereArgs: [id]);
      final r = await t.query('receipts', where: 'sale_id=?', whereArgs: [id]);
      if (r.isNotEmpty) {
        final rid = r.first['id'] as int;
        await t.delete('receipt_lump_tx', where: 'receipt_id=?', whereArgs: [rid]);
        await t.delete('receipt_credit_inst', where: 'receipt_id=?', whereArgs: [rid]);
        await t.delete('receipt_cheque_inst', where: 'receipt_id=?', whereArgs: [rid]);
        await t.delete('receipts', where: 'id=?', whereArgs: [rid]);
      }
    });
    version.value++;
  }

  // ---------- سررسید و حساب طرف‌ها ----------
  static const Set<String> _paidTables = {
    'lump_tx',
    'credit_inst',
    'cheque_inst',
    'receipt_lump_tx',
    'receipt_credit_inst',
    'receipt_cheque_inst',
  };

  /// وضعیت «پرداخت/دریافت شد» یک تراکنش (یکجا، قسط یا چک) را عوض می‌کند
  Future<void> setPaid(String table, int id, bool paid) async {
    if (!_paidTables.contains(table)) throw ArgumentError('جدول نامعتبر');
    await (await db).update(table, {'paid': paid ? 1 : 0}, where: 'id=?', whereArgs: [id]);
    version.value++;
  }

  /// نام همه‌ی فروشنده‌ها و خریدارهای ثبت‌شده (برای پیشنهاد خودکار هنگام تایپ)
  Future<List<String>> partyNames() async {
    final rows = await (await db).rawQuery(
        "SELECT TRIM(seller) AS n FROM purchases WHERE seller IS NOT NULL AND TRIM(seller) <> '' "
        "UNION SELECT TRIM(buyer) FROM sales WHERE buyer IS NOT NULL AND TRIM(buyer) <> '' "
        "ORDER BY 1");
    return rows.map((r) => (r['n'] as String)).toList();
  }

  /// آیا هنوز هیچ خرید یا فروشی ثبت نشده؟
  Future<bool> isEmpty() async {
    final n = Sqflite.firstIntValue(await (await db).rawQuery(
            'SELECT (SELECT COUNT(*) FROM purchases) + (SELECT COUNT(*) FROM sales)')) ??
        0;
    return n == 0;
  }

  // ---------- گزارش کلی تراکنش‌ها (برای خروجی PDF) ----------
  Future<List<Map<String, dynamic>>> allPaymentTransactions({DateTime? from, DateTime? to}) async {
    final d = await db;
    final out = <Map<String, dynamic>>[];
    final lumps = await d.rawQuery('''
        SELECT lt.date AS date, lt.amount AS amount, lt.paid AS paid,
               p.type_name AS type_name, c.name AS category_name
        FROM lump_tx lt
        JOIN payments pay ON pay.id = lt.payment_id
        JOIN purchases p ON p.id = pay.purchase_id
        JOIN categories c ON c.id = p.category_id''');
    for (final r in lumps) {
      out.add({
        'kind': 'یکجا',
        'date': r['date'],
        'amount': r['amount'],
        'paid': (r['paid'] as int?) ?? 1,
        'label': '${r['type_name']} (${r['category_name']})',
      });
    }
    final credits = await d.rawQuery('''
        SELECT ci.due_date AS date, ci.amount AS amount, ci.paid AS paid,
               p.type_name AS type_name, c.name AS category_name
        FROM credit_inst ci
        JOIN payments pay ON pay.id = ci.payment_id
        JOIN purchases p ON p.id = pay.purchase_id
        JOIN categories c ON c.id = p.category_id''');
    for (final r in credits) {
      out.add({
        'kind': 'قسط',
        'date': r['date'],
        'amount': r['amount'],
        'paid': r['paid'],
        'label': '${r['type_name']} (${r['category_name']})',
      });
    }
    final cheques = await d.rawQuery('''
        SELECT chi.due_date AS date, chi.amount AS amount, chi.paid AS paid,
               p.type_name AS type_name, c.name AS category_name
        FROM cheque_inst chi
        JOIN payments pay ON pay.id = chi.payment_id
        JOIN purchases p ON p.id = pay.purchase_id
        JOIN categories c ON c.id = p.category_id''');
    for (final r in cheques) {
      out.add({
        'kind': 'چک',
        'date': r['date'],
        'amount': r['amount'],
        'paid': r['paid'],
        'label': '${r['type_name']} (${r['category_name']})',
      });
    }
    return _filterAndSort(out, from, to);
  }

  Future<List<Map<String, dynamic>>> allReceiptTransactions({DateTime? from, DateTime? to}) async {
    final d = await db;
    final out = <Map<String, dynamic>>[];
    final lumps = await d.rawQuery('''
        SELECT lt.date AS date, lt.amount AS amount, lt.paid AS paid, s.buyer AS buyer
        FROM receipt_lump_tx lt
        JOIN receipts rec ON rec.id = lt.receipt_id
        JOIN sales s ON s.id = rec.sale_id''');
    for (final r in lumps) {
      out.add({
        'kind': 'یکجا',
        'date': r['date'],
        'amount': r['amount'],
        'paid': (r['paid'] as int?) ?? 1,
        'label': (r['buyer'] as String?) ?? '-',
      });
    }
    final credits = await d.rawQuery('''
        SELECT ci.due_date AS date, ci.amount AS amount, ci.paid AS paid, s.buyer AS buyer
        FROM receipt_credit_inst ci
        JOIN receipts rec ON rec.id = ci.receipt_id
        JOIN sales s ON s.id = rec.sale_id''');
    for (final r in credits) {
      out.add({
        'kind': 'قسط',
        'date': r['date'],
        'amount': r['amount'],
        'paid': r['paid'],
        'label': (r['buyer'] as String?) ?? '-',
      });
    }
    final cheques = await d.rawQuery('''
        SELECT chi.due_date AS date, chi.amount AS amount, chi.paid AS paid, s.buyer AS buyer
        FROM receipt_cheque_inst chi
        JOIN receipts rec ON rec.id = chi.receipt_id
        JOIN sales s ON s.id = rec.sale_id''');
    for (final r in cheques) {
      out.add({
        'kind': 'چک',
        'date': r['date'],
        'amount': r['amount'],
        'paid': r['paid'],
        'label': (r['buyer'] as String?) ?? '-',
      });
    }
    return _filterAndSort(out, from, to);
  }

  List<Map<String, dynamic>> _filterAndSort(
      List<Map<String, dynamic>> rows, DateTime? from, DateTime? to) {
    var filtered = rows;
    if (from != null || to != null) {
      filtered = rows.where((r) {
        final dt = DateTime.parse(r['date'] as String);
        if (from != null && dt.isBefore(from)) return false;
        if (to != null && dt.isAfter(to)) return false;
        return true;
      }).toList();
    }
    filtered.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    return filtered;
  }
}
