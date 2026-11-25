// v91 p3 — ویرایش فروش قدیمیِ چندقلمی (قبلاً «قابل ویرایش نیست»). فایل مشترک اندروید و ویندوز.
// هر قلم: وزن و فی؛ و خریدار، توضیحات، هزینهٔ کارگر/حمل. گونی هر قلم همان مقدار ثبت‌شده می‌ماند.
// سرور (sales.update با items چندتایی) اقلام را برمی‌گرداند و دوباره برمی‌دارد؛ بهای تمام‌شده و سند حسابداری دوباره ثبت می‌شود.
import 'package:flutter/material.dart';

import 'db.dart';
import 'doc_actions_ui.dart' show LockedFormBanner, LockedFields, SaleDocActions, canUnlockSale;
import 'fmt.dart' show MoneyField;
import 'perms.dart';
import 'utils.dart';
import 'widgets.dart';

class LegacySaleForm extends StatefulWidget {
  const LegacySaleForm({super.key, required this.saleId, this.locked = false, this.doc});
  final int saleId;
  final bool locked;
  final Map<String, dynamic>? doc;
  @override
  State<LegacySaleForm> createState() => _LegacySaleFormState();
}

class _Line {
  _Line(this.row);
  final Map<String, dynamic> row;
  final TextEditingController kg = TextEditingController();
  final TextEditingController price = TextEditingController();
}

class _LegacySaleFormState extends State<LegacySaleForm> {
  late bool _viewOnly = widget.locked;
  bool _loading = true, _saving = false;
  final List<_Line> _lines = <_Line>[];
  final TextEditingController _buyer = TextEditingController(), _note = TextEditingController(), _labor = TextEditingController(), _transport = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final _Line l in _lines) {
      l.kg.dispose();
      l.price.dispose();
    }
    _buyer.dispose();
    _note.dispose();
    _labor.dispose();
    _transport.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final d = await AppDb.I.db;
    final rows = await d.rawQuery('SELECT si.*, p.code AS code, p.type_name AS type_name FROM sale_items si LEFT JOIN purchases p ON p.id=si.purchase_id WHERE si.sale_id=? ORDER BY si.id', <Object?>[widget.saleId]);
    final sale = await AppDb.I.saleById(widget.saleId);
    if (!mounted) return;
    setState(() {
      for (final r in rows) {
        final _Line l = _Line(Map<String, dynamic>.from(r));
        l.kg.text = plain((r['weight'] as num?) ?? 0);
        MoneyField.setStored(l.price, ((r['item_price'] as num?) ?? (sale?['price'] as num?) ?? 0));
        _lines.add(l);
      }
      _buyer.text = (sale?['buyer'] as String?) ?? '';
      _note.text = (sale?['note'] as String?) ?? '';
      MoneyField.setStored(_labor, sale?['labor_cost'] as num?);
      MoneyField.setStored(_transport, sale?['transport_cost'] as num?);
      _loading = false;
    });
  }

  Future<void> _save() async {
    final items = <Map<String, dynamic>>[];
    double sumW = 0, sumV = 0, small = 0, large = 0;
    for (final _Line l in _lines) {
      final double w = parseNum(l.kg.text) ?? 0;
      final double p = (MoneyField.stored(l.price) ?? 0).toDouble();
      if (w <= 0) return snack(context, 'وزن هر قلم باید بیشتر از صفر باشد');
      if (p <= 0) return snack(context, 'فی هر قلم را وارد کنید');
      final double ss = ((l.row['small_sacks'] as num?) ?? 0).toDouble(), ls = ((l.row['large_sacks'] as num?) ?? 0).toDouble();
      items.add(<String, dynamic>{'purchase_id': l.row['purchase_id'], 'weight': w, 'item_price': p, 'small_sacks': l.row['small_sacks'], 'large_sacks': l.row['large_sacks'], if (l.row['warehouse_uid'] != null) 'warehouse_uid': l.row['warehouse_uid']});
      sumW += w; sumV += w * p; small += ss; large += ls;
    }
    if (items.isEmpty) return;
    final data = <String, dynamic>{
      'price': sumV / sumW,
      'total_weight': sumW + small * 0.1 + large * 0.2,
      'small_sack_count': small,
      'large_sack_count': large,
      'buyer': _buyer.text.trim().isEmpty ? null : _buyer.text.trim(),
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      'labor_cost': MoneyField.stored(_labor),
      'transport_cost': MoneyField.stored(_transport),
    };
    setState(() => _saving = true);
    final bool ok = await saveConfirmed(context, () => AppDb.I.updateSale(widget.saleId, data, items), successMsg: 'ویرایش فروش با موفقیت ثبت شد');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> fields = <Widget>[
      sectionTitle(context, 'اقلام این فروش (فروش قدیمیِ چندقلمی)'),
      for (final _Line l in _lines)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Text('${l.row['type_name'] ?? ''}  •  کد ${l.row['code'] ?? '-'}', style: Theme.of(context).textTheme.titleSmall),
              Row(children: <Widget>[
                Expanded(child: numField(l.kg, 'وزن خالص (کیلو)')),
                const SizedBox(width: 8),
                if (StaffPerms.I.canPriceIn('sales')) Expanded(child: MoneyField(controller: l.price, label: 'فی هر کیلو')),
              ]),
            ]),
          ),
        ),
      textField(_buyer, 'خریدار (اختیاری)'),
      textField(_note, 'توضیحات (اختیاری)', lines: 2),
      MoneyField(controller: _labor, label: 'هزینه کارگر — اختیاری'),
      MoneyField(controller: _transport, label: 'هزینه حمل‌ونقل / باسکول — اختیاری'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(_viewOnly ? 'جزئیات فروش' : 'ویرایش فروش')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
              if (_viewOnly) LockedFormBanner(canEdit: canUnlockSale(StaffPerms.I.can), onEdit: () => setState(() => _viewOnly = false)),
              for (final Widget f in fields) LockedFields(locked: _viewOnly, child: f),
              if (!_viewOnly) ...<Widget>[
                const SizedBox(height: 8),
                FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.check), label: const Text('ذخیره تغییرات')),
              ],
              if (_viewOnly && widget.doc != null) SaleDocActions(doc: widget.doc!, onDeleted: () { if (mounted) Navigator.pop(context); }),
              const SizedBox(height: 24),
            ]),
    );
  }
}
