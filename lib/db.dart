import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
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

  Database? _db;
  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'pesteh_bazar_v2.db');
    return openDatabase(path, version: 2, onCreate: _onCreate, onUpgrade: _onUpgrade);
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
        note TEXT
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
        weight REAL NOT NULL
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
  Future<List<Map<String, dynamic>>> purchases() async => (await db).rawQuery('''
        SELECT p.*, c.name AS category_name, c.preset_key AS category_preset
        FROM purchases p JOIN categories c ON c.id = p.category_id
        ORDER BY p.id DESC''');

  Future<Map<String, dynamic>?> purchaseById(int id) async {
    final rows = await (await db).rawQuery('''
        SELECT p.*, c.name AS category_name, c.preset_key AS category_preset
        FROM purchases p JOIN categories c ON c.id = p.category_id
        WHERE p.id = ?''', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> insertPurchase(Map<String, dynamic> p) async {
    p['remaining'] = p['net_weight'];
    final id = await (await db).insert('purchases', p);
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

  /// اگر از این خرید فروشی انجام شده باشد حذف نمی‌شود
  Future<bool> deletePurchase(int id) async {
    final d = await db;
    final used = await d.query('sale_items', where: 'purchase_id=?', whereArgs: [id], limit: 1);
    if (used.isNotEmpty) return false;
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
  Future<List<Map<String, dynamic>>> lots() async => (await db).rawQuery('''
        SELECT p.*, c.name AS category_name, c.preset_key AS category_preset
        FROM purchases p JOIN categories c ON c.id = p.category_id
        WHERE p.remaining > 0.0005
        ORDER BY c.name, p.type_name, p.id''');

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
        SELECT si.weight, p.price AS cost_price, p.type_name AS type_name, c.name AS category_name
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
      await t.insert('sale_items', {'sale_id': saleId, 'purchase_id': it['purchase_id'], 'weight': w});
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
