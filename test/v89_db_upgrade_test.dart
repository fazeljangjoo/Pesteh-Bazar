import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('v89: a current local database whose version was set back by an older build still upgrades', () async {
    final Database d = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDb.I.debugCreate(d); // همهٔ ستون‌ها از قبل هست (warehouse_uid، stock_hold، …)
    for (final int oldV in <int>[7, 15, 20, 30]) {
      await AppDb.I.debugUpgrade(d, oldV); // قبلاً: duplicate column name: warehouse_uid
    }
    final List<String> cols = <String>[for (final Map<String, Object?> c in await d.rawQuery('PRAGMA table_info(purchases)')) '${c['name']}'];
    expect(cols, containsAll(<String>['warehouse_uid', 'small_sacks_remaining', 'stock_hold']));
    await d.close();
  });
}
