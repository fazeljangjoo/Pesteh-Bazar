import 'package:flutter/material.dart';

import 'access_catalog.dart';
import 'edition.dart';
import 'fiscal_ui.dart';
import 'perms.dart';
import 'staff_login_logic.dart'; // v91 p2: قاعدهٔ نام کاربری
import 'utils.dart' show faNum;
import 'warehouse_ui.dart' show StockApi, StockApiException;

/// v87 — «کارکنان، نقش‌ها و دسترسی‌ها» (فایل مشترک اندروید و ویندوز؛ جایگزین صفحه‌های قدیمی staff_screens).
///   ۱) بخش‌هایی که کارکن/نقش به آن‌ها دسترسی دارد (خرید، انبار، فراوری، …)
///   ۲) در هر بخش: کدام گزینه‌ها باز/بسته، «نمایش قیمت در این بخش»، و قسمت‌های فرم (نمایش / قفل / پنهان).
///   کارکن می‌تواند چند نقش داشته باشد (مثلاً «اتاق انس» + «انباردار») و دسترسی اختصاصی بیشتر/کمتر از نقش‌هایش.
///   مالک همه‌کار می‌کند؛ کارکنِ دارای «کارکنان، نقش‌ها و دسترسی‌ها» فقط تا حد دسترسی خودش (سرور هم بررسی می‌کند).
///   هر تغییر بلافاصله روی دستگاه‌های آن کارکن اعمال می‌شود (نسخهٔ دسترسی در پینگ همگام‌سازی).

List<Map<String, dynamic>> _maps(dynamic raw) =>
    <Map<String, dynamic>>[if (raw is List) for (final dynamic x in raw) if (x is Map) Map<String, dynamic>.from(x)];
Set<String> _strs(dynamic raw) => <String>{if (raw is List) for (final dynamic x in raw) if (x is String) x};
Map<String, String> _modes(dynamic raw) => <String, String>{
      if (raw is Map)
        for (final MapEntry<dynamic, dynamic> e in raw.entries)
          if (kFieldModes.contains('${e.value}')) '${e.key}': '${e.value}',
    };
String _err(Object e) => e is StockApiException ? e.message : e.toString().replaceFirst('Exception: ', '');

class AccessRole {
  AccessRole({required this.id, required this.name, required this.perms, required this.fields, required this.system});
  final int id;
  final String name;
  final Set<String> perms;
  final Map<String, String> fields;
  final bool system;

  static AccessRole fromJson(Map<String, dynamic> j) => AccessRole(
        id: (j['id'] as num).toInt(),
        name: '${j['name'] ?? ''}',
        perms: _strs(j['perms']),
        fields: _modes(j['field_rules'])..removeWhere((String k, String v) => v == 'hide'), // v89: فقط قسمت‌های باز
        system: j['is_system'] == true,
      );
}

/// داده‌های مشترک صفحه‌ها: کاتالوگ بخش‌ها، نقش‌ها و دسترسی ویرایشگر.
class AccessData {
  AccessData(this.sections, this.roles, this.actor, this.owner);
  final List<AccessSection> sections;
  final List<AccessRole> roles;
  final Set<String> actor;
  final bool owner;

  /// ویرایشگر می‌تواند این کلید را بدهد/بگیرد؟ (مالک همه؛ کارکن فقط آنچه خودش دارد)
  bool may(String key) => owner || actor.contains(key) || (key.startsWith('price.') && actor.contains('price.view'));

  AccessRole? role(int id) {
    for (final AccessRole r in roles) {
      if (r.id == id) return r;
    }
    return null;
  }

  static Future<AccessData> load() async {
    final Map<String, dynamic> r = await StockApi.call('roles.list');
    final List<Map<String, dynamic>> sec = _maps(r['sections']);
    final bool owner = !StaffPerms.I.isStaff;
    final Set<String> actor = owner ? <String>{} : _strs(r['actor_perms']).union(_strs(StaffPerms.I.current.value?['perms']));
    return AccessData(
      sec.isEmpty ? kAccessSections : <AccessSection>[for (final Map<String, dynamic> s in sec) AccessSection.fromJson(s)],
      <AccessRole>[for (final Map<String, dynamic> x in _maps(r['items'])) AccessRole.fromJson(x)],
      actor,
      owner,
    );
  }
}

/// دسترسی در حال ویرایش (کلیدهای مجوز + قسمت‌های فرم lock/hide).
class AccessDraft {
  AccessDraft(Set<String> perms, Map<String, String> fields)
      : perms = <String>{...perms},
        fields = <String, String>{...fields};
  final Set<String> perms;
  final Map<String, String> fields;
  AccessDraft copy() => AccessDraft(perms, fields);
}

bool accessSectionOn(AccessSection s, Set<String> perms) => s.perms.any((AccessOption o) => perms.contains(o.key));

/// قیمت این بخش دیده می‌شود؟ (اتاق انس فقط با intake.price؛ بقیه با price.view یا price.<بخش>)
bool accessPriceOn(AccessSection s, Set<String> perms) {
  final String? k = s.price;
  if (k == null) return false;
  if (k == 'intake.price') return perms.contains(k);
  return perms.contains('price.view') || perms.contains(k);
}

/// یکدست‌کردن قیمت پیش از ذخیره: اگر قیمت همهٔ بخش‌های انتخاب‌شده (به‌جز اتاق انس) روشن است ⇒ price.view (همان رفتار قدیمی)؛
/// وگرنه کلید هر بخش جداگانه. بخش انتخاب‌نشده کلید قیمت ندارد.
Set<String> accessNormalizePrice(Set<String> perms, List<AccessSection> sections) {
  final Set<String> p = <String>{...perms};
  final List<AccessSection> priced = <AccessSection>[
    for (final AccessSection s in sections)
      if (s.price != null && s.price != 'intake.price' && accessSectionOn(s, p)) s,
  ];
  for (final AccessSection s in sections) {
    if (s.price != null && s.price != 'intake.price' && !accessSectionOn(s, p)) p.remove(s.price);
    if (s.price == 'intake.price' && !accessSectionOn(s, p)) p.remove('intake.price');
  }
  if (priced.isEmpty) {
    p.remove('price.view');
    return p;
  }
  final bool all = priced.every((AccessSection s) => accessPriceOn(s, p));
  if (all) {
    for (final AccessSection s in priced) {
      p.remove(s.price);
    }
    p.add('price.view');
  } else {
    final bool global = p.remove('price.view');
    if (global) {
      for (final AccessSection s in priced) {
        p.add(s.price!);
      }
    }
  }
  return p;
}

// ───────────────────────── ویرایشگر بخش‌محور ─────────────────────────

class SectionAccessEditor extends StatelessWidget {
  const SectionAccessEditor({super.key, required this.data, required this.draft, required this.onChanged, this.base});
  final AccessData data;
  final AccessDraft draft;
  final ValueChanged<AccessDraft> onChanged;

  /// دسترسی نقش‌ها (فقط برای کارکن): گزینه‌ای که با دسترسی اختصاصی عوض شده علامت می‌خورد.
  final AccessDraft? base;

  void _emit(void Function(AccessDraft d) f) {
    final AccessDraft d = draft.copy();
    f(d);
    onChanged(d);
  }

  void _toggleSection(AccessSection s, bool on) => _emit((AccessDraft d) {
        if (on) {
          final AccessOption? first = s.perms.where((AccessOption o) => data.may(o.key)).firstOrNull;
          if (first != null) d.perms.add(first.key);
        } else {
          for (final AccessOption o in s.perms) {
            if (data.may(o.key)) d.perms.remove(o.key);
          }
          if (s.price != null && s.price != 'intake.price' && d.perms.contains('price.view')) {
            d.perms.remove('price.view'); // قیمت بقیهٔ بخش‌ها می‌ماند
            for (final AccessSection x in data.sections) {
              if (x != s && x.price != null && x.price != 'intake.price' && accessSectionOn(x, d.perms)) d.perms.add(x.price!);
            }
          }
          if (s.price != null) d.perms.remove(s.price);
          for (final AccessOption f in s.fields) {
            d.fields.remove(f.key);
          }
        }
      });

  void _togglePrice(AccessSection s, bool on) => _emit((AccessDraft d) {
        final String k = s.price!;
        if (on) {
          d.perms.add(k);
        } else {
          d.perms.remove(k);
          if (k != 'intake.price' && d.perms.remove('price.view')) {
            for (final AccessSection x in data.sections) {
              if (x != s && x.price != null && x.price != 'intake.price' && accessSectionOn(x, d.perms)) d.perms.add(x.price!);
            }
          }
        }
      });

  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final List<AccessSection> on = <AccessSection>[for (final AccessSection s in data.sections) if (accessSectionOn(s, draft.perms)) s];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text('۱) بخش‌هایی که دسترسی دارد', style: th.textTheme.titleMedium),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
        for (final AccessSection s in data.sections)
          FilterChip(
            label: Text(s.label),
            selected: accessSectionOn(s, draft.perms),
            onSelected: s.perms.any((AccessOption o) => data.may(o.key)) ? (bool v) => _toggleSection(s, v) : null,
          ),
      ]),
      const SizedBox(height: 14),
      Text('۲) گزینه‌های هر بخش', style: th.textTheme.titleMedium),
      if (on.isEmpty)
        Padding(padding: const EdgeInsets.all(12), child: Text('هنوز بخشی انتخاب نشده؛ این کاربر به هیچ قسمتی دسترسی ندارد.', style: TextStyle(color: th.hintColor))),
      for (final AccessSection s in on) _sectionCard(context, s),
    ]);
  }

  Widget _changedMark(BuildContext context, bool changed) => changed
      ? Padding(
          padding: const EdgeInsetsDirectional.only(start: 6),
          child: Tooltip(message: 'با دسترسی اختصاصی این کارمند عوض شده (با نقش‌هایش فرق دارد)', child: Icon(Icons.person_pin, size: 16, color: Theme.of(context).colorScheme.tertiary)),
        )
      : const SizedBox.shrink();

  Widget _sectionCard(BuildContext context, AccessSection s) {
    final ThemeData th = Theme.of(context);
    final int n = s.perms.where((AccessOption o) => draft.perms.contains(o.key)).length;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(s.label, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${faNum(n, dec: 0)} از ${faNum(s.perms.length, dec: 0)} گزینه'
            '${s.price == null ? '' : (accessPriceOn(s, draft.perms) ? '  •  قیمت نمایش داده می‌شود' : '  •  بدون قیمت')}'
            '${s.fields.any((AccessOption f) => draft.fields.containsKey(f.key)) ? '  •  قسمت قفل/پنهان دارد' : ''}'),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: <Widget>[
          for (final AccessOption o in s.perms)
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Row(children: <Widget>[Flexible(child: Text(o.label)), if (base != null) _changedMark(context, base!.perms.contains(o.key) != draft.perms.contains(o.key))]),
              subtitle: data.may(o.key) ? null : const Text('خودتان این دسترسی را ندارید', style: TextStyle(fontSize: 11)),
              value: draft.perms.contains(o.key),
              onChanged: data.may(o.key)
                  ? (bool v) => _emit((AccessDraft d) {
                        if (v) {
                          d.perms.add(o.key);
                        } else {
                          d.perms.remove(o.key);
                        }
                      })
                  : null,
            ),
          if (s.price != null) ...<Widget>[
            const Divider(height: 8),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              secondary: const Icon(Icons.payments_outlined),
              title: Row(children: <Widget>[
                const Flexible(child: Text('نمایش قیمت‌ها و مبالغ در این بخش')),
                if (base != null) _changedMark(context, accessPriceOn(s, base!.perms) != accessPriceOn(s, draft.perms)),
              ]),
              subtitle: Text(accessPriceOn(s, draft.perms) ? 'فی، بها، مبلغ و سود این بخش دیده می‌شود' : 'هیچ فی، بها یا مبلغی در این بخش نشان داده نمی‌شود',
                  style: const TextStyle(fontSize: 11.5)),
              value: accessPriceOn(s, draft.perms),
              onChanged: data.may(s.price!) ? (bool v) => _togglePrice(s, v) : null,
            ),
          ],
          if (s.fields.isNotEmpty) ...<Widget>[
            const Divider(height: 8),
            Align(alignment: AlignmentDirectional.centerStart, child: Text('قسمت‌های فرم (فقط قسمت‌های «نمایش» و «قفل» برای کارمند دیده می‌شوند)', style: TextStyle(color: th.hintColor, fontWeight: FontWeight.w600))),
            for (final AccessOption f in s.fields)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(children: <Widget>[
                  Expanded(child: Row(children: <Widget>[Flexible(child: Text(f.label)), if (base != null) _changedMark(context, (base!.fields[f.key] ?? 'hide') != (draft.fields[f.key] ?? 'hide'))])),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: <ButtonSegment<String>>[
                      for (final String m in kFieldModes) ButtonSegment<String>(value: m, label: Text(kFieldModeLabels[m]!, style: const TextStyle(fontSize: 12))),
                    ],
                    selected: <String>{draft.fields[f.key] ?? 'hide'}, // v89: باز نشده = پنهان
                    onSelectionChanged: (Set<String> v) => _emit((AccessDraft d) {
                      if (v.first == 'hide') {
                        d.fields.remove(f.key);
                      } else {
                        d.fields[f.key] = v.first;
                      }
                    }),
                  ),
                ]),
              ),
          ],
        ],
      ),
    );
  }
}

/// خلاصهٔ یک دسترسی برای کارت فهرست: «خرید، انبار (با قیمت)، فراوری».
String accessSummary(AccessData data, Set<String> perms) {
  final List<String> parts = <String>[
    for (final AccessSection s in data.sections)
      if (accessSectionOn(s, perms)) '${s.label}${s.price != null && accessPriceOn(s, perms) ? ' (با قیمت)' : ''}',
  ];
  return parts.isEmpty ? 'بدون دسترسی' : parts.join('، ');
}

// ───────────────────────── صفحهٔ اصلی ─────────────────────────

class AccessHomeScreen extends StatefulWidget {
  const AccessHomeScreen({super.key});

  @override
  State<AccessHomeScreen> createState() => _AccessHomeScreenState();
}

class _AccessHomeScreenState extends State<AccessHomeScreen> {
  AccessData? _data;
  List<Map<String, dynamic>> _staff = <Map<String, dynamic>>[];
  int? _limit;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final AccessData d = await AccessData.load();
      final Map<String, dynamic> s = await StockApi.call('staff.list');
      if (!mounted) return;
      setState(() {
        _data = d;
        _staff = _maps(s['items']);
        _limit = (s['limit'] as num?)?.toInt();
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _err(e);
        _loading = false;
      });
    }
  }

  Future<void> _open(Widget page) async {
    final bool? ch = await Navigator.push<bool>(context, MaterialPageRoute<bool>(builder: (_) => page));
    if (ch == true) await _load();
  }

  Set<String> _effective(Map<String, dynamic> s) {
    final AccessData d = _data!;
    final List<AccessRole> roles = <AccessRole>[
      for (final dynamic id in (s['role_ids'] is List ? s['role_ids'] as List<dynamic> : <dynamic>[s['role_id']]))
        if (id is num && d.role(id.toInt()) != null) d.role(id.toInt())!,
    ];
    return accessEffective(<Set<String>>[for (final AccessRole r in roles) r.perms], const <Map<String, String>>[], _strs(s['perm_grants']), _strs(s['perm_denies']),
        const <String, String>{}).perms;
  }

  @override
  Widget build(BuildContext context) {
    final AccessData? d = _data;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('کارمندان، نقش‌ها و دسترسی‌ها'),
          actions: <Widget>[IconButton(tooltip: 'به‌روزرسانی', icon: const Icon(Icons.refresh), onPressed: _load)],
          bottom: const TabBar(tabs: <Widget>[Tab(text: 'کارمندان'), Tab(text: 'نقش‌ها')]),
        ),
        body: _loading && d == null
            ? const Center(child: CircularProgressIndicator())
            : (d == null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error ?? 'خطا', textAlign: TextAlign.center)))
                : TabBarView(children: <Widget>[_staffTab(d), _rolesTab(d)])),
      ),
    );
  }

  Widget _staffTab(AccessData d) {
    final int active = _staff.where((Map<String, dynamic> s) => s['active'] == true).length;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'acc-staff',
        onPressed: (_limit != null && active >= _limit!) ? null : () => _open(StaffAccessScreen(data: d)),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('کارمند تازه'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: <Widget>[
          if (_error != null) Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(10), child: Text(_error!))),
          if (_limit != null) Text('کارمند فعال: ${faNum(active, dec: 0)} از ${faNum(_limit!, dec: 0)}', style: TextStyle(color: Theme.of(context).hintColor)),
          if (_staff.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('هنوز کارمندی تعریف نشده'))),
          for (final Map<String, dynamic> s in _staff)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Icon(s['active'] == true ? Icons.person_outline : Icons.person_off_outlined)),
                title: Text('${s['name'] ?? ''}  •  ${s['username'] ?? ''}${s['active'] == true ? '' : '  •  غیرفعال'}'),
                subtitle: Text(
                  'نقش: ${(s['role_names'] is List && (s['role_names'] as List<dynamic>).isNotEmpty) ? (s['role_names'] as List<dynamic>).join(' + ') : (s['role_name'] ?? '—')}'
                  '${_strs(s['perm_grants']).isNotEmpty || _strs(s['perm_denies']).isNotEmpty || (s['field_rules'] is Map && (s['field_rules'] as Map<dynamic, dynamic>).isNotEmpty) ? '  •  دسترسی اختصاصی' : ''}\n'
                  '${accessSummary(d, _effective(s))}',
                ),
                isThreeLine: true,
                onTap: () => _open(StaffAccessScreen(data: d, staff: s)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _rolesTab(AccessData d) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'acc-role',
        onPressed: () => _open(RoleAccessScreen(data: d)),
        icon: const Icon(Icons.add_moderator_outlined),
        label: const Text('نقش تازه'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: <Widget>[
          for (final AccessRole r in d.roles)
            Card(
              child: ListTile(
                leading: Icon(r.system ? Icons.verified_user_outlined : Icons.badge_outlined),
                title: Text('${r.name}${r.system ? '  •  پیش‌فرض' : ''}'),
                subtitle: Text('${accessSummary(d, r.perms)}${r.fields.isEmpty ? '' : '\n${faNum(r.fields.length, dec: 0)} قسمت فرم قفل/پنهان'}'),
                isThreeLine: r.fields.isNotEmpty,
                onTap: () => _open(RoleAccessScreen(data: d, role: r)),
              ),
            ),
        ]),
      ),
    );
  }
}

// ───────────────────────── ویرایش نقش ─────────────────────────

class RoleAccessScreen extends StatefulWidget {
  const RoleAccessScreen({super.key, required this.data, this.role});
  final AccessData data;
  final AccessRole? role;

  @override
  State<RoleAccessScreen> createState() => _RoleAccessScreenState();
}

class _RoleAccessScreenState extends State<RoleAccessScreen> {
  late final TextEditingController _name = TextEditingController(text: widget.role?.name ?? '');
  late AccessDraft _draft = AccessDraft(widget.role?.perms ?? <String>{}, widget.role?.fields ?? <String, String>{});
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'نام نقش را وارد کنید');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Set<String> perms = accessNormalizePrice(_draft.perms, widget.data.sections);
      await StockApi.call('roles.save', <String, dynamic>{
        if (widget.role != null) 'id': widget.role!.id,
        'name': name,
        'perms': perms.toList()..sort(),
        'field_rules': _draft.fields,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: const Text('حذف نقش؟'),
            content: Text('نقش «${widget.role!.name}» حذف شود؟ (فقط اگر به هیچ کارمندی داده نشده باشد)'),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await StockApi.call('roles.delete', <String, dynamic>{'id': widget.role!.id});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.role == null ? 'نقش تازه' : 'نقش «${widget.role!.name}»'),
        actions: <Widget>[
          if (widget.role != null && !widget.role!.system) IconButton(tooltip: 'حذف نقش', icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : _delete),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: <Widget>[
        TextField(controller: _name, maxLength: 100, decoration: const InputDecoration(labelText: 'نام نقش', border: OutlineInputBorder())),
        if (widget.role?.system == true)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('نقش پیش‌فرض است؛ دسترسی‌هایش را می‌توانید عوض کنید ولی حذف نمی‌شود.', style: TextStyle(color: Theme.of(context).hintColor))),
        SectionAccessEditor(data: widget.data, draft: _draft, onChanged: (AccessDraft d) => setState(() => _draft = d)),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_busy ? 'در حال ذخیره…' : 'ذخیرهٔ نقش')),
        const SizedBox(height: 6),
        Text('تغییر نقش بلافاصله روی دستگاه همهٔ کارمندانِ این نقش اعمال می‌شود.', style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
      ]),
    );
  }
}

// ───────────────────────── ویرایش کارکن ─────────────────────────

class StaffAccessScreen extends StatefulWidget {
  const StaffAccessScreen({super.key, required this.data, this.staff});
  final AccessData data;
  final Map<String, dynamic>? staff;

  @override
  State<StaffAccessScreen> createState() => _StaffAccessScreenState();
}

class _StaffAccessScreenState extends State<StaffAccessScreen> {
  late final Map<String, dynamic>? _s = widget.staff;
  late final TextEditingController _name = TextEditingController(text: '${_s?['name'] ?? ''}');
  late final TextEditingController _user = TextEditingController(text: '${_s?['username'] ?? ''}');
  final TextEditingController _pass = TextEditingController();
  late final TextEditingController _phone = TextEditingController(text: '${_s?['phone'] ?? ''}'); // v89: بازیابی رمز با پیامک
  late bool _active = _s == null || _s['active'] == true;
  late final Set<int> _roles = <int>{
    if (_s != null)
      for (final dynamic id in (_s['role_ids'] is List && (_s['role_ids'] as List<dynamic>).isNotEmpty ? _s['role_ids'] as List<dynamic> : <dynamic>[_s['role_id']]))
        if (id is num && widget.data.role(id.toInt()) != null) id.toInt(),
  };
  late Set<String> _grants = _strs(_s?['perm_grants']);
  late Set<String> _denies = _strs(_s?['perm_denies']);
  late Map<String, String> _ufields = _modes(_s?['field_rules']);
  late Set<int>? _fyIds = _s?['allowed_fy_ids'] is List ? (_s!['allowed_fy_ids'] as List<dynamic>).whereType<num>().map((num n) => n.toInt()).toSet() : null;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (EditionService.I.edition.isGold) FiscalService.I.refresh();
  }

  @override
  void dispose() {
    _name.dispose();
    _user.dispose();
    _pass.dispose();
    _phone.dispose();
    super.dispose();
  }

  List<AccessRole> get _roleList => <AccessRole>[for (final int id in _roles) if (widget.data.role(id) != null) widget.data.role(id)!];

  /// دسترسی نقش‌ها (بدون دسترسی اختصاصی).
  AccessDraft get _base {
    final ({Set<String> perms, Map<String, String> fields}) e =
        accessEffective(<Set<String>>[for (final AccessRole r in _roleList) r.perms], <Map<String, String>>[for (final AccessRole r in _roleList) r.fields], const <String>{}, const <String>{}, const <String, String>{});
    return AccessDraft(e.perms, e.fields);
  }

  /// دسترسی نهایی = نقش‌ها + اختصاصی.
  AccessDraft get _effective {
    final ({Set<String> perms, Map<String, String> fields}) e = accessEffective(<Set<String>>[for (final AccessRole r in _roleList) r.perms],
        <Map<String, String>>[for (final AccessRole r in _roleList) r.fields], _grants, _denies, _ufields);
    return AccessDraft(e.perms, e.fields);
  }

  /// ویرایشگر دسترسی نهایی را تغییر داد ⇒ دسترسی اختصاصی = اختلاف با نقش‌ها.
  void _onEditor(AccessDraft d) {
    final AccessDraft b = _base;
    setState(() {
      _grants = d.perms.difference(b.perms);
      _denies = b.perms.difference(d.perms);
      final Map<String, String> uf = <String, String>{};
      for (final AccessSection s in widget.data.sections) {
        for (final AccessOption f in s.fields) {
          final String want = d.fields[f.key] ?? 'hide', fromRoles = b.fields[f.key] ?? 'hide'; // v89
          if (want != fromRoles) uf[f.key] = want;
        }
      }
      _ufields = uf;
    });
  }

  bool get _custom => _grants.isNotEmpty || _denies.isNotEmpty || _ufields.isNotEmpty;

  Future<void> _save() async {
    final String user = _user.text.trim(), name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'نام کارمند را وارد کنید');
    final String? uErr = validateStaffUsername(user, original: _s == null ? null : '${_s['username'] ?? ''}'); // v91 p2
    if (uErr != null) return setState(() => _error = uErr);
    if (_s == null && _pass.text.length < 6) return setState(() => _error = 'رمز اولیه حداقل ۶ نویسه');
    if (_pass.text.isNotEmpty && _pass.text.length < 6) return setState(() => _error = 'رمز حداقل ۶ نویسه');
    if (_roles.isEmpty) return setState(() => _error = 'حداقل یک نقش انتخاب کنید (برای دسترسی کاملاً اختصاصی، یک نقش با کمترین دسترسی بسازید)');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // قیمت نهایی یکدست ⇒ اختلاف دوباره با نقش‌ها
      final AccessDraft eff = _effective;
      final Set<String> normEff = accessNormalizePrice(eff.perms, widget.data.sections);
      final Set<String> base = _base.perms;
      final List<int> ids = _roles.toList()..sort();
      await StockApi.call('staff.save', <String, dynamic>{
        if (_s != null) 'id': (_s['id'] as num).toInt(),
        'name': name,
        'username': user,
        if (_pass.text.isNotEmpty) 'password': _pass.text,
        'active': _active,
        'role_id': ids.first,
        'role_ids': ids,
        'perm_grants': (normEff.difference(base).toList()..sort()),
        'perm_denies': (base.difference(normEff).toList()..sort()),
        'field_rules': _ufields,
        'phone': _phone.text.trim(), // v89
        if (EditionService.I.edition.isGold) 'allowed_fy_ids': _fyIds?.toList(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: const Text('حذف کارمند؟'),
            content: Text('«${_s?['name']}» حذف شود؟ نشست‌های فعلی‌اش هم قطع می‌شود.'),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await StockApi.call('staff.delete', <String, dynamic>{'id': (_s!['id'] as num).toInt()});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_s == null ? 'کارمند تازه' : '${_s['name']}'),
        actions: <Widget>[if (_s != null) IconButton(tooltip: 'حذف کارمند', icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : _delete)],
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'نام کارمند', border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const ValueKey<String>('staff_username'),
              controller: _user,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 60, // نام قدیمی بلندتر (حق قدیمی) هم نمایش داده شود
              onChanged: (_) => setState(() {}), // v91 p2: اعتبارسنجی زنده
              decoration: InputDecoration(
                labelText: 'نام کاربری (انگلیسی)',
                helperText: 'حروف انگلیسی و عدد، ۳ تا ۳۰ نویسه؛ در کل سامانه یکتا',
                helperMaxLines: 2,
                errorMaxLines: 3,
                errorText: _user.text.trim().isEmpty ? null : validateStaffUsername(_user.text, original: _s == null ? null : '${_s['username'] ?? ''}'),
                counterText: '',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _pass,
          obscureText: true,
          decoration: InputDecoration(labelText: _s == null ? 'رمز اولیه (حداقل ۶ نویسه)' : 'رمز تازه (خالی = بدون تغییر)', border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: 'شمارهٔ موبایل کارمند (اختیاری)',
            helperText: 'اگر کارمند رمزش را فراموش کند، کد بازیابی به همین شماره پیامک می‌شود',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.phone_iphone),
          ),
        ),
        if ('${_s?['staff_code'] ?? ''}'.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('کد پرسنلی: ${_s!['staff_code']}', style: TextStyle(color: th.hintColor))),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('فعال'),
          subtitle: const Text('غیرفعال‌کردن، ورود و نشست‌های فعلی را قطع می‌کند'),
          value: _active,
          onChanged: (bool v) => setState(() => _active = v),
        ),
        const Divider(),
        Text('نقش‌ها (یک یا چند نقش؛ دسترسی‌ها جمع می‌شوند)', style: th.textTheme.titleMedium),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          for (final AccessRole r in widget.data.roles)
            FilterChip(
              label: Text(r.name),
              selected: _roles.contains(r.id),
              onSelected: (r.perms.every(widget.data.may))
                  ? (bool v) => setState(() {
                        if (v) {
                          _roles.add(r.id);
                        } else {
                          _roles.remove(r.id);
                        }
                      })
                  : null,
            ),
        ]),
        const SizedBox(height: 12),
        Card(
          color: th.colorScheme.secondaryContainer.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: <Widget>[
              const Icon(Icons.tune),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_custom
                    ? 'این کارمند دسترسی اختصاصی دارد: ${faNum(_grants.length, dec: 0)} مورد بیشتر، ${faNum(_denies.length, dec: 0)} مورد کمتر از نقش‌ها'
                        '${_ufields.isEmpty ? '' : '، ${faNum(_ufields.length, dec: 0)} قسمت فرم'}'
                    : 'دسترسی این کارمند دقیقاً همان نقش‌هایش است. هر تغییری پایین، فقط برای همین کارمند اعمال می‌شود.'),
              ),
              if (_custom)
                TextButton(
                  onPressed: () => setState(() {
                    _grants = <String>{};
                    _denies = <String>{};
                    _ufields = <String, String>{};
                  }),
                  child: const Text('برگشت به نقش‌ها'),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        SectionAccessEditor(data: widget.data, draft: _effective, base: _base, onChanged: _onEditor),
        if (EditionService.I.edition.isGold) ...<Widget>[
          const Divider(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('دسترسی به همهٔ سال‌های مالی'),
            value: _fyIds == null,
            onChanged: (bool v) => setState(() => _fyIds = v ? null : <int>{}),
          ),
          if (_fyIds != null)
            ValueListenableBuilder<List<FiscalYear>>(
              valueListenable: FiscalService.I.years,
              builder: (BuildContext c, List<FiscalYear> ys, Widget? _) => Column(children: <Widget>[
                for (final FiscalYear y in ys)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${y.name} (${y.statusFa})'),
                    value: _fyIds!.contains(y.id),
                    onChanged: (bool? v) => setState(() => v == true ? _fyIds!.add(y.id) : _fyIds!.remove(y.id)),
                  ),
              ]),
            ),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error!, style: TextStyle(color: th.colorScheme.error))),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_busy ? 'در حال ذخیره…' : 'ذخیرهٔ کارمند')),
        const SizedBox(height: 6),
        Text('تغییر دسترسی بلافاصله روی همهٔ دستگاه‌هایی که این کارمند با آن‌ها وارد شده اعمال می‌شود.', style: TextStyle(fontSize: 12, color: th.hintColor)),
      ]),
    );
  }
}
