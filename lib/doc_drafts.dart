import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show Database;

import 'db.dart';
import 'purchase_form.dart' show PurchaseForm; // v87
import 'sale_form.dart' show SaleForm; // v94
import 'utils.dart';
import 'widgets.dart';

/// S35.T35.9b — پیش‌نویس سند (فقط محلی، بدون هیچ اثر انباری/مالی).
/// پیش‌نویس یک عکس‌فوری از داده‌های فرم است؛ «ثبت نهایی» همان مسیر ثبتِ معمولی (insertPurchase) را اجرا می‌کند.
class DocDraftsLocal {
  DocDraftsLocal._();

  static Future<Database> _d() async {
    final Database d = await AppDb.I.db;
    await d.execute('''
      CREATE TABLE IF NOT EXISTS doc_drafts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_type TEXT NOT NULL,
        title TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      )''');
    return d;
  }

  static Future<int> save(String docType, String title, Map<String, dynamic> payload) async {
    final Database d = await _d();
    final Map<String, dynamic> clean = Map<String, dynamic>.from(payload)..remove('photo');
    return d.insert('doc_drafts', <String, Object?>{
      'doc_type': docType,
      'title': title,
      'payload': jsonEncode(clean),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, Object?>>> list(String docType) async {
    final Database d = await _d();
    return d.query('doc_drafts', where: 'doc_type = ?', whereArgs: <Object?>[docType], orderBy: 'id DESC');
  }

  static Future<void> delete(int id) async {
    final Database d = await _d();
    await d.delete('doc_drafts', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  static Map<String, dynamic> decode(Map<String, Object?> row) =>
      Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map<dynamic, dynamic>);

  /// v87: «ذخیرهٔ خودکار» هنگام ترک فرم (یک ردیف برای هر نوع سند؛ ردیف قبلی جایگزین می‌شود).
  static const String autoTitle = 'ذخیرهٔ خودکار';
  static Future<void> autosave(String docType, String title, Map<String, dynamic> payload) async {
    try {
      final Database d = await _d();
      await d.delete('doc_drafts', where: 'doc_type = ? AND title LIKE ?', whereArgs: <Object?>[docType, '$autoTitle%']);
      await save(docType, '$autoTitle — $title', payload);
    } catch (_) {
      // ذخیرهٔ خودکار هرگز نباید خطا بدهد
    }
  }

  /// v87: ذخیرهٔ دستی با جایگزینی پیش‌نویسِ بازشده (id) و حذف ذخیرهٔ خودکار همان نوع.
  static Future<int> saveOrReplace(String docType, String title, Map<String, dynamic> payload, {int? replaceId}) async {
    final Database d = await _d();
    if (replaceId != null) await d.delete('doc_drafts', where: 'id = ?', whereArgs: <Object?>[replaceId]);
    await d.delete('doc_drafts', where: 'doc_type = ? AND title LIKE ?', whereArgs: <Object?>[docType, '$autoTitle%']);
    return save(docType, title, payload);
  }
}

/// v87: انتخاب پیش‌نویس یک نوع سند (پایین‌برگه) ⇒ {id, payload} یا null. حذف هم از همین‌جا.
Future<({int id, Map<String, dynamic> data})?> pickDocDraft(BuildContext context, String docType, {String title = 'پیش‌نویس‌ها'}) async {
  List<Map<String, Object?>> rows = await DocDraftsLocal.list(docType);
  if (!context.mounted) return null;
  return showModalBottomSheet<({int id, Map<String, dynamic> data})>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => StatefulBuilder(
      builder: (BuildContext ctx, StateSetter set) => SafeArea(
        child: ListView(shrinkWrap: true, children: <Widget>[
          ListTile(title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
          if (rows.isEmpty) const ListTile(title: Text('پیش‌نویسی وجود ندارد')),
          for (final Map<String, Object?> r in rows)
            ListTile(
              leading: Icon('${r['title']}'.startsWith(DocDraftsLocal.autoTitle) ? Icons.history : Icons.edit_note),
              title: Text('${r['title']}'),
              subtitle: Text('ذخیره: ${jalaliDate('${r['created_at']}')}'),
              onTap: () => Navigator.pop(ctx, (id: r['id'] as int, data: DocDraftsLocal.decode(r))),
              trailing: IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await DocDraftsLocal.delete(r['id'] as int);
                  rows = await DocDraftsLocal.list(docType);
                  set(() {});
                },
              ),
            ),
        ]),
      ),
    ),
  );
}

/// v87: کادر «پیش‌نویس ذخیره‌شده دارید» بالای فرم تازه (بازیابی / حذف).
class DraftRestoreBanner extends StatefulWidget {
  const DraftRestoreBanner({super.key, required this.docType, required this.onRestore});
  final String docType;
  final void Function(int id, Map<String, dynamic> data) onRestore;

  @override
  State<DraftRestoreBanner> createState() => _DraftRestoreBannerState();
}

class _DraftRestoreBannerState extends State<DraftRestoreBanner> {
  Map<String, Object?>? _row;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    DocDraftsLocal.list(widget.docType).then((List<Map<String, Object?>> r) {
      if (!mounted) return;
      setState(() {
        _row = r.isEmpty ? null : r.first;
        _count = r.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, Object?>? r = _row;
    if (r == null) return const SizedBox.shrink();
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(children: <Widget>[
          const Icon(Icons.history),
          const SizedBox(width: 8),
          Expanded(child: Text('پیش‌نویس ذخیره‌شده دارید: ${r['title']}${_count > 1 ? ' (و ${toFaDigits('${_count - 1}')} پیش‌نویس دیگر)' : ''}')),
          TextButton(
            onPressed: () {
              widget.onRestore(r['id'] as int, DocDraftsLocal.decode(r));
              setState(() => _row = null);
            },
            child: const Text('ادامه'),
          ),
          TextButton(onPressed: () => setState(() => _row = null), child: const Text('بستن')),
        ]),
      ),
    );
  }
}

/// لیست پیش‌نویس‌های خرید یا فروش (docType = purchase | sale) با «ثبت نهایی» و حذف.
class DraftsScreen extends StatefulWidget {
  const DraftsScreen({super.key, required this.docType});
  final String docType;

  @override
  State<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends State<DraftsScreen> {
  List<Map<String, Object?>> _rows = <Map<String, Object?>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<Map<String, Object?>> r = await DocDraftsLocal.list(widget.docType);
    if (!mounted) return;
    setState(() {
      _rows = r;
      _loading = false;
    });
  }

  Future<void> _finalize(Map<String, Object?> row) async {
    if (!await confirm(context, 'این پیش‌نویس به‌صورت نهایی ثبت شود؟ موجودی انبار و حساب‌ها تغییر می‌کند.')) return;
    final Map<String, dynamic> data = DocDraftsLocal.decode(row);
    try {
      if (widget.docType == 'sale') {
        final Map<String, dynamic> sale = Map<String, dynamic>.from(data['sale'] as Map<dynamic, dynamic>);
        final List<Map<String, dynamic>> items = (data['items'] as List<dynamic>)
            .map((dynamic e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
            .toList();
        sale['date'] = DateTime.now().toIso8601String();
        await AppDb.I.insertSale(sale, items);
      } else {
        data['date'] = DateTime.now().toIso8601String();
        await AppDb.I.insertPurchase(data);
      }
      await DocDraftsLocal.delete(row['id'] as int);
      if (mounted) snack(context, 'پیش‌نویس به‌صورت نهایی ثبت شد');
    } catch (e) {
      if (mounted) snack(context, 'ثبت نهایی انجام نشد: $e');
    }
    await _load();
  }

  Future<void> _remove(Map<String, Object?> row) async {
    if (!await confirm(context, 'این پیش‌نویس حذف شود؟')) return;
    await DocDraftsLocal.delete(row['id'] as int);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.docType == 'sale' ? 'پیش‌نویس‌های فروش' : 'پیش‌نویس‌های خرید')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(child: Text('پیش‌نویسی وجود ندارد'))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: <Widget>[
                    for (final Map<String, Object?> r in _rows)
                      Card(
                        child: ListTile(
                          onTap: () async { // v87: ادامهٔ پیش‌نویس در فرم خرید · v94: و فرم فروش
                            await Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                    builder: (_) => widget.docType == 'sale'
                                        ? SaleForm(draft: DocDraftsLocal.decode(r), draftId: r['id'] as int)
                                        : PurchaseForm(draft: DocDraftsLocal.decode(r), draftId: r['id'] as int)));
                            await _load();
                          },
                          title: Text('${r['title']}'),
                          subtitle: Text('ذخیره: ${jalaliDate('${r['created_at']}')}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                            if (widget.docType != 'sale' || DocDraftsLocal.decode(r)['sale'] is Map) // v94: پیش‌نویس ناقص فروش ⇒ فقط ادامه در فرم
                              IconButton(tooltip: 'ثبت نهایی', icon: const Icon(Icons.check_circle_outline), onPressed: () => _finalize(r)),
                            IconButton(tooltip: 'حذف', icon: const Icon(Icons.delete_outline), onPressed: () => _remove(r)),
                          ]),
                        ),
                      ),
                  ],
                ),
    );
  }
}
