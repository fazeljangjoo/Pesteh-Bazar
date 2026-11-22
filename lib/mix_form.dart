import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'access_catalog.dart' show FieldGate; // v87: قسمت‌های قفل/پنهان فرم
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';
import 'license_service.dart';
import 'pdf_output.dart' show PdfOutput;
import 'perms.dart' show StaffPerms;
import 'pdf_service.dart' show PdfService;
import 'processing_flow_ui.dart' show askEndReport;
import 'utils.dart';
import 'warehouse_ui.dart';
import 'widgets.dart';

/// v86 — «کوت‌ریزی» به‌صورت فرایند (فایل مشترک اندروید و ویندوز):
///   ۱) انتخاب لات‌ها مثل فرم خط شکست: فهرست با نام فروشنده/نام کوت، کد، انس، گرم و مانده؛ بعد از انتخاب کادر مشخصات لات
///      (فروشنده/نام لات، انس، گرم، عدل کوچک و بزرگ، وزن خالص در انبار) و روبه‌رویش وزن خالص و عدل‌های برداشتی.
///   ۲) مشخصات لات جدید + «مشاهده میانگین» روبه‌روی آن.
///   تاریخ شروع و پایان؛ «ذخیره (کوت در جریان)» ⇒ پسته‌ها قاطی شده ولی مشخصات لات جدید بعداً وارد می‌شود
///   (روی همین دستگاه نگه داشته می‌شود؛ موجودی هنگام «ثبت در انبار» کم می‌شود). پایان ⇒ گزارش PDF.

double _n(dynamic v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);
String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// یک لات مبدأ: لات + وزن خالص + عدل کوچک/بزرگ + «همه موجودی» + انبار برداشت.
class _SourceRow {
  _SourceRow({this.lot});
  int? lot;
  bool all = false;
  final weight = TextEditingController();
  final small = TextEditingController();
  final large = TextEditingController();
  String? wh;
  void dispose() {
    weight.dispose();
    small.dispose();
    large.dispose();
  }
}

/// کوت‌ریزی‌های «در جریان» روی همین دستگاه (پسته قاطی شده، مشخصات لات جدید هنوز ثبت نشده).
class MixProcessStore {
  MixProcessStore._();
  static const String _k = 'mix_process_v86';

  static Future<List<Map<String, dynamic>>> list() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final Object? j = jsonDecode(sp.getString(_k) ?? '[]');
      return j is List ? <Map<String, dynamic>>[for (final Object? x in j) if (x is Map) Map<String, dynamic>.from(x)] : <Map<String, dynamic>>[];
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> l) async => (await SharedPreferences.getInstance()).setString(_k, jsonEncode(l));

  static Future<void> put(Map<String, dynamic> d) async {
    final List<Map<String, dynamic>> l = (await list()).where((Map<String, dynamic> x) => x['key'] != d['key']).toList()..insert(0, d);
    await _save(l);
  }

  static Future<void> remove(String? key) async {
    if (key == null) return;
    await _save((await list()).where((Map<String, dynamic> x) => x['key'] != key).toList());
  }
}

class MixForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final Map<String, dynamic>? process; // کوت در جریان برای ادامه
  const MixForm({super.key, this.existing, this.process});
  @override
  State<MixForm> createState() => _MixFormState();
}

class _MixFormState extends State<MixForm> with EditGuard<MixForm> {
  final _form = GlobalKey<FormState>();
  List<Map<String, dynamic>> _lots = [];
  Map<int, Map<String, dynamic>> _byId = {};
  final List<_SourceRow> _rows = [_SourceRow()];
  bool _loading = true;
  bool _saving = false;
  String? _warehouseUid;
  String? _ounceUid;
  bool _showAvg = false;
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  String? _procKey; // کلید کوت در جریان
  int _procCount = 0;

  bool get _isEdit => widget.existing != null;

  List<Map<String, dynamic>> _categories = [];
  int? _categoryId;
  List<Map<String, dynamic>> _baseTypes = [];
  String? _baseType;
  final _typeName = TextEditingController();
  final _netWeight = TextEditingController();
  final _smallSack = TextEditingController();
  final _largeSack = TextEditingController();
  final _ounce = TextEditingController();
  final _gram = TextEditingController();
  final _waste = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lots = _isEdit ? await AppDb.I.lotsForMixEdit(widget.existing!['id'] as int) : await AppDb.I.lots();
    final cats = await AppDb.I.categories();
    final procs = await MixProcessStore.list();
    if (!mounted) return;
    setState(() {
      _lots = lots.where((e) => _n(e['is_mix']) != 3).toList();
      _byId = {for (final e in _lots) e['id'] as int: e};
      _categories = cats;
      _categoryId = cats.isNotEmpty ? cats.first['id'] as int : null;
      _procCount = procs.length;
      _loading = false;
    });
    await _loadBaseTypes();
    if (_isEdit) await _loadExisting();
    if (widget.process != null) _applyProcess(widget.process!);
  }

  Future<void> _loadExisting() async {
    final e = widget.existing!;
    final full = await AppDb.I.purchaseById(e['id'] as int) ?? e;
    final sources = await AppDb.I.mixSourcesOf(e['id'] as int);
    _typeName.text = e['type_name'] as String? ?? '';
    _netWeight.text = plain(e['net_weight'] as num);
    _smallSack.text = plain(e['small_sack_count'] as num);
    _largeSack.text = plain(e['large_sack_count'] as num);
    _ounce.text = e['ounce'] == null ? '' : plain(e['ounce'] as num);
    _gram.text = e['gram'] == null ? '' : plain(e['gram'] as num);
    _warehouseUid = e['warehouse_uid'] as String?;
    _ounceUid = e['ounce_uid'] as String?;
    _note.text = e['note'] as String? ?? '';
    _categoryId = e['category_id'] as int?;
    _baseType = e['base_type'] as String?;
    _start = DateTime.tryParse('${full['date'] ?? ''}') ?? _start;
    _end = DateTime.tryParse('${full['end_date'] ?? ''}') ?? _start;
    await _loadBaseTypes();
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
    var takenOld = 0.0;
    for (final s in sources) {
      final r = _SourceRow(lot: s['source_purchase_id'] as int);
      r.weight.text = plain(s['weight'] as num);
      r.small.text = plain(s['small_sacks'] as num? ?? 0);
      r.large.text = plain(s['large_sacks'] as num? ?? 0);
      takenOld += (s['weight'] as num).toDouble();
      _rows.add(r);
    }
    if (_rows.isEmpty) _rows.add(_SourceRow());
    if (e['waste'] != null) {
      _waste.text = plain(e['waste'] as num);
    } else {
      final d = takenOld - (e['net_weight'] as num).toDouble();
      _waste.text = d > 0.0005 ? plain(double.parse(d.toStringAsFixed(3))) : '';
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    for (final c in [_typeName, _netWeight, _smallSack, _largeSack, _ounce, _gram, _waste, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  // ───────── محاسبه‌ها ─────────
  List<_SourceRow> get _chosen => _rows.where((r) => r.lot != null && _byId[r.lot] != null).toList();
  double get _takenSum => _chosen.fold<double>(0, (s, r) => s + (parseNum(r.weight.text) ?? 0));

  double get _balanceDiff {
    final net = parseNum(_netWeight.text) ?? 0;
    final double waste = parseNum(_waste.text) ?? 0.0;
    return double.parse((_takenSum - net - waste).toStringAsFixed(3));
  }

  /// میانگین وزنی گرم/انس/فی بر اساس وزن برداشتی (جنس بی‌مقدار ⇒ «قابل محاسبه نیست»).
  ({double? gram, double? ounce, double? price, double w, List<String> noGram, List<String> noOunce, List<String> noPrice}) get _avg {
    double w = 0, g = 0, o = 0, p = 0;
    final noG = <String>[], noO = <String>[], noP = <String>[];
    for (final r in _chosen) {
      final e = _byId[r.lot]!;
      final x = parseNum(r.weight.text) ?? 0;
      if (x <= 0) continue;
      final name = _who(e);
      w += x;
      final gv = e['gram'] as num?, ov = e['ounce'] as num?, pv = e['price'] as num?;
      if (gv == null) {
        noG.add(name);
      } else {
        g += gv * x;
      }
      if (ov == null || ov <= 0) {
        noO.add(name);
      } else {
        o += ov * x;
      }
      if (pv == null || pv <= 0) {
        noP.add(name);
      } else {
        p += pv * x;
      }
    }
    return (
      gram: w > 0 && noG.isEmpty ? g / w : null,
      ounce: w > 0 && noO.isEmpty ? o / w : null,
      price: w > 0 && noP.isEmpty ? p / w : null,
      w: w,
      noGram: noG,
      noOunce: noO,
      noPrice: noP,
    );
  }

  static String _who(Map<String, dynamic> e) {
    final String seller = '${e['seller'] ?? ''}'.trim();
    if (_n(e['is_mix']) == 1) return 'کوت: ${e['type_name'] ?? ''}';
    return seller.isNotEmpty ? seller : '${e['category_name'] ?? ''} ${e['type_name'] ?? ''}'.trim();
  }

  String? _rowError(_SourceRow r) {
    final e = _byId[r.lot];
    if (e == null) return null;
    double kg = 0, sm = 0, lg = 0;
    for (final x in _rows) {
      if (x.lot != r.lot) continue;
      kg += parseNum(x.weight.text) ?? 0;
      sm += parseNum(x.small.text) ?? 0;
      lg += parseNum(x.large.text) ?? 0;
    }
    final out = <String>[];
    if (kg > _n(e['remaining']) + 1e-6) out.add('وزن از موجودی (${faNum(_n(e['remaining']))} کیلو) بیشتر است');
    if (sm > _n(e['small_left']) + 1e-6) out.add('عدل کوچک از موجودی (${faNum(_n(e['small_left']))}) بیشتر است');
    if (lg > _n(e['large_left']) + 1e-6) out.add('عدل بزرگ از موجودی (${faNum(_n(e['large_left']))}) بیشتر است');
    return out.isEmpty ? null : out.join(' • ');
  }

  void _fillAll(_SourceRow r) {
    final e = _byId[r.lot];
    if (!r.all || e == null) return;
    r.weight.text = plain(_n(e['remaining']));
    r.small.text = plain(_n(e['small_left']));
    r.large.text = plain(_n(e['large_left']));
  }

  // ───────── کوت در جریان ─────────
  Map<String, dynamic> _processData() => <String, dynamic>{
        'key': _procKey ?? 'mp${DateTime.now().microsecondsSinceEpoch}',
        'start': _ymd(_start),
        'saved_at': DateTime.now().toIso8601String(),
        'rows': [
          for (final r in _chosen) {'lot': r.lot, 'kg': r.weight.text, 'small': r.small.text, 'large': r.large.text, 'wh': r.wh},
        ],
        'spec': {
          'cat': _categoryId, 'base': _baseType, 'name': _typeName.text, 'net': _netWeight.text, 'waste': _waste.text,
          'small': _smallSack.text, 'large': _largeSack.text, 'ounce': _ounce.text, 'gram': _gram.text, 'note': _note.text,
        },
      };

  void _applyProcess(Map<String, dynamic> p) {
    _procKey = '${p['key']}';
    _start = DateTime.tryParse('${p['start'] ?? ''}') ?? _start;
    for (final r in _rows) {
      r.dispose();
    }
    _rows.clear();
    for (final Object? x in (p['rows'] as List? ?? const [])) {
      if (x is! Map) continue;
      final r = _SourceRow(lot: (x['lot'] as num?)?.toInt());
      if (r.lot != null && !_byId.containsKey(r.lot)) continue; // لات دیگر موجود نیست
      r.weight.text = '${x['kg'] ?? ''}';
      r.small.text = '${x['small'] ?? ''}';
      r.large.text = '${x['large'] ?? ''}';
      r.wh = x['wh'] as String?;
      _rows.add(r);
    }
    if (_rows.isEmpty) _rows.add(_SourceRow());
    final Map sp = p['spec'] is Map ? p['spec'] as Map : const {};
    if (sp['cat'] is num && _categories.any((c) => c['id'] == sp['cat'])) _categoryId = (sp['cat'] as num).toInt();
    _baseType = sp['base'] as String?;
    _typeName.text = '${sp['name'] ?? ''}';
    _netWeight.text = '${sp['net'] ?? ''}';
    _waste.text = '${sp['waste'] ?? ''}';
    _smallSack.text = '${sp['small'] ?? ''}';
    _largeSack.text = '${sp['large'] ?? ''}';
    _ounce.text = '${sp['ounce'] ?? ''}';
    _gram.text = '${sp['gram'] ?? ''}';
    _note.text = '${sp['note'] ?? ''}';
    _loadBaseTypes();
    if (mounted) setState(() {});
  }

  Future<void> _saveProcess() async {
    if (_chosen.isEmpty) return snack(context, 'حداقل یک لات را انتخاب کنید');
    for (final r in _chosen) {
      final err = _rowError(r);
      if (err != null) return snack(context, err);
    }
    final d = _processData();
    await MixProcessStore.put(d);
    _procKey = '${d['key']}';
    if (!mounted) return;
    snack(context, 'کوت‌ریزی «در جریان» ذخیره شد؛ بعداً مشخصات لات جدید را وارد و «ثبت در انبار» کنید');
    Navigator.pop(context);
  }

  Future<void> _openProcesses() async {
    final list = await MixProcessStore.list();
    if (!mounted) return;
    final Map<String, dynamic>? pick = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('کوت‌ریزی‌های در جریان', style: TextStyle(fontWeight: FontWeight.bold))),
          if (list.isEmpty) const ListTile(title: Text('کوت‌ریزی در جریانی نیست')),
          for (final p in list)
            ListTile(
              leading: const Icon(Icons.pending_actions),
              title: Text('${'${(p['spec'] as Map?)?['name'] ?? ''}'.isEmpty ? 'کوت بی‌نام' : (p['spec'] as Map)['name']}  •  شروع ${jalaliDate('${p['start'] ?? ''}')}'),
              subtitle: Text('${faNum((p['rows'] as List?)?.length ?? 0, dec: 0)} لات  •  '
                  '${faNum(((p['rows'] as List?) ?? const []).fold<double>(0, (s, x) => s + (parseNum('${(x as Map)['kg'] ?? ''}') ?? 0)))} کیلو'),
              trailing: IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await MixProcessStore.remove('${p['key']}');
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ]),
      ),
    );
    final procs = await MixProcessStore.list();
    if (mounted) setState(() => _procCount = procs.length);
    if (pick != null) _applyProcess(pick);
  }

  // ───────── ثبت نهایی ─────────
  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    final sel = _chosen;
    if (sel.isEmpty) return snack(context, 'حداقل یک لات مبدأ را انتخاب کنید');
    if (_takenSum <= 0) return snack(context, 'وزنی که از انبار برمی‌دارید را وارد کنید');
    for (final r in sel) {
      final err = _rowError(r);
      if (err != null) return snack(context, err);
    }
    if (_end.isBefore(DateTime(_start.year, _start.month, _start.day))) return snack(context, 'تاریخ پایان نمی‌تواند قبل از تاریخ شروع باشد');
    if (_categoryId == null) return snack(context, 'دسته را انتخاب کنید');
    if (_baseType == null || _baseType!.isEmpty) return snack(context, 'نوع پسته (زیردسته) را انتخاب کنید');
    if (_typeName.text.trim().isEmpty) return snack(context, 'نام لات جدید را وارد کنید');
    final net = parseNum(_netWeight.text) ?? 0;
    if (net <= 0) return snack(context, 'وزن نهایی لات جدید (بعد از توزین) را وارد کنید');
    final double waste = parseNum(_waste.text) ?? 0.0;
    final diff = _balanceDiff;
    if (diff.abs() > 0.0015) {
      return snack(context, diff > 0 ? '${faNum(diff)} کیلو اختلاف ثبت‌نشده دارید؛ اگر خاک یا ضایعات بوده در «ضایعات» وارد کنید' : 'وزن (خالص) + ضایعات به اندازهٔ ${faNum(-diff)} کیلو از وزن برداشته‌شده بیشتر است');
    }
    setState(() => _saving = true);
    try {
      // یک لات چند بار ⇒ جمع (همان قاعدهٔ سرور)
      final Map<int, Map<String, dynamic>> agg = {};
      for (final r in sel) {
        final w = parseNum(r.weight.text) ?? 0;
        if (w <= 0) continue;
        final a = agg.putIfAbsent(r.lot!, () => {'purchase_id': r.lot, 'weight': 0.0, 'small_sacks': 0.0, 'large_sacks': 0.0});
        a['weight'] = (a['weight'] as double) + w;
        a['small_sacks'] = (a['small_sacks'] as double) + (parseNum(r.small.text) ?? 0);
        a['large_sacks'] = (a['large_sacks'] as double) + (parseNum(r.large.text) ?? 0);
        if (r.wh != null) a['warehouse_uid'] = r.wh;
      }
      final sources = agg.values.toList();
      final String? note = _note.text.trim().isEmpty ? null : _note.text.trim();
      final ok = await saveConfirmed(context, () async {
        if (_isEdit) {
          await AppDb.I.updateMix(
            mixPurchaseId: widget.existing!['id'] as int,
            categoryId: _categoryId!,
            typeName: _typeName.text.trim(),
            baseType: _baseType,
            sources: sources,
            netWeight: net,
            smallSackCount: parseNum(_smallSack.text) ?? 0.0,
            largeSackCount: parseNum(_largeSack.text) ?? 0.0,
            ounce: parseNum(_ounce.text),
            gram: parseNum(_gram.text),
            waste: waste,
            note: note,
            warehouseUid: _warehouseUid,
            ounceUid: _ounceUid,
            uidsGiven: true,
            date: _ymd(_start),
            endDate: _ymd(_end),
          );
        } else {
          await AppDb.I.createMix(
            categoryId: _categoryId!,
            typeName: _typeName.text.trim(),
            baseType: _baseType,
            sources: sources,
            netWeight: net,
            smallSackCount: parseNum(_smallSack.text) ?? 0.0,
            largeSackCount: parseNum(_largeSack.text) ?? 0.0,
            ounce: parseNum(_ounce.text),
            gram: parseNum(_gram.text),
            waste: waste,
            note: note,
            warehouseUid: _warehouseUid,
            ounceUid: _ounceUid,
            date: _ymd(_start),
            endDate: _ymd(_end),
          );
        }
      }, successMsg: _isEdit ? 'کوت‌ریزی ویرایش شد' : 'کوت‌ریزی تمام شد و لات جدید به انبار اضافه شد');
      if (!mounted || !ok) return;
      await MixProcessStore.remove(_procKey);
      if (mounted && await askEndReport(context) && mounted) await _report();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) snack(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// گزارش PDF پایان کوت‌ریزی: لات‌های ورودی، میانگین‌ها، لات جدید، ضایعات، تاریخ شروع و پایان.
  Future<void> _report() async {
    final a = _avg;
    final net = parseNum(_netWeight.text) ?? 0, waste = parseNum(_waste.text) ?? 0;
    final cat = _categories.where((c) => c['id'] == _categoryId).map((c) => '${c['name']}').join();
    final File f = await PdfService.buildTableReport(
      title: 'گزارش پایان کوت‌ریزی — ${_typeName.text.trim()}',
      subtitle: 'شروع ${jalaliDateFromDt(_start)}  •  پایان ${jalaliDateFromDt(_end)}',
      kv: [
        ['جمع وزن برداشته‌شده (خالص)', '${faNum(_takenSum)} کیلو', 'b'],
        ['میانگین گرم ورودی', a.gram == null ? 'قابل محاسبه نیست' : faNum(a.gram!, dec: 2)],
        ['میانگین انس ورودی', a.ounce == null ? 'قابل محاسبه نیست' : faNum(a.ounce!, dec: 2)],
        if (StaffPerms.I.canPriceIn('mixing') /* v87 */) ['میانگین فی ورودی', a.price == null ? 'قابل محاسبه نیست' : faNum(a.price!, dec: 0)],
        ['لات جدید', '$cat ${_baseType ?? ''} — ${_typeName.text.trim()}'],
        ['وزن نهایی لات جدید (خالص)', '${faNum(net)} کیلو', 'b'],
        ['ضایعات / خاک', '${faNum(waste)} کیلو${_takenSum > 0 ? ' (${faNum(waste * 100 / _takenSum, dec: 2)}٪)' : ''}'],
        ['عدل کوچک / بزرگ لات جدید', '${faNum(parseNum(_smallSack.text) ?? 0, dec: 0)} / ${faNum(parseNum(_largeSack.text) ?? 0, dec: 0)}'],
        if (parseNum(_ounce.text) != null) ['انس لات جدید', faNum(parseNum(_ounce.text)!, dec: 2)],
        if (parseNum(_gram.text) != null) ['گرم لات جدید', faNum(parseNum(_gram.text)!, dec: 2)],
        if (_note.text.trim().isNotEmpty) ['توضیحات', _note.text.trim()],
      ],
      headers: const ['کد', 'فروشنده / نام لات', 'نوع', 'وزن برداشتی (کیلو)', 'عدل کوچک/بزرگ', 'انس', 'گرم'],
      rows: [
        for (final r in _chosen)
          () {
            final e = _byId[r.lot]!;
            return <String>[
              '${e['code'] ?? ''}', _who(e), '${e['category_name'] ?? ''} ${e['type_name'] ?? ''}', faNum(parseNum(r.weight.text) ?? 0),
              '${faNum(parseNum(r.small.text) ?? 0, dec: 0)}/${faNum(parseNum(r.large.text) ?? 0, dec: 0)}',
              e['ounce'] == null ? '—' : faNum(e['ounce'] as num, dec: 2), e['gram'] == null ? '—' : faNum(e['gram'] as num, dec: 2),
            ];
          }(),
      ],
      filePrefix: 'mix_report',
      signatures: const ['مسئول کوت‌ریزی', 'انباردار'],
    );
    if (mounted) await PdfOutput.show(context, f);
  }

  // ───────── ویجت‌ها ─────────
  Widget _lotDropdown(_SourceRow r) {
    final cur = _byId[r.lot];
    return DropdownButtonFormField<int>(
      key: ValueKey('ml-${identityHashCode(r)}-${_lots.length}'),
      initialValue: cur == null ? null : r.lot,
      isExpanded: true,
      itemHeight: 56,
      decoration: const InputDecoration(labelText: 'لات', border: OutlineInputBorder()),
      selectedItemBuilder: (_) => [
        for (final e in _lots) Align(alignment: AlignmentDirectional.centerStart, child: Text('${_who(e)}  ·  ${e['code'] ?? ''}', overflow: TextOverflow.ellipsis)),
      ],
      items: [
        for (final e in _lots)
          DropdownMenuItem<int>(
            value: e['id'] as int,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_who(e), overflow: TextOverflow.ellipsis),
              Text(
                '${e['code'] ?? ''}  ·  ${e['category_name'] ?? ''} ${e['type_name'] ?? ''}'
                '${e['ounce'] == null ? '' : '  ·  انس ${faNum(e['ounce'] as num, dec: 2)}'}'
                '${e['gram'] == null ? '' : '  ·  گرم ${faNum(e['gram'] as num, dec: 2)}'}'
                '  ·  ${faNum(_n(e['remaining']))} کیلو',
                style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
      ],
      onChanged: (v) => setState(() {
        r.lot = v;
        r.wh = null;
        _fillAll(r);
      }),
    );
  }

  Widget _lotInfo(Map<String, dynamic> e) {
    final th = Theme.of(context);
    Widget kv(String k, String v) => Text.rich(
          TextSpan(children: [TextSpan(text: '$k: ', style: TextStyle(color: th.hintColor)), TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w600))]),
          style: const TextStyle(fontSize: 12.5),
        );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: th.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: th.dividerColor),
      ),
      child: Wrap(spacing: 16, runSpacing: 4, children: [
        kv(_n(e['is_mix']) == 1 ? 'نام لات (کوت)' : 'فروشنده / نام لات', _n(e['is_mix']) == 1 ? '${e['type_name'] ?? ''}' : _who(e)),
        kv('کد', '${e['code'] ?? '-'}'),
        kv('انس', e['ounce'] == null ? '—' : faNum(e['ounce'] as num, dec: 2)),
        kv('گرم', e['gram'] == null ? '—' : faNum(e['gram'] as num, dec: 2)),
        kv('عدل کوچک', faNum(_n(e['small_left']), dec: 0)),
        kv('عدل بزرگ', faNum(_n(e['large_left']), dec: 0)),
        kv('وزن خالص در انبار', '${faNum(_n(e['remaining']))} کیلو'),
        if (LicenseService.I.isFx.value && e['price_usd'] != null) kv('فی دلاری', faUsd(e['price_usd'] as num, dec: 3)),
      ]),
    );
  }

  Widget _qty(_SourceRow r) {
    TextFormField f(TextEditingController c, String l, {bool req = false}) => TextFormField(
          controller: c,
          enabled: !r.all,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: l, border: const OutlineInputBorder(), isDense: true),
          onChanged: (_) => setState(() {}),
          validator: req
              ? (v) {
                  final n = parseNum(v);
                  return (n == null || n <= 0) ? 'وزن را وارد کنید' : null;
                }
              : null,
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      f(r.weight, 'وزن خالص برداشتی (کیلو)', req: true),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: f(r.small, 'عدل کوچک')),
        const SizedBox(width: 6),
        Expanded(child: f(r.large, 'عدل بزرگ')),
      ]),
      CheckboxListTile(
        value: r.all,
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('همه موجودی'),
        onChanged: r.lot == null
            ? null
            : (v) => setState(() {
                  r.all = v ?? false;
                  _fillAll(r);
                }),
      ),
      if (r.lot != null) SaleWarehouseField(key: ValueKey('mw-${identityHashCode(r)}-${r.lot}'), lotId: r.lot!, onChanged: (v) => r.wh = v),
    ]);
  }

  Widget _rowCard(int i, bool wide) {
    final r = _rows[i];
    final e = _byId[r.lot];
    final err = _rowError(r);
    final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _lotDropdown(r)),
        if (_rows.length > 1)
          IconButton(tooltip: 'حذف لات', icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() => _rows.removeAt(i).dispose())),
      ]),
      if (e != null) _lotInfo(e),
    ]);
    return Card(
      key: ObjectKey(r),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: left), const SizedBox(width: 10), Expanded(flex: 2, child: _qty(r))])
          else ...[left, const SizedBox(height: 8), _qty(r)],
          if (err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12.5))),
        ]),
      ),
    );
  }

  Widget _avgCard() {
    final scheme = Theme.of(context).colorScheme;
    final a = _avg;
    if (a.w <= 0) return const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('وزن برداشتی هر لات را وارد کنید تا میانگین محاسبه شود.')));
    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          infoRow('میانگین گرم', a.gram == null ? 'قابل محاسبه نیست' : faNum(a.gram!, dec: 2), valueColor: a.gram == null ? scheme.error : null),
          infoRow('میانگین انس', a.ounce == null ? 'قابل محاسبه نیست' : faNum(a.ounce!, dec: 2), valueColor: a.ounce == null ? scheme.error : null),
          infoRow('میانگین قیمت (فی)', a.price == null ? 'قابل محاسبه نیست' : faNum(a.price!, dec: 0), valueColor: a.price == null ? scheme.error : null),
          if (a.noGram.isNotEmpty) Text('⚠ بدون گرم: ${a.noGram.join('، ')}', style: TextStyle(color: scheme.error, fontSize: 12)),
          if (a.noOunce.isNotEmpty) Text('⚠ بدون انس: ${a.noOunce.join('، ')}', style: TextStyle(color: scheme.error, fontSize: 12)),
          if (a.noPrice.isNotEmpty) Text('⚠ بدون قیمت: ${a.noPrice.join('، ')}', style: TextStyle(color: scheme.error, fontSize: 12)),
          Text('میانگین وزنی بر اساس وزن برداشتی از هر لات (${faNum(a.w)} کیلو).', style: const TextStyle(color: Colors.black54, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _balanceCard() {
    final scheme = Theme.of(context).colorScheme;
    final net = parseNum(_netWeight.text) ?? 0;
    final double waste = parseNum(_waste.text) ?? 0.0;
    final diff = _balanceDiff;
    final ok = diff.abs() <= 0.0015;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          infoRow('برداشته‌شده (خالص)', '${faNum(_takenSum)} کیلو'),
          infoRow('وزن (خالص) + ضایعات', '${faNum(net + waste)} کیلو'),
          Text(
            ok ? '✓ وزن‌ها برابرند' : (diff > 0 ? '${faNum(diff)} کیلو اختلاف ثبت‌نشده دارید؛ اگر خاک یا ضایعات بوده در «ضایعات» وارد کنید' : 'وزن (خالص) + ضایعات به اندازهٔ ${faNum(-diff)} کیلو از وزن برداشته‌شده بیشتر است'),
            style: TextStyle(color: ok ? Colors.green.shade700 : scheme.error),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final String title = _isEdit ? 'ویرایش کوت‌ریزی' : 'کوت‌ریزی';
    if (_lots.isEmpty) return Scaffold(appBar: AppBar(title: Text(title)), body: const Center(child: Text('انبار خالی است')));
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        if (!_isEdit)
          IconButton(
            tooltip: 'کوت‌ریزی‌های در جریان',
            onPressed: _openProcesses,
            icon: Badge(isLabelVisible: _procCount > 0, label: Text(faNum(_procCount, dec: 0)), child: const Icon(Icons.pending_actions)),
          ),
      ]),
      body: Form(
        key: _form,
        child: LayoutBuilder(builder: (context, c) {
          final bool wide = c.maxWidth >= 760;
          return ListView(padding: const EdgeInsets.all(14), children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('کوت‌ریزی یک فرایند است: لات‌ها را انتخاب کنید (پسته‌ها قاطی می‌شوند)؛ اگر مشخصات لات جدید هنوز معلوم نیست «ذخیره (کوت در جریان)» '
                    'را بزنید و بعداً از آیکن بالا ادامه دهید. هزینهٔ ضایعات به‌صورت میانگین روی فی لات جدید می‌نشیند.'),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: JalaliDateField(label: 'تاریخ شروع', value: _start, onChanged: (d) => setState(() => _start = d))),
              const SizedBox(width: 8),
              Expanded(child: JalaliDateField(label: 'تاریخ پایان', value: _end, onChanged: (d) => setState(() => _end = d))),
            ]),
            const SizedBox(height: 6),
            sectionTitle(context, '۱) انتخاب لات‌ها (همین حالا وزن و عدل برداشتی را بنویسید)'),
            for (int i = 0; i < _rows.length; i++) _rowCard(i, wide),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(onPressed: () => setState(() => _rows.add(_SourceRow())), icon: const Icon(Icons.add), label: const Text('لات دیگر')),
            ),
            Card(child: Padding(padding: const EdgeInsets.all(12), child: infoRow('جمع وزن برداشته‌شده (خالص)', '${faNum(_takenSum)} کیلو'))),
            const SizedBox(height: 8),
            // ۲) مشخصات لات جدید + «مشاهده میانگین» روبه‌روی آن
            Row(children: [
              Expanded(child: sectionTitle(context, '۲) مشخصات لات جدید')),
              FilterChip(
                avatar: const Icon(Icons.calculate_outlined, size: 18),
                label: const Text('مشاهده میانگین'),
                selected: _showAvg,
                onSelected: (v) => setState(() => _showAvg = v),
              ),
            ]),
            if (_showAvg) _avgCard(),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('cat-$_categoryId-${_categories.length}'),
                  initialValue: _categoryId,
                  decoration: const InputDecoration(labelText: 'دسته', border: OutlineInputBorder()),
                  items: [for (final c in _categories) DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] as String))],
                  onChanged: (v) {
                    setState(() {
                      _categoryId = v;
                      _baseType = null;
                    });
                    _loadBaseTypes();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: _addCategory, icon: const Icon(Icons.add), tooltip: 'افزودن دسته'),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('bt-$_categoryId-$_baseType-${_baseTypes.length}'),
                  initialValue: _baseTypes.any((t) => t['name'] == _baseType) ? _baseType : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'نوع پسته (زیردسته)', border: OutlineInputBorder()),
                  items: [for (final t in _baseTypes) DropdownMenuItem<String>(value: t['name'] as String, child: Text(t['name'] as String))],
                  onChanged: (v) => setState(() => _baseType = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: _addBaseType, icon: const Icon(Icons.add), tooltip: 'افزودن نوع'),
            ]),
            const SizedBox(height: 12),
            textField(_typeName, 'نام لات جدید (مثلاً «کوت‌ریز»)', required: true),
            Row(children: [
              Expanded(child: numField(_netWeight, 'وزن نهایی (خالص) — طبق ترازو', required: true, onChanged: () => setState(() {}))),
              const SizedBox(width: 8),
              Expanded(child: numField(_waste, 'ضایعات / خاک (کیلو)', hint: '0', onChanged: () => setState(() {}))),
            ]),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () {
                  final d = double.parse((_takenSum - (parseNum(_netWeight.text) ?? 0)).toStringAsFixed(3));
                  _waste.text = d > 0 ? plain(d) : '0';
                  setState(() {});
                },
                icon: const Icon(Icons.balance),
                label: const Text('ثبت اختلاف به‌عنوان ضایعات'),
              ),
            ),
            _balanceCard(),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: numField(_smallSack, 'عدل کوچک', hint: '0')),
              const SizedBox(width: 8),
              Expanded(child: numField(_largeSack, 'عدل بزرگ', hint: '0')),
              const SizedBox(width: 8),
              Expanded(child: numField(_ounce, 'انس (اختیاری)', hint: '0')),
              const SizedBox(width: 8),
              Expanded(child: numField(_gram, 'گرم (اختیاری)', hint: '0')),
            ]),
            WarehousePicker(label: 'انبار لات جدید', value: _warehouseUid, useLast: !_isEdit, onChanged: (v) => _warehouseUid = v),
            OuncePicker(value: _ounceUid, onChanged: (v) => _ounceUid = v),
            FieldGate(field: 'mix.note', child: textField(_note, 'توضیحات (اختیاری)', lines: 2)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (!_isEdit)
                OutlinedButton.icon(
                  onPressed: _saving ? null : _saveProcess,
                  icon: const Icon(Icons.pending_actions),
                  label: const Text('ذخیره (کوت در جریان)'),
                ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                label: Text(_isEdit ? 'ذخیره تغییرات' : 'ثبت در انبار (پایان کوت‌ریزی)'),
              ),
            ]),
            const SizedBox(height: 24),
          ]);
        }),
      ),
    );
  }

  Future<void> _loadBaseTypes() async {
    final id = _categoryId;
    final list = id == null ? <Map<String, dynamic>>[] : await AppDb.I.typesOf(id);
    if (!mounted) return;
    setState(() {
      _baseTypes = list;
      if (_baseType != null && !list.any((t) => t['name'] == _baseType)) _baseType = null;
    });
  }

  Future<String?> _ask(String title, String label) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('افزودن')),
        ],
      ),
    );
    c.dispose();
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<void> _addBaseType() async {
    final cid = _categoryId;
    if (cid == null) return snack(context, 'اول دسته را انتخاب کنید');
    final name = await _ask('افزودن نوع پسته جدید', 'نام نوع');
    if (name == null || !mounted) return;
    final ok = await saveConfirmed(context, () => AppDb.I.addType(cid, name), successMsg: 'نوع «$name» اضافه شد');
    if (!ok) return;
    _baseType = name;
    await _loadBaseTypes();
  }

  Future<void> _addCategory() async {
    final name = await _ask('افزودن دسته جدید', 'نام دسته');
    if (name == null) return;
    final id = await AppDb.I.addCategory(name);
    final cats = await AppDb.I.categories();
    if (mounted) {
      setState(() {
        _categories = cats;
        _categoryId = id;
        _baseType = null;
      });
    }
    await _loadBaseTypes();
  }
}
