// v95/v96 — فرایند مرحله‌ای «کوت‌ریزی» و «جداکردن / غربال» (DESIGN_v95_mix_sep_FA.md بخش‌های ۲ و ۸). فایل مشترک اندروید و ویندوز.
// شروع در mix_form.dart (mixes.open با kind). این فایل: انتخاب نوع، فهرست فرایندها، و صفحهٔ فرایند:
//   باز  ⇒ افزودن/تغییر ورودی‌ها، ثبت خروجی‌ها و هزینه‌ها (ذخیره روی سرور، چند بار)، بستن و ثبت در انبار، لغو.
//   بسته ⇒ «ویرایش کامل» همان صفحه (mixes.edit): ورودی‌ها، خروجی‌ها، هزینه‌ها؛ خروجیِ مصرف‌شده ⇒ وزن ≥ مصرف و تعداد ثابت.
// خروجی‌ها مثل فرم خرید: انس، گرم، درصدها با «گرم مغز» هر درصد (بخش درصدهای فرم خرید، بدون قیمت‌گذاری). همه اختیاری.
import 'dart:convert';

import 'package:flutter/material.dart';

import 'db.dart';
import 'fmt.dart' show Fmt, MoneyField;
import 'mix_form.dart' show MixForm;
import 'purchase_pct_ui.dart' show PurchasePctCtl, PurchasePctSection;
import 'returns_ui.dart' show ReturnsHelp;
import 'separation_form.dart' show SeparationsScreen;
import 'sync_service.dart';
import 'utils.dart';
import 'warehouse_ui.dart' show StockApi, StockApiException, WarehousePicker;
import 'widgets.dart';

/// بهای فرایند مرحله‌ای — آینهٔ دقیق pb_mix_staged_cost سرور.
/// بهای هر کیلو خروجی = (V + c × I + X) ÷ O؛ تفکیک: V÷I + سهم ضایعات W×(V÷I)÷O + سهم هزینه‌ها (c×I + X)÷O.
class MixStagedCost {
  final double unit, base, wasteShare, costShare, waste;
  const MixStagedCost(this.unit, this.base, this.wasteShare, this.costShare, this.waste);
}

MixStagedCost mixStagedCost(double inKg, double inValue, double outKg, double costPerKg, [double extra = 0]) {
  final double w = inKg - outKg > 0 ? inKg - outKg : 0;
  if (inKg <= 0 || outKg <= 0) return MixStagedCost(0, 0, 0, 0, w);
  final double base = inValue / inKg;
  return MixStagedCost((inValue + costPerKg * inKg + extra) / outKg, base, w * base / outKg, (costPerKg * inKg + extra) / outKg, w);
}

String _noun(String kind) => kind == 'sep' ? 'جداسازی' : 'کوت';

/// فرایندهای در جریان روی این دستگاه (آینهٔ محلی؛ کارت انبار)
Future<List<Map<String, dynamic>>> loadOpenMixes() => loadStagedProcesses(openOnly: true);

/// فرایندهای مرحله‌ای (باز، و بسته‌های اخیر برای ویرایش). [kind] null = همه.
Future<List<Map<String, dynamic>>> loadStagedProcesses({String? kind, bool openOnly = false}) async {
  try {
    final rows = await (await AppDb.I.db).rawQuery(
        "SELECT id, code, type_name, date, net_weight, price, mix_status, mix_kind FROM purchases WHERE mix_status ${openOnly ? "= 'open'" : "IS NOT NULL"} ORDER BY mix_status = 'open' DESC, date DESC, id DESC LIMIT 200");
    return <Map<String, dynamic>>[
      for (final r in rows)
        if (kind == null || (r['mix_kind'] == 'sep' ? 'sep' : 'mix') == kind) Map<String, dynamic>.from(r),
    ];
  } catch (_) {
    return <Map<String, dynamic>>[]; // ستون‌ها هنوز نیست
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
          subtitle: const Text('چند لات ⇒ کوت؛ ورودی و خروجی‌ها را در طول کار ثبت کنید و در پایان ببندید'),
          onTap: () => Navigator.pop(ctx, 'mix'),
        ),
        ListTile(
          leading: const Icon(Icons.call_split),
          title: const Text('جداکردن / غربال'),
          subtitle: const Text('یک یا چند لات ⇒ چند خروجی؛ مثل کوت‌ریزی مرحله‌ای'),
          onTap: () => Navigator.pop(ctx, 'sep'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (!context.mounted || pick == null) return;
  await showMixHub(context, kind: pick);
}

/// فرایندهای یک نوع + «تازه» (+ جداسازی‌های قبلی برای جداسازی)
Future<void> showMixHub(BuildContext context, {String kind = 'mix'}) async {
  final List<Map<String, dynamic>> list = await loadStagedProcesses(kind: kind);
  if (!context.mounted) return;
  final String noun = _noun(kind);
  final Object? pick = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: <Widget>[
        ListTile(
          leading: const Icon(Icons.add_circle_outline),
          title: Text(kind == 'sep' ? 'جداسازی / غربال تازه' : 'کوت‌ریزی تازه'),
          onTap: () => Navigator.pop(ctx, 'new'),
        ),
        if (kind == 'sep')
          ListTile(leading: const Icon(Icons.history), title: const Text('جداسازی‌های قبلی (یک‌مرحله‌ای)'), onTap: () => Navigator.pop(ctx, 'old')),
        if (list.isNotEmpty) ...<Widget>[
          const Divider(),
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text('${noun == 'کوت' ? 'کوت‌ها' : 'جداسازی‌ها'}ی مرحله‌ای', style: const TextStyle(fontWeight: FontWeight.bold))),
          for (final Map<String, dynamic> m in list)
            ListTile(
              leading: Icon(m['mix_status'] == 'open' ? Icons.pending_actions : Icons.check_circle_outline),
              title: Text('${m['type_name'] ?? ''} — ${m['code'] ?? ''}'),
              subtitle: Text('${m['mix_status'] == 'open' ? 'در جریان' : 'بسته'} • ${jalaliDate('${m['date'] ?? ''}')} • ${faNum((m['net_weight'] as num?) ?? 0)} کیلو'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.pop(ctx, m),
            ),
        ],
      ]),
    ),
  );
  if (!context.mounted || pick == null) return;
  if (pick == 'new') {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MixForm(kind: kind)));
  } else if (pick == 'old') {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SeparationsScreen()));
  } else if (pick is Map<String, dynamic>) {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MixProcessScreen(mixId: pick['id'] as int, title: '${pick['type_name'] ?? ''}')));
  }
}

/// سازگاری با نام قبلی
typedef MixCloseScreen = MixProcessScreen;

class _InRow {
  _InRow({this.lot});
  int? lot;
  final TextEditingController kg = TextEditingController();
  final TextEditingController small = TextEditingController();
  final TextEditingController large = TextEditingController();
  void dispose() {
    kg.dispose();
    small.dispose();
    large.dispose();
  }
}

class _OutRow {
  _OutRow({this.lotId, this.usedKg = 0});
  final int? lotId; // خروجی موجود (فرایند بسته)
  final double usedKg; // فروخته/مصرف‌شده
  int? cat; // v96: دستهٔ پستهٔ خروجی (مثل فرم خرید)
  String? type; // v96: نوع پستهٔ خروجی (type_name لات)
  String get label => (type ?? '').isNotEmpty ? type! : (lotName.text.trim().isNotEmpty ? lotName.text.trim() : 'خروجی');
  final TextEditingController name = TextEditingController();
  final TextEditingController lotName = TextEditingController();
  final TextEditingController kg = TextEditingController();
  final TextEditingController small = TextEditingController();
  final TextEditingController large = TextEditingController();
  final TextEditingController ounce = TextEditingController();
  final TextEditingController gram = TextEditingController();
  final TextEditingController note = TextEditingController();
  final PurchasePctCtl pct = PurchasePctCtl(allowPricing: false); // درصدها + گرم مغز هر درصد (مثل فرم خرید)
  String? wh;

  /// پر کردن از ردیف سرور (خروجی بسته یا ذخیره‌شده)
  void fill(Map<String, dynamic> o) {
    String t(Object? v) => v == null ? '' : (v is num ? plain(v) : '$v');
    type = '${o['type_name'] ?? ''}'.trim().isEmpty ? null : '${o['type_name']}';
    final Object? c = o['category_id'];
    cat = c is num && c > 0 ? c.toInt() : (int.tryParse('${c ?? ''}') ?? cat);
    lotName.text = t(o['lot_name'] ?? o['seller']);
    kg.text = t(o['kg'] ?? o['net_weight']);
    final Object? sm = o['small_sacks'] ?? o['small_sack_count'], lg = o['large_sacks'] ?? o['large_sack_count'];
    small.text = sm is num && sm == 0 ? '' : t(sm);
    large.text = lg is num && lg == 0 ? '' : t(lg);
    ounce.text = t(o['ounce']);
    gram.text = t(o['gram']);
    note.text = t(o['note']);
    wh = o['warehouse_uid'] as String?;
    final Object? cs = o['custom_specs'];
    pct.loadFrom(<String, dynamic>{
      for (final String k in const <String>['pct_tuchin', 'pct_dombest', 'pct_crooked', 'pct_khandan']) k: o[k],
      'custom_specs': cs is String ? cs : (cs is List ? jsonEncode(cs) : null),
    });
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (lotId != null) 'lot_id': lotId,
        'type_name': (type ?? '').trim(),
        if (cat != null) 'category_id': cat, // در _payload به شناسهٔ سرور تبدیل می‌شود
        'kg': parseNum(kg.text) ?? 0,
        'small_sacks': parseNum(small.text) ?? 0,
        'large_sacks': parseNum(large.text) ?? 0,
        'lot_name': lotName.text.trim(),
        'note': note.text.trim(),
        if (wh != null) 'warehouse_uid': wh,
        'ounce': parseNum(ounce.text),
        'gram': parseNum(gram.text),
        ...pct.fields(),
        'custom_specs': pct.specRows(),
      };

  void dispose() {
    for (final TextEditingController c in <TextEditingController>[name, lotName, kg, small, large, ounce, gram, note]) {
      c.dispose();
    }
    pct.dispose();
  }
}

/// صفحهٔ یک فرایند مرحله‌ای (کوت یا جداسازی): باز ⇒ ثبت/ذخیره/بستن؛ بسته ⇒ ویرایش کامل.
class MixProcessScreen extends StatefulWidget {
  const MixProcessScreen({super.key, required this.mixId, this.title = ''});
  final int mixId;
  final String title;

  @override
  State<MixProcessScreen> createState() => _MixProcessScreenState();
}

class _MixProcessScreenState extends State<MixProcessScreen> with EditGuard<MixProcessScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  Map<String, dynamic>? _info;
  String? _err;
  bool _saving = false;
  DateTime _end = DateTime.now();
  final TextEditingController _cost = TextEditingController();
  final TextEditingController _extra = TextEditingController();
  final List<_InRow> _ins = <_InRow>[];
  final List<_OutRow> _outs = <_OutRow>[];
  Map<int, Map<String, dynamic>> _lots = <int, Map<String, dynamic>>{};
  Map<int, double> _ownKg = <int, double>{}; // وزنی که همین فرایند از هر لات برداشته (برای موجودی قابل انتخاب)
  List<Map<String, dynamic>> _cats = <Map<String, dynamic>>[]; // v96: دسته‌ها (مثل فرم خرید)
  final Map<int, List<String>> _types = <int, List<String>>{}; // نوع‌های هر دسته

  Future<void> _loadTypes(int? cat) async {
    if (cat == null || _types.containsKey(cat)) return;
    final List<Map<String, dynamic>> l = await AppDb.I.typesOf(cat);
    if (mounted) setState(() => _types[cat] = <String>[for (final Map<String, dynamic> t in l) '${t['name']}']);
  }

  Future<void> _addType(_OutRow o) async {
    final int? cid = o.cat;
    if (cid == null) return snack(context, 'اول دسته را انتخاب کنید');
    final TextEditingController c = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('افزودن نوع پسته'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'نام نوع')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('افزودن')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final bool ok = await saveConfirmed(context, () => AppDb.I.addType(cid, name), successMsg: 'نوع «$name» اضافه شد');
    if (!ok || !mounted) return;
    _types.remove(cid);
    o.type = name;
    await _loadTypes(cid);
  }

  bool get _open => _info?['status'] == 'open';
  String get _kind => _info?['kind'] == 'sep' ? 'sep' : 'mix';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cost.dispose();
    _extra.dispose();
    for (final _InRow r in _ins) {
      r.dispose();
    }
    for (final _OutRow r in _outs) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final Map<String, dynamic> r = await StockApi.call('mixes.info', <String, dynamic>{'id': widget.mixId});
      final List<Map<String, dynamic>> lots = await AppDb.I.lots();
      _cats = await AppDb.I.categories();
      final int defCat = ReturnsHelp.d(r['category_id']).toInt();
      final List<_OutRow> outs = <_OutRow>[];
      final bool open = r['status'] == 'open';
      final List<Map<String, dynamic>> src = ReturnsHelp.maps(open ? r['pending'] : r['outputs']);
      for (final Map<String, dynamic> o in src) {
        final _OutRow x = _OutRow(lotId: open ? null : ReturnsHelp.d(o['id']).toInt(), usedKg: open ? 0 : ReturnsHelp.d(o['used_kg']))..cat = defCat > 0 ? defCat : null;
        await x.pct.init();
        x.fill(o);
        outs.add(x);
      }
      if (outs.isEmpty) {
        final _OutRow x = _OutRow()
          ..cat = defCat > 0 ? defCat : null
          ..type = '${r['base_type'] ?? ''}'.isEmpty ? null : '${r['base_type']}';
        await x.pct.init();
        outs.add(x);
      }
      if (!mounted) return;
      setState(() {
        _info = r;
        _lots = <int, Map<String, dynamic>>{for (final Map<String, dynamic> l in lots) ReturnsHelp.d(l['id']).toInt(): l};
        for (final _InRow x in _ins) {
          x.dispose();
        }
        _ins.clear();
        _ownKg = <int, double>{};
        for (final Map<String, dynamic> i in ReturnsHelp.maps(r['inputs'])) {
          final int lot = ReturnsHelp.d(i['lot_id']).toInt();
          _ownKg[lot] = (_ownKg[lot] ?? 0) + ReturnsHelp.d(i['kg']);
          _ins.add(_InRow(lot: lot)
            ..kg.text = plain(ReturnsHelp.d(i['kg']))
            ..small.text = ReturnsHelp.d(i['small_sacks']) == 0 ? '' : plain(ReturnsHelp.d(i['small_sacks']))
            ..large.text = ReturnsHelp.d(i['large_sacks']) == 0 ? '' : plain(ReturnsHelp.d(i['large_sacks'])));
          // لات تمام‌شده هم در فهرست انتخاب بماند
          _lots.putIfAbsent(lot, () => <String, dynamic>{'id': lot, 'code': i['code'], 'type_name': i['type_name'], 'seller': i['seller'], 'remaining': 0, 'small_left': 0, 'large_left': 0});
        }
        for (final _OutRow x in _outs) {
          x.dispose();
        }
        _outs
          ..clear()
          ..addAll(outs);
        for (final _OutRow o in outs) {
          _loadTypes(o.cat);
        }
        final double c = ReturnsHelp.d(r['cost_per_kg']), x = ReturnsHelp.d(r['extra_cost']);
        if (c > 0) {
          MoneyField.setStored(_cost, c);
        } else {
          _cost.clear();
        }
        if (x > 0) {
          MoneyField.setStored(_extra, x);
        } else {
          _extra.clear();
        }
        _end = DateTime.tryParse('${r['end_date'] ?? ''}') ?? DateTime.now();
      });
    } on StockApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
  }

  // ---- محاسبه ----
  double get _inKg => _ins.fold<double>(0, (double s, _InRow r) => s + (parseNum(r.kg.text) ?? 0));
  double get _outKg => _outs.fold<double>(0, (double s, _OutRow r) => s + (parseNum(r.kg.text) ?? 0));
  bool get _inputsChanged {
    final Map<int, double> now = <int, double>{};
    for (final _InRow r in _ins) {
      if (r.lot != null) now[r.lot!] = (now[r.lot!] ?? 0) + (parseNum(r.kg.text) ?? 0);
    }
    if (now.length != _ownKg.length) return true;
    for (final MapEntry<int, double> e in now.entries) {
      if (((_ownKg[e.key] ?? -1) - e.value).abs() > 1e-6) return true;
    }
    return false;
  }

  /// ارزش ورودی: سرور (دقیق، با کارمزد دلال) یا تخمین محلی اگر ورودی‌ها تغییر کرده‌اند
  double get _inValue {
    if (!_inputsChanged) return ReturnsHelp.d(_info?['input_value']);
    double v = 0;
    for (final _InRow r in _ins) {
      v += (parseNum(r.kg.text) ?? 0) * ReturnsHelp.d(_lots[r.lot]?['price']);
    }
    return v;
  }

  double _avail(int lot) => ReturnsHelp.d(_lots[lot]?['remaining']) + (_ownKg[lot] ?? 0);

  String? _problem() {
    final List<_InRow> ins = _ins.where((r) => r.lot != null && (parseNum(r.kg.text) ?? 0) > 0).toList();
    if (ins.map((r) => r.lot).toSet().length < (_kind == 'sep' ? 1 : 2)) return _kind == 'sep' ? 'حداقل یک لات ورودی لازم است' : 'برای کوت‌ریزی حداقل دو لات ورودی لازم است';
    final Map<int, double> byLot = <int, double>{};
    for (final _InRow r in ins) {
      byLot[r.lot!] = (byLot[r.lot!] ?? 0) + (parseNum(r.kg.text) ?? 0);
    }
    for (final MapEntry<int, double> e in byLot.entries) {
      if (e.value > _avail(e.key) + 1e-6) return 'وزن «${_lots[e.key]?['type_name'] ?? ''}» از موجودی (${faNum(_avail(e.key))} کیلو) بیشتر است';
    }
    for (final _OutRow o in _outs) {
      if (o.cat == null || (o.type ?? '').trim().isEmpty) return 'دسته و نوع پستهٔ هر خروجی را انتخاب کنید';
      if ((parseNum(o.kg.text) ?? 0) <= 0) return 'وزن هر خروجی باید بیشتر از صفر باشد';
      if ((parseNum(o.kg.text) ?? 0) + 1e-6 < o.usedKg) return 'وزن «${o.label}» نمی‌تواند کمتر از مقدار فروخته/مصرف‌شده (${faNum(o.usedKg)} کیلو) باشد';
      final String? pe = o.pct.validate();
      if (pe != null) return '«${o.label}»: $pe';
    }
    if (_outKg - _inKg > 0.0015) return 'جمع وزن خروجی‌ها (${faNum(_outKg)}) از وزن ورودی (${faNum(_inKg)} کیلو) بیشتر است';
    return null;
  }

  /// شناسهٔ سرور دستهٔ خروجی‌ها (دستهٔ تازهٔ همگام‌نشده ⇒ اول همگام‌سازی)
  Future<Map<String, dynamic>> _payload() async {
    final Map<String, dynamic> p = _payloadRaw();
    for (final Map<String, dynamic> o in (p['outputs'] as List<Map<String, dynamic>>? ?? const <Map<String, dynamic>>[])) {
      final Object? c = o['category_id'];
      if (c is int) o['category_id'] = await ReturnsHelp.serverId('cat', c);
    }
    return p;
  }

  Map<String, dynamic> _payloadRaw({bool withOutputs = true}) => <String, dynamic>{
        'id': widget.mixId,
        if (!_open) 'end_date': _end.toIso8601String().substring(0, 10),
        'cost_per_kg': (MoneyField.stored(_cost) ?? 0).toDouble(),
        'extra_cost': (MoneyField.stored(_extra) ?? 0).toDouble(),
        'sources': <Map<String, dynamic>>[
          for (final _InRow r in _ins)
            if (r.lot != null && (parseNum(r.kg.text) ?? 0) > 0)
              <String, dynamic>{'purchase_id': r.lot, 'weight': parseNum(r.kg.text) ?? 0, 'small_sacks': parseNum(r.small.text), 'large_sacks': parseNum(r.large.text)},
        ],
        if (withOutputs) 'outputs': <Map<String, dynamic>>[for (final _OutRow o in _outs) if (!_open || (parseNum(o.kg.text) ?? 0) > 0) o.toJson()], // باز: ردیف خالی فرستاده نمی‌شود
      };

  Future<bool> _run(Future<void> Function() f, String ok) async {
    setState(() => _saving = true);
    try {
      await SyncService.I.syncNow(pull: false);
      await f();
      SyncService.I.pollNow();
      if (mounted) snack(context, ok);
      return true;
    } on StockApiException catch (e) {
      if (mounted) snack(context, e.message);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// باز ⇒ ذخیرهٔ ورودی‌ها، خروجی‌ها و هزینه‌ها روی سرور (بدون بستن)؛ بسته ⇒ ذخیرهٔ ویرایش کامل
  Future<void> _save() async {
    final String? p = _open ? _problemOpen() : _problem();
    if (p != null) return snack(context, p);
    if (!_open && !await confirm(context, 'ویرایش ذخیره شود؟ بهای خروجی‌ها و اسناد بعدی (فروش، …) دوباره حساب می‌شود.')) return;
    if (await _run(() async => StockApi.call('mixes.edit', await _payload()), _open ? 'ذخیره شد (فرایند هنوز باز است)' : 'ویرایش ذخیره شد')) await _load();
  }

  /// فرایندِ باز: خروجی‌ها می‌توانند هنوز کامل نباشند
  String? _problemOpen() {
    final List<_InRow> ins = _ins.where((r) => r.lot != null && (parseNum(r.kg.text) ?? 0) > 0).toList();
    if (ins.map((r) => r.lot).toSet().length < (_kind == 'sep' ? 1 : 2)) return _kind == 'sep' ? 'حداقل یک لات ورودی لازم است' : 'برای کوت‌ریزی حداقل دو لات ورودی لازم است';
    for (final _InRow r in ins) {
      double kg = 0;
      for (final _InRow x in ins) {
        if (x.lot == r.lot) kg += parseNum(x.kg.text) ?? 0;
      }
      if (kg > _avail(r.lot!) + 1e-6) return 'وزن «${_lots[r.lot]?['type_name'] ?? ''}» از موجودی (${faNum(_avail(r.lot!))} کیلو) بیشتر است';
    }
    for (final _OutRow o in _outs) {
      if ((o.type ?? '').trim().isEmpty && (parseNum(o.kg.text) ?? 0) > 0) return 'دسته و نوع پستهٔ هر خروجی را انتخاب کنید';
      final String? pe = o.pct.validate();
      if (pe != null) return pe;
    }
    return null;
  }

  Future<void> _close() async {
    final String? p = _problem();
    if (p != null) return snack(context, p);
    final MixStagedCost c = mixStagedCost(_inKg, _inValue, _outKg, (MoneyField.stored(_cost) ?? 0).toDouble(), (MoneyField.stored(_extra) ?? 0).toDouble());
    if (!await confirm(context,
        '${_noun(_kind)} بسته شود و خروجی‌ها در انبار ثبت شوند؟\n${faNum(_outs.length, dec: 0)} خروجی، جمع ${faNum(_outKg)} کیلو، ضایعات ${faNum(c.waste)} کیلو\nبهای هر کیلو: ${Fmt.money(c.unit)}')) {
      return;
    }
    final bool ok = await _run(() async {
      await StockApi.call('mixes.edit', await _payload());
      await StockApi.call('mixes.close', <String, dynamic>{'id': widget.mixId, 'end_date': _end.toIso8601String().substring(0, 10)});
    }, '${_noun(_kind)} بسته شد و لات‌های خروجی در انبار ثبت شدند');
    if (ok && mounted) await _load();
  }

  Future<void> _cancel() async {
    if (!await confirm(context, '${_noun(_kind)} لغو شود؟ وزن و عدل‌ها به لات‌های ورودی برمی‌گردد و خروجی‌های ذخیره‌شده پاک می‌شود.')) return;
    if (await _run(() => StockApi.call('mixes.cancel_open', <String, dynamic>{'id': widget.mixId}), '${_noun(_kind)} لغو شد') && mounted) Navigator.pop(context, true);
  }

  // ---- رابط ----
  Widget _num(TextEditingController c, String label, {bool money = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: money
            ? MoneyField(controller: c, label: label, onChanged: () => setState(() {}))
            : TextFormField(
                controller: c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
                onChanged: (_) => setState(() {}),
              ),
      );

  Widget _txt(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(controller: c, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true), onChanged: (_) => setState(() {})),
      );

  Widget _row(List<Widget> w) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        for (int i = 0; i < w.length; i++) ...<Widget>[if (i > 0) const SizedBox(width: 8), Expanded(child: w[i])],
      ]);

  String _lotLabel(Map<String, dynamic> l) {
    final String who = '${l['seller'] ?? ''}'.trim().isNotEmpty ? '${l['seller']}' : '${l['type_name'] ?? ''}';
    return '$who · ${l['code'] ?? ''} · ${faNum(_avail(ReturnsHelp.d(l['id']).toInt()))} کیلو';
  }

  Widget _inCard(int i) {
    final _InRow r = _ins[i];
    // فقط لات‌های رسیده به سرور (شناسهٔ مثبت)
    final List<Map<String, dynamic>> choices = _lots.values.where((l) => ReturnsHelp.d(l['id']) > 0 && (_avail(ReturnsHelp.d(l['id']).toInt()) > 0.0005 || ReturnsHelp.d(l['id']).toInt() == r.lot)).toList();
    return Card(
      key: ObjectKey(r),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: <Widget>[
          Row(children: <Widget>[
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey<String>('in-${identityHashCode(r)}-${choices.length}'),
                initialValue: choices.any((l) => ReturnsHelp.d(l['id']).toInt() == r.lot) ? r.lot : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'لات ورودی', border: OutlineInputBorder(), isDense: true),
                items: <DropdownMenuItem<int>>[
                  for (final Map<String, dynamic> l in choices)
                    DropdownMenuItem<int>(value: ReturnsHelp.d(l['id']).toInt(), child: Text(_lotLabel(l), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (int? v) => setState(() => r.lot = v),
              ),
            ),
            IconButton(tooltip: 'حذف', icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() => _ins.removeAt(i).dispose())),
          ]),
          const SizedBox(height: 8),
          _row(<Widget>[_num(r.kg, 'وزن (کیلو)'), _num(r.small, 'عدل کوچک'), _num(r.large, 'عدل بزرگ')]),
        ]),
      ),
    );
  }

  Widget _outCard(int i) {
    final _OutRow o = _outs[i];
    return Card(
      key: ObjectKey(o),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: Text('خروجی ${faNum(i + 1, dec: 0)}${o.usedKg > 0 ? ' — ${faNum(o.usedKg)} کیلو فروخته/مصرف شده' : ''}', style: const TextStyle(fontWeight: FontWeight.bold))),
            if (o.usedKg <= 0 && _outs.length > 1)
              IconButton(tooltip: 'حذف', icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _outs.removeAt(i).dispose())),
          ]),
          // v96: دسته و نوع پسته مثل فرم خرید؛ نام دلخواه در «نام لات»
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DropdownButtonFormField<int>(
                  key: ValueKey<String>('oc-${identityHashCode(o)}-${o.cat}-${_cats.length}'),
                  initialValue: _cats.any((Map<String, dynamic> c) => c['id'] == o.cat) ? o.cat : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'دسته', border: OutlineInputBorder(), isDense: true),
                  items: <DropdownMenuItem<int>>[
                    for (final Map<String, dynamic> c in _cats) DropdownMenuItem<int>(value: c['id'] as int, child: Text('${c['name']}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (int? v) {
                    setState(() {
                      o.cat = v;
                      o.type = null;
                    });
                    _loadTypes(v);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DropdownButtonFormField<String>(
                  key: ValueKey<String>('ot-${identityHashCode(o)}-${o.cat}-${o.type}-${_types[o.cat]?.length}'),
                  initialValue: o.type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'نوع پسته', border: OutlineInputBorder(), isDense: true),
                  items: <DropdownMenuItem<String>>[
                    for (final String t in <String>{...?_types[o.cat], if (o.type != null) o.type!}) DropdownMenuItem<String>(value: t, child: Text(t, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (String? v) => setState(() => o.type = v),
                ),
              ),
            ),
            IconButton(tooltip: 'افزودن نوع', icon: const Icon(Icons.add), onPressed: () => _addType(o)),
          ]),
          _txt(o.lotName, 'نام لات (اختیاری)'),
          _row(<Widget>[_num(o.kg, 'وزن خالص (کیلو)'), _num(o.small, 'عدل کوچک'), _num(o.large, 'عدل بزرگ')]),
          _row(<Widget>[_num(o.ounce, 'انس (اختیاری)'), _num(o.gram, 'گرم (اختیاری)')]),
          // درصدها و گرم مغز هر درصد — همان بخش فرم خرید (اختیاری؛ بدون قیمت‌گذاری)
          PurchasePctSection(ctl: o.pct, basePrice: null, netKg: parseNum(o.kg.text) ?? 0, onChanged: () => setState(() {})),
          WarehousePicker(label: 'انبار این خروجی', value: o.wh, onChanged: (String? v) => o.wh = v),
          _txt(o.note, 'توضیح (اختیاری)'),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String noun = _info == null ? 'فرایند' : _noun(_kind);
    final String title = _info == null ? widget.title : '$noun ${_open ? 'در جریان' : '(ویرایش کامل)'} — ${_info!['type_name'] ?? widget.title}';
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
    final double cpk = (MoneyField.stored(_cost) ?? 0).toDouble(), extra = (MoneyField.stored(_extra) ?? 0).toDouble();
    final MixStagedCost c = mixStagedCost(_inKg, _inValue, _outKg, cpk, extra);
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
                infoRow(noun, '${_info!['code'] ?? ''} — ${_open ? 'در جریان (ورودی‌ها از انبار برداشته شده)' : 'بسته'}'),
                infoRow('شروع', jalaliDate('${_info!['date'] ?? ''}')),
                Text(
                    _open
                        ? 'ورودی‌ها و خروجی‌ها را هر وقت لازم شد اضافه یا اصلاح کنید و «ذخیره» بزنید (روی همهٔ دستگاه‌ها دیده می‌شود). در پایان «بستن و ثبت در انبار».'
                        : 'همهٔ بخش‌ها قابل ویرایش است. اگر از خروجی‌ای فروش یا مصرف شده، تعداد خروجی‌ها ثابت می‌ماند و وزنش از مقدار مصرف‌شده کمتر نمی‌شود.',
                    style: const TextStyle(fontSize: 12.5)),
              ]),
            ),
          ),
          sectionTitle(context, 'ورودی‌ها'),
          for (int i = 0; i < _ins.length; i++) _inCard(i),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(onPressed: () => setState(() => _ins.add(_InRow())), icon: const Icon(Icons.add), label: const Text('افزودن لات ورودی')),
          ),
          infoRow('جمع ورودی', '${faNum(_inKg)} کیلو'),
          sectionTitle(context, 'خروجی‌ها'),
          for (int i = 0; i < _outs.length; i++) _outCard(i),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () async {
                final int defCat = ReturnsHelp.d(_info!['category_id']).toInt();
                final _OutRow x = _OutRow()..cat = defCat > 0 ? defCat : null;
                _loadTypes(x.cat);
                await x.pct.init();
                if (mounted) setState(() => _outs.add(x));
              },
              icon: const Icon(Icons.add),
              label: const Text('خروجی دیگر'),
            ),
          ),
          sectionTitle(context, 'هزینه‌ها'),
          _row(<Widget>[
            _num(_cost, 'هزینهٔ هر کیلو ورودی (اختیاری)', money: true),
            _num(_extra, _kind == 'sep' ? 'دستمزد، حمل و سایر (کل، اختیاری)' : 'سایر هزینه‌ها (کل، اختیاری)', money: true),
          ]),
          if (!_open) Padding(padding: const EdgeInsets.only(bottom: 8), child: JalaliDateField(label: 'تاریخ پایان', value: _end, onChanged: (DateTime d) => setState(() => _end = d))),
          Card(
            color: over ? Theme.of(context).colorScheme.errorContainer : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                infoRow('جمع خروجی‌ها', '${faNum(_outKg)} کیلو'),
                infoRow('ضایعات', over ? 'خروجی از ورودی بیشتر است' : '${faNum(c.waste)} کیلو'),
                const Divider(),
                infoRow('بهای پستهٔ ورودی (هر کیلو)${_inputsChanged ? ' — تقریبی' : ''}', Fmt.money(c.base)),
                infoRow('سهم ضایعات (هر کیلو)', Fmt.money(c.wasteShare)),
                infoRow('سهم هزینه‌ها (هر کیلو)', Fmt.money(c.costShare)),
                infoRow('بهای تمام‌شدهٔ هر کیلو خروجی', Fmt.money(c.unit), valueColor: Theme.of(context).colorScheme.primary),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (_open) ...<Widget>[
            OutlinedButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('ذخیره (فرایند باز می‌ماند)'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving || over ? null : _close,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
              label: const Text('بستن و ثبت خروجی‌ها در انبار'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _saving ? null : _cancel, icon: const Icon(Icons.undo), label: Text('لغو ${_noun(_kind)} (برگشت به لات‌های ورودی)')),
          ] else
            FilledButton.icon(
              onPressed: _saving || over ? null : _save,
              icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
              label: const Text('ذخیرهٔ ویرایش'),
            ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
