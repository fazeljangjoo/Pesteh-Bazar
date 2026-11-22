import 'package:flutter/material.dart';

import 'db.dart';
import 'fmt.dart' show Fmt;
import 'perms.dart';
import 'processing_ui.dart' show ProcessingStore;
import 'returns_ui.dart' show ReturnsHelp;
import 'utils.dart';
import 'warehouse_ui.dart' show StockApi, StockApiException;
import 'workshop_calc.dart';

/// کارگاه داخلی (مرحلهٔ ۱) — فرم ثبت یک عملیات: ورودی از لات‌های انبار، خروجی به تفکیک دسته (سالم، بدشکل و ریز، پوست، مغز، خاک، بدرنگ) و افت.
/// تراز (H − (I+J+K+L+M+N+O)) زنده نشان داده می‌شود؛ هشدار است و جلوی ثبت را نمی‌گیرد.
/// سرور: processing.create با direction=internal (api/workshop.php)؛ آفلاین از صف ProcessingStore (uid ایدمپوتنت).
/// بها (مرحلهٔ ۲): بخش «بها» فقط برای دارندهٔ price.view + workshop.cost؛ محاسبه در سرور (pb_ws_cost)، پیش‌نمایش زنده با wsCost (آینه).

String _wsEn(String s) {
  const String fa = '۰۱۲۳۴۵۶۷۸۹';
  const String ar = '٠١٢٣٤٥٦٧٨٩';
  final StringBuffer b = StringBuffer();
  for (final int c in s.runes) {
    final String ch = String.fromCharCode(c);
    final int fi = fa.indexOf(ch);
    final int ai = ar.indexOf(ch);
    if (fi >= 0) {
      b.write(fi);
    } else if (ai >= 0) {
      b.write(ai);
    } else if (ch == '٫') {
      b.write('.');
    } else if (ch == '٬' || ch == ',') {
      // thousands separator
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

double _wsNum(String s) => double.tryParse(_wsEn(s).trim()) ?? 0.0;

/// برای فایل‌های دیگر (فرم ویرایش بها در processing_ui).
double wsParseNum(String s) => _wsNum(s);

/// دیدن/ثبت بهای کارگاه: price.view + workshop.cost (مالک همیشه).
bool wsCanCost() => StaffPerms.I.canPriceIn('workshop') && StaffPerms.I.can('workshop.cost'); // v87: قیمت بخش کارگاه

/// فیلدهای قابل‌ورود بها. فاز ۱ (مجد): «قیمت خرید هر کیلو» (V) دیگر وارد نمی‌شود (فقط‌نمایش با [kWsBuyLabel])؛ چفت و دهنبست با قیمت جدا.
const List<List<String>> kWsCostFields = <List<String>>[
  <String>['wage_per_kg', 'اجرت تولید هر کیلو (X؛ روی وزن ورودی)'],
  <String>['other_cost', 'سایر هزینهٔ تولید — مبلغ کل (Y)'],
  <String>['price_deformed', 'قیمت بدشکل و ریز (AA)'],
  <String>['price_discolored', 'قیمت بدرنگ (AB)'],
  <String>['price_hull', 'قیمت فروش پوست (AC)'],
  <String>['price_soil', 'قیمت خاک (AD)'],
  <String>['price_kernel', 'قیمت فروش مغز (AE)'],
  <String>['price_chaft', 'قیمت فروش چفت'],
  <String>['price_dombest', 'قیمت فروش دهنبست'],
];

/// برچسب فیلد فقط‌نمایش V (فرم ثبت و فرم ویرایش بها).
const String kWsBuyLabel = 'قیمت خرید هر کیلو (V) — از بهای لات‌های ورودی';

/// متن هشدار لات ورودی بی‌بها (پاسخ سرور: input_cost_warning = missing_input_cost).
const String kWsMissingInputCost = 'یکی از لات‌های ورودی بها ندارد؛ سهم آن در قیمت خرید صفر حساب شده است.';

/// فیلد فقط‌نمایش (خاکستری) با برچسب و متن.
Widget wsReadOnlyField(String label, String value, {Color? color, String? helper}) => InputDecorator(
      decoration: InputDecoration(labelText: label, helperText: helper, border: const OutlineInputBorder(), filled: true),
      child: Text(value, style: TextStyle(color: color, fontWeight: color == null ? null : FontWeight.bold)),
    );

class _WsInput {
  final TextEditingController kg = TextEditingController();
  String? lotLocalId;
  void dispose() => kg.dispose();
}

class WorkshopFormScreen extends StatefulWidget {
  const WorkshopFormScreen({super.key});

  @override
  State<WorkshopFormScreen> createState() => _WorkshopFormScreenState();
}

class _WorkshopFormScreenState extends State<WorkshopFormScreen> {
  final TextEditingController _date = TextEditingController(text: ReturnsHelp.iso(DateTime.now()));
  final TextEditingController _owner = TextEditingController();
  final TextEditingController _defect = TextEditingController();
  final TextEditingController _initial = TextEditingController();
  final TextEditingController _bales = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final List<_WsInput> _inputs = <_WsInput>[_WsInput()];
  final Map<String, TextEditingController> _outs = <String, TextEditingController>{
    for (final String g in kWsGrades) g: TextEditingController(),
  };
  final Map<String, TextEditingController> _cost = <String, TextEditingController>{
    for (final List<String> f in kWsCostFields) f[0]: TextEditingController(),
  };
  Map<String, String> _lots = <String, String>{};
  /// قیمت هر کیلوی لات (فقط پیش‌نمایش V؛ لات‌های سرور برای اپراتور قیمت ندارند).
  Map<String, double> _lotPrice = <String, double>{};
  String _op = 'dehull';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadLots();
  }

  /// اپراتور کارگاه purchases را همگام نمی‌کند (بدون stock.view) ⇒ لات‌ها از workshop.lots (بدون قیمت) و شناسهٔ سرور مستقیم.
  bool get _serverLots => StaffPerms.I.isWorkshopOperatorOnly;

  Future<void> _loadLots() async {
    if (_serverLots) {
      try {
        final Map<String, dynamic> r = await StockApi.call('workshop.lots');
        final Map<String, String> lots = <String, String>{};
        for (final Map<String, dynamic> l in ReturnsHelp.maps(r['items'])) {
          final double rem = ReturnsHelp.d(l['remaining']);
          if (rem <= 0) continue;
          lots['${l['id']}'] = '${l['code'] ?? ''} · ${l['type_name'] ?? ''} · ${faNum(rem, dec: 3)} کیلو';
        }
        if (mounted) setState(() => _lots = lots);
      } on StockApiException catch (e) {
        _snack(e.message);
      }
      return;
    }
    final List<Map<String, dynamic>> rows = await AppDb.I.inventoryAll();
    final Map<String, String> lots = <String, String>{};
    final Map<String, double> prices = <String, double>{};
    for (final Map<String, dynamic> r in rows) {
      final double rem = ReturnsHelp.d(r['remaining']);
      if (rem <= 0 || ReturnsHelp.d(r['is_mix']) == 3) continue;
      lots['${r['id']}'] = '${r['code'] ?? ''} · ${r['type_name'] ?? ''} · ${faNum(rem, dec: 3)} کیلو';
      prices['${r['id']}'] = ReturnsHelp.d(r['price']);
    }
    if (mounted) {
      setState(() {
        _lots = lots;
        _lotPrice = prices;
      });
    }
  }

  @override
  void dispose() {
    _date.dispose();
    _owner.dispose();
    _defect.dispose();
    _initial.dispose();
    _bales.dispose();
    _note.dispose();
    for (final _WsInput i in _inputs) {
      i.dispose();
    }
    for (final TextEditingController c in _outs.values) {
      c.dispose();
    }
    for (final TextEditingController c in _cost.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  double get _inKg => _inputs.fold<double>(0.0, (double s, _WsInput i) => s + _wsNum(i.kg.text));

  Map<String, num> get _outByGrade => <String, num>{for (final MapEntry<String, TextEditingController> e in _outs.entries) e.key: _wsNum(e.value.text)};

  /// فاز ۱: افت خودکار (lossKg = null ⇒ ورودی − Σ خروجی‌ها).
  WsBalance get _balance => wsBalance(
        inputKg: _inKg,
        out: _outByGrade,
        initialKg: _initial.text.trim().isEmpty ? null : _wsNum(_initial.text),
      );

  /// پیش‌نمایش V = میانگین موزون قیمت لات‌های ورودی (آینهٔ wsInputCost). سرور مقدار قطعی را با هزینهٔ دلالی و … حساب می‌کند.
  WsInputCost get _liveV => wsInputCost(<Map<String, Object?>>[
        for (final _WsInput i in _inputs)
          if (i.lotLocalId != null && _wsNum(i.kg.text) > 0)
            <String, Object?>{
              'kg': _wsNum(i.kg.text),
              'unit_cost': _lotPrice[i.lotLocalId],
              'cost': wsR2(_wsNum(i.kg.text) * (_lotPrice[i.lotLocalId] ?? 0)),
            },
      ]);

  Future<void> _submit() async {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(_wsEn(_date.text.trim()))) return _snack('تاریخ را به صورت yyyy-mm-dd وارد کنید');
    if (_balance.overOutput) return _snack('جمع خروجی‌ها از ورودی بیشتر است');
    setState(() => _saving = true);
    try {
      final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
      for (final _WsInput i in _inputs) {
        final double kg = _wsNum(i.kg.text);
        if (i.lotLocalId == null) {
          _snack('برای هر ورودی لات انبار را انتخاب کنید');
          return;
        }
        if (kg <= 0) {
          _snack('وزن هر ورودی باید بیشتر از صفر باشد');
          return;
        }
        items.add(<String, dynamic>{'purchase_id': _serverLots ? int.parse(i.lotLocalId!) : await ReturnsHelp.serverId('purchase', int.parse(i.lotLocalId!)), 'kg': kg});
      }
      final List<Map<String, dynamic>> outputs = <Map<String, dynamic>>[
        for (final MapEntry<String, TextEditingController> e in _outs.entries)
          if (_wsNum(e.value.text) > 0) <String, dynamic>{'grade': e.key, 'kg': _wsNum(e.value.text)},
      ];
      final Map<String, dynamic> payload = <String, dynamic>{
        'uid': ReturnsHelp.newUid('ws'),
        'direction': 'internal',
        'op_type': _op,
        'date': _wsEn(_date.text.trim()),
        'owner': _owner.text.trim(),
        'defect_note': _defect.text.trim(),
        'loss_kg': _balance.lossKg, // فاز ۱: سرور نادیده می‌گیرد و خودش حساب می‌کند (فقط سازگاری با سرور قدیمی)
        'note': _note.text.trim(),
        'items': items,
        'outputs': outputs,
      };
      if (wsCanCost()) {
        for (final MapEntry<String, TextEditingController> e in _cost.entries) {
          if (e.value.text.trim().isNotEmpty) payload[e.key] = _wsNum(e.value.text); // V ارسال نمی‌شود (سرور از لات‌های ورودی حساب می‌کند)
        }
      }
      if (_initial.text.trim().isNotEmpty) payload['initial_kg'] = _wsNum(_initial.text);
      if (_bales.text.trim().isNotEmpty) payload['bale_count'] = _wsNum(_bales.text);
      final bool queued = await ProcessingStore.write('processing.create', payload, 'کارگاه داخلی: ${kWsOpLabels[_op]}');
      if (!mounted) return;
      _snack(queued ? 'آفلاین ذخیره شد؛ پس از اتصال ارسال می‌شود' : 'ثبت شد');
      Navigator.pop(context, true);
    } on StockApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('خطا: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _numField(TextEditingController c, String label, {bool live = true, bool money = false}) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: money ? [ThousandsInputFormatter()] : null,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        onChanged: live ? (_) => setState(() {}) : null,
      );

  /// پیش‌نمایش بها. V فقط‌نمایش (از لات‌های ورودی)؛ بقیهٔ قیمت‌ها ورودی کاربر.
  Widget _costCard() {
    final WsInputCost v = _liveV;
    final Map<String, num> pr = <String, num>{
      'buy_per_kg': v.buyPerKg ?? 0,
      for (final List<String> f in kWsCostFields) f[0]: _wsNum(_cost[f[0]]!.text),
    };
    final WsCost c = wsCost(inputKg: _inKg, out: _outByGrade, pr: pr);
    final bool hasV = v.buyPerKg != null;
    String m(double v) => Fmt.money(v, label: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('بها (${Fmt.unitLabel()})', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: wsReadOnlyField(
                kWsBuyLabel,
                v.buyPerKg == null ? '—' : m(v.buyPerKg!),
                helper: _serverLots ? 'سرور هنگام ثبت محاسبه می‌کند' : 'پیش‌نمایش؛ مقدار قطعی را سرور حساب می‌کند',
              ),
            ),
            if (v.warning != null && !_serverLots) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text(kWsMissingInputCost, style: TextStyle(color: Colors.orange))),
            for (final List<String> f in kWsCostFields)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: _numField(_cost[f[0]]!, f[1], money: true)),
            if (!hasV) const Text('برای پیش‌نمایش بها لات و وزن ورودی را وارد کنید.')
            else ...<Widget>[
              Text('ارزش ورودی (W): ${m(c.valueIn)} · هزینه تولید (Z): ${m(c.costTotal)}'),
              Text('ارزش محصولات فرعی (AF): ${m(c.recoveryValue)}'),
              Text('بهای تمام‌شدهٔ سالم (AG): ${m(c.costSound)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(c.costPerKgSound == null ? 'بهای هر کیلو سالم: —' : 'بهای هر کیلو سالم (AH): ${m(c.costPerKgSound!)}'),
              if (c.warning != null) const Text('هشدار: ارزش فرعی بیش از هزینه است و بهای سالم منفی شد (ثبت مجاز است).', style: TextStyle(color: Colors.orange)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final WsBalance b = _balance;
    final Color tone = b.overOutput ? Colors.red : (b.ok ? Colors.green : Colors.orange);
    return Scaffold(
      appBar: AppBar(title: const Text('عملیات کارگاه داخلی')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: <Widget>[
          DropdownButtonFormField<String>(
            value: _op,
            decoration: const InputDecoration(labelText: 'نوع عملیات', border: OutlineInputBorder()),
            items: <DropdownMenuItem<String>>[
              for (final String k in kWsOpTypes) DropdownMenuItem<String>(value: k, child: Text(kWsOpLabels[k] ?? k)),
            ],
            onChanged: (String? v) => setState(() => _op = v ?? 'dehull'),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _date,
                  decoration: const InputDecoration(labelText: 'تاریخ (yyyy-mm-dd)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(controller: _owner, decoration: const InputDecoration(labelText: 'مالک', border: OutlineInputBorder())),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(controller: _defect, decoration: const InputDecoration(labelText: 'ایراد بار (اختیاری)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(child: _numField(_initial, 'وزن خالص اولیه (کیلو)')),
              const SizedBox(width: 10),
              Expanded(child: _numField(_bales, 'تعداد عدل', live: false)),
            ],
          ),
          const SizedBox(height: 16),
          Text('ورودی از انبار', style: Theme.of(context).textTheme.titleMedium),
          for (int idx = 0; idx < _inputs.length; idx++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _inputs[idx].lotLocalId,
                      decoration: const InputDecoration(labelText: 'لات', border: OutlineInputBorder()),
                      items: <DropdownMenuItem<String>>[
                        for (final MapEntry<String, String> e in _lots.entries)
                          DropdownMenuItem<String>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (String? v) => setState(() => _inputs[idx].lotLocalId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _numField(_inputs[idx].kg, 'وزن (کیلو)')),
                  if (_inputs.length > 1)
                    IconButton(
                      tooltip: 'حذف ورودی',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setState(() => _inputs.removeAt(idx).dispose()),
                    ),
                ],
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _inputs.add(_WsInput())),
              icon: const Icon(Icons.add),
              label: const Text('ورودی دیگر'),
            ),
          ),
          const SizedBox(height: 8),
          Text('خروجی (به موجودی برمی‌گردد)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final String g in kWsGrades)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _numField(_outs[g]!, '${kWsGradeLabels[g]} (کیلو)'),
            ),
          wsReadOnlyField(
            'افت وزن (کیلو) — ورودی − جمع خروجی‌ها',
            '${faNum(b.lossKg, dec: 3)}${b.lossPct == null ? '' : '  (${faNum(b.lossPct!, dec: 1)}٪)'}',
            color: b.overOutput ? Colors.red : null,
            helper: b.overOutput ? 'جمع خروجی‌ها از ورودی بیشتر است' : 'خودکار؛ به موجودی برنمی‌گردد',
          ),
          const SizedBox(height: 12),
          Card(
            color: tone.withOpacity(0.12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(b.label, style: TextStyle(fontWeight: FontWeight.bold, color: tone)),
                  Text('ورودی ${faNum(b.inputKg, dec: 3)} · جمع خروجی ${faNum(b.inputKg - b.lossKg, dec: 3)} · افت ${faNum(b.lossKg, dec: 3)} کیلو'),
                  if (b.lossPct != null) Text('درصد افت: ${faNum(b.lossPct!, dec: 1)}٪'),
                  if (b.soundPct != null) Text('درصد سالم: ${faNum(b.soundPct!, dec: 1)}٪'),
                  if (b.undeliveredKg != null) Text('مانده تحویل‌نشده: ${faNum(b.undeliveredKg!, dec: 3)} کیلو'),
                  if (b.overOutput) const Text('ثبت ممکن نیست: وزن خروجی‌ها را اصلاح کنید.', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          if (wsCanCost()) ...<Widget>[const SizedBox(height: 10), _costCard()],
          const SizedBox(height: 10),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'یادداشت (اختیاری)', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: (_saving || b.overOutput) ? null : _submit,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'در حال ثبت…' : 'ثبت عملیات'),
          ),
        ],
      ),
    );
  }
}
