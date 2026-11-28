import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart' show FileSaveLocation, XTypeGroup, getSaveLocation;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart' as sp;

import 'company_profile.dart' show CompanyProfile;
import 'entity_store.dart';
import 'mk_countries.dart' show kMkCountryNames;
import 'marketing_store.dart';
import 'pdf_output.dart';
import 'proforma_export.dart';
import 'proforma_model.dart';
import 'widgets.dart' show confirm, snack;

// v96 — پیش‌فاکتور صادراتی در «بازاریابی بین‌المللی»: مدیر یک بار قالب شرکت را تنظیم می‌کند (سربرگ، رنگ، لوگو، فروشنده،
// بانک، مشخصات کیفی، شرایط، مدارک و ردیف‌های پیش‌فرض)؛ بازاریاب‌ها و مدیر برای هر فروش پیش‌فاکتور را در همان قالب پر می‌کنند.
// خروجی: PDF (چاپ/اشتراک) و Word.

const String _kTplE = 'mk_pf_templates';
const String _kPfE = 'mk_proformas';

Future<bool> mkProformaAvailable() async {
  try {
    return await EntityStore.I.isVisible(_kPfE) && await EntityStore.I.isVisible(_kTplE);
  } catch (_) {
    return false;
  }
}

/// (uid, title, data) قالب‌ها
Future<List<(String, String, PfData)>> _templates() async => <(String, String, PfData)>[
      for (final Map<String, dynamic> r in await EntityStore.I.list(_kTplE)) ('${r['uid']}', '${r['title'] ?? ''}', PfData.fromJson(r['data'])),
    ];

/// پیش‌فاکتور + لوگوی قالبش (لوگو فقط در قالب ذخیره می‌شود)
Future<PfData> _withLogo(PfData d, String templateUid) async {
  if (d.logo.isNotEmpty || templateUid.isEmpty) return d;
  final Map<String, dynamic>? t = await EntityStore.I.get(_kTplE, templateUid);
  if (t != null) d.logo = PfData.fromJson(t['data']).logo;
  return d;
}

Future<void> _exportPdf(BuildContext context, PfData d) async {
  try {
    final File f = await PfExport.pdf(d);
    if (context.mounted) await PdfOutput.show(context, f);
  } catch (e) {
    if (context.mounted) snack(context, 'خطا در ساخت PDF: $e');
  }
}

Future<void> _exportWord(BuildContext context, PfData d) async {
  try {
    final File f = await PfExport.docx(d);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final FileSaveLocation? loc = await getSaveLocation(
          suggestedName: p.basename(f.path), acceptedTypeGroups: <XTypeGroup>[const XTypeGroup(label: 'Word', extensions: <String>['docx'])]);
      if (loc == null) return;
      String path = loc.path;
      if (!path.toLowerCase().endsWith('.docx')) path = '$path.docx';
      await f.copy(path);
      if (context.mounted) snack(context, 'فایل Word ذخیره شد');
      return;
    }
    await sp.Share.shareXFiles(<sp.XFile>[sp.XFile(f.path, mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')]);
  } catch (e) {
    if (context.mounted) snack(context, 'خطا در ساخت فایل Word: $e');
  }
}

// ============================================================ تب «پیش‌فاکتور»

class MkProformaView extends StatefulWidget {
  const MkProformaView({super.key});
  @override
  State<MkProformaView> createState() => _MkProformaViewState();
}

class _MkProformaViewState extends State<MkProformaView> {
  String _q = '';

  Future<(bool, List<(String, String, PfData)>, List<Map<String, dynamic>>)> _load() async {
    if (!await mkProformaAvailable()) return (false, <(String, String, PfData)>[], <Map<String, dynamic>>[]);
    final List<Map<String, dynamic>> list = await EntityStore.I.list(_kPfE, q: _q);
    final bool mgr = MkStore.I.isManager;
    final int me = MkStore.I.myId;
    // بازاریاب فقط پیش‌فاکتورهای خودش (سرور هم همین را می‌فرستد)
    final List<Map<String, dynamic>> mine = mgr ? list : list.where((Map<String, dynamic> r) => ((r['staff_id'] as num?) ?? -1).toInt() == me).toList();
    return (true, await _templates(), mine);
  }

  Future<void> _editTemplate(List<(String, String, PfData)> tpls) async {
    final (String, String, PfData)? t = tpls.isEmpty ? null : tpls.first;
    PfData d = t?.$3 ?? PfData.sample();
    if (t == null) {
      // قالب تازه: نام و لوگوی شرکت از «مشخصات شرکت» اگر ثبت شده باشد
      try {
        final CompanyProfile? cp = await CompanyProfile.load();
        if (cp != null && cp.name.isNotEmpty) d.company = cp.name;
        if (cp != null && cp.logo.isNotEmpty) d.logo = cp.logo;
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MkPfTemplateScreen(uid: t?.$1, title: t?.$2 ?? 'قالب اصلی', data: d)));
    if (mounted) setState(() {});
  }

  Future<void> _open(List<(String, String, PfData)> tpls, {Map<String, dynamic>? row}) async {
    if (row == null && tpls.isEmpty) {
      snack(context, MkStore.I.isManager ? 'اول «قالب پیش‌فاکتور» را بسازید' : 'مدیر بازاریابی هنوز قالب پیش‌فاکتور را نساخته است');
      return;
    }
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MkProformaFormScreen(row: row, templates: tpls)));
    if (mounted) setState(() {});
  }

  Future<void> _rowMenu(Map<String, dynamic> r, String action) async {
    final PfData d = await _withLogo(PfData.fromJson(r['data']), '${r['template_uid'] ?? ''}');
    if (!mounted) return;
    switch (action) {
      case 'pdf':
        await _exportPdf(context, d);
      case 'word':
        await _exportWord(context, d);
      case 'delete':
        if (!await confirm(context, 'پیش‌فاکتور شمارهٔ ${r['number']} حذف شود؟')) return;
        try {
          await EntityStore.I.delete(_kPfE, '${r['uid']}');
          if (mounted) setState(() {});
        } catch (e) {
          if (mounted) snack(context, '$e'.replaceFirst('Exception: ', ''));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(bool, List<(String, String, PfData)>, List<Map<String, dynamic>>)>(
      future: _load(),
      builder: (BuildContext context, AsyncSnapshot<(bool, List<(String, String, PfData)>, List<Map<String, dynamic>>)> snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final (bool ok, List<(String, String, PfData)> tpls, List<Map<String, dynamic>> list) = snap.data!;
        if (!ok) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('پیش‌فاکتور صادراتی هنوز روی سرور فعال نشده است؛ پس از به‌روزرسانی سرور و همگام‌سازی کامل در دسترس است.', textAlign: TextAlign.center)));
        }
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
              heroTag: 'mk_pf_new', onPressed: () => _open(tpls), icon: const Icon(Icons.add), label: const Text('پیش‌فاکتور جدید')),
          body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: <Widget>[
            if (MkStore.I.isManager)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.design_services_outlined),
                  title: const Text('قالب پیش‌فاکتور شرکت'),
                  subtitle: Text(tpls.isEmpty ? 'هنوز ساخته نشده — قالب آماده را باز و اطلاعات شرکت را وارد کنید' : 'سربرگ، رنگ‌ها، بانک، مشخصات کیفی، شرایط و مدارک'),
                  trailing: Icon(tpls.isEmpty ? Icons.add_circle_outline : Icons.edit_outlined),
                  onTap: () => _editTemplate(tpls),
                ),
              ),
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'جست‌وجوی شماره یا خریدار', isDense: true),
              onSubmitted: (String v) => setState(() => _q = v.trim()),
            ),
            const SizedBox(height: 8),
            if (list.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('پیش‌فاکتوری ثبت نشده است'))),
            for (final Map<String, dynamic> r in list)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.request_quote_outlined),
                  title: Text('No. ${r['number'] ?? ''}  —  ${r['buyer'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(<String>[
                    pfDate('${r['date'] ?? ''}'),
                    if (r['total'] != null) pfMoney(((r['total'] as num?) ?? 0).toDouble(), '${r['ccy'] ?? 'USD'}'),
                    if (MkStore.I.isManager && '${r['staff_name'] ?? ''}'.isNotEmpty) '👤 ${r['staff_name']}',
                  ].join('   ')),
                  onTap: () => _open(tpls, row: r),
                  trailing: PopupMenuButton<String>(
                    onSelected: (String a) => _rowMenu(r, a),
                    itemBuilder: (_) => const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('PDF / چاپ'))),
                      PopupMenuItem<String>(value: 'word', child: ListTile(leading: Icon(Icons.description_outlined), title: Text('فایل Word'))),
                      PopupMenuItem<String>(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('حذف'))),
                    ],
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }
}

// ============================================================ قالب (مدیر)

class MkPfTemplateScreen extends StatefulWidget {
  const MkPfTemplateScreen({super.key, this.uid, required this.title, required this.data});
  final String? uid;
  final String title;
  final PfData data;
  @override
  State<MkPfTemplateScreen> createState() => _MkPfTemplateScreenState();
}

class _MkPfTemplateScreenState extends State<MkPfTemplateScreen> {
  late final PfData _d = widget.data.copy();
  late final TextEditingController _title = TextEditingController(text: widget.title);
  bool _busy = false;

  Future<void> _save() async {
    if (_d.company.trim().isEmpty) return snack(context, 'نام شرکت را وارد کنید');
    setState(() => _busy = true);
    try {
      _d.number = '';
      _d.date = '';
      _d.buyer = '';
      await EntityStore.I.save(_kTplE, <String, dynamic>{'title': _title.text.trim().isEmpty ? 'قالب اصلی' : _title.text.trim(), 'data': _d.toJson()}, uid: widget.uid);
      if (mounted) {
        snack(context, 'قالب ذخیره شد');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('قالب پیش‌فاکتور'), actions: <Widget>[
          IconButton(tooltip: 'پیش‌نمایش PDF', icon: const Icon(Icons.visibility_outlined), onPressed: () => _exportPdf(context, _sampleDoc())),
        ]),
        body: _pfWide(ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: <Widget>[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('اطلاعاتی که در همهٔ پیش‌فاکتورها ثابت است را یک بار این‌جا وارد کنید. ردیف‌های هر بخش پیش‌فرض پیش‌فاکتورهای تازه‌اند '
                  'و در هر پیش‌فاکتور قابل تغییرند (هر بخش حداکثر $kPfMaxRows ردیف). متن پیش‌فاکتور انگلیسی است.'),
            ),
          ),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'نام قالب')),
          const SizedBox(height: 8),
          PfEditor(data: _d, template: true, onChanged: () => setState(() {})),
        ])),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('ذخیرهٔ قالب')),
      );

  PfData _sampleDoc() {
    final PfData s = _d.copy();
    s.number = '${_d.nextNo}';
    s.date = _iso(DateTime.now());
    s.buyer = 'Buyer company\nAddress ...';
    return s;
  }
}

// ============================================================ پیش‌فاکتور هر فروش

class MkProformaFormScreen extends StatefulWidget {
  const MkProformaFormScreen({super.key, this.row, required this.templates});
  final Map<String, dynamic>? row;
  final List<(String, String, PfData)> templates;
  @override
  State<MkProformaFormScreen> createState() => _MkProformaFormScreenState();
}

class _MkProformaFormScreenState extends State<MkProformaFormScreen> {
  PfData? _d;
  String _tplUid = '';
  String? _leadUid;
  List<Map<String, dynamic>> _leads = <Map<String, dynamic>>[];
  bool _busy = false;
  int _gen = 0; // با عوض‌شدن قالب، فرم از نو ساخته می‌شود

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final List<Map<String, dynamic>> leads = await MkStore.I.leads();
    PfData d;
    final Map<String, dynamic>? r = widget.row;
    if (r != null) {
      d = PfData.fromJson(r['data']);
      _tplUid = '${r['template_uid'] ?? ''}';
      _leadUid = r['lead_uid'] == null || '${r['lead_uid']}'.isEmpty ? null : '${r['lead_uid']}';
    } else {
      final (String, String, PfData) t = widget.templates.first;
      _tplUid = t.$1;
      d = _fromTemplate(t.$3);
      d.number = await _nextNumber(t.$3);
    }
    if (!mounted) return;
    setState(() {
      _leads = leads;
      _d = d;
    });
  }

  PfData _fromTemplate(PfData t) {
    final PfData d = t.copy();
    d.logo = ''; // لوگو در قالب می‌ماند
    d.date = _iso(DateTime.now());
    d.buyer = '';
    return d;
  }

  /// بزرگ‌ترین شمارهٔ عددی پیش‌فاکتورهای موجود + ۱ (نه کمتر از «شمارهٔ شروع» قالب)
  Future<String> _nextNumber(PfData t) async {
    int top = t.nextNo - 1;
    for (final Map<String, dynamic> r in await EntityStore.I.list(_kPfE)) {
      final int? n = int.tryParse('${r['number'] ?? ''}'.trim());
      if (n != null && n > top) top = n;
    }
    return '${top + 1}';
  }

  String _buyerOf(Map<String, dynamic> l) {
    String s(String k) => '${l[k] ?? ''}'.trim();
    final String place = <String>[s('city'), if (s('country').isNotEmpty) _countryEn(s('country'))].where((String e) => e.isNotEmpty).join(', ');
    return <String>[
      s('name'),
      if (s('contact').isNotEmpty) 'Attn: ${s('contact')}',
      if (place.isNotEmpty) place,
      <String>[if (s('phone').isNotEmpty) 'Phone ${s('phone')}', if (s('email').isNotEmpty) 'Email: ${s('email')}'].join('  '),
    ].where((String e) => e.trim().isNotEmpty).join('\n');
  }

  Future<void> _save() async {
    final PfData d = _d!;
    if (d.number.trim().isEmpty) return snack(context, 'شمارهٔ پیش‌فاکتور را وارد کنید');
    if (d.buyer.trim().isEmpty) return snack(context, 'خریدار را انتخاب یا وارد کنید');
    if (d.items.isEmpty) return snack(context, 'حداقل یک ردیف پسته وارد کنید');
    setState(() => _busy = true);
    try {
      final bool isNew = widget.row == null;
      final String uid = await EntityStore.I.save(
          _kPfE,
          <String, dynamic>{
            'lead_uid': _leadUid,
            'template_uid': _tplUid,
            'number': d.number.trim(),
            'date': d.date,
            'buyer': d.buyer.split('\n').first.trim(),
            'total': double.parse(d.total.toStringAsFixed(2)),
            'ccy': d.ccy.toUpperCase(),
            'data': d.toJson(withLogo: false),
          },
          uid: widget.row?['uid'] as String?);
      // اولین ثبت ⇒ یک خط «پیش‌فاکتور» در تاریخچهٔ مشتری (مرحلهٔ کارت هم «پیش‌فاکتور» می‌شود)
      if (isNew && _leadUid != null) {
        try {
          await MkStore.I.addActivity(_leadUid!, kind: 'proforma', result: 'پیش‌فاکتور شمارهٔ ${d.number} — ${pfMoney(d.total, d.ccy)}');
        } catch (_) {}
      }
      if (!mounted) return;
      snack(context, 'پیش‌فاکتور ذخیره شد');
      Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
              builder: (_) => MkProformaFormScreen(row: <String, dynamic>{
                    'uid': uid, 'lead_uid': _leadUid, 'template_uid': _tplUid, 'data': d.toJson(withLogo: false),
                  }, templates: widget.templates)));
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<PfData> _forExport() => _withLogo(_d!.copy(), _tplUid);

  @override
  Widget build(BuildContext context) {
    final PfData? d = _d;
    return Scaffold(
      appBar: AppBar(title: Text(widget.row == null ? 'پیش‌فاکتور جدید' : 'پیش‌فاکتور ${d?.number ?? ''}'), actions: <Widget>[
        if (d != null) ...<Widget>[
          IconButton(
              tooltip: 'PDF / چاپ',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () async {
                final PfData x = await _forExport();
                if (context.mounted) await _exportPdf(context, x);
              }),
          IconButton(
              tooltip: 'فایل Word',
              icon: const Icon(Icons.description_outlined),
              onPressed: () async {
                final PfData x = await _forExport();
                if (context.mounted) await _exportWord(context, x);
              }),
        ],
      ]),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : _pfWide(ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: <Widget>[
              if (widget.row == null && widget.templates.length > 1)
                DropdownButtonFormField<String>(
                  initialValue: _tplUid,
                  decoration: const InputDecoration(labelText: 'قالب'),
                  items: <DropdownMenuItem<String>>[for (final (String, String, PfData) t in widget.templates) DropdownMenuItem<String>(value: t.$1, child: Text(t.$2))],
                  onChanged: (String? v) async {
                    if (v == null) return;
                    final PfData t = widget.templates.firstWhere(((String, String, PfData) e) => e.$1 == v).$3;
                    final PfData n = _fromTemplate(t)..number = d.number;
                    setState(() {
                      _tplUid = v;
                      _d = n;
                      _gen++;
                    });
                  },
                ),
              DropdownButtonFormField<String?>(
                initialValue: _leads.any((Map<String, dynamic> l) => l['uid'] == _leadUid) ? _leadUid : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'مشتری (از فهرست مشتری‌ها)'),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(value: null, child: Text('— بدون انتخاب (خریدار را دستی بنویسید) —')),
                  for (final Map<String, dynamic> l in _leads) DropdownMenuItem<String?>(value: '${l['uid']}', child: Text('${l['name'] ?? ''}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (String? v) => setState(() {
                  _leadUid = v;
                  if (v != null) {
                    d.buyer = _buyerOf(_leads.firstWhere((Map<String, dynamic> l) => l['uid'] == v));
                    _gen++;
                  }
                }),
              ),
              const SizedBox(height: 8),
              PfEditor(key: ValueKey<int>(_gen), data: d, template: false, onChanged: () => setState(() {})),
            ])),
      floatingActionButton: d == null
          ? null
          : FloatingActionButton.extended(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('ذخیره')),
    );
  }
}

// ============================================================ ویرایشگر مشترک

Widget _pfWide(Widget child) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 920), child: child));

String _countryEn(String iso) {
  final List<String>? n = kMkCountryNames[iso.toUpperCase()];
  return n != null && n.length > 1 ? n[1] : iso.toUpperCase();
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

double _parse(String s) => double.tryParse(s.replaceAll(',', '').replaceAll('٬', '').trim()) ?? 0;

/// ویرایش همهٔ بخش‌ها. [template] = قالب (سربرگ/رنگ/لوگو/پانویس باز)؛ در پیش‌فاکتور این‌ها در یک بخش بسته‌اند.
class PfEditor extends StatefulWidget {
  const PfEditor({super.key, required this.data, required this.template, required this.onChanged});
  final PfData data;
  final bool template;
  final VoidCallback onChanged;
  @override
  State<PfEditor> createState() => _PfEditorState();
}

class _PfEditorState extends State<PfEditor> {
  PfData get d => widget.data;

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  Widget _f(String label, String value, ValueChanged<String> on, {int lines = 1, bool ltr = true, TextInputType? kb, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          initialValue: value,
          maxLines: lines,
          minLines: 1,
          keyboardType: kb ?? (lines > 1 ? TextInputType.multiline : null),
          textDirection: ltr ? TextDirection.ltr : null,
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
          onChanged: on,
        ),
      );

  Widget _section(String title, List<Widget> children, {bool open = true, String? subtitle}) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ExpansionTile(
          initiallyExpanded: open,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(fontSize: 12)),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: children,
        ),
      );

  Widget _addBtn(int count, VoidCallback add, String what) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: count >= kPfMaxRows ? null : add,
          icon: const Icon(Icons.add),
          label: Text(count >= kPfMaxRows ? 'حداکثر $kPfMaxRows ردیف' : 'افزودن $what ($count از $kPfMaxRows)'),
        ),
      );

  Widget _del(VoidCallback on) => IconButton(icon: const Icon(Icons.close, size: 20), tooltip: 'حذف ردیف', onPressed: on);

  Widget _pairs(String title, List<PfPair> l, {String a = 'Label', String b = 'Value', bool open = true, bool numeric = false, String? subtitle}) => _section(
        title,
        <Widget>[
          for (final PfPair e in l)
            Row(key: ObjectKey(e), crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Expanded(flex: 4, child: _f(a, e.label, (String v) => e.label = v)),
              const SizedBox(width: 6),
              Expanded(
                  flex: 6,
                  child: _f(b, e.value, (String v) {
                    e.value = v;
                    if (numeric) widget.onChanged();
                  }, lines: numeric ? 1 : 3, kb: numeric ? const TextInputType.numberWithOptions(decimal: true) : null)),
              _del(() {
                l.remove(e);
                _changed();
              }),
            ]),
          _addBtn(l.length, () {
            l.add(PfPair('', ''));
            _changed();
          }, 'ردیف'),
        ],
        open: open,
        subtitle: subtitle,
      );

  Widget _lines(String title, List<String> l, String what, {bool open = true}) => _section(title, <Widget>[
        for (int i = 0; i < l.length; i++)
          Row(key: ValueKey<String>('$title#$i#${l.length}'), crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Expanded(child: _f('${i + 1}', l[i], (String v) => l[i] = v, lines: 3)),
            _del(() {
              l.removeAt(i);
              _changed();
            }),
          ]),
        _addBtn(l.length, () {
          l.add('');
          _changed();
        }, what),
      ], open: open);

  Future<void> _pickLogo() async {
    try {
      final XFile? f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 400, maxHeight: 400, imageQuality: 85);
      if (f == null) return;
      final List<int> bytes = await f.readAsBytes();
      final String mime = f.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      final String url = 'data:$mime;base64,${base64Encode(bytes)}';
      if (url.length > 250000) {
        if (mounted) snack(context, 'تصویر لوگو بزرگ است؛ تصویر کوچک‌تری انتخاب کنید');
        return;
      }
      d.logo = url;
      _changed();
    } catch (e) {
      if (mounted) snack(context, 'خطا در انتخاب تصویر: $e');
    }
  }

  static const List<(String, String, String, String, String)> _palettes = <(String, String, String, String, String)>[
    ('سبز و طلایی (نمونه)', '2F4A2B', 'B08D3C', 'F1F5EC', 'E6D9AE'),
    ('سرمه‌ای و طلایی', '1F3A5F', 'C9A227', 'EEF2F7', 'E8DDB5'),
    ('زرشکی و طلایی', '6B1E2E', 'B08D3C', 'F7EEF0', 'EAD7B0'),
    ('خاکستری و سبز پسته‌ای', '3A3F44', '8DB33A', 'F0F2F3', 'D9E8B8'),
  ];

  Widget _colorDot(String hex) => Container(
      width: 18, height: 18, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(color: Color(int.parse('FF$hex', radix: 16)), shape: BoxShape.circle));

  List<Widget> _headerFields() => <Widget>[
        _f('Company name', d.company, (String v) => d.company = v),
        _f('Tagline', d.tagline, (String v) => d.tagline = v, hint: 'Premium Iranian Pistachio Exporter'),
        _f('Document title', d.title, (String v) => d.title = v),
        Row(children: <Widget>[
          if (d.logoBytes != null)
            Container(width: 56, height: 56, margin: const EdgeInsets.only(left: 8), child: Image.memory(d.logoBytes!, fit: BoxFit.contain)),
          OutlinedButton.icon(onPressed: _pickLogo, icon: const Icon(Icons.image_outlined), label: Text(d.logo.isEmpty ? 'انتخاب لوگو' : 'تغییر لوگو')),
          if (d.logo.isNotEmpty)
            TextButton(
                onPressed: () {
                  d.logo = '';
                  _changed();
                },
                child: const Text('حذف لوگو')),
        ]),
        const SizedBox(height: 8),
        const Text('رنگ‌بندی', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
          for (final (String, String, String, String, String) pl in _palettes)
            ChoiceChip(
              selected: d.cPrimary == pl.$2 && d.cAccent == pl.$3,
              avatar: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[_colorDot(pl.$2), _colorDot(pl.$3)]),
              label: Text(pl.$1),
              onSelected: (_) {
                d
                  ..cPrimary = pl.$2
                  ..cAccent = pl.$3
                  ..cLight = pl.$4
                  ..cTagline = pl.$5;
                _changed();
              },
            ),
        ]),
        const SizedBox(height: 8),
        Row(key: ValueKey<String>('colors${d.cPrimary}${d.cAccent}'), children: <Widget>[
          Expanded(child: _f('رنگ اصلی (hex)', d.cPrimary, (String v) => d.cPrimary = _hexOr(v, d.cPrimary))),
          const SizedBox(width: 6),
          Expanded(child: _f('رنگ عنوان (hex)', d.cAccent, (String v) => d.cAccent = _hexOr(v, d.cAccent))),
        ]),
        _f('Footer (address, phones, website)', d.footer, (String v) => d.footer = v, lines: 3),
        Row(children: <Widget>[
          Expanded(child: _f('Signature (left)', d.signLeft, (String v) => d.signLeft = v)),
          const SizedBox(width: 6),
          Expanded(child: _f('Signature (right)', d.signRight, (String v) => d.signRight = v)),
        ]),
      ];

  static String _hexOr(String v, String old) {
    final String h = v.replaceAll('#', '').trim().toUpperCase();
    return RegExp(r'^[0-9A-F]{6}$').hasMatch(h) ? h : old;
  }

  Widget _items() => _section('PISTACHIO DESCRIPTION — اقلام', <Widget>[
        for (final PfItem i in d.items)
          Card(
            key: ObjectKey(i),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 0, 4),
              child: Column(children: <Widget>[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Expanded(flex: 4, child: _f('Pistachio Type', i.type, (String v) => i.type = v)),
                  const SizedBox(width: 6),
                  Expanded(flex: 3, child: _f('Grade', i.grade, (String v) => i.grade = v)),
                  const SizedBox(width: 6),
                  Expanded(flex: 3, child: _f('Ounce', i.ounce, (String v) => i.ounce = v)),
                  _del(() {
                    d.items.remove(i);
                    _changed();
                  }),
                ]),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Expanded(
                      flex: 3,
                      child: _f('Weight', i.qty == 0 ? '' : pfQty(i.qty), (String v) {
                        i.qty = _parse(v);
                        _changed();
                      }, kb: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const <ButtonSegment<String>>[ButtonSegment<String>(value: 'MT', label: Text('MT')), ButtonSegment<String>(value: 'kg', label: Text('kg'))],
                      selected: <String>{i.unit},
                      onSelectionChanged: (Set<String> s) {
                        i.unit = s.first;
                        _changed();
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                      flex: 3,
                      child: _f('Price per kg (${d.ccy})', i.price == 0 ? '' : pfQty(i.price), (String v) {
                        i.price = _parse(v);
                        _changed();
                      }, kb: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 8),
                ]),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text('Total: ${pfMoney(i.total, d.ccy)}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ),
          ),
        _addBtn(d.items.length, () {
          d.items.add(PfItem(unit: d.items.isEmpty ? 'MT' : d.items.last.unit));
          _changed();
        }, 'ردیف'),
        if (d.items.length > 1)
          Text('جمع کل: ${pfMoney(d.total, d.ccy)}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.bold)),
      ]);

  @override
  Widget build(BuildContext context) {
    final bool t = widget.template;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      if (!t)
        _section('اطلاعات این پیش‌فاکتور', <Widget>[
          Row(children: <Widget>[
            Expanded(child: _f('No.', d.number, (String v) => d.number = v.trim())),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Date: ${pfDate(d.date)}', textDirection: TextDirection.ltr),
                  onPressed: () async {
                    final DateTime init = DateTime.tryParse(d.date) ?? DateTime.now();
                    final DateTime? x = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (x == null) return;
                    d.date = _iso(x);
                    _changed();
                  },
                ),
              ),
            ),
          ]),
          _f('Buyer', d.buyer, (String v) => d.buyer = v, lines: 5),
        ]),
      _section(
        'سربرگ، رنگ‌ها، فروشنده و پانویس',
        <Widget>[
          ..._headerFields(),
          _f('Seller', d.seller, (String v) => d.seller = v, lines: 5),
          Row(children: <Widget>[
            Expanded(child: _f('Currency (USD, EUR, …)', d.ccy, (String v) {
              d.ccy = v.trim().toUpperCase().isEmpty ? 'USD' : v.trim().toUpperCase();
              widget.onChanged();
            })),
            if (t) ...<Widget>[
              const SizedBox(width: 6),
              Expanded(
                  child: _f('شمارهٔ شروع پیش‌فاکتورها', '${d.nextNo}', (String v) => d.nextNo = int.tryParse(v.trim()) ?? d.nextNo,
                      kb: TextInputType.number)),
            ],
          ]),
        ],
        open: t,
        subtitle: t ? null : 'از قالب آمده؛ فقط اگر برای این پیش‌فاکتور فرق دارد تغییر دهید',
      ),
      _items(),
      _pairs('PAYMENT TERMS — شرایط پرداخت', d.payment, a: 'Title (e.g. Deposit)', b: 'Amount or text', numeric: true,
          subtitle: 'مبلغ عددی با ارز پیش‌فاکتور نوشته می‌شود'),
      _pairs('Packing / HS Code / Delivery', d.info, open: t),
      _pairs('BANK INFORMATION — اطلاعات بانکی', d.bank, open: t),
      _pairs('QUALITY SPECIFICATIONS — مشخصات کیفی', d.quality, a: 'Parameter', b: 'Limit', open: t),
      _lines('IMPORTANT CONDITIONS — شرایط مهم', d.conditions, 'شرط', open: t),
      _lines('DOCUMENTS — مدارک', d.documents, 'مدرک', open: t),
    ]);
  }
}
