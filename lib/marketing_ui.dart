// v90 — بازاریابی بین‌المللی: صفحهٔ اصلی بخش، مشتری‌ها (فهرست/کانبان)، کارت مشتری، پیگیری، فروش، «امروز من» و مدیریت.
import 'package:flutter/material.dart';

import 'access_ui.dart' show AccessHomeScreen;
import 'db.dart' show AppDb;
import 'entity_store.dart' show EntityStore;
import 'import_engine.dart' show kMkLeadImportKind;
import 'import_screen.dart';
import 'marketing_calc.dart';
import 'marketing_dashboard_ui.dart';
import 'marketing_store.dart';
import 'perms.dart';
import 'user_badge.dart' show UserRoleLine, staffLogout;
import 'utils.dart';
import 'warehouse_ui.dart' show StockApiException;
import 'widgets.dart' show confirm, pickDate, snack;

String mkErr(Object e) => e is StockApiException ? e.message : (e is ArgumentError ? '${e.message}' : e.toString().replaceFirst('Exception: ', ''));
String mkDate(Object? v) {
  final String s = '${v ?? ''}';
  return s.length < 10 ? '' : jalaliDate(s.substring(0, 10));
}

String mkDateTime(Object? v) {
  final String s = '${v ?? ''}';
  if (s.length < 16) return mkDate(s);
  return '${jalaliDate(s.substring(0, 10))} — ${toFaDigits(s.substring(11, 16))}';
}

Widget mkStageChip(String stage, {bool dense = false}) {
  final Color c = kMkStageColors[stage] ?? Colors.grey;
  return Container(
    padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: dense ? 2 : 4),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withValues(alpha: 0.5))),
    child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      Icon(kMkStageIcons[stage] ?? Icons.circle, size: dense ? 12 : 14, color: c),
      const SizedBox(width: 4),
      Text(kMkStageLabels[stage] ?? stage, style: TextStyle(color: c, fontSize: dense ? 11 : 12, fontWeight: FontWeight.w600)),
    ]),
  );
}

/// صفحهٔ اصلی بخش: داشبورد (مدیر/مالک/گزارش) · امروز من (بازاریاب) · مشتری‌ها · مدیریت (مدیر).
class MarketingHomeScreen extends StatelessWidget {
  /// v91: true ⇒ صفحهٔ اول برنامه برای بازاریاب / مدیر بازاریابی (پوستهٔ جدا): نام و نقش کاربر، مدیریت کارمندان (مدیر) و خروج
  /// در نوار بالا؛ دکمهٔ بازگشت ندارد چون صفحهٔ دیگری برای این نقش‌ها وجود ندارد.
  final bool shell;
  const MarketingHomeScreen({super.key, this.shell = false});

  @override
  Widget build(BuildContext context) {
    final MkStore s = MkStore.I;
    final List<(String, IconData, Widget)> tabs = <(String, IconData, Widget)>[
      if (s.canTeamReports) ('داشبورد', Icons.insights_outlined, const MarketingDashboard()),
      if (s.canEntry && StaffPerms.I.isStaff) ('امروز من', Icons.today_outlined, const MkMyDayView()),
      if (s.canEntry || s.isManager) ('مشتری‌ها', Icons.groups_2_outlined, const MkLeadsView()),
      if (s.isManager) ('مدیریت', Icons.tune, const MkAdminView()),
    ];
    final List<Widget> actions = shell
        ? <Widget>[
            if (StaffPerms.I.can('users.manage'))
              IconButton(
                tooltip: 'کارمندان بازاریابی',
                icon: const Icon(Icons.manage_accounts_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AccessHomeScreen())),
              ),
            IconButton(tooltip: 'خروج از حساب', icon: const Icon(Icons.logout), onPressed: () => staffLogout(context)),
          ]
        : const <Widget>[];
    final Widget title = shell
        ? const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text('بازاریابی بین‌المللی'),
            UserRoleLine(),
          ])
        : const Text('بازاریابی بین‌المللی');
    if (tabs.isEmpty) {
      return Scaffold(appBar: AppBar(title: title, actions: actions, automaticallyImplyLeading: !shell), body: const Center(child: Text('دسترسی به این بخش ندارید')));
    }
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: title,
          actions: actions,
          automaticallyImplyLeading: !shell,
          bottom: TabBar(isScrollable: tabs.length > 3, tabs: <Widget>[for (final (String, IconData, Widget) t in tabs) Tab(icon: Icon(t.$2), text: t.$1)]),
        ),
        body: TabBarView(children: <Widget>[for (final (String, IconData, Widget) t in tabs) t.$3]),
      ),
    );
  }
}

// ============================================================ مشتری‌ها
class MkLeadsView extends StatefulWidget {
  const MkLeadsView({super.key});
  @override
  State<MkLeadsView> createState() => _MkLeadsViewState();
}

class _MkLeadsViewState extends State<MkLeadsView> {
  String _q = '';
  String? _stage; // null = همهٔ مراحل باز
  bool _kanban = false;
  bool _showClosed = false;

  @override
  void initState() {
    super.initState();
    AppDb.I.version.addListener(_refresh);
  }

  @override
  void dispose() {
    AppDb.I.version.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      floatingActionButton: MkStore.I.canEntry
          ? FloatingActionButton.extended(onPressed: () => _open(const MkLeadFormScreen()), icon: const Icon(Icons.person_add_alt_1), label: const Text('مشتری تازه'))
          : null,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: MkStore.I.leads(q: _q),
        builder: (BuildContext c, AsyncSnapshot<List<Map<String, dynamic>>> snap) {
          final List<Map<String, dynamic>> all = snap.data ?? const <Map<String, dynamic>>[];
          final List<Map<String, dynamic>> list = all.where((Map<String, dynamic> l) {
            final String st = '${l['stage'] ?? 'lead'}';
            if (_stage != null) return st == _stage;
            return _showClosed || kMkOpenStages.contains(st);
          }).toList()
            ..sort((Map<String, dynamic> a, Map<String, dynamic> b) {
              final String x = '${a['next_followup_at'] ?? '9999'}', y = '${b['next_followup_at'] ?? '9999'}';
              return x.compareTo(y);
            });
          final Map<String, int> counts = <String, int>{for (final String s in kMkStages) s: all.where((Map<String, dynamic> l) => '${l['stage'] ?? 'lead'}' == s).length};
          return Column(children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(children: <Widget>[
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(hintText: 'جستجوی نام، شخص، شهر، تلفن، ایمیل…', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
                    onChanged: (String v) => setState(() => _q = v),
                  ),
                ),
                if (MkStore.I.canEntry) ...<Widget>[
                  const SizedBox(width: 4),
                  IconButton(tooltip: 'اضافه کردن از اکسل', icon: const Icon(Icons.upload_file), onPressed: () => _open(const MkImportScreen())),
                ],
                if (wide) ...<Widget>[
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    segments: const <ButtonSegment<bool>>[
                      ButtonSegment<bool>(value: false, icon: Icon(Icons.view_list), label: Text('فهرست')),
                      ButtonSegment<bool>(value: true, icon: Icon(Icons.view_kanban_outlined), label: Text('کانبان')),
                    ],
                    selected: <bool>{_kanban},
                    onSelectionChanged: (Set<bool> v) => setState(() => _kanban = v.first),
                  ),
                ],
              ]),
            ),
            if (!(_kanban && wide))
              SizedBox(
                height: 46,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(label: Text('همهٔ باز (${toFaDigits('${kMkOpenStages.fold<int>(0, (int a, String s) => a + (counts[s] ?? 0))}')})'), selected: _stage == null && !_showClosed, onSelected: (_) => setState(() {
                          _stage = null;
                          _showClosed = false;
                        })),
                  ),
                  for (final String s in kMkStages)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: ChoiceChip(
                        avatar: Icon(kMkStageIcons[s], size: 16, color: kMkStageColors[s]),
                        label: Text('${kMkStageLabels[s]} (${toFaDigits('${counts[s] ?? 0}')})'),
                        selected: _stage == s,
                        onSelected: (_) => setState(() => _stage = _stage == s ? null : s),
                      ),
                    ),
                ]),
              ),
            Expanded(
              child: snap.connectionState != ConnectionState.done && all.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : (_kanban && wide)
                      ? _Kanban(leads: all, onOpen: (String uid) => _open(MkLeadScreen(uid: uid)), onRefresh: _refresh)
                      : list.isEmpty
                          ? const _Empty(icon: Icons.groups_2_outlined, text: 'مشتری‌ای نیست. با «مشتری تازه» اولین کارت را بسازید.')
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                              itemCount: list.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (BuildContext c, int i) => MkLeadTile(lead: list[i], onTap: () => _open(MkLeadScreen(uid: '${list[i]['uid']}'))),
                            ),
            ),
          ]);
        },
      ),
    );
  }
}

/// v90 — «اضافه کردن از اکسل»: همان جادوی ورود اطلاعات، فقط برای مشتری‌های بازاریابی (اعتبارسنجی دوباره و تکراری‌ها روی سرور).
class MkImportScreen extends StatelessWidget {
  const MkImportScreen({super.key});
  @override
  Widget build(BuildContext context) => ImportScreen(
        fixedKind: kMkLeadImportKind,
        perms: const <String>['marketing.entry', 'marketing.manage'],
        hint: '۱. «دانلود قالب» را بزنید و هر مشتری را در یک ردیف بنویسید (ردیف نمونه را پاک کنید).\n'
            '۲. کشور: نام فارسی یا انگلیسی هر کشوری (مثل آرژانتین یا Argentina) یا کد دوحرفی (مثل AR). '
            'منبع آشنایی: هر متنی، مثل «Gulfood 2026» یا «نمایشگاه استانبول ۲۰۲۵»؛ دسته‌اش خودکار تعیین و متن اصلی در «جزئیات منبع» نگه داشته می‌شود. '
            'مرحله فقط لید جدید، ارتباط گرفته، مذاکره یا پیش‌فاکتور. پیگیری بعدی: مثل ۱۴۰۵/۰۹/۱۰. چند شماره تلفن را در یک خانه با «/» جدا کنید.\n'
            '۳. «مسئول» را خالی بگذارید تا مشتری به نام خودتان ثبت شود؛ سپردن به بازاریاب دیگر فقط با مدیر است (نام دقیقاً مثل فهرست کارمندان).\n'
            '۴. اگر یک مشتری در فایل دو بار آمده باشد، دو ردیف با هم ادغام می‌شوند. مشتری‌ای که از قبل در برنامه هست رد می‌شود، '
            'مگر گزینهٔ «رکوردهای تکراری به‌روزرسانی شوند» را روشن کنید؛ مرحله با اکسل عوض نمی‌شود.\n'
            '۵. ردیف‌های سالم ثبت می‌شوند؛ ردیف‌های خطادار را با «دانلود ردیف خطادار» بگیرید، اصلاح و دوباره وارد کنید.\n'
            '۶. مشتری‌های واردشده در «مشتری جدید»، قیف و امتیاز شمرده نمی‌شوند؛ پیگیری و فروش بعدی آن‌ها مثل بقیه امتیاز دارد.',
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(icon, size: 56, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
          ]),
        ),
      );
}

class MkLeadTile extends StatelessWidget {
  const MkLeadTile({super.key, required this.lead, this.onTap, this.compact = false});
  final Map<String, dynamic> lead;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final String stage = '${lead['stage'] ?? 'lead'}';
    final String nf = '${lead['next_followup_at'] ?? ''}';
    final String today = MkStore.ymd(DateTime.now());
    final bool overdue = nf.length >= 10 && nf.substring(0, 10).compareTo(today) < 0 && kMkOpenStages.contains(stage);
    final bool isToday = nf.length >= 10 && nf.substring(0, 10) == today;
    final List<String> sub = <String>[
      if ('${lead['contact'] ?? ''}'.isNotEmpty) '${lead['contact']}',
      '${mkFlag('${lead['country'] ?? ''}')} ${mkCountryName('${lead['country'] ?? ''}')}${'${lead['city'] ?? ''}'.isNotEmpty ? '، ${lead['city']}' : ''}',
      if (MkStore.I.isManager && '${lead['owner_name'] ?? ''}'.isNotEmpty) '👤 ${lead['owner_name']}',
    ];
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: overdue ? th.colorScheme.error.withValues(alpha: 0.6) : th.dividerColor)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 12),
          child: Row(children: <Widget>[
            CircleAvatar(
              radius: compact ? 16 : 20,
              backgroundColor: (kMkStageColors[stage] ?? Colors.grey).withValues(alpha: 0.15),
              child: Text(mkFlag('${lead['country'] ?? ''}'), style: TextStyle(fontSize: compact ? 15 : 18)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('${lead['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(sub.join('  ·  '), style: TextStyle(fontSize: 12, color: th.hintColor), maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis),
                if (nf.length >= 10 && kMkOpenStages.contains(stage))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: <Widget>[
                      Icon(Icons.alarm, size: 14, color: overdue ? th.colorScheme.error : (isToday ? Colors.orange.shade800 : th.hintColor)),
                      const SizedBox(width: 3),
                      Text(overdue ? 'پیگیری عقب‌افتاده: ${mkDate(nf)}' : (isToday ? 'پیگیری امروز' : 'پیگیری: ${mkDate(nf)}'),
                          style: TextStyle(fontSize: 11.5, color: overdue ? th.colorScheme.error : (isToday ? Colors.orange.shade800 : th.hintColor), fontWeight: overdue || isToday ? FontWeight.bold : null)),
                    ]),
                  ),
              ]),
            ),
            if (!compact) mkStageChip(stage),
          ]),
        ),
      ),
    );
  }
}

class _Kanban extends StatelessWidget {
  const _Kanban({required this.leads, required this.onOpen, required this.onRefresh});
  final List<Map<String, dynamic>> leads;
  final void Function(String uid) onOpen;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(10), children: <Widget>[
      for (final String st in kMkStages)
        DragTarget<String>(
          onWillAcceptWithDetails: (DragTargetDetails<String> d) => MkStore.I.canEntry,
          onAcceptWithDetails: (DragTargetDetails<String> d) async {
            final Map<String, dynamic>? l = await MkStore.I.lead(d.data);
            if (l == null || '${l['stage']}' == st || !context.mounted) return;
            String? reason;
            if (st == 'lost') {
              reason = await mkAskLostReason(context);
              if (reason == null) return;
            }
            if (st == 'won') {
              if (!context.mounted) return;
              await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MkSaleFormScreen(leadUid: d.data)));
              onRefresh();
              return;
            }
            await MkStore.I.changeStage(d.data, st, lostReason: reason);
            onRefresh();
          },
          builder: (BuildContext c, List<String?> cand, List<dynamic> rej) {
            final List<Map<String, dynamic>> col = leads.where((Map<String, dynamic> l) => '${l['stage'] ?? 'lead'}' == st).toList();
            final Color color = kMkStageColors[st] ?? Colors.grey;
            return Container(
              width: 270,
              margin: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                color: cand.isNotEmpty ? color.withValues(alpha: 0.10) : Theme.of(c).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cand.isNotEmpty ? color : Colors.transparent, width: 1.5),
              ),
              child: Column(children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
                  child: Row(children: <Widget>[
                    Icon(kMkStageIcons[st], color: color, size: 18),
                    const SizedBox(width: 6),
                    Text(kMkStageLabels[st]!, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                    const Spacer(),
                    Text(toFaDigits('${col.length}'), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                  ]),
                ),
                Expanded(
                  child: ListView(padding: const EdgeInsets.all(8), children: <Widget>[
                    for (final Map<String, dynamic> l in col)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: LongPressDraggable<String>(
                          data: '${l['uid']}',
                          feedback: Material(elevation: 6, borderRadius: BorderRadius.circular(12), child: SizedBox(width: 250, child: MkLeadTile(lead: l, compact: true))),
                          childWhenDragging: Opacity(opacity: 0.35, child: MkLeadTile(lead: l, compact: true)),
                          child: MkLeadTile(lead: l, compact: true, onTap: () => onOpen('${l['uid']}')),
                        ),
                      ),
                  ]),
                ),
              ]),
            );
          },
        ),
    ]);
  }
}

Future<String?> mkAskLostReason(BuildContext context) => showDialog<String>(
      context: context,
      builder: (BuildContext c) => SimpleDialog(
        title: const Text('چرا این مشتری از دست رفت؟'),
        children: <Widget>[for (final MapEntry<String, String> e in kMkLostLabels.entries) SimpleDialogOption(onPressed: () => Navigator.pop(c, e.key), child: Text(e.value))],
      ),
    );

// ============================================================ کارت مشتری
class MkLeadScreen extends StatefulWidget {
  const MkLeadScreen({super.key, required this.uid});
  final String uid;
  @override
  State<MkLeadScreen> createState() => _MkLeadScreenState();
}

class _MkLeadScreenState extends State<MkLeadScreen> {
  Map<String, dynamic>? _l;
  List<Map<String, dynamic>> _acts = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _sales = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Map<String, dynamic>? l = await MkStore.I.lead(widget.uid);
    final List<Map<String, dynamic>> a = await MkStore.I.activities(widget.uid);
    final List<Map<String, dynamic>> s = await MkStore.I.sales(leadUid: widget.uid);
    if (!mounted) return;
    setState(() {
      _l = l;
      _acts = a;
      _sales = s;
      _loading = false;
    });
  }

  Future<void> _go(Widget page) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    await _load();
  }

  Future<void> _stage(String st) async {
    if (st == 'won') return _go(MkSaleFormScreen(leadUid: widget.uid));
    String? reason;
    if (st == 'lost') {
      reason = await mkAskLostReason(context);
      if (reason == null) return;
    }
    try {
      await MkStore.I.changeStage(widget.uid, st, lostReason: reason);
    } catch (e) {
      if (mounted) snack(context, mkErr(e));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? l = _l;
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (l == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('این مشتری پیدا نشد')));
    final ThemeData th = Theme.of(context);
    final String stage = '${l['stage'] ?? 'lead'}';
    final bool canEdit = MkStore.I.canEntry;
    final double tons = _sales.where((Map<String, dynamic> s) => s['status'] == 'confirmed').fold<double>(0, (double a, Map<String, dynamic> s) => a + ((s['tons'] as num?) ?? 0).toDouble());
    return Scaffold(
      appBar: AppBar(
        title: Text('${l['name'] ?? ''}'),
        actions: <Widget>[
          if (MkStore.I.isManager)
            IconButton(tooltip: 'سپردن به بازاریاب دیگر', icon: const Icon(Icons.swap_horiz), onPressed: () => _go(MkAssignScreen(leadUid: widget.uid, current: l))),
          if (canEdit) IconButton(tooltip: 'ویرایش', icon: const Icon(Icons.edit_outlined), onPressed: () => _go(MkLeadFormScreen(uid: widget.uid))),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () async {
                await mkActivitySheet(context, widget.uid);
                await _load();
              },
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('پیگیری تازه'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 96), children: <Widget>[
          Card(
            elevation: 0,
            color: (kMkStageColors[stage] ?? Colors.grey).withValues(alpha: 0.07),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  Text(mkFlag('${l['country'] ?? ''}'), style: const TextStyle(fontSize: 30)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text('${l['name'] ?? ''}', style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      Text('${mkCountryName('${l['country'] ?? ''}')}${'${l['city'] ?? ''}'.isNotEmpty ? '، ${l['city']}' : ''}  ·  ${kMkSourceLabels['${l['source'] ?? 'other'}'] ?? ''}${'${l['source_detail'] ?? ''}'.isNotEmpty ? ' (${l['source_detail']})' : ''}',
                          style: TextStyle(color: th.hintColor)),
                    ]),
                  ),
                  mkStageChip(stage),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 18, runSpacing: 8, children: <Widget>[
                  if ('${l['contact'] ?? ''}'.isNotEmpty) _info(Icons.person_outline, '${l['contact']}'),
                  if ('${l['phone'] ?? ''}'.isNotEmpty) _info(Icons.phone_outlined, '${l['phone']}', ltr: true),
                  if ('${l['email'] ?? ''}'.isNotEmpty) _info(Icons.alternate_email, '${l['email']}', ltr: true),
                  if ('${l['products'] ?? ''}'.isNotEmpty) _info(Icons.inventory_2_outlined, '${l['products']}'),
                  if (l['est_tons'] != null) _info(Icons.scale_outlined, 'تخمین ${faNum((l['est_tons'] as num), dec: 1)} تن'),
                  if (tons > 0) _info(Icons.local_shipping_outlined, 'فروخته‌شده ${faNum(tons, dec: 1)} تن'),
                  if ('${l['owner_name'] ?? ''}'.isNotEmpty) _info(Icons.badge_outlined, 'مسئول: ${l['owner_name']}'),
                  if ('${l['next_followup_at'] ?? ''}'.isNotEmpty) _info(Icons.alarm, 'پیگیری بعدی: ${mkDateTime(l['next_followup_at'])}'),
                  if (stage == 'lost') _info(Icons.block, 'دلیل: ${kMkLostLabels['${l['lost_reason'] ?? 'other'}'] ?? ''}'),
                ]),
                if ('${l['note'] ?? ''}'.isNotEmpty) ...<Widget>[const SizedBox(height: 10), Text('${l['note']}')],
              ]),
            ),
          ),
          if (canEdit) ...<Widget>[
            const SizedBox(height: 8),
            Text('تغییر مرحله', style: th.textTheme.titleSmall),
            const SizedBox(height: 6),
            _StageStepper(stage: stage, onTap: _stage),
          ],
          const SizedBox(height: 14),
          Row(children: <Widget>[
            Text('فروش‌ها', style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (canEdit) TextButton.icon(onPressed: () => _go(MkSaleFormScreen(leadUid: widget.uid)), icon: const Icon(Icons.add), label: const Text('ثبت فروش')),
          ]),
          if (_sales.isEmpty) Text('هنوز فروشی ثبت نشده', style: TextStyle(color: th.hintColor)),
          for (final Map<String, dynamic> s in _sales) MkSaleTile(sale: s, onChanged: _load),
          const SizedBox(height: 14),
          Text('تاریخچهٔ پیگیری‌ها', style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (_acts.isEmpty) Text('هنوز پیگیری‌ای ثبت نشده', style: TextStyle(color: th.hintColor)),
          for (int i = 0; i < _acts.length; i++) _ActRow(a: _acts[i], last: i == _acts.length - 1),
        ]),
      ),
    );
  }

  Widget _info(IconData i, String t, {bool ltr = false}) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(i, size: 16, color: Theme.of(context).hintColor),
        const SizedBox(width: 4),
        Text(t, textDirection: ltr ? TextDirection.ltr : null),
      ]);
}

class _StageStepper extends StatelessWidget {
  const _StageStepper({required this.stage, required this.onTap});
  final String stage;
  final void Function(String) onTap;
  @override
  Widget build(BuildContext context) {
    final int cur = kMkStages.indexOf(stage);
    return Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
      for (int i = 0; i < kMkStages.length; i++)
        ActionChip(
          avatar: Icon(kMkStageIcons[kMkStages[i]], size: 16, color: i == cur ? Colors.white : kMkStageColors[kMkStages[i]]),
          label: Text(kMkStageLabels[kMkStages[i]]!, style: TextStyle(color: i == cur ? Colors.white : null, fontWeight: i == cur ? FontWeight.bold : null)),
          backgroundColor: i == cur ? kMkStageColors[kMkStages[i]] : null,
          onPressed: i == cur ? null : () => onTap(kMkStages[i]),
        ),
    ]);
  }
}

class _ActRow extends StatelessWidget {
  const _ActRow({required this.a, required this.last});
  final Map<String, dynamic> a;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final String kind = '${a['kind'] ?? 'note'}';
    final bool st = kind == 'stage';
    final Color c = st ? (kMkStageColors['${a['to_stage']}'] ?? th.colorScheme.primary) : th.colorScheme.primary;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        SizedBox(
          width: 34,
          child: Column(children: <Widget>[
            CircleAvatar(radius: 14, backgroundColor: c.withValues(alpha: 0.14), child: Icon(kMkKindIcons[kind] ?? Icons.circle, size: 15, color: c)),
            if (!last) Expanded(child: Container(width: 2, color: th.dividerColor)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(st ? '${kMkStageLabels['${a['from_stage']}'] ?? ''} ← ${kMkStageLabels['${a['to_stage']}'] ?? ''}' : (kMkKindLabels[kind] ?? kind),
                  style: TextStyle(fontWeight: FontWeight.bold, color: st ? c : null)),
              if ('${a['result'] ?? ''}'.isNotEmpty) Text('${a['result']}'),
              Text('${mkDateTime(a['at'])}${'${a['staff_name'] ?? ''}'.isNotEmpty ? '  ·  ${a['staff_name']}' : ''}', style: TextStyle(fontSize: 11.5, color: th.hintColor)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// پیگیری تازه (چند ثانیه): نوع، نتیجه، موعد بعدی.
Future<void> mkActivitySheet(BuildContext context, String leadUid) async {
  String kind = 'call';
  final TextEditingController res = TextEditingController();
  DateTime? next = DateTime.now().add(const Duration(days: 3));
  DateTime at = DateTime.now();
  bool busy = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext c) => StatefulBuilder(
      builder: (BuildContext c, StateSetter set) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text('پیگیری تازه', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
            for (final String k in kMkKindLabels.keys.where((String k) => k != 'stage'))
              ChoiceChip(avatar: Icon(kMkKindIcons[k], size: 16), label: Text(kMkKindLabels[k]!), selected: kind == k, onSelected: (_) => set(() => kind = k)),
          ]),
          const SizedBox(height: 10),
          TextField(controller: res, autofocus: true, maxLength: 500, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'نتیجه (اختیاری)', border: OutlineInputBorder())),
          Row(children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined),
                label: Text('زمان: ${jalaliDateFromDt(at)}'),
                onPressed: () async {
                  final DateTime? d = await pickDate(c, initial: at, firstDate: MkStore.I.isManager ? DateTime(2020) : DateTime.now().subtract(const Duration(days: 7)), lastDate: DateTime.now());
                  if (d != null) set(() => at = DateTime(d.year, d.month, d.day, DateTime.now().hour, DateTime.now().minute));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.alarm_add_outlined),
                label: Text(next == null ? 'بدون پیگیری بعدی' : 'بعدی: ${jalaliDateFromDt(next!)}'),
                onPressed: () async {
                  final DateTime? d = await pickDate(c, initial: next ?? DateTime.now().add(const Duration(days: 3)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)));
                  set(() => next = d == null ? null : DateTime(d.year, d.month, d.day, 10));
                },
              ),
            ),
          ]),
          Wrap(spacing: 6, children: <Widget>[
            for (final (String, int) q in const <(String, int)>[('فردا', 1), ('۳ روز', 3), ('یک هفته', 7), ('دو هفته', 14)])
              ActionChip(label: Text(q.$1), onPressed: () => set(() => next = DateTime.now().add(Duration(days: q.$2)))),
            ActionChip(label: const Text('بدون'), onPressed: () => set(() => next = null)),
          ]),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    set(() => busy = true);
                    try {
                      await MkStore.I.addActivity(leadUid, kind: kind, result: res.text.trim(), at: at, next: next, clearNext: next == null);
                      if (c.mounted) Navigator.pop(c);
                    } catch (e) {
                      set(() => busy = false);
                      if (c.mounted) snack(c, mkErr(e));
                    }
                  },
            icon: const Icon(Icons.check),
            label: const Text('ثبت پیگیری'),
          ),
        ]),
      ),
    ),
  );
  res.dispose();
}

// ============================================================ فرم مشتری
class MkLeadFormScreen extends StatefulWidget {
  const MkLeadFormScreen({super.key, this.uid});
  final String? uid;
  @override
  State<MkLeadFormScreen> createState() => _MkLeadFormScreenState();
}

class _MkLeadFormScreenState extends State<MkLeadFormScreen> {
  final Map<String, TextEditingController> _c = <String, TextEditingController>{
    for (final String k in <String>['name', 'contact', 'city', 'phone', 'email', 'products', 'est_tons', 'note', 'source_detail']) k: TextEditingController(),
  };
  String? _country;
  String _source = 'other';
  String _stage = 'lead';
  final Set<String> _prods = <String>{};
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.uid != null) {
      final Map<String, dynamic>? l = await MkStore.I.lead(widget.uid!);
      if (l != null) {
        for (final String k in _c.keys) {
          final Object? v = l[k];
          _c[k]!.text = v == null ? '' : (v is num ? plain(v) : '$v');
        }
        _country = '${l['country'] ?? ''}'.isEmpty ? null : '${l['country']}'.toUpperCase();
        _source = '${l['source'] ?? 'other'}';
        _stage = '${l['stage'] ?? 'lead'}';
        for (final String p in '${l['products'] ?? ''}'.split('،')) {
          if (kMkProducts.contains(p.trim())) _prods.add(p.trim());
        }
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final TextEditingController c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_c['name']!.text.trim().isEmpty) return snack(context, 'نام شرکت یا مشتری را وارد کنید');
    setState(() => _busy = true);
    final List<String> prods = <String>[..._prods, ..._c['products']!.text.split('،').map((String s) => s.trim()).where((String s) => s.isNotEmpty && !kMkProducts.contains(s))];
    try {
      await MkStore.I.saveLead(<String, dynamic>{
        'name': _c['name']!.text,
        'contact': _c['contact']!.text,
        'country': _country,
        'city': _c['city']!.text,
        'phone': _c['phone']!.text,
        'email': _c['email']!.text,
        'source': _source,
        'source_detail': _c['source_detail']!.text,
        'products': prods.join('، '),
        'est_tons': double.tryParse(toEnDigits(_c['est_tons']!.text.trim())),
        'note': _c['note']!.text,
        if (widget.uid == null) 'stage': _stage,
      }, uid: widget.uid);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, mkErr(e));
      }
    }
  }

  InputDecoration _d(String l, IconData i) => InputDecoration(labelText: l, prefixIcon: Icon(i), border: const OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(widget.uid == null ? 'مشتری تازه' : 'ویرایش مشتری')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            TextField(controller: _c['name'], maxLength: 150, decoration: _d('نام شرکت / مشتری *', Icons.apartment_outlined)),
            TextField(controller: _c['contact'], maxLength: 120, decoration: _d('شخص رابط', Icons.person_outline)),
            Row(children: <Widget>[
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: _country,
                  isExpanded: true,
                  decoration: _d('کشور', Icons.public),
                  items: <DropdownMenuItem<String>>[
                    for (final MapEntry<String, String> e in kMkCountryChoices) DropdownMenuItem<String>(value: e.key, child: Text('${mkFlag(e.key)}  ${e.value}')),
                    if (_country != null && !kMkCountryChoices.any((MapEntry<String, String> e) => e.key == _country))
                      DropdownMenuItem<String>(value: _country, child: Text('${mkFlag(_country)}  $_country')),
                  ],
                  onChanged: (String? v) => setState(() => _country = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(controller: _c['city'], maxLength: 80, decoration: _d('شهر', Icons.location_city_outlined))),
            ]),
            Row(children: <Widget>[
              Expanded(child: TextField(controller: _c['phone'], maxLength: 200, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr, decoration: _d('تلفن / واتساپ', Icons.phone_outlined))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _c['email'], maxLength: 120, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, decoration: _d('ایمیل', Icons.alternate_email))),
            ]),
            DropdownButtonFormField<String>(
              initialValue: _source,
              decoration: _d('منبع آشنایی', Icons.campaign_outlined),
              items: <DropdownMenuItem<String>>[for (final MapEntry<String, String> e in kMkSourceLabels.entries) DropdownMenuItem<String>(value: e.key, child: Text(e.value))],
              onChanged: (String? v) => setState(() => _source = v ?? 'other'),
            ),
            const SizedBox(height: 8),
            TextField(controller: _c['source_detail'], maxLength: 150, decoration: _d('جزئیات منبع (مثلاً Gulfood 2026)', Icons.event_note_outlined)),
            const SizedBox(height: 12),
            Text('محصول مورد علاقه', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
              for (final String p in kMkProducts)
                FilterChip(label: Text(p), selected: _prods.contains(p), onSelected: (bool v) => setState(() => v ? _prods.add(p) : _prods.remove(p))),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _c['products'], maxLength: 200, decoration: _d('محصول دیگر (با «،» جدا کنید)', Icons.inventory_2_outlined)),
            TextField(
                controller: _c['est_tons'],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _d('حجم تخمینی خرید (تن)', Icons.scale_outlined)),
            if (widget.uid == null) ...<Widget>[
              const SizedBox(height: 12),
              Text('مرحلهٔ فعلی', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                for (final String s in kMkOpenStages) ChoiceChip(label: Text(kMkStageLabels[s]!), selected: _stage == s, onSelected: (_) => setState(() => _stage = s)),
              ]),
            ],
            const SizedBox(height: 12),
            TextField(controller: _c['note'], maxLength: 3000, minLines: 2, maxLines: 5, decoration: _d('یادداشت', Icons.sticky_note_2_outlined)),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_busy ? 'در حال ذخیره…' : 'ذخیره')),
          ]),
        ),
      ),
    );
  }
}

// ============================================================ فروش
class MkSaleTile extends StatelessWidget {
  const MkSaleTile({super.key, required this.sale, required this.onChanged, this.showLead});
  final Map<String, dynamic> sale;
  final VoidCallback onChanged;
  final String? showLead;

  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final String st = '${sale['status'] ?? 'pending'}';
    final (Color, String, IconData) badge = switch (st) {
      'confirmed' => (Colors.green.shade700, 'تأییدشده', Icons.verified_outlined),
      'rejected' => (th.colorScheme.error, 'ردشده', Icons.cancel_outlined),
      _ => (Colors.orange.shade800, 'منتظر تأیید مدیر', Icons.hourglass_top),
    };
    final bool canEdit = MkStore.I.isManager || (MkStore.I.canEntry && st != 'confirmed');
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: th.dividerColor)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: badge.$1.withValues(alpha: 0.12), child: Icon(badge.$3, color: badge.$1)),
        title: Text('${showLead != null ? '$showLead — ' : ''}${faNum(((sale['tons'] as num?) ?? 0), dec: 2)} تن${'${sale['product'] ?? ''}'.isNotEmpty ? ' ${sale['product']}' : ''}'),
        subtitle: Text(<String>[
          mkDate(sale['date']),
          if (((sale['deal_value'] as num?) ?? 0) > 0) faCcy('${sale['ccy'] ?? 'USD'}', (sale['deal_value'] as num), dec: 0),
          sale['collected'] == true ? 'وصول شد ${mkDate(sale['collected_at'])}' : 'وصول نشده',
          if ('${sale['staff_name'] ?? ''}'.isNotEmpty) '${sale['staff_name']}',
        ].join('  ·  ')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(badge.$2, style: TextStyle(color: badge.$1, fontSize: 12, fontWeight: FontWeight.bold)),
          if (MkStore.I.isManager && st != 'confirmed')
            IconButton(
                tooltip: 'تأیید',
                icon: Icon(Icons.check_circle, color: Colors.green.shade700),
                onPressed: () async {
                  await MkStore.I.setSaleStatus('${sale['uid']}', 'confirmed');
                  onChanged();
                }),
          if (MkStore.I.isManager && st == 'pending')
            IconButton(
                tooltip: 'رد',
                icon: Icon(Icons.cancel, color: th.colorScheme.error),
                onPressed: () async {
                  if (!await confirm(context, 'این فروش رد شود؟ (در امتیاز و گزارش شمرده نمی‌شود)')) return;
                  await MkStore.I.setSaleStatus('${sale['uid']}', 'rejected');
                  onChanged();
                }),
        ]),
        onTap: canEdit
            ? () async {
                await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MkSaleFormScreen(leadUid: '${sale['lead_uid']}', sale: sale)));
                onChanged();
              }
            : null,
      ),
    );
  }
}

class MkSaleFormScreen extends StatefulWidget {
  const MkSaleFormScreen({super.key, required this.leadUid, this.sale});
  final String leadUid;
  final Map<String, dynamic>? sale;
  @override
  State<MkSaleFormScreen> createState() => _MkSaleFormScreenState();
}

class _MkSaleFormScreenState extends State<MkSaleFormScreen> {
  late final TextEditingController _tons = TextEditingController(text: widget.sale?['tons'] == null ? '' : plain(widget.sale!['tons'] as num));
  late final TextEditingController _value = TextEditingController(text: widget.sale?['deal_value'] == null ? '' : plain(widget.sale!['deal_value'] as num));
  late final TextEditingController _note = TextEditingController(text: '${widget.sale?['note'] ?? ''}');
  late String _ccy = '${widget.sale?['ccy'] ?? 'USD'}';
  late String? _product = widget.sale?['product'] as String?;
  late DateTime _date = DateTime.tryParse('${widget.sale?['date'] ?? ''}') ?? DateTime.now();
  late bool _collected = widget.sale?['collected'] == true;
  late DateTime _colAt = DateTime.tryParse('${widget.sale?['collected_at'] ?? ''}') ?? DateTime.now();
  late final String _uid = (widget.sale?['uid'] as String?) ?? EntityStore.newUid(); // v90: ذخیرهٔ دوباره ⇒ همان فروش
  bool _busy = false;

  @override
  void dispose() {
    _tons.dispose();
    _value.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final double? t = double.tryParse(toEnDigits(_tons.text.trim()));
    if (t == null || t <= 0) return snack(context, 'تناژ فروش را وارد کنید');
    setState(() => _busy = true);
    try {
      await MkStore.I.saveSale(widget.leadUid, <String, dynamic>{
        'date': MkStore.ymd(_date),
        'tons': t,
        'deal_value': double.tryParse(toEnDigits(_value.text.trim().replaceAll(',', ''))),
        'ccy': _ccy,
        'product': _product,
        'collected': _collected,
        'collected_at': _collected ? MkStore.ymd(_colAt) : null,
        'note': _note.text,
      }, uid: _uid);
      if (!mounted) return;
      if (!MkStore.I.isManager) snack(context, 'فروش ثبت شد؛ پس از تأیید مدیر بازاریابی در امتیاز شمرده می‌شود');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, mkErr(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool mgr = MkStore.I.isManager;
    return Scaffold(
      appBar: AppBar(title: Text(widget.sale == null ? 'ثبت فروش' : 'ویرایش فروش')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            if (!mgr)
              Card(
                color: Colors.orange.withValues(alpha: 0.1),
                elevation: 0,
                child: const Padding(padding: EdgeInsets.all(12), child: Text('فروش و وصول پس از تأیید مدیر بازاریابی در امتیاز و گزارش‌ها شمرده می‌شود.')),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_outlined),
              label: Text('تاریخ فروش: ${jalaliDateFromDt(_date)}'),
              onPressed: () async {
                final DateTime? d = await pickDate(context, initial: _date, firstDate: mgr ? DateTime(2020) : DateTime.now().subtract(const Duration(days: 7)), lastDate: DateTime.now());
                if (d != null) setState(() => _date = d);
              },
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _tons,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'تناژ (تن) *', prefixIcon: Icon(Icons.scale_outlined), border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(children: <Widget>[
              Expanded(
                flex: 3,
                child: TextField(
                    controller: _value,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'مبلغ قرارداد', prefixIcon: Icon(Icons.payments_outlined), border: OutlineInputBorder())),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: kMkCurrencies.contains(_ccy) ? _ccy : 'USD',
                  decoration: const InputDecoration(labelText: 'ارز', border: OutlineInputBorder()),
                  items: <DropdownMenuItem<String>>[for (final String c in kMkCurrencies) DropdownMenuItem<String>(value: c, child: Text(c))],
                  onChanged: (String? v) => setState(() => _ccy = v ?? 'USD'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
              for (final String p in kMkProducts) ChoiceChip(label: Text(p), selected: _product == p, onSelected: (bool v) => setState(() => _product = v ? p : null)),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('مبلغ وصول شد'),
              value: _collected,
              onChanged: (bool v) => setState(() => _collected = v),
            ),
            if (_collected)
              OutlinedButton.icon(
                icon: const Icon(Icons.event_available_outlined),
                label: Text('تاریخ وصول: ${jalaliDateFromDt(_colAt)}'),
                onPressed: () async {
                  final DateTime? d = await pickDate(context, initial: _colAt, lastDate: DateTime.now());
                  if (d != null) setState(() => _colAt = d);
                },
              ),
            const SizedBox(height: 12),
            TextField(controller: _note, maxLength: 500, decoration: const InputDecoration(labelText: 'یادداشت', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_busy ? 'در حال ذخیره…' : 'ذخیره')),
          ]),
        ),
      ),
    );
  }
}

// ============================================================ امروز من (بازاریاب)
class MkMyDayView extends StatefulWidget {
  const MkMyDayView({super.key});
  @override
  State<MkMyDayView> createState() => _MkMyDayViewState();
}

class _MkMyDayViewState extends State<MkMyDayView> {
  Map<String, dynamic>? _srv; // گزارش ماه خود از سرور (هدف و رتبه)

  @override
  void initState() {
    super.initState();
    AppDb.I.version.addListener(_refresh);
    _loadServer();
  }

  @override
  void dispose() {
    AppDb.I.version.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadServer() async {
    final DateTime now = DateTime.now();
    final List<int> j = gregorianToJalali(now.year, now.month, now.day);
    try {
      final Map<String, dynamic> r = await MkStore.I.report(jalaliToGregorian(j[0], j[1], 1), now);
      if (mounted) setState(() => _srv = r);
    } catch (_) {/* آفلاین: فقط شمارش‌های محلی */}
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    return FutureBuilder<({MkCounts counts, MkScore score, int overdue, int today, int open})>(
      future: MkStore.I.myMonth(),
      builder: (BuildContext c, AsyncSnapshot<({MkCounts counts, MkScore score, int overdue, int today, int open})> snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final ({MkCounts counts, MkScore score, int overdue, int today, int open}) m = snap.data!;
        final Map<String, dynamic>? tgt = (_srv?['board'] is List && (_srv!['board'] as List).isNotEmpty) ? ((_srv!['board'] as List).first as Map)['target'] as Map<String, dynamic>? : null;
        final int? rank = (_srv?['rank'] as num?)?.toInt();
        final int team = ((_srv?['team_size'] as num?) ?? 0).toInt();
        double t(String k, double d) => ((tgt?[k] as num?) ?? d).toDouble();
        return RefreshIndicator(
          onRefresh: _loadServer,
          child: ListView(padding: const EdgeInsets.all(14), children: <Widget>[
            Card(
              elevation: 0,
              color: th.colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: <Widget>[
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text('سلام ${MkStore.I.myName} 👋', style: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                          m.overdue + m.today == 0
                              ? 'امروز پیگیری موعدرسیده‌ای ندارید.'
                              : '${toFaDigits('${m.today}')} پیگیری امروز${m.overdue > 0 ? ' و ${toFaDigits('${m.overdue}')} پیگیری عقب‌افتاده' : ''} دارید.',
                          style: TextStyle(color: th.colorScheme.onPrimaryContainer)),
                      if (rank != null && team > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('🏆 رتبهٔ شما این ماه: ${toFaDigits('$rank')} از ${toFaDigits('$team')}')),
                    ]),
                  ),
                  Column(children: <Widget>[
                    Text(faNum(m.score.finalScore, dec: 0), style: th.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: th.colorScheme.primary)),
                    const Text('امتیاز ماه'),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (BuildContext c, BoxConstraints bc) {
              final int cols = bc.maxWidth > 900 ? 6 : (bc.maxWidth > 560 ? 3 : 2);
              final List<Widget> cards = <Widget>[
                MkProgressCard(label: 'پیگیری', value: m.counts.followUps, target: t('follow_ups', 100), icon: Icons.call_outlined, color: const Color(0xFF0EA5E9)),
                MkProgressCard(label: 'مشتری جدید', value: m.counts.newLeads, target: t('new_leads', 50), icon: Icons.person_add_alt_1_outlined, color: const Color(0xFF64748B)),
                MkProgressCard(label: 'مذاکره', value: m.counts.negotiations, target: t('negotiations', 0), icon: Icons.handshake_outlined, color: const Color(0xFF8B5CF6)),
                MkProgressCard(label: 'پیش‌فاکتور', value: m.counts.proformas, target: t('proformas', 1), icon: Icons.request_quote_outlined, color: const Color(0xFFF59E0B)),
                MkProgressCard(label: 'فروش', value: m.counts.sales, target: t('sales', 15), icon: Icons.emoji_events_outlined, color: const Color(0xFF16A34A)),
                MkProgressCard(label: 'تناژ', value: m.counts.tons, target: t('tons', 25), icon: Icons.local_shipping_outlined, color: const Color(0xFF0F766E), unit: 'تن'),
              ];
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.45,
                children: cards,
              );
            }),
            const SizedBox(height: 14),
            Text('پیگیری‌های امروز و عقب‌افتاده', style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: MkStore.I.leads(),
              builder: (BuildContext c, AsyncSnapshot<List<Map<String, dynamic>>> s) {
                final String today = MkStore.ymd(DateTime.now());
                final List<Map<String, dynamic>> due = (s.data ?? const <Map<String, dynamic>>[]).where((Map<String, dynamic> l) {
                  final String nf = '${l['next_followup_at'] ?? ''}';
                  return kMkOpenStages.contains(l['stage']) && nf.length >= 10 && nf.substring(0, 10).compareTo(today) <= 0;
                }).toList()
                  ..sort((Map<String, dynamic> a, Map<String, dynamic> b) => '${a['next_followup_at']}'.compareTo('${b['next_followup_at']}'));
                if (due.isEmpty) return const _Empty(icon: Icons.task_alt, text: 'همهٔ پیگیری‌ها انجام شده است 👌');
                return Column(children: <Widget>[
                  for (final Map<String, dynamic> l in due)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: MkLeadTile(
                        lead: l,
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MkLeadScreen(uid: '${l['uid']}')));
                          _refresh();
                        },
                      ),
                    ),
                ]);
              },
            ),
          ]),
        );
      },
    );
  }
}

class MkProgressCard extends StatelessWidget {
  const MkProgressCard({super.key, required this.label, required this.value, required this.target, required this.icon, required this.color, this.unit = '', this.previous});
  final String label;
  final double value;
  final double target;
  final IconData icon;
  final Color color;
  final String unit;
  final double? previous;

  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final double p = target > 0 ? (value / target).clamp(0, 1).toDouble() : 0;
    final double? delta = (previous != null && previous! > 0) ? (value - previous!) / previous! * 100 : null;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: color.withValues(alpha: 0.25))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: TextStyle(color: th.hintColor), overflow: TextOverflow.ellipsis)),
            if (delta != null)
              Text('${delta >= 0 ? '▲' : '▼'} ${faNum(delta.abs(), dec: 0)}٪',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: delta >= 0 ? Colors.green.shade700 : th.colorScheme.error)),
          ]),
          const Spacer(),
          Text('${faNum(value, dec: unit.isEmpty ? 0 : 1)}${unit.isEmpty ? '' : ' $unit'}', style: th.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (target > 0) ...<Widget>[
            ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: p, minHeight: 7, color: color, backgroundColor: color.withValues(alpha: 0.12))),
            const SizedBox(height: 3),
            Text('${faNum(p * 100, dec: 0)}٪ از هدف ${faNum(target, dec: unit.isEmpty ? 0 : 1)}', style: TextStyle(fontSize: 11, color: th.hintColor)),
          ] else
            Text('بدون هدف', style: TextStyle(fontSize: 11, color: th.hintColor)),
        ]),
      ),
    );
  }
}

// ============================================================ مدیریت (مدیر بازاریابی)
class MkAdminView extends StatelessWidget {
  const MkAdminView({super.key});
  @override
  Widget build(BuildContext context) {
    Widget tile(IconData i, String t, String s, Widget page) => Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Theme.of(context).dividerColor)),
          child: ListTile(
            leading: Icon(i, color: Theme.of(context).colorScheme.primary),
            title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(s),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page)),
          ),
        );
    return ListView(padding: const EdgeInsets.all(14), children: <Widget>[
      tile(Icons.fact_check_outlined, 'فروش‌های منتظر تأیید', 'تأیید یا رد فروش و وصولی که بازاریاب‌ها ثبت کرده‌اند', const MkPendingSalesScreen()),
      tile(Icons.flag_outlined, 'هدف ماهانهٔ بازاریاب‌ها', 'پیگیری، مشتری جدید، مذاکره، پیش‌فاکتور، فروش و تناژ هر نفر در هر ماه', const MkTargetsScreen()),
      tile(Icons.calculate_outlined, 'امتیازدهی و تنظیمات', 'وزن امتیازها، فرمول امتیاز نهایی، روزهای بی‌حرکتی و احتمال هر مرحله', const MkSettingsScreen()),
      const SizedBox(height: 8),
      Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('دسترسی بازاریاب‌ها از «کارمندان، نقش‌ها و دسترسی‌ها» داده می‌شود: نقش آمادهٔ «بازاریاب» یا «مدیر بازاریابی»، یا بخش «بازاریابی بین‌المللی» در هر نقش.'),
        ),
      ),
    ]);
  }
}

class MkPendingSalesScreen extends StatefulWidget {
  const MkPendingSalesScreen({super.key});
  @override
  State<MkPendingSalesScreen> createState() => _MkPendingSalesScreenState();
}

class _MkPendingSalesScreenState extends State<MkPendingSalesScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فروش‌های منتظر تأیید')),
      body: FutureBuilder<(List<Map<String, dynamic>>, Map<String, String>)>(
        future: () async {
          final List<Map<String, dynamic>> s = await MkStore.I.sales(status: 'pending');
          final Map<String, String> names = <String, String>{for (final Map<String, dynamic> l in await MkStore.I.leads()) '${l['uid']}': '${l['name']}'};
          return (s, names);
        }(),
        builder: (BuildContext c, AsyncSnapshot<(List<Map<String, dynamic>>, Map<String, String>)> snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final List<Map<String, dynamic>> list = snap.data!.$1;
          if (list.isEmpty) return const _Empty(icon: Icons.task_alt, text: 'فروش منتظر تأییدی نیست');
          return ListView(padding: const EdgeInsets.all(12), children: <Widget>[
            for (final Map<String, dynamic> s in list) MkSaleTile(sale: s, showLead: snap.data!.$2['${s['lead_uid']}'] ?? '', onChanged: () => setState(() {})),
          ]);
        },
      ),
    );
  }
}

/// فهرست بازاریاب‌ها (از گزارش سرور؛ مدیر/گزارش).
Future<List<(int, String)>> mkStaffList() async {
  try {
    final DateTime now = DateTime.now();
    final Map<String, dynamic> r = await MkStore.I.report(now, now);
    return <(int, String)>[
      for (final dynamic x in (r['staff'] as List<dynamic>? ?? const <dynamic>[]))
        if (x is Map) (((x['id'] as num?) ?? 0).toInt(), '${x['name'] ?? ''}'),
    ];
  } catch (_) {
    return const <(int, String)>[];
  }
}

class MkTargetsScreen extends StatefulWidget {
  const MkTargetsScreen({super.key});
  @override
  State<MkTargetsScreen> createState() => _MkTargetsScreenState();
}

class _MkTargetsScreenState extends State<MkTargetsScreen> {
  late int _jy, _jm;
  List<(int, String)> _staff = <(int, String)>[];
  List<Map<String, dynamic>> _targets = <Map<String, dynamic>>[];
  Map<String, dynamic> _set = <String, dynamic>{};
  bool _loading = true;
  static const List<(String, String)> _cols = <(String, String)>[
    ('follow_ups', 'پیگیری'), ('new_leads', 'مشتری جدید'), ('negotiations', 'مذاکره'), ('proformas', 'پیش‌فاکتور'), ('sales', 'فروش'), ('tons', 'تناژ'),
  ];

  @override
  void initState() {
    super.initState();
    final DateTime n = DateTime.now();
    final List<int> j = gregorianToJalali(n.year, n.month, n.day);
    _jy = j[0];
    _jm = j[1];
    _load();
  }

  String get _month => '$_jy-${_jm.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final List<(int, String)> st = await mkStaffList();
    final List<Map<String, dynamic>> t = await MkStore.I.targets();
    final Map<String, dynamic> s = await MkStore.I.settings();
    if (!mounted) return;
    setState(() {
      _staff = st;
      _targets = t;
      _set = s;
      _loading = false;
    });
  }

  double _val(int sid, String k) {
    for (final Map<String, dynamic> t in _targets) {
      if ('${t['month']}' == _month && ((t['staff_id'] as num?) ?? -1).toInt() == sid && t[k] != null) return (t[k] as num).toDouble();
    }
    final Object? d = _set['t_$k'];
    return d is num ? d.toDouble() : const <String, double>{'follow_ups': 100, 'new_leads': 50, 'negotiations': 0, 'proformas': 1, 'sales': 15, 'tons': 25}[k]!;
  }

  Future<void> _edit(int sid, String name) async {
    final Map<String, TextEditingController> c = <String, TextEditingController>{for (final (String, String) col in _cols) col.$1: TextEditingController(text: plain(_val(sid, col.$1)))};
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        title: Text('هدف $name — ${toFaDigits(_month)}'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              for (final (String, String) col in _cols)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                      controller: c[col.$1],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: col.$2, border: const OutlineInputBorder(), isDense: true)),
                ),
            ]),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('ذخیره')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await MkStore.I.saveTarget(sid, _month, <String, dynamic>{for (final (String, String) col in _cols) col.$1: double.tryParse(toEnDigits(c[col.$1]!.text.trim())) ?? 0});
        await _load();
      } catch (e) {
        if (mounted) snack(context, mkErr(e));
      }
    }
    for (final TextEditingController x in c.values) {
      x.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('هدف ماهانهٔ بازاریاب‌ها')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: <Widget>[
              Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() {
                          if (--_jm < 1) {
                            _jm = 12;
                            _jy--;
                          }
                        })),
                Text('${kJalaliMonths[_jm - 1]} ${toFaDigits('$_jy')}', style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() {
                          if (++_jm > 12) {
                            _jm = 1;
                            _jy++;
                          }
                        })),
              ]),
              if (_staff.isEmpty) const _Empty(icon: Icons.group_off_outlined, text: 'برای دیدن فهرست بازاریاب‌ها به اینترنت وصل شوید.'),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: <DataColumn>[const DataColumn(label: Text('بازاریاب')), for (final (String, String) col in _cols) DataColumn(label: Text(col.$2), numeric: true), const DataColumn(label: Text(''))],
                  rows: <DataRow>[
                    for (final (int, String) s in _staff)
                      DataRow(cells: <DataCell>[
                        DataCell(Text(s.$2)),
                        for (final (String, String) col in _cols) DataCell(Text(faNum(_val(s.$1, col.$1), dec: col.$1 == 'tons' ? 1 : 0))),
                        DataCell(IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(s.$1, s.$2))),
                      ]),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('ماهی که هدف ندارد، هدف پیش‌فرض «امتیازدهی و تنظیمات» را می‌گیرد. هدف هفته/فصل/سال به نسبت روزها از هدف ماه حساب می‌شود.',
                  style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
            ]),
    );
  }
}

const List<String> kJalaliMonths = <String>['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];

class MkSettingsScreen extends StatefulWidget {
  const MkSettingsScreen({super.key});
  @override
  State<MkSettingsScreen> createState() => _MkSettingsScreenState();
}

class _MkSettingsScreenState extends State<MkSettingsScreen> {
  static const List<(String, String, double)> _groups = <(String, String, double)>[
    ('w_lead', 'امتیاز هر مشتری جدید', 5), ('w_negotiation', 'امتیاز هر مذاکره', 15), ('w_proforma', 'امتیاز هر پیش‌فاکتور', 30), ('w_sale', 'امتیاز هر فروش', 70),
    ('w_ton', 'امتیاز هر تن', 7), ('w_collection', 'امتیاز هر وصول', 100), ('no_sale_factor', 'ضریب امتیاز نهایی وقتی فروشی نیست', 0.4),
    ('per_sale_deduct', 'کسر از مجموع به‌ازای هر فروش', 50), ('stale_days', 'مشتری بی‌حرکت پس از (روز)', 14),
    ('p_lead', 'احتمال فروش: لید جدید (٪)', 5), ('p_contacted', 'احتمال فروش: ارتباط گرفته (٪)', 10), ('p_negotiation', 'احتمال فروش: مذاکره (٪)', 30), ('p_proforma', 'احتمال فروش: پیش‌فاکتور (٪)', 60),
    ('t_follow_ups', 'هدف پیش‌فرض ماهانه: پیگیری', 100), ('t_new_leads', 'هدف پیش‌فرض: مشتری جدید', 50), ('t_negotiations', 'هدف پیش‌فرض: مذاکره', 0),
    ('t_proformas', 'هدف پیش‌فرض: پیش‌فاکتور', 1), ('t_sales', 'هدف پیش‌فرض: فروش', 15), ('t_tons', 'هدف پیش‌فرض: تناژ', 25),
  ];
  final Map<String, TextEditingController> _c = <String, TextEditingController>{};
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    MkStore.I.settings().then((Map<String, dynamic> s) {
      for (final (String, String, double) g in _groups) {
        final Object? v = s[g.$1];
        _c[g.$1] = TextEditingController(text: plain(v is num ? v : g.$3));
      }
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    for (final TextEditingController c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await MkStore.I.saveSettings(<String, dynamic>{for (final (String, String, double) g in _groups) g.$1: double.tryParse(toEnDigits(_c[g.$1]!.text.trim())) ?? g.$3});
      if (mounted) {
        snack(context, 'تنظیمات ذخیره شد');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        snack(context, mkErr(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('امتیازدهی و تنظیمات')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('امتیاز نهایی: اگر فروشی نباشد = مجموع × ضریب؛ وگرنه = مجموع − (کسر × تعداد فروش). پیش‌فرض‌ها همان شیت ارزیابی فعلی‌اند.'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final (String, String, double) g in _groups)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                          controller: _c[g.$1],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: g.$2, helperText: 'پیش‌فرض: ${faNum(g.$3, dec: 2)}', border: const OutlineInputBorder(), isDense: true)),
                    ),
                  FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined), label: const Text('ذخیره')),
                ]),
              ),
            ),
    );
  }
}

class MkAssignScreen extends StatefulWidget {
  const MkAssignScreen({super.key, required this.leadUid, required this.current});
  final String leadUid;
  final Map<String, dynamic> current;
  @override
  State<MkAssignScreen> createState() => _MkAssignScreenState();
}

class _MkAssignScreenState extends State<MkAssignScreen> {
  List<(int, String)>? _staff;

  @override
  void initState() {
    super.initState();
    mkStaffList().then((List<(int, String)> s) {
      if (mounted) setState(() => _staff = <(int, String)>[(0, 'مالک'), ...s]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final int cur = ((widget.current['owner_staff_id'] as num?) ?? -1).toInt();
    return Scaffold(
      appBar: AppBar(title: Text('سپردن «${widget.current['name']}»')),
      body: _staff == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: <Widget>[
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text('امتیاز کارهای گذشته با همان کسی می‌ماند که انجامشان داده؛ از این به بعد کارت مال مسئول تازه است و بازاریاب قبلی دیگر آن را نمی‌بیند.'),
              ),
              for (final (int, String) s in _staff!)
                ListTile(
                  leading: Icon(s.$1 == cur ? Icons.radio_button_checked : Icons.radio_button_off),
                  title: Text(s.$2),
                  onTap: s.$1 == cur
                      ? null
                      : () async {
                          await MkStore.I.assign(widget.leadUid, s.$1, s.$2);
                          if (context.mounted) Navigator.pop(context);
                        },
                ),
            ]),
    );
  }
}
