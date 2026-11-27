// v95 — کوت‌ریزی مرحله‌ای (DESIGN_v95_mix_sep_FA.md بخش ۲): انتخاب «کوت‌ریزی / جداکردن-غربال»، فهرست کوت‌های در جریان،
// و فرم «ثبت خروجی‌ها و بستن کوت» (چند خروجی با همهٔ مشخصات، هزینهٔ هر کیلو، بها و تفکیک). فایل مشترک اندروید و ویندوز.
// شروع کوت در mix_form.dart است (mixes.open). شروع/بستن/لغو آنلاین است (StockApi)؛ بعد از هر کدام همگام‌سازی صدا زده می‌شود.
import 'package:flutter/material.dart';

import 'db.dart';
import 'fmt.dart' show Fmt, MoneyField;
import 'mix_form.dart' show MixForm;
import 'separation_form.dart' show SeparationsScreen;
import 'sync_service.dart';
import 'utils.dart';
import 'warehouse_ui.dart' show StockApi, StockApiException, WarehousePicker;
import 'widgets.dart';

/// بهای کوت مرحله‌ای — آینهٔ دقیق pb_mix_staged_cost سرور.
/// بهای هر کیلو خروجی = (V + c × I) ÷ O؛ تفکیک: بهای ورودی V÷I + سهم ضایعات W×(V÷I)÷O + سهم هزینه c×I÷O.
class MixStagedCost {
  final double unit, base, wasteShare, costShare, waste;
  const MixStagedCost(this.unit, this.base, this.wasteShare, this.costShare, this.waste);
}

MixStagedCost mixStagedCost(double inKg, double inValue, double outKg, double costPerKg) {
  final double w = inKg - outKg > 0 ? inKg - outKg : 0;
  if (inKg <= 0 || outKg <= 0) return MixStagedCost(0, 0, 0, 0, w);
  final double base = inValue / inKg;
  return MixStagedCost((inValue + costPerKg * inKg) / outKg, base, w * base / outKg, costPerKg * inKg / outKg, w);
}

/// کوت‌های در جریان روی این دستگاه (آینهٔ محلی)
Future<List<Map<String, dynamic>>> loadOpenMixes() async {
  try {
    final rows = await (await AppDb.I.db).rawQuery(
        "SELECT id, code, type_name, date, net_weight, small_sack_count, large_sack_count, price FROM purchases WHERE mix_status = 'open' ORDER BY date DESC, id DESC");
    return <Map<String, dynamic>>[for (final r in rows) Map<String, dynamic>.from(r)];
  } catch (_) {
    return <Map<String, dynamic>>[]; // ستون v95 هنوز نیست
  }
}

/// دکمهٔ «مخلوط / جداسازی» انبار ⇒ «کوت‌ریزی» یا «جداکردن / غربال»
Future<void> showMixOrSeparation(BuildContext context) async {
  final String? pick = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        ListTile(
          leading: const Icon(Icons.merge_type),
          title: const Text('کوت‌ریزی'),
          subtitle: const Text('چند لات ⇒ یک کوت؛ بعد ثبت یک یا چند خروجی'),
          onTap: () => Navigator.pop(ctx, 'mix'),
        ),
        ListTile(
          leading: const Icon(Icons.call_split),
          title: const Text('جداکردن / غربال'),
          subtitle: const Text('یک یا چند لات ⇒ چند خروجی'),
          onTap: () => Navigator.pop(ctx, 'sep'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (!context.mounted || pick == null) return;
  if (pick == 'sep') {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SeparationsScreen()));
    return;
  }
  await showMixHub(context);
}

/// کوت‌های در جریان + «کوت‌ریزی تازه»
Future<void> showMixHub(BuildContext context) async {
  final List<Map<String, dynamic>> open = await loadOpenMixes();
  if (!context.mounted) return;
  if (open.isEmpty) {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const MixForm()));
    return;
  }
  final Object? pick = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: <Widget>[
        ListTile(
          leading: const Icon(Icons.add_circle_outline),
          title: const Text('کوت‌ریزی تازه'),
          onTap: () => Navigator.pop(ctx, 'new'),
        ),
        const Divider(),
        const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text('کوت‌های در جریان (منتظر ثبت خروجی)', style: TextStyle(fontWeight: FontWeight.bold))),
        for (final Map<String, dynamic> m in open)
          ListTile(
            leading: const Icon(Icons.pending_actions),
            title: Text('${m['type_name'] ?? ''} — ${m['code'] ?? ''}'),
            subtitle: Text('شروع ${jalaliDate('${m['date'] ?? ''}')} • ${faNum((m['net_weight'] as num?) ?? 0)} کیلو'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.pop(ctx, m),
          ),
      ]),
    ),
  );
  if (!context.mounted || pick == null) return;
  if (pick == 'new') {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const MixForm()));
  } else if (pick is Map<String, dynamic>) {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MixCloseScreen(mixId: pick['id'] as int, title: '${pick['type_name'] ?? ''}')));
  }
}

/// یک ردیف خروجی
class _OutRow {
  final TextEditingController name = TextEditingController();
  final TextEditingController lotName = TextEditingController();
  final TextEditingController kg = TextEditingController();
  final TextEditingController small = TextEditingController();
  final TextEditingController large = TextEditingController();
  final TextEditingController ounce = TextEditingController();
  final TextEditingController gram = TextEditingController();
  final TextEditingController tuchin = TextEditingController();
  final TextEditingController dombest = TextEditingController();
  final TextEditingController crooked = TextEditingController();
  final TextEditingController khandan = TextEditingController();
  final TextEditingController note = TextEditingController();
  final List<(TextEditingController, TextEditingController)> specs = <(TextEditingController, TextEditingController)>[];
  String? wh;

  List<TextEditingController> get _all => <TextEditingController>[name, lotName, kg, small, large, ounce, gram, tuchin, dombest, crooked, khandan, note];

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type_name': name.text.trim(),
        'kg': parseNum(kg.text) ?? 0,
        'small_sacks': parseNum(small.text) ?? 0,
        'large_sacks': parseNum(large.text) ?? 0,
        if (lotName.text.trim().isNotEmpty) 'lot_name': lotName.text.trim(),
        if (wh != null) 'warehouse_uid': wh,
        for (final (String k, TextEditingController c) in <(String, TextEditingController)>[
          ('ounce', ounce), ('gram', gram), ('pct_tuchin', tuchin), ('pct_dombest', dombest), ('pct_crooked', crooked), ('pct_khandan', khandan),
        ])
          if (parseNum(c.text) != null) k: parseNum(c.text),
        if (note.text.trim().isNotEmpty) 'note': note.text.trim(),
        'custom_specs': <Map<String, String>>[
          for (final (TextEditingController l, TextEditingController v) in specs)
            if (l.text.trim().isNotEmpty) <String, String>{'label': l.text.trim(), 'value': v.text.trim()},
        ],
      };

  void dispose() {
    for (final TextEditingController c in _all) {
      c.dispose();
    }
    for (final (TextEditingController l, TextEditingController v) in specs) {
      l.dispose();
      v.dispose();
    }
  }
}

/// «ثبت خروجی‌ها و بستن کوت» (mixes.close) — [mixId] شناسهٔ سرور لات کوت در جریان.
class MixCloseScreen extends StatefulWidget {
  const MixCloseScreen({super.key, required this.mixId, this.title = ''});
  final int mixId;
  final String title;

  @override
  State<MixCloseScreen> createState() => _MixCloseScreenState();
}

class _MixCloseScreenState extends State<MixCloseScreen> with EditGuard<MixCloseScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  Map<String, dynamic>? _info;
  String? _err;
  bool _saving = false;
  DateTime _end = DateTime.now();
  final TextEditingController _cost = TextEditingController();
  final List<_OutRow> _rows = <_OutRow>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cost.dispose();
    for (final _OutRow r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final Map<String, dynamic> r = await StockApi.call('mixes.info', <String, dynamic>{'id': widget.mixId});
      if (!mounted) return;
      setState(() {
        _info = r;
        if (_rows.isEmpty) {
          final _OutRow o = _OutRow()..name.text = widget.title;
          o.kg.text = plain(_inKg);
          _rows.add(o);
        }
      });
    } on StockApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
  }

  double get _inKg => ((_info?['input_kg'] as num?) ?? 0).toDouble();
  double get _inValue => ((_info?['input_value'] as num?) ?? 0).toDouble();
  double get _outKg => _rows.fold<double>(0, (double s, _OutRow r) => s + (parseNum(r.kg.text) ?? 0));
  double get _costPerKg => (MoneyField.stored(_cost) ?? 0).toDouble();

  Future<void> _close() async {
    if (!_form.currentState!.validate()) return;
    for (final _OutRow r in _rows) {
      if (r.name.text.trim().isEmpty) return snack(context, 'نام هر خروجی را وارد کنید');
      if ((parseNum(r.kg.text) ?? 0) <= 0) return snack(context, 'وزن هر خروجی باید بیشتر از صفر باشد');
    }
    if (_outKg - _inKg > 0.0015) return snack(context, 'جمع وزن خروجی‌ها از وزن ورودی (${faNum(_inKg)} کیلو) بیشتر است');
    final MixStagedCost c = mixStagedCost(_inKg, _inValue, _outKg, _costPerKg);
    if (!await confirm(context,
        'کوت بسته شود؟\n${faNum(_rows.length, dec: 0)} خروجی، جمع ${faNum(_outKg)} کیلو، ضایعات ${faNum(c.waste)} کیلو\nبهای هر کیلو: ${Fmt.money(c.unit)}')) {
      return;
    }
    setState(() => _saving = true);
    try {
      await StockApi.call('mixes.close', <String, dynamic>{
        'id': widget.mixId,
        'end_date': _end.toIso8601String().substring(0, 10),
        if (_costPerKg > 0) 'cost_per_kg': _costPerKg,
        'outputs': <Map<String, dynamic>>[for (final _OutRow r in _rows) r.toJson()],
      });
      SyncService.I.pollNow();
      if (!mounted) return;
      snack(context, 'کوت بسته شد و لات‌های خروجی در انبار ثبت شدند');
      Navigator.pop(context, true);
    } on StockApiException catch (e) {
      if (mounted) snack(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelMix() async {
    if (!await confirm(context, 'کوت لغو شود؟ وزن و عدل‌ها به لات‌های ورودی برمی‌گردد.')) return;
    setState(() => _saving = true);
    try {
      await StockApi.call('mixes.cancel_open', <String, dynamic>{'id': widget.mixId});
      SyncService.I.pollNow();
      if (!mounted) return;
      snack(context, 'کوت لغو شد');
      Navigator.pop(context, true);
    } on StockApiException catch (e) {
      if (mounted) snack(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _num(TextEditingController c, String label, {bool req = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
          validator: (String? v) {
            if ((v ?? '').trim().isEmpty) return req ? 'لازم است' : null;
            final double? n = parseNum(v);
            return n == null || n < 0 ? 'عدد معتبر' : null;
          },
          onChanged: (_) => setState(() {}),
        ),
      );

  Widget _txt(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(controller: c, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true)),
      );

  Widget _pair(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Expanded(child: a), const SizedBox(width: 8), Expanded(child: b)]);

  Widget _outCard(int i) {
    final _OutRow r = _rows[i];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: Text('خروجی ${faNum(i + 1, dec: 0)}', style: const TextStyle(fontWeight: FontWeight.bold))),
            if (_rows.length > 1)
              IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => _rows.removeAt(i).dispose()),
              ),
          ]),
          _pair(_txt(r.name, 'نام / نوع لات خروجی'), _txt(r.lotName, 'نام لات (اختیاری)')),
          _pair(_num(r.kg, 'وزن خالص (کیلو)', req: true), _pair(_num(r.small, 'عدل کوچک'), _num(r.large, 'عدل بزرگ'))),
          _pair(_num(r.ounce, 'انس'), _num(r.gram, 'گرم')),
          _pair(_pair(_num(r.tuchin, 'توچین ٪'), _num(r.dombest, 'دهن‌بست ٪')), _pair(_num(r.crooked, 'کج ٪'), _num(r.khandan, 'خندان ٪'))),
          for (final (TextEditingController l, TextEditingController v) in r.specs) _pair(_txt(l, 'مشخصه'), _txt(v, 'مقدار')),
          if (r.specs.length < 4)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => r.specs.add((TextEditingController(), TextEditingController()))),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('مشخصهٔ دلخواه'),
              ),
            ),
          WarehousePicker(label: 'انبار این خروجی', value: r.wh, onChanged: (String? v) => r.wh = v),
          _txt(r.note, 'توضیح (اختیاری)'),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String title = 'بستن کوت${widget.title.isEmpty ? '' : ' — ${widget.title}'}';
    if (_info == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: _err == null
              ? const CircularProgressIndicator()
              : Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Padding(padding: const EdgeInsets.all(16), child: Text(_err!, textAlign: TextAlign.center)),
                  FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('تلاش دوباره')),
                ]),
        ),
      );
    }
    final MixStagedCost c = mixStagedCost(_inKg, _inValue, _outKg, _costPerKg);
    final bool over = _outKg - _inKg > 0.0015;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(12), children: <Widget>[
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                infoRow('کوت', '${_info!['code'] ?? ''}'),
                infoRow('وزن ورودی', '${faNum(_inKg)} کیلو'),
                infoRow('ارزش ورودی', Fmt.money(_inValue)),
                infoRow('بهای هر کیلو ورودی', Fmt.money(c.base == 0 && _inKg > 0 ? _inValue / _inKg : c.base)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: <Widget>[
            Expanded(child: JalaliDateField(label: 'تاریخ پایان', value: _end, onChanged: (DateTime d) => setState(() => _end = d))),
            const SizedBox(width: 8),
            Expanded(child: MoneyField(controller: _cost, label: 'هزینهٔ کوت‌ریزی هر کیلو (اختیاری)', onChanged: () => setState(() {}))),
          ]),
          sectionTitle(context, 'خروجی‌ها'),
          for (int i = 0; i < _rows.length; i++) _outCard(i),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _rows.add(_OutRow()..name.text = widget.title)),
              icon: const Icon(Icons.add),
              label: const Text('خروجی دیگر'),
            ),
          ),
          Card(
            color: over ? Theme.of(context).colorScheme.errorContainer : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                infoRow('جمع خروجی‌ها', '${faNum(_outKg)} کیلو'),
                infoRow('ضایعات', over ? 'خروجی از ورودی بیشتر است' : '${faNum(c.waste)} کیلو'),
                const Divider(),
                infoRow('بهای پستهٔ ورودی (هر کیلو)', Fmt.money(c.base)),
                infoRow('سهم ضایعات (هر کیلو)', Fmt.money(c.wasteShare)),
                infoRow('سهم هزینهٔ کوت‌ریزی (هر کیلو)', Fmt.money(c.costShare)),
                infoRow('بهای تمام‌شدهٔ هر کیلو خروجی', Fmt.money(c.unit), valueColor: Theme.of(context).colorScheme.primary),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving || over ? null : _close,
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
            label: const Text('ثبت خروجی‌ها و بستن کوت'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saving ? null : _cancelMix,
            icon: const Icon(Icons.undo),
            label: const Text('لغو کوت (برگشت به لات‌های ورودی)'),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
