import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// دسته‌بندی‌های پسته
const Map<String, String> kCategories = {
  'dombest': 'پسته دنبست',
  'khandan': 'پسته خندان',
  'kernel': 'پسته رومیدانی (مغز)',
};

const Map<String, List<String>> _defaultTypes = {
  'dombest': ['اکبری', 'احمدآقایی', 'فندقی'],
  'khandan': ['اکبری', 'احمدآقایی', 'فندقی'],
  'kernel': ['مغز کال', 'مغز سبز', 'مغز یک', 'مغز دو', 'مغز نخودی'],
};

class AppDb {
  AppDb._();
  static final AppDb I = AppDb._();

  /// با هر تغییر داده زیاد می‌شود تا صفحه‌ها بازخوانی شوند
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  Database? _db;
  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'pesteh_bazar.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE types(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT NOT NULL,
            name TEXT NOT NULL
          )''');
        await d.execute('''
          CREATE TABLE purchases(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type_id INTEGER NOT NULL,
            date TEXT NOT NULL,
            photo TEXT,
            ounce REAL,
            price REAL NOT NULL,
            total_weight REAL NOT NULL,
            sack_count REAL NOT NULL,
            sack_weight REAL NOT NULL,
            net_weight REAL NOT NULL,
            remaining REAL NOT NULL,
            gram REAL,
            pct_dombest REAL,
            pct_tuchin REAL,
            pct_crooked REAL,
            pct_khandan REAL,
            seller TEXT,
            note TEXT
          )''');
        await d.execute('''
          CREATE TABLE sales(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,
            price REAL NOT NULL,
            total_weight REAL NOT NULL,
            sack_count REAL NOT NULL,
            sack_weight REAL NOT NULL,
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
        for (final e in _defaultTypes.entries) {
          for (final n in e.value) {
            await d.insert('types', {'category': e.key, 'name': n});
          }
        }
      },
    );
  }

  // ---------- انواع پسته ----------
  Future<List<Map<String, dynamic>>> types() async =>
      (await db).query('types', orderBy: 'id');

  Future<int> addType(String category, String name) async {
    final id = await (await db).insert('types', {'category': category, 'name': name});
    version.value++;
    return id;
  }

  // ---------- خرید ----------
  Future<List<Map<String, dynamic>>> purchases() async => (await db).rawQuery('''
        SELECT p.*, t.name AS type_name, t.category AS category
        FROM purchases p JOIN types t ON t.id = p.type_id
        ORDER BY p.id DESC''');

  Future<void> insertPurchase(Map<String, dynamic> p) async {
    p['remaining'] = p['net_weight'];
    await (await db).insert('purchases', p);
    version.value++;
  }

  /// اگر از این خرید فروشی انجام شده باشد حذف نمی‌شود
  Future<bool> deletePurchase(int id) async {
    final d = await db;
    final used = await d.query('sale_items', where: 'purchase_id=?', whereArgs: [id], limit: 1);
    if (used.isNotEmpty) return false;
    await d.delete('purchases', where: 'id=?', whereArgs: [id]);
    version.value++;
    return true;
  }

  // ---------- موجودی ----------
  Future<List<Map<String, dynamic>>> lots() async => (await db).rawQuery('''
        SELECT p.*, t.name AS type_name, t.category AS category
        FROM purchases p JOIN types t ON t.id = p.type_id
        WHERE p.remaining > 0.0005
        ORDER BY t.category, t.name, p.id''');

  // ---------- فروش ----------
  Future<List<Map<String, dynamic>>> sales() async {
    final d = await db;
    final rows = await d.query('sales', orderBy: 'id DESC');
    final out = <Map<String, dynamic>>[];
    for (final s in rows) {
      final items = await d.rawQuery('''
        SELECT si.weight, p.price AS cost_price, t.name AS type_name, t.category AS category
        FROM sale_items si
        JOIN purchases p ON p.id = si.purchase_id
        JOIN types t ON t.id = p.type_id
        WHERE si.sale_id = ?''', [s['id']]);
      out.add({...s, 'items': items});
    }
    return out;
  }

  Future<void> insertSale(Map<String, dynamic> sale, List<Map<String, dynamic>> items) async {
    final d = await db;
    await d.transaction((t) async {
      final sid = await t.insert('sales', sale);
      for (final it in items) {
        final rows = await t.query('purchases',
            columns: ['remaining'], where: 'id=?', whereArgs: [it['purchase_id']]);
        final rem = (rows.first['remaining'] as num).toDouble();
        final w = it['weight'] as double;
        if (w > rem + 1e-6) throw Exception('موجودی کافی نیست');
        await t.insert('sale_items',
            {'sale_id': sid, 'purchase_id': it['purchase_id'], 'weight': w});
        await t.update('purchases', {'remaining': math.max(0.0, rem - w)},
            where: 'id=?', whereArgs: [it['purchase_id']]);
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
    });
    version.value++;
  }
}
