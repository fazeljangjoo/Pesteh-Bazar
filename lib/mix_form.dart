import 'package:flutter/material.dart';

import 'db.dart';
import 'utils.dart';
import 'widgets.dart';

/// یکسان‌سازی «ي/ك» عربی و «ی/ک» فارسی برای جستجو
String _norm(String s) => s.replaceAll('ي', 'ی').replaceAll('ك', 'ک').trim();

/// سهم هر جنس مبدأ در مخلوط: وزنی که برداشته می‌شود + (اختیاری) تعداد گونیِ مصرف‌شده از آن جنس
class _SourceRow {
  final weight = TextEditingController();
  final small = TextEditingController();
  final large = TextEditingController();
  void dispose() {
    weight.dispose();
    small.dispose();
    large.dispose();
  }
}

/// صفحه‌ی «ساخت مخلوط (کوت‌ریزی)»: چند بار موجود در انبار را با وزن دلخواه
/// ترکیب می‌کند و یک بار تازه با وزن خالص و تعداد گونیِ واقعیِ اندازه‌گیری‌شده می‌سازد.
/// از این پس در فروش فقط همین یک بار انتخاب می‌شود.
class MixForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const MixForm({super.key, this.existing});
  @override
  State<MixForm> createState() => _MixFormState();
}

class _MixFormState extends State<MixForm> {
  final _form = GlobalKey<FormState>();
  List<Map<String, dynamic>> _lots = [];
  final Map<int, bool> _sel = {};
  final Map<int, _SourceRow> _rows = {};
  bool _loading = true;
  bool _saving = false;
  String _query = '';

  bool get _isEdit => widget.existing != null;

  List<Map<String, dynamic>> _categories = [];
  int? _categoryId;
  final _typeName = TextEditingController();
  final _netWeight = TextEditingController();
  final _smallSack = TextEditingController();
  final _largeSack = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lots = _isEdit
        ? await AppDb.I.lotsForSaleEdit(widget.existing!['id'] as int)
        : await AppDb.I.lots();
    final cats = await AppDb.I.categories();
    if (!mounted) return;
    setState(() {
      _lots = lots;
      _categories = cats;
      _categoryId = cats.isNotEmpty ? cats.first['id'] as int : null;
      _loading = false;
    });
    if (_isEdit) {
      final e = widget.existing!;
      final sources = await AppDb.I.mixSourcesOf(e['id'] as int);
      _typeName.text = e['type_name'] as String? ?? '';
      _netWeight.text = plain(e['net_weight'] as num);
      _smallSack.text = plain(e['small_sack_count'] as num);
      _largeSack.text = plain(e['large_sack_count'] as num);
      _note.text = e['note'] as String? ?? '';
      _categoryId = e['category_id'] as int?;
      for (final source in sources) {
        final id = source['source_purchase_id'] as int;
        _sel[id] = true;
        final row = _rows.putIfAbsent(id, () => _SourceRow());
        row.weight.text = plain(source['weight'] as num);
        row.small.text = plain(source['small_sacks'] as num? ?? 0);
        row.large.text = plain(source['large_sacks'] as num? ?? 0);
      }
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    for (final r in _rows.values) {
      r.dispose();
    }
    _typeName.dispose();
    _netWeight.dispose();
    _smallSack.dispose();
    _largeSack.dispose();
    _note.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _selected =>
      _lots.where((e) => _sel[e['id'] as int] ?? false).toList();

  double get _takenSum => _selected.fold<double>(
      0, (s, e) => s + (parseNum(_rows[e['id'] as int]?.weight.text) ?? 0));

  void _toggle(int id, bool v) {
    setState(() {
      _sel[id] = v;
      _rows.putIfAbsent(id, () => _SourceRow());
    });
  }

  String? _overStock() {
    for (final e in _selected) {
      final id = e['id'] as int;
      final rem = (e['remaining'] as num).toDouble();
      final w = parseNum(_rows[id]?.weight.text) ?? 0;
      if (w > rem + 1e-6) {
        return 'وزن برداشته‌شده از «${e['type_name']}» بیشتر از موجودی آن (${faNum(rem)} کیلو) است';
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    final sel = _selected;
    if (sel.isEmpty) {
      snack(context, 'حداقل یک جنس مبدأ را انتخاب کنید');
      return;
    }
    if (_takenSum <= 0) {
      snack(context, 'وزنی که از انبار برمی‌دارید را وارد کنید');
      return;
    }
    final over = _overStock();
    if (over != null) {
      snack(context, over);
      return;
    }
    if (_categoryId == null) {
      snack(context, 'دسته را انتخاب کنید');
      return;
    }
    if (_typeName.text.trim().isEmpty) {
      snack(context, 'نام/نوع مخلوط را وارد کنید');
      return;
    }
    final net = parseNum(_netWeight.text) ?? 0;
    if (net <= 0) {
      snack(context, 'وزن نهایی مخلوط (بعد از توزین) را وارد کنید');
      return;
    }
    setState(() => _saving = true);
    try {
      final sources = <Map<String, dynamic>>[];
      for (final e in sel) {
        final id = e['id'] as int;
        final r = _rows[id]!;
        final w = parseNum(r.weight.text) ?? 0;
        if (w <= 0) continue;
        sources.add({
          'purchase_id': id,
          'weight': w,
            'small_sacks': parseNum(r.small.text) ?? 0,
            'large_sacks': parseNum(r.large.text) ?? 0,
        });
      }
      final args = {
        'categoryId': _categoryId!,
        'typeName': _typeName.text.trim(),
        'sources': sources,
        'netWeight': net,
        'smallSackCount': parseNum(_smallSack.text) ?? 0,
        'largeSackCount': parseNum(_largeSack.text) ?? 0,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      };
      if (_isEdit) {
        await AppDb.I.updateMix(
          mixPurchaseId: widget.existing!['id'] as int,
          categoryId: args['categoryId'] as int,
          typeName: args['typeName'] as String,
          sources: sources,
          netWeight: net,
          smallSackCount: args['smallSackCount'] as double,
          largeSackCount: args['largeSackCount'] as double,
          note: args['note'] as String?,
        );
      } else {
        await AppDb.I.createMix(
          categoryId: args['categoryId'] as int,
          typeName: args['typeName'] as String,
          sources: sources,
          netWeight: net,
          smallSackCount: args['smallSackCount'] as double,
          largeSackCount: args['largeSackCount'] as double,
          note: args['note'] as String?,
        );
      }
      if (mounted) {
        snack(context, _isEdit ? 'مخلوط ویرایش شد' : 'مخلوط با موفقیت به انبار اضافه شد');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) snack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Map<String, dynamic>> get _visibleLots {
    final q = _norm(_query);
    if (q.isEmpty) return _lots;
    return _lots.where((e) {
      if (_sel[e['id'] as int] ?? false) return true;
      return _norm('${e['code']} ${e['category_name']} ${e['type_name']}').contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_lots.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_isEdit ? 'ویرایش مخلوط' : 'ساخت مخلوط (کوت‌ریزی)')),
        body: const Center(child: Text('انبار خالی است')),
      );
    }
    final sel = _selected;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'ویرایش مخلوط' : 'ساخت مخلوط (کوت‌ریزی)')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: scheme.primaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'از بین اجناس موجود در انبار انتخاب کنید، از هرکدام هرچقدر می‌خواهید بردارید '
                  'و مخلوط کنید. بعد از مخلوط‌کردن، تعداد گونیِ به‌وجودآمده و وزن نهایی (طبق ترازو) '
                  'را وارد کنید تا یک قلم تازه به انبار اضافه شود؛ موقع فروش فقط همین یک قلم را '
                  'انتخاب می‌کنید.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            sectionTitle(context, '۱) انتخاب اجناس مبدأ'),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'جستجو',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _selectAll,
                icon: const Icon(Icons.select_all),
                label: const Text('انتخاب همه اجناس'),
              ),
            ),
            for (final e in _visibleLots) _lotTile(e),
            const SizedBox(height: 8),
            if (sel.isNotEmpty) ...[
              sectionTitle(context, '۲) چقدر از هرکدام برمی‌دارید'),
              for (final e in sel) _sourceCard(e),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: infoRow('جمع وزن برداشته‌شده', '${faNum(_takenSum)} کیلو'),
                ),
              ),
              const SizedBox(height: 8),
              sectionTitle(context, '۳) مشخصات مخلوطِ تازه'),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _categoryId,
                    decoration:
                        const InputDecoration(labelText: 'دسته', border: OutlineInputBorder()),
                    items: _categories
                        .map((c) =>
                            DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] as String)))
                        .toList(),
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _addCategory,
                  icon: const Icon(Icons.add),
                  tooltip: 'افزودن دسته',
                ),
              ]),
              const SizedBox(height: 12),
              textField(_typeName, 'نام مخلوط (مثلاً «کوت‌ریزی مخلوط»)', required: true),
              numField(_netWeight, 'وزن خالص نهایی مخلوط (کیلو) — طبق ترازو', required: true),
              Row(children: [
                Expanded(child: numField(_smallSack, 'تعداد گونی کوچک (۱۰۰ گرم)', hint: '0')),
                const SizedBox(width: 8),
                Expanded(child: numField(_largeSack, 'تعداد گونی بزرگ (۲۰۰ گرم)', hint: '0')),
              ]),
              textField(_note, 'توضیحات (اختیاری)', lines: 2),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(_isEdit ? 'ذخیره تغییرات' : 'ثبت مخلوط در انبار'),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _lotTile(Map<String, dynamic> e) {
    final id = e['id'] as int;
    final rem = (e['remaining'] as num).toDouble();
    return Card(
      key: ValueKey('lot$id'),
      child: CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        value: _sel[id] ?? false,
        onChanged: (v) => _toggle(id, v ?? false),
        title: Text('${e['category_name']} - ${e['type_name']}'),
        subtitle: Text('کد ${e['code'] ?? '-'}  •  موجودی ${faNum(rem)} کیلو  •  فی ${faNum(e['price'] as num, dec: 0)}'),
      ),
    );
  }

  Widget _sourceCard(Map<String, dynamic> e) {
    final id = e['id'] as int;
    final rem = (e['remaining'] as num).toDouble();
    final r = _rows.putIfAbsent(id, () => _SourceRow());
    final w = parseNum(r.weight.text) ?? 0;
    final over = w > rem + 1e-6;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('src$id'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${e['category_name']} - ${e['type_name']}',
              style: Theme.of(context).textTheme.titleSmall),
          Text('موجودی ${faNum(rem)} کیلو', style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                r.weight.text = plain(rem);
                r.small.text = plain(e['small_left'] as num);
                r.large.text = plain(e['large_left'] as num);
                setState(() {});
              },
              icon: const Icon(Icons.all_inclusive),
              label: const Text('همه موجودی'),
            ),
          ),
          TextFormField(
            controller: r.weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'وزنی که از این جنس برمی‌دارید (کیلو)',
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
          if (over)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('بیشتر از موجودی این جنس است', style: TextStyle(color: scheme.error)),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: r.small,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'گونی کوچک مصرف‌شده (اختیاری)',
                    hintText: '0',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: r.large,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'گونی بزرگ مصرف‌شده (اختیاری)',
                    hintText: '0',
                    border: OutlineInputBorder()),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  void _selectAll() {
    setState(() {
      for (final e in _lots) {
        final id = e['id'] as int;
        _sel[id] = true;
        final row = _rows.putIfAbsent(id, () => _SourceRow());
        row.weight.text = plain(e['remaining'] as num);
        row.small.text = plain(e['small_left'] as num);
        row.large.text = plain(e['large_left'] as num);
      }
    });
  }

  Future<void> _addCategory() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('افزودن دسته جدید'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'نام دسته')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('افزودن')),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.isEmpty) return;
    final id = await AppDb.I.addCategory(name);
    final cats = await AppDb.I.categories();
    if (mounted) setState(() { _categories = cats; _categoryId = id; });
  }
}
