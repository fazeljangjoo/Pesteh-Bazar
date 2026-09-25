import 'package:flutter/material.dart';

import 'db.dart';
import 'party_field.dart';
import 'utils.dart';
import 'widgets.dart';

/// وزن هر گونی (کیلو) — همان مقادیر فرم خرید
const double _kSmallSackKg = 0.1;
const double _kLargeSackKg = 0.2;

/// گرد کردن به ۳ رقم اعشار (جلوگیری از خطای اعشاری مثل 999.3000000000001)
double _r3(double v) => (v * 1000).round() / 1000;

/// یکسان‌سازی «ي/ك» عربی و «ی/ک» فارسی برای جستجو
String _norm(String s) => s.replaceAll('ي', 'ی').replaceAll('ك', 'ک').trim();

/// یک «وزن‌کشی»: وزن کل + گونی (به تعداد یا به کیلو) => وزن خالص.
/// هم برای کل بار استفاده می‌شود و هم برای هر جنس جداگانه.
class _Weigh {
  final gross = TextEditingController();
  final small = TextEditingController();
  final large = TextEditingController();
  final tareKg = TextEditingController();
  bool byCount = true;

  double get grossKg => parseNum(gross.text) ?? 0;
  double get smallN => byCount ? (parseNum(small.text) ?? 0) : 0;
  double get largeN => byCount ? (parseNum(large.text) ?? 0) : 0;
  double get tare => byCount
      ? smallN * _kSmallSackKg + largeN * _kLargeSackKg
      : (parseNum(tareKg.text) ?? 0);
  double get net => _r3(grossKg - tare);

  void dispose() {
    gross.dispose();
    small.dispose();
    large.dispose();
    tareKg.dispose();
  }
}

enum _Mode { whole, perLot }
enum _PriceMode { shared, separate }

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
  final Map<int, TextEditingController> _kg = {}; // سهم هر جنس (حالت کل بار)
  final Map<int, FocusNode> _focus = {};
  final Map<int, _Weigh> _lotWeigh = {}; // وزن‌کشی هر جنس (حالت جدا)
  final Set<int> _typed = {}; // اجناسی که کاربر خودش وزنشان را نوشته
  final _whole = _Weigh();
  _Mode _mode = _Mode.whole;
  bool _loading = true;
  bool _saving = false;
  String _query = '';

  final _price = TextEditingController();
  final Map<int, TextEditingController> _lotPrice = {};
  _PriceMode _priceMode = _PriceMode.shared;
  final _buyer = TextEditingController();
  final _note = TextEditingController();

  bool get _isEdit => widget.editSaleId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _price.dispose();
    _buyer.dispose();
    _note.dispose();
    _whole.dispose();
    for (final c in _kg.values) {
      c.dispose();
    }
    for (final c in _lotPrice.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    for (final w in _lotWeigh.values) {
      w.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    List<Map<String, dynamic>> l;
    if (_isEdit) {
      l = await AppDb.I.lotsForSaleEdit(widget.editSaleId!);
      final sale = await AppDb.I.saleById(widget.editSaleId!);
      if (sale != null) {
        _price.text = plain(sale['price'] as num);
        final total = (sale['total_weight'] as num).toDouble();
        final net = (sale['net_weight'] as num).toDouble();
        final small = (sale['small_sack_count'] as num).toDouble();
        final large = (sale['large_sack_count'] as num).toDouble();
        _whole.gross.text = plain(total);
        if (small + large > 0) {
          _whole.small.text = small == 0 ? '' : plain(small);
          _whole.large.text = large == 0 ? '' : plain(large);
        } else if (total - net > 0.0005) {
          _whole.byCount = false;
          _whole.tareKg.text = plain(total - net);
        }
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
      _lotPrice[id] = TextEditingController();
      if (saleWeight > 0) _typed.add(id);
      final f = FocusNode();
      f.addListener(() {
        if (!f.hasFocus && mounted) _changed();
      });
      _focus[id] = f;
    }
    if (!mounted) return;
    setState(() {
      _lots = l;
      _loading = false;
    });
  }

  // ------------------------- محاسبات -------------------------
  List<Map<String, dynamic>> get _selected =>
      _lots.where((e) => _sel[e['id'] as int] ?? false).toList();

  /// «هر جنس جدا وزن شد» فقط وقتی معنی دارد که حداقل دو جنس انتخاب شده باشد
  bool get _perLot => _mode == _Mode.perLot && _selected.length >= 2;

  /// چند جنس، یک وزن‌کشی برای کل بار => باید وزن خالص بین اجناس تقسیم شود
  bool get _wholeMulti => !_perLot && _selected.length >= 2;

  double get _gross => _perLot
      ? _selected.fold<double>(0, (s, e) => s + (_lotWeigh[e['id'] as int]?.grossKg ?? 0))
      : _whole.grossKg;

  double get _tare => _perLot
      ? _selected.fold<double>(0, (s, e) => s + (_lotWeigh[e['id'] as int]?.tare ?? 0))
      : _whole.tare;

  double get _smallCount => _perLot
      ? _selected.fold<double>(0, (s, e) => s + (_lotWeigh[e['id'] as int]?.smallN ?? 0))
      : _whole.smallN;

  double get _largeCount => _perLot
      ? _selected.fold<double>(0, (s, e) => s + (_lotWeigh[e['id'] as int]?.largeN ?? 0))
      : _whole.largeN;

  double get _net => _perLot
      ? _r3(_selected.fold<double>(0, (s, e) => s + (_lotWeigh[e['id'] as int]?.net ?? 0)))
      : _whole.net;

  double get _revenue => _net * (parseNum(_price.text) ?? 0);

  /// وزن خالصی که به این جنس تعلق می‌گیرد
  double _alloc(int id) {
    if (_perLot) return _lotWeigh[id]?.net ?? 0;
    if (_selected.length == 1) return _net;
    return parseNum(_kg[id]!.text) ?? 0;
  }

  double get _allocatedSum =>
      _selected.fold<double>(0, (s, e) => s + _alloc(e['id'] as int));
  double get _left => _net - _allocatedSum;

  String? _overStock() {
    for (final e in _selected) {
      final rem = (e['remaining'] as num).toDouble();
      if (_alloc(e['id'] as int) > rem + 1e-6) {
        return 'وزن «${e['type_name']}» از موجودی آن (${faNum(rem)} کیلو) بیشتر است';
      }
    }
    return null;
  }

  /// بعد از هر تغییر: اگر فقط یک جنس بدون وزن مانده، باقی‌مانده خودکار به آن داده می‌شود
  void _changed() {
    if (_wholeMulti) {
      final sel = _selected;
      final untouched = sel.where((e) => !_typed.contains(e['id'] as int)).toList();
      if (untouched.length == 1) {
        final id = untouched.first['id'] as int;
        if (!(_focus[id]?.hasFocus ?? false)) {
          var others = 0.0;
          for (final e in sel) {
            final oid = e['id'] as int;
            if (oid != id) others += parseNum(_kg[oid]!.text) ?? 0;
          }
          final v = _r3(_net - others);
          _kg[id]!.text = v > 0 ? plain(v) : '';
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _toggle(int id, bool v) {
    _sel[id] = v;
    _typed.remove(id);
    _kg[id]!.text = '';
    if (v) _lotWeigh.putIfAbsent(id, () => _Weigh());
    _changed();
  }

  // ------------------------- ذخیره -------------------------
  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    final sel = _selected;
    if (sel.isEmpty) {
      snack(context, 'حداقل یک پسته از انبار انتخاب کنید');
      return;
    }
    if ((parseNum(_price.text) ?? 0) <= 0) {
      if (_priceMode == _PriceMode.shared || sel.length == 1) {
        snack(context, 'فی فروش را وارد کنید');
        return;
      }
    }
    if (_priceMode == _PriceMode.separate && sel.length >= 2 &&
        sel.any((e) => (parseNum(_lotPrice[e['id'] as int]?.text) ?? 0) <= 0)) {
      snack(context, 'فی فروش هر جنس را وارد کنید');
      return;
    }
    final net = _net;
    if (net <= 0) {
      snack(context, 'وزن خالص باید بیشتر از صفر باشد (وزن گونی‌ها از وزن کل بیشتر است؟)');
      return;
    }
    if (_wholeMulti && _left.abs() > 0.005) {
      snack(
          context,
          _left > 0
              ? '${faNum(_left)} کیلو از وزن خالص هنوز بین اجناس تقسیم نشده'
              : '${faNum(-_left)} کیلو بیشتر از وزن خالص کل تقسیم شده');
      return;
    }

    final items = <Map<String, dynamic>>[];
    for (final e in sel) {
      final id = e['id'] as int;
      final price = _priceMode == _PriceMode.separate && sel.length >= 2
          ? parseNum(_lotPrice[id]!.text)!
          : parseNum(_price.text)!;
      items.add({'purchase_id': id, 'weight': _r3(_alloc(id)), 'item_price': price});
    }
    if (_wholeMulti) {
      // اختلاف بسیار ناچیز گرد کردن را روی آخرین جنس می‌گذاریم تا جمع دقیقاً برابر شود
      var others = 0.0;
      for (var i = 0; i < items.length - 1; i++) {
        others += items[i]['weight'] as double;
      }
      items.last['weight'] = _r3(net - others);
    }
    for (var i = 0; i < items.length; i++) {
      final e = sel[i];
      final w = items[i]['weight'] as double;
      final rem = (e['remaining'] as num).toDouble();
      if (w <= 0) {
        snack(context, 'وزن خالص «${e['type_name']}» باید بیشتر از صفر باشد');
        return;
      }
      if (w > rem + 1e-6) {
        snack(context, 'وزن «${e['type_name']}» از موجودی آن (${faNum(rem)} کیلو) بیشتر است');
        return;
      }
    }
    final netFinal =
        _r3(items.fold<double>(0, (s, it) => s + (it['weight'] as double)));
    final salePrice = items.fold<double>(0, (sum, item) =>
        sum + (item['weight'] as double) * (item['item_price'] as num).toDouble()) /
      netFinal;
    _attachSacks(items, sel);

    final saleData = <String, dynamic>{
      'price': salePrice,
      'total_weight': _gross,
      'small_sack_count': _smallCount,
      'large_sack_count': _largeCount,
      'net_weight': netFinal,
      'buyer': _buyer.text.trim().isEmpty ? null : _buyer.text.trim(),
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    };

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await AppDb.I.updateSale(widget.editSaleId!, saleData, items);
      } else {
        saleData['date'] = DateTime.now().toIso8601String();
        await AppDb.I.insertSale(saleData, items);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        snack(context, '$e'.replaceFirst('Exception: ', ''));
      }
    }
  }

  /// تعداد گونی هر جنس را برای ذخیره در فروش آماده می‌کند تا موجودی گونی انبار درست کم شود.
  /// اگر تعداد گونی وارد نشده باشد، مقدار null می‌ماند (برآورد تناسبی در انبار).
  void _attachSacks(List<Map<String, dynamic>> items, List<Map<String, dynamic>> sel) {
    if (_perLot) {
      for (var i = 0; i < items.length; i++) {
        final w = _lotWeigh[sel[i]['id'] as int];
        if (w != null && w.byCount && (w.smallN + w.largeN) > 0) {
          items[i]['small_sacks'] = w.smallN;
          items[i]['large_sacks'] = w.largeN;
        } else {
          items[i]['small_sacks'] = null;
          items[i]['large_sacks'] = null;
        }
      }
      return;
    }
    if (!(_whole.byCount && (_whole.smallN + _whole.largeN) > 0)) {
      for (final it in items) {
        it['small_sacks'] = null;
        it['large_sacks'] = null;
      }
      return;
    }
    final ws = <double>[for (final it in items) it['weight'] as double];
    final sm = _splitCount(_whole.smallN, ws);
    final lg = _splitCount(_whole.largeN, ws);
    for (var i = 0; i < items.length; i++) {
      items[i]['small_sacks'] = sm[i];
      items[i]['large_sacks'] = lg[i];
    }
  }

  /// تقسیم تعداد گونی بین اجناس به‌نسبت وزن (با روش بزرگ‌ترین باقی‌مانده تا جمع دقیق بماند)
  List<double> _splitCount(double total, List<double> weights) {
    final sum = weights.fold<double>(0, (a, b) => a + b);
    if (total <= 0 || sum <= 0) return List<double>.filled(weights.length, 0);
    final raw = <double>[for (final w in weights) total * w / sum];
    if (total != total.roundToDouble()) {
      return <double>[for (final r in raw) (r * 100).round() / 100];
    }
    final floors = <double>[for (final r in raw) r.floorToDouble()];
    final left = (total - floors.fold<double>(0, (a, b) => a + b)).round();
    final order = List<int>.generate(raw.length, (i) => i)
      ..sort((a, b) => (raw[b] - floors[b]).compareTo(raw[a] - floors[a]));
    for (var k = 0; k < left && k < order.length; k++) {
      floors[order[k]] += 1;
    }
    return floors;
  }

  // ------------------------- رابط کاربری -------------------------
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
                    children: _children(context),
                  ),
                ),
    );
  }

  List<Widget> _children(BuildContext context) {
    final sel = _selected;
    final w = <Widget>[];

    w.add(sectionTitle(context, '۱) پستهٔ فروخته‌شده را از انبار انتخاب کنید'));
    if (_lots.length > 6) {
      w.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          decoration: const InputDecoration(
            labelText: 'جستجو (نام دسته یا نوع)',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ));
    }
    w.add(Column(children: [for (final e in _visibleLots) _lotTile(e)]));

    if (sel.isEmpty) {
      w.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('بعد از انتخاب پسته، وزن فروش را وارد کنید.',
            style: TextStyle(color: Colors.black54)),
      ));
    } else {
      if (sel.length >= 2) {
        w.add(sectionTitle(context, '۲) این فروش مخلوط است؛ وزن چطور کشیده شد؟'));
        w.add(SegmentedButton<_Mode>(
          segments: const <ButtonSegment<_Mode>>[
            ButtonSegment<_Mode>(value: _Mode.whole, label: Text('کل بار یک‌جا')),
            ButtonSegment<_Mode>(value: _Mode.perLot, label: Text('هر جنس جدا')),
          ],
          selected: <_Mode>{_mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) {
            _mode = s.first;
            _changed();
          },
        ));
        w.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text(
            _perLot
                ? 'برای هر جنس، وزن کل و گونی‌های همان جنس را وارد کنید؛ وزن خالص هر جنس خودکار محاسبه می‌شود.'
                : 'وزن کل بار را یک‌بار وارد کنید، بعد وزن خالص را بین اجناس تقسیم کنید.',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ));
      } else {
        w.add(sectionTitle(context, '۲) وزن فروش'));
      }

      if (_perLot) {
        for (final e in sel) {
          w.add(_perLotCard(e));
        }
      } else {
        w.add(KeyedSubtree(
          key: const ValueKey('whole'),
          child: _weighFields(_whole, grossLabel: 'وزن کل (با گونی) — مثل ترازوی بارگیری'),
        ));
      }

      w.add(_summaryCard(context));

      if (_wholeMulti) {
        w.add(sectionTitle(context, '۳) وزن خالص هر جنس (جمع باید برابر وزن خالص کل باشد)'));
        w.add(_allocationBanner(context));
        for (final e in sel) {
          w.add(_allocCard(e));
        }
      }
      w.add(_priceFields());
    }

    w.add(const SizedBox(height: 12));
    w.add(KeyedSubtree(
        key: const ValueKey('buyer'),
        child: PartyField(controller: _buyer, label: 'خریدار (اختیاری)')));
    w.add(KeyedSubtree(
        key: const ValueKey('note'), child: textField(_note, 'توضیحات (اختیاری)', lines: 2)));
    w.add(FilledButton.icon(
      onPressed: _saving ? null : _save,
      icon: _saving
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.check),
      label: Text(_isEdit ? 'ذخیره تغییرات' : 'ثبت فروش'),
    ));
    w.add(const SizedBox(height: 24));
    return w;
  }

  List<Map<String, dynamic>> get _visibleLots {
    final q = _norm(_query);
    if (q.isEmpty) return _lots;
    return _lots.where((e) {
      if (_sel[e['id'] as int] ?? false) return true; // انتخاب‌شده‌ها همیشه دیده می‌شوند
      return _norm('${e['code']} ${e['category_name']} ${e['type_name']}').contains(q);
    }).toList();
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
        subtitle: Text(
          'کد ${e['code'] ?? '-'}  •  خرید ${jalaliDate(e['date'] as String)}  •  فی ${faNum(e['price'] as num, dec: 0)}\n'
            'موجودی ${faNum(rem)} کیلو'),
        isThreeLine: true,
      ),
    );
  }

  /// فیلدهای وزن کل + گونی (تعدادی یا به کیلو)
  Widget _weighFields(_Weigh w, {required String grossLabel, Map<String, dynamic>? lot}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      numField(w.gross, grossLabel, required: true, onChanged: _changed),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _fillAll(w, lot),
          icon: const Icon(Icons.all_inclusive),
          label: const Text('همه موجودی'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: true, label: Text('تعداد گونی')),
            ButtonSegment<bool>(value: false, label: Text('وزن گونی (کیلو)')),
          ],
          selected: <bool>{w.byCount},
          showSelectedIcon: false,
          onSelectionChanged: (s) {
            w.byCount = s.first;
            _changed();
          },
        ),
      ),
      if (w.byCount)
        Row(children: [
          Expanded(
              child: numField(w.small, 'گونی کوچک (${faNum(_kSmallSackKg * 1000, dec: 0)} گرم)',
                  hint: '0', onChanged: _changed)),
          const SizedBox(width: 8),
          Expanded(
              child: numField(w.large, 'گونی بزرگ (${faNum(_kLargeSackKg * 1000, dec: 0)} گرم)',
                  hint: '0', onChanged: _changed)),
        ])
      else
        numField(w.tareKg, 'وزن کل گونی‌ها (کیلو)', hint: '0', onChanged: _changed),
    ]);
  }

  void _fillAll(_Weigh w, Map<String, dynamic>? lot) {
    final selected = lot == null ? _selected : [lot];
    final net = selected.fold<double>(0, (sum, e) => sum + (e['remaining'] as num).toDouble());
    final small = selected.fold<double>(0, (sum, e) => sum + (e['small_left'] as num).toDouble());
    final large = selected.fold<double>(0, (sum, e) => sum + (e['large_left'] as num).toDouble());
    w.byCount = true;
    w.small.text = plain(small);
    w.large.text = plain(large);
    w.gross.text = plain(net + small * _kSmallSackKg + large * _kLargeSackKg);
    if (lot == null && selected.length > 1) {
      for (final e in selected) {
        final id = e['id'] as int;
        _kg[id]!.text = plain(e['remaining'] as num);
        _typed.add(id);
      }
    }
    _changed();
  }

  Widget _perLotCard(Map<String, dynamic> e) {
    final id = e['id'] as int;
    final w = _lotWeigh.putIfAbsent(id, () => _Weigh());
    final rem = (e['remaining'] as num).toDouble();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('pl$id'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${e['category_name']} - ${e['type_name']}',
              style: Theme.of(context).textTheme.titleSmall),
          Text('موجودی ${faNum(rem)} کیلو', style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 10),
          _weighFields(w, grossLabel: 'وزن کل این جنس (با گونی)', lot: e),
          infoRow('وزن خالص این جنس', '${faNum(w.net)} کیلو',
              valueColor: w.net > rem + 1e-6 ? scheme.error : null),
        ]),
      ),
    );
  }

  Widget _summaryCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = _overStock();
    final tooHeavy = _gross > 0 && _net <= 0;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          infoRow('وزن کل (با گونی)', '${faNum(_gross)} کیلو'),
          infoRow('وزن گونی‌ها', '${faNum(_tare)} کیلو'),
          infoRow('وزن خالص پسته', '${faNum(_net)} کیلو'),
          infoRow('مبلغ فروش تقریبی', '${faNum(_revenue, dec: 0)} تومان'),
          if (tooHeavy)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('وزن گونی‌ها از وزن کل بیشتر یا مساوی آن است',
                  style: TextStyle(color: scheme.error)),
            ),
          if (over != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(over, style: TextStyle(color: scheme.error)),
            ),
        ]),
      ),
    );
  }

  Widget _priceFields() {
    final sel = _selected;
    if (sel.length < 2) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sectionTitle(context, '۳) فی فروش'),
        numField(_price, 'فی فروش (تومان به ازای هر کیلو)', required: true,
            thousands: true, onChanged: _changed),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sectionTitle(context, '۳) فی فروش'),
      SegmentedButton<_PriceMode>(
        segments: const [
          ButtonSegment(value: _PriceMode.shared, label: Text('یک فی برای همه')),
          ButtonSegment(value: _PriceMode.separate, label: Text('فی جداگانه')),
        ],
        selected: {_priceMode},
        showSelectedIcon: false,
        onSelectionChanged: (v) => setState(() => _priceMode = v.first),
      ),
      const SizedBox(height: 8),
      if (_priceMode == _PriceMode.shared)
        numField(_price, 'فی مشترک فروش', required: true, thousands: true, onChanged: _changed)
      else
        for (final e in sel)
          numField(_lotPrice[e['id'] as int]!, 'فی ${e['type_name']}', required: true,
              thousands: true, onChanged: _changed),
    ]);
  }

  Widget _allocationBanner(BuildContext context) {
    final ok = _left.abs() <= 0.005 && _net > 0;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: ok ? scheme.secondaryContainer : scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(ok ? Icons.check_circle_outline : Icons.error_outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_net <= 0
                ? 'ابتدا وزن کل و گونی‌ها را وارد کنید'
                : ok
                    ? 'کل وزن خالص تقسیم شد'
                    : _left > 0
                        ? '${faNum(_left)} کیلو هنوز باقی مانده تا تقسیم شود'
                        : '${faNum(-_left)} کیلو بیشتر از وزن خالص تقسیم شده'),
          ),
        ]),
      ),
    );
  }

  Widget _allocCard(Map<String, dynamic> e) {
    final id = e['id'] as int;
    final rem = (e['remaining'] as num).toDouble();
    return Card(
      key: ValueKey('al$id'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${e['category_name']} - ${e['type_name']}',
              style: Theme.of(context).textTheme.titleSmall),
          Text('موجودی ${faNum(rem)} کیلو', style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextFormField(
                controller: _kg[id],
                focusNode: _focus[id],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'وزن خالص این جنس (کیلو)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  if (v.trim().isEmpty) {
                    _typed.remove(id);
                  } else {
                    _typed.add(id);
                  }
                  _changed();
                },
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
                final fill = _left + _alloc(id);
                final v = fill < 0 ? 0.0 : (fill > rem ? rem : fill);
                _kg[id]!.text = v > 0 ? plain(_r3(v)) : '';
                _typed.add(id);
                _changed();
              },
              child: const Text('پر کن'),
            ),
          ]),
        ]),
      ),
    );
  }
}
