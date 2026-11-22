// فاز ۴ «قابلیت‌های فناورانه» — صفحهٔ «بهینه‌ساز کوت‌ریزی» (برنامه‌ریزی خطی). پشت پرچم features.blend_optimizer (پیش‌فرض خاموش).
// لات‌ها و شاخص‌ها از سرور (blend_opt.lots)؛ حل روی همین دستگاه با آینهٔ Dart (blend_opt_calc.dart؛ همان جواب سرور).
// «ساخت کوت از این پیشنهاد» ⇒ همان فرم ثبت کوت موجود (MixForm) پیش‌پر می‌شود؛ ثبت از مسیر عادی کوت (قواعد موجودی و بها همان).
// بها فقط با مجوز مشاهدهٔ قیمت؛ بدون آن هدف‌ها «کمترین تعداد لات» یا «اول قدیمی‌ترین» است و هیچ عدد بهایی نمایش داده نمی‌شود.
import 'package:flutter/material.dart';

import 'blend_opt_calc.dart';
import 'mix_form.dart' show MixForm;
import 'perms.dart' show StaffPerms;
import 'utils.dart' show faNum, jalaliDate;
import 'warehouse_ui.dart' show StockApi, StockApiException;

double? _p(String s) {
  final String t = s.trim().replaceAll('٫', '.').replaceAll(',', '');
  if (t.isEmpty) return null;
  const String fa = '۰۱۲۳۴۵۶۷۸۹';
  final StringBuffer b = StringBuffer();
  for (final int c in t.runes) {
    final int i = fa.indexOf(String.fromCharCode(c));
    b.write(i >= 0 ? '$i' : String.fromCharCode(c));
  }
  return double.tryParse(b.toString());
}

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class BlendOptimizerScreen extends StatefulWidget {
  const BlendOptimizerScreen({super.key});

  @override
  State<BlendOptimizerScreen> createState() => _BlendOptimizerScreenState();
}

class _BlendOptimizerScreenState extends State<BlendOptimizerScreen> {
  List<Map<String, dynamic>> _lots = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _metrics = <Map<String, dynamic>>[];
  bool _canPrice = false;
  bool _loading = true;
  String? _error;
  final TextEditingController _target = TextEditingController();
  final TextEditingController _minTake = TextEditingController(text: '5');
  final Map<String, TextEditingController> _min = <String, TextEditingController>{};
  final Map<String, TextEditingController> _max = <String, TextEditingController>{};
  String _objective = 'cost';
  String _type = '';
  String _owner = '';
  String _wh = '';
  final Set<int> _forced = <int>{};
  final Set<int> _forbidden = <int>{};
  final Map<int, double> _perMax = <int, double>{};
  Map<String, dynamic>? _result;
  Map<String, dynamic>? _lastReq;

  @override
  void initState() {
    super.initState();
    for (final String k in kBoMetrics.keys) {
      _min[k] = TextEditingController();
      _max[k] = TextEditingController();
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> r = await StockApi.call('blend_opt.lots');
      if (!mounted) return;
      setState(() {
        _lots = (r['items'] as List? ?? <Object?>[]).whereType<Map>().map((Map m) => Map<String, dynamic>.from(m)).toList();
        _metrics = (r['metrics'] as List? ?? <Object?>[]).whereType<Map>().map((Map m) => Map<String, dynamic>.from(m)).toList();
        _canPrice = r['can_price'] == true;
        if (!_canPrice && _objective == 'cost') _objective = 'oldest';
        _loading = false;
        _error = null;
      });
    } on StockApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filtered => _lots
      .where((Map<String, dynamic> l) =>
          (_type.isEmpty || l['type_name'] == _type) && (_owner.isEmpty || l['owner'] == _owner) && (_wh.isEmpty || l['warehouse_uid'] == _wh))
      .toList();

  void _solve() {
    final double? t = _p(_target.text);
    if (t == null || t <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('وزن کل هدف (کیلو) را وارد کنید')));
      return;
    }
    final Map<String, List<double?>> bounds = <String, List<double?>>{};
    for (final String k in kBoMetrics.keys) {
      final double? lo = _p(_min[k]!.text), hi = _p(_max[k]!.text);
      if (lo != null || hi != null) bounds[k] = <double?>[lo, hi];
    }
    final Map<String, dynamic> req = <String, dynamic>{
      'target_kg': t,
      'objective': _objective,
      'bounds': bounds,
      'forced': _forced.toList(),
      'forbidden': _forbidden.toList(),
      'per_lot': <String, dynamic>{for (final MapEntry<int, double> e in _perMax.entries) '${e.key}': <String, double>{'max': e.value}},
      'min_take_kg': _p(_minTake.text) ?? kBoMinTake,
    };
    final Stopwatch sw = Stopwatch()..start();
    final Map<String, dynamic> r = boSolve(_filtered, req);
    sw.stop();
    setState(() {
      _result = r..['solve_ms'] = sw.elapsedMilliseconds;
      _lastReq = req;
    });
  }

  void _buildMix() {
    final Map<String, dynamic>? r = _result;
    if (r == null || r['status'] != 'optimal') return;
    final Map<String, dynamic> m = r['metrics'] as Map<String, dynamic>;
    String fmt(Object? v) => v == null ? '' : boNumStr((v as num).toDouble());
    final String types = (r['takes'] as List)
        .map((dynamic t) => _lots.firstWhere((Map<String, dynamic> l) => l['id'] == (t as Map)['id'], orElse: () => <String, dynamic>{})['type_name'])
        .whereType<String>()
        .toSet()
        .join('، ');
    final Map<String, dynamic> process = <String, dynamic>{
      'key': 'opt${DateTime.now().microsecondsSinceEpoch}',
      'start': _ymd(DateTime.now()),
      'rows': <Map<String, dynamic>>[
        for (final dynamic t in r['takes'] as List) <String, dynamic>{'lot': (t as Map)['id'], 'kg': fmt(t['kg'])},
      ],
      'spec': <String, dynamic>{
        'name': types,
        'net': fmt(r['total_kg']),
        'ounce': fmt((m['ounce'] as Map?)?['value']),
        'gram': fmt((m['gram'] as Map?)?['value']),
        'note': 'پیشنهاد بهینه‌ساز کوت‌ریزی',
      },
    };
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MixForm(process: process))).then((_) => _load());
  }

  Future<void> _editQuality(Map<String, dynamic> l) async {
    final Map<String, dynamic> q = (l['q'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final TextEditingController mo = TextEditingController(text: q['moisture_pct'] == null ? '' : '${q['moisture_pct']}');
    final TextEditingController de = TextEditingController(text: q['defect_pct'] == null ? '' : '${q['defect_pct']}');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('شاخص کیفی لات ${l['code'] ?? l['id']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          TextField(controller: mo, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'درصد رطوبت')),
          TextField(controller: de, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'درصد ایراد')),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ثبت')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await StockApi.call('blend_opt.quality_save', <String, dynamic>{'lot_id': l['id'], 'moisture_pct': _p(mo.text), 'defect_pct': _p(de.text)});
      await _load();
    } on StockApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _lotOptions(Map<String, dynamic> l) async {
    final int id = l['id'] as int;
    final TextEditingController mx = TextEditingController(text: _perMax[id] == null ? '' : boNumStr(_perMax[id]!));
    String mode = _forced.contains(id) ? 'forced' : (_forbidden.contains(id) ? 'forbidden' : 'auto');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter set) => AlertDialog(
          title: Text('لات ${l['code'] ?? id}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'auto', label: Text('خودکار')),
                ButtonSegment<String>(value: 'forced', label: Text('اجباری')),
                ButtonSegment<String>(value: 'forbidden', label: Text('ممنوع')),
              ],
              selected: <String>{mode},
              onSelectionChanged: (Set<String> v) => set(() => mode = v.first),
            ),
            const SizedBox(height: 8),
            TextField(controller: mx, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'حداکثر برداشت (کیلو؛ اختیاری)')),
          ]),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأیید')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      _forced.remove(id);
      _forbidden.remove(id);
      if (mode == 'forced') _forced.add(id);
      if (mode == 'forbidden') _forbidden.add(id);
      final double? v = _p(mx.text);
      if (v == null) {
        _perMax.remove(id);
      } else {
        _perMax[id] = v;
      }
    });
  }

  Widget _drop(String label, String value, List<String> opts, void Function(String) on) => DropdownButton<String>(
        value: value,
        items: <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(value: '', child: Text(label)),
          for (final String o in opts) DropdownMenuItem<String>(value: o, child: Text(o)),
        ],
        onChanged: (String? v) => setState(() => on(v ?? '')),
      );

  Widget _resultCard() {
    final Map<String, dynamic>? r = _result;
    if (r == null) return const SizedBox.shrink();
    final List<String> warns = (r['warnings'] as List? ?? <Object?>[]).map((Object? w) => '$w').toList();
    if (r['status'] == 'invalid') {
      return Card(color: Theme.of(context).colorScheme.errorContainer, child: ListTile(title: Text('${r['message']}')));
    }
    if (r['status'] == 'infeasible') {
      final Map<String, dynamic>? nr = r['nearest'] as Map<String, dynamic>?;
      return Card(
        color: Colors.orange.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const Text('ترکیبی که همهٔ قیدها را برآورده کند وجود ندارد', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('قید مانع:'),
            for (final dynamic b in r['blocking'] as List) Text('• ${(b as Map)['text']}'),
            if (nr != null) ...<Widget>[
              const SizedBox(height: 8),
              const Text('نزدیک‌ترین ترکیب ممکن:', style: TextStyle(fontWeight: FontWeight.bold)),
              ..._takes(nr),
              for (final MapEntry<String, dynamic> e in (nr['metrics'] as Map<String, dynamic>).entries)
                if ((e.value as Map)['deviation'] != null)
                  Text('${(e.value as Map)['label']}: ${faNum(((e.value as Map)['value'] as num).toDouble(), dec: 2)}'
                      '${((e.value as Map)['deviation'] as num) == 0 ? ' (در محدوده)' : ' (اختلاف ${faNum(((e.value as Map)['deviation'] as num).toDouble(), dec: 2)})'}'),
            ],
            for (final String w in warns) Text('⚠ $w', style: const TextStyle(color: Colors.orange)),
          ]),
        ),
      );
    }
    final Map<String, dynamic>? simple = r['simple'] as Map<String, dynamic>?;
    return Card(
      color: Colors.green.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('پیشنهاد: ${faNum((r['lots_count'] as num).toDouble(), dec: 0)} لات، ${faNum((r['total_kg'] as num).toDouble(), dec: 3)} کیلو',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          if (_canPrice && r['cost_per_kg'] != null) Text('بهای هر کیلوی کوت: ${faNum((r['cost_per_kg'] as num).toDouble(), dec: 0)}  •  بهای کل: ${faNum((r['cost_total'] as num).toDouble(), dec: 0)}'),
          const Divider(),
          ..._takes(r),
          const Divider(),
          const Text('شاخص‌های کیفی حاصل:'),
          for (final MapEntry<String, dynamic> e in (r['metrics'] as Map<String, dynamic>).entries)
            if ((e.value as Map)['value'] != null)
              Text('${(e.value as Map)['label']}: ${faNum(((e.value as Map)['value'] as num).toDouble(), dec: 2)}'
                  '${(e.value as Map)['min'] == null && (e.value as Map)['max'] == null ? '' : '  (هدف ${(e.value as Map)['min'] == null ? '…' : faNum(((e.value as Map)['min'] as num).toDouble(), dec: 2)} تا ${(e.value as Map)['max'] == null ? '…' : faNum(((e.value as Map)['max'] as num).toDouble(), dec: 2)})'}'),
          if (_canPrice && simple != null) ...<Widget>[
            const Divider(),
            Text('ترکیب ساده (اول قدیمی‌ترین لات‌ها): ${simple['cost_per_kg'] == null ? '—' : faNum((simple['cost_per_kg'] as num).toDouble(), dec: 0)} برای هر کیلو'
                '${simple['meets_bounds'] == true ? '' : ' — قیدهای کیفی را برآورده نمی‌کند'}'),
            if (r['saving'] != null)
              Text((r['saving'] as num) > 0 ? 'صرفه‌جویی نسبت به ترکیب ساده: ${faNum((r['saving'] as num).toDouble(), dec: 0)}' : 'ترکیب ساده ارزان‌تر یا برابر است (اما قیدها را برآورده نمی‌کند)',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
          for (final String w in warns) Text('⚠ $w', style: const TextStyle(color: Colors.orange)),
          Text('زمان حل: ${faNum((r['solve_ms'] as num? ?? 0).toDouble(), dec: 0)} میلی‌ثانیه', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (StaffPerms.I.can('mixes.create'))
            FilledButton.icon(onPressed: _buildMix, icon: const Icon(Icons.merge_type), label: const Text('ساخت کوت از این پیشنهاد')),
        ]),
      ),
    );
  }

  List<Widget> _takes(Map<String, dynamic> r) => <Widget>[
        for (final dynamic t in r['takes'] as List)
          Text('لات ${(t as Map)['code'] ?? t['id']}: ${faNum((t['kg'] as num).toDouble(), dec: 3)} کیلو  (می‌ماند ${faNum((t['left_kg'] as num).toDouble(), dec: 3)})'),
      ];

  @override
  Widget build(BuildContext context) {
    final List<String> types = _lots.map((Map<String, dynamic> l) => '${l['type_name'] ?? ''}').where((String s) => s.isNotEmpty).toSet().toList()..sort();
    final List<String> owners = _lots.map((Map<String, dynamic> l) => '${l['owner'] ?? ''}').where((String s) => s.isNotEmpty).toSet().toList()..sort();
    final List<String> whs = _lots.map((Map<String, dynamic> l) => '${l['warehouse_uid'] ?? ''}').where((String s) => s.isNotEmpty).toSet().toList()..sort();
    final bool canQuality = StaffPerms.I.can('purchases.create');
    final List<Map<String, dynamic>> shown = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('بهینه‌ساز کوت‌ریزی'), actions: <Widget>[IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'به‌روزرسانی')]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(padding: const EdgeInsets.all(12), children: <Widget>[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        const Text('هدف کوت را بدهید؛ بهینه‌ساز از لات‌های موجود، ترکیبی با کمترین بهای کل (یا کمترین تعداد لات / اول قدیمی‌ترین) پیدا می‌کند که همهٔ قیدها را برآورده کند. چیزی از انبار کم نمی‌شود.'),
                        const SizedBox(height: 8),
                        Row(children: <Widget>[
                          Expanded(child: TextField(controller: _target, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'وزن کل هدف (کیلو)'))),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(controller: _minTake, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'حداقل برداشت عملی (کیلو)'))),
                        ]),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: <ButtonSegment<String>>[
                            if (_canPrice) const ButtonSegment<String>(value: 'cost', label: Text('کمترین بها')),
                            const ButtonSegment<String>(value: 'few', label: Text('کمترین تعداد لات')),
                            const ButtonSegment<String>(value: 'oldest', label: Text('اول قدیمی‌ترین')),
                          ],
                          selected: <String>{_objective},
                          onSelectionChanged: (Set<String> s) => setState(() => _objective = s.first),
                        ),
                        Wrap(spacing: 8, children: <Widget>[
                          _drop('همهٔ انواع', _type, types, (String v) => _type = v),
                          _drop('همهٔ مالک‌ها', _owner, owners, (String v) => _owner = v),
                          if (whs.length > 1) _drop('همهٔ انبارها', _wh, whs, (String v) => _wh = v),
                        ]),
                      ]),
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        const Text('قیدهای کیفی (میانگین وزنی؛ هر کدام خالی = بدون قید)', style: TextStyle(fontWeight: FontWeight.bold)),
                        for (final Map<String, dynamic> m in _metrics)
                          Row(children: <Widget>[
                            Expanded(flex: 3, child: Text('${m['label']}')),
                            Expanded(flex: 2, child: TextField(controller: _min['${m['key']}'], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'حداقل'))),
                            const SizedBox(width: 8),
                            Expanded(flex: 2, child: TextField(controller: _max['${m['key']}'], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'حداکثر'))),
                          ]),
                      ]),
                    ),
                  ),
                  FilledButton.icon(onPressed: _solve, icon: const Icon(Icons.auto_graph), label: const Text('پیشنهاد ترکیب بهینه')),
                  const SizedBox(height: 8),
                  _resultCard(),
                  const SizedBox(height: 8),
                  Text('لات‌های موجود (${faNum(shown.length.toDouble(), dec: 0)})', style: const TextStyle(fontWeight: FontWeight.bold)),
                  for (final Map<String, dynamic> l in shown)
                    Card(
                      child: ListTile(
                        dense: true,
                        onTap: () => _lotOptions(l),
                        leading: Icon(_forced.contains(l['id']) ? Icons.push_pin : (_forbidden.contains(l['id']) ? Icons.block : Icons.inventory_2_outlined),
                            color: _forced.contains(l['id']) ? Colors.green : (_forbidden.contains(l['id']) ? Colors.red : null)),
                        title: Text('${l['code'] ?? l['id']} — ${l['type_name'] ?? ''}  •  ${faNum((l['kg'] as num).toDouble(), dec: 1)} کیلو'
                            '${_canPrice && l['cost'] != null ? '  •  ${faNum((l['cost'] as num).toDouble(), dec: 0)}' : ''}'),
                        subtitle: Text(<String>[
                          if ('${l['date'] ?? ''}'.isNotEmpty) jalaliDate('${l['date']}'),
                          for (final MapEntry<String, String> e in kBoMetrics.entries)
                            if ((l['q'] as Map?)?[e.key] != null) '${e.value} ${faNum(((l['q'] as Map)[e.key] as num).toDouble(), dec: 2)}',
                          if (_perMax[l['id']] != null) 'حداکثر ${faNum(_perMax[l['id']]!, dec: 1)}',
                        ].join(' • ')),
                        trailing: canQuality
                            ? IconButton(tooltip: 'ثبت رطوبت / ایراد', icon: const Icon(Icons.water_drop_outlined), onPressed: () => _editQuality(l))
                            : null,
                      ),
                    ),
                  if (_lastReq != null) const SizedBox(height: 24),
                ]),
    );
  }
}
