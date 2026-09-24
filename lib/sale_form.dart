import 'package:flutter/material.dart';

import 'db.dart';
import 'utils.dart';
import 'widgets.dart';

class SaleForm extends StatefulWidget {
  final int? editSaleId;
  const SaleForm({super.key, this.editSaleId});
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
  final _total = TextEditingController(); // وزن کل با گونی (مثل خرید)
  final _smallSack = TextEditingController();
  final _largeSack = TextEditingController();
  final _buyer = TextEditingController();
  final _note = TextEditingController();

  bool get _isEdit => widget.editSaleId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<Map<String, dynamic>> l;
    if (_isEdit) {
      l = await AppDb.I.lotsForSaleEdit(widget.editSaleId!);
      final sale = await AppDb.I.saleById(widget.editSaleId!);
      if (sale != null) {
        _price.text = plain(sale['price'] as num);
        _total.text = plain(sale['total_weight'] as num);
        final small = (sale['small_sack_count'] as num).toDouble();
        final large = (sale['large_sack_count'] as num).toDouble();
        _smallSack.text = small == 0 ? '' : plain(small);
        _largeSack.text = large == 0 ? '' : plain(large);
        _buyer.text = (sale['buyer'] as String?) ?? '';
        _note.text = (sale['note'] as String?) ?? '';
      }
    } else {
      l = await AppDb.I.lots();
    }
    for (final e in l) {
      final id = e['id'] as int;
      final saleWeight = (e['sale_weight'] as num?)?.toDouble() ?? 0;
      _sel[id] = saleWeight > 0;
      _kg[id] = TextEditingController(text: saleWeight > 0 ? plain(saleWeight) : '');
    }
    if (!mounted) return;
    setState(() {
      _lots = l;
      _loading = false;
    });
  }

  // ---- وزن‌ها: دقیقاً مثل خرید یک‌بار محاسبه می‌شود، نه به‌ازای هر جنس ----
  double get _tare =>
      (parseNum(_smallSack.text) ?? 0) * 0.1 + (parseNum(_largeSack.text) ?? 0) * 0.2;
  double get _netTarget => (parseNum(_total.text) ?? 0) - _tare; // وزن خالصی که باید بین اجناس تقسیم شود

  double _alloc(int id) => (_sel[id] ?? false) ? (parseNum(_kg[id]!.text) ?? 0) : 0;
  double get _allocatedSum => _lots.fold(0.0, (s, e) => s + _alloc(e['id'] as int));
  double get _leftToAllocate => _netTarget - _allocatedSum;
  double get _revenue => _netTarget * (parseNum(_price.text) ?? 0);

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_netTarget <= 0) {
      snack(context, 'وزن خالص باید بیشتر از صفر باشد');
      return;
    }
    if (_leftToAllocate.abs() > 0.005) {
      snack(
          context,
          _leftToAllocate > 0
              ? '${faNum(_leftToAllocate)} کیلو از وزن خالص هنوز بین اجناس تقسیم نشده'
              : '${faNum(-_leftToAllocate)} کیلو بیشتر از وزن خالص کل تقسیم شده');
      return;
    }
    final items = <Map<String, dynamic>>[];
    for (final e in _lots) {
      final id = e['id'] as int;
      if (_sel[id] == true && _alloc(id) > 0) {
        items.add({'purchase_id': id, 'weight': _alloc(id)});
      }
    }
    if (items.isEmpty) {
      snack(context, 'حداقل یک پسته از انبار انتخاب کنید');
      return;
    }
    final saleData = {
      'price': parseNum(_price.text),
      'total_weight': parseNum(_total.text) ?? 0,
      'small_sack_count': parseNum(_smallSack.text) ?? 0,
      'large_sack_count': parseNum(_largeSack.text) ?? 0,
      'net_weight': _netTarget,
      'buyer': _buyer.text.trim().isEmpty ? null : _buyer.text.trim(),
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    };
    try {
      if (_isEdit) {
        await AppDb.I.updateSale(widget.editSaleId!, saleData, items);
      } else {
        saleData['date'] = DateTime.now().toIso8601String();
        await AppDb.I.insertSale(saleData, items);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'ویرایش فروش' : 'فروش جدید')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lots.isEmpty
              ? const Center(child: Text('انبار خالی است؛ ابتدا خرید ثبت کنید'))
              : Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      sectionTitle(context, 'قیمت و وزن کل فروش'),
                      numField(_price, 'فی فروش (تومان به ازای هر کیلو)',
                          required: true, thousands: true, onChanged: () => setState(() {})),
                      numField(_total, 'وزن کل (با گونی) — مثل ترازوی بارگیری',
                          required: true, onChanged: () => setState(() {})),
                      Row(children: [
                        Expanded(
                            child: numField(_smallSack, 'تعداد گونی کوچک (۱۰۰گ)',
                                hint: '0', onChanged: () => setState(() {}))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: numField(_largeSack, 'تعداد گونی بزرگ (۲۰۰گ)',
                                hint: '0', onChanged: () => setState(() {}))),
                      ]),
                      Card(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(children: [
                            infoRow('وزن گونی‌ها', '${faNum(_tare)} کیلو'),
                            infoRow('وزن خالص کل فروش', '${faNum(_netTarget)} کیلو'),
                            infoRow('مبلغ فروش', '${faNum(_revenue, dec: 0)} تومان'),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      sectionTitle(context,
                          'تخصیص وزن خالص از انبار (اگر مخلوط بود چند جنس را انتخاب کنید)'),
                      _allocationBanner(context),
                      for (final e in _lots) _lotCard(e),
                      const SizedBox(height: 12),
                      textField(_buyer, 'خریدار (اختیاری)'),
                      textField(_note, 'توضیحات (اختیاری)', lines: 2),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check),
                        label: Text(_isEdit ? 'ذخیره تغییرات' : 'ثبت فروش'),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _allocationBanner(BuildContext context) {
    final ok = _leftToAllocate.abs() <= 0.005 && _netTarget > 0;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: ok ? scheme.secondaryContainer : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(ok ? Icons.check_circle_outline : Icons.error_outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_netTarget <= 0
                ? 'ابتدا وزن کل فروش را وارد کنید'
                : ok
                    ? 'کل وزن خالص تخصیص داده شد'
                    : _leftToAllocate > 0
                        ? '${faNum(_leftToAllocate)} کیلو هنوز باقی مانده تا تخصیص داده شود'
                        : '${faNum(-_leftToAllocate)} کیلو بیشتر از وزن خالص تخصیص داده شده'),
          ),
        ]),
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
                    labelText: 'سهم این جنس از وزن خالص (کیلو)',
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
                onPressed: () {
                  final fill = _leftToAllocate + _alloc(id);
                  final v = fill < 0 ? 0.0 : (fill > rem ? rem : fill);
                  setState(() => _kg[id]!.text = plain(v));
                },
                child: const Text('پر کن'),
              ),
            ]),
          ),
      ]),
    );
  }
}
