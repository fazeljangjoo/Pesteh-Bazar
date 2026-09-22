import 'package:flutter/material.dart';

import 'db.dart';
import 'utils.dart';
import 'widgets.dart';

class SaleForm extends StatefulWidget {
  const SaleForm({super.key});
  @override
  State<SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<SaleForm> {
  final _form = GlobalKey<FormState>();
  List<Map<String, dynamic>> _lots = [];
  final Map<int, bool> _sel = {};
  final Map<int, TextEditingController> _kg = {};
  bool _loading = true;

  final _price = TextEditingController();
  final _smallSack = TextEditingController(text: '0');
  final _largeSack = TextEditingController(text: '0');
  final _buyer = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await AppDb.I.lots();
    for (final e in l) {
      final id = e['id'] as int;
      _sel[id] = false;
      _kg[id] = TextEditingController();
    }
    if (!mounted) return;
    setState(() {
      _lots = l;
      _loading = false;
    });
  }

  double _w(int id) => (_sel[id] ?? false) ? (parseNum(_kg[id]!.text) ?? 0) : 0;
  double get _net => _lots.fold(0.0, (s, e) => s + _w(e['id'] as int));
  double get _tare =>
      (parseNum(_smallSack.text) ?? 0) * 0.1 + (parseNum(_largeSack.text) ?? 0) * 0.2;
  double get _revenue => _net * (parseNum(_price.text) ?? 0);

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final items = <Map<String, dynamic>>[];
    for (final e in _lots) {
      final id = e['id'] as int;
      if (_sel[id] == true) {
        items.add({'purchase_id': id, 'weight': parseNum(_kg[id]!.text)!});
      }
    }
    if (items.isEmpty) {
      snack(context, 'حداقل یک پسته از انبار انتخاب کنید');
      return;
    }
    try {
      await AppDb.I.insertSale({
        'date': DateTime.now().toIso8601String(),
        'price': parseNum(_price.text),
        'total_weight': _net + _tare,
        'small_sack_count': parseNum(_smallSack.text) ?? 0,
        'large_sack_count': parseNum(_largeSack.text) ?? 0,
        'net_weight': _net,
        'buyer': _buyer.text.trim().isEmpty ? null : _buyer.text.trim(),
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      }, items);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فروش جدید')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lots.isEmpty
              ? const Center(child: Text('انبار خالی است؛ ابتدا خرید ثبت کنید'))
              : Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      sectionTitle(context,
                          'انتخاب از انبار (می‌توانید چند پسته را با هم ترکیب کنید)'),
                      for (final e in _lots) _lotCard(e),
                      const SizedBox(height: 8),
                      sectionTitle(context, 'قیمت و وزن فروش'),
                      numField(_price, 'فی فروش (تومان به ازای هر کیلو)',
                          required: true, thousands: true, onChanged: () => setState(() {})),
                      Row(children: [
                        Expanded(
                            child: numField(_smallSack, 'تعداد گونی کوچک (۱۰۰گ)',
                                onChanged: () => setState(() {}))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: numField(_largeSack, 'تعداد گونی بزرگ (۲۰۰گ)',
                                onChanged: () => setState(() {}))),
                      ]),
                      _summary(context),
                      const SizedBox(height: 12),
                      textField(_buyer, 'خریدار (اختیاری)'),
                      textField(_note, 'توضیحات (اختیاری)', lines: 2),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check),
                        label: const Text('ثبت فروش'),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _lotCard(Map<String, dynamic> e) {
    final id = e['id'] as int;
    final rem = (e['remaining'] as num).toDouble();
    return Card(
      child: Column(children: [
        CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          value: _sel[id],
          onChanged: (v) => setState(() => _sel[id] = v ?? false),
          title: Text('${e['category_name']} - ${e['type_name']}'),
          subtitle: Text(
              'خرید ${jalaliDate(e['date'] as String)}  •  فی ${faNum(e['price'] as num, dec: 0)}\n'
              'موجودی ${faNum(rem)} کیلو'),
          isThreeLine: true,
        ),
        if (_sel[id] == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _kg[id],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'وزن خالص برداشتی (کیلو)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final n = parseNum(v);
                    if (n == null || n <= 0) return 'وزن را وارد کنید';
                    if (n > rem + 1e-6) return 'بیشتر از موجودی';
                    return null;
                  },
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _kg[id]!.text = plain(rem)),
                child: const Text('همه'),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _summary(BuildContext context) {
    final parts = <Widget>[];
    if (_net > 0) {
      for (final e in _lots) {
        final id = e['id'] as int;
        final w = _w(id);
        if (w > 0) {
          parts.add(infoRow('${e['type_name']} (${e['category_name']})',
              '${faNum(w)} کیلو • ${faNum(w / _net * 100, dec: 1)}٪'));
        }
      }
    }
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          ...parts,
          if (parts.isNotEmpty) const Divider(),
          infoRow('وزن خالص', '${faNum(_net)} کیلو'),
          infoRow('وزن گونی‌ها', '${faNum(_tare)} کیلو'),
          infoRow('وزن کل', '${faNum(_net + _tare)} کیلو'),
          infoRow('مبلغ فروش', '${faNum(_revenue, dec: 0)} تومان'),
        ]),
      ),
    );
  }
}
