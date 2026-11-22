// v90 — بازاریابی بین‌المللی: داشبورد گزارش مدیر و مالک (نمودارهای تعاملی fl_chart؛ داده از marketing.report سرور).
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'excel_io.dart';
import 'marketing_calc.dart';
import 'marketing_store.dart';
import 'marketing_ui.dart';
import 'utils.dart';
import 'widgets.dart' show pickDate, snack;

enum _Period { month, prevMonth, quarter, year, last30, custom }

const Map<_Period, String> _periodLabels = <_Period, String>{
  _Period.month: 'این ماه',
  _Period.prevMonth: 'ماه قبل',
  _Period.quarter: 'این فصل',
  _Period.year: 'امسال',
  _Period.last30: '۳۰ روز اخیر',
  _Period.custom: 'بازهٔ دلخواه',
};

class MarketingDashboard extends StatefulWidget {
  const MarketingDashboard({super.key, this.debugReport});

  /// فقط برای تست: گزارش آماده (بدون تماس با سرور)
  final Map<String, dynamic>? debugReport;
  @override
  State<MarketingDashboard> createState() => _MarketingDashboardState();
}

class _MarketingDashboardState extends State<MarketingDashboard> {
  _Period _p = _Period.month;
  DateTimeRange? _custom;
  int _staff = -1;
  String? _country;
  String? _source;
  Map<String, dynamic>? _r;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.debugReport != null) {
      _r = widget.debugReport;
      _loading = false;
      return;
    }
    _load();
  }

  DateTimeRange _range() {
    final DateTime n = DateTime.now();
    final DateTime today = DateTime(n.year, n.month, n.day);
    final List<int> j = gregorianToJalali(n.year, n.month, n.day);
    switch (_p) {
      case _Period.month:
        return DateTimeRange(start: jalaliToGregorian(j[0], j[1], 1), end: today);
      case _Period.prevMonth:
        final int py = j[1] == 1 ? j[0] - 1 : j[0], pm = j[1] == 1 ? 12 : j[1] - 1;
        return DateTimeRange(start: jalaliToGregorian(py, pm, 1), end: jalaliToGregorian(py, pm, daysInJalaliMonth(py, pm)));
      case _Period.quarter:
        final int qm = ((j[1] - 1) ~/ 3) * 3 + 1;
        return DateTimeRange(start: jalaliToGregorian(j[0], qm, 1), end: today);
      case _Period.year:
        return DateTimeRange(start: jalaliToGregorian(j[0], 1, 1), end: today);
      case _Period.last30:
        return DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
      case _Period.custom:
        return _custom ?? DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final DateTimeRange r = _range();
    try {
      final Map<String, dynamic> res = await MkStore.I.report(r.start, r.end, staffId: _staff, country: _country, source: _source);
      if (mounted) setState(() => _r = res);
    } catch (e) {
      if (mounted) setState(() => _error = mkErr(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickCustom() async {
    final DateTime? a = await pickDate(context, initial: _range().start, lastDate: DateTime.now());
    if (a == null || !mounted) return;
    final DateTime? b = await pickDate(context, initial: DateTime.now(), firstDate: a, lastDate: DateTime.now());
    if (b == null) return;
    setState(() {
      _custom = DateTimeRange(start: a, end: b);
      _p = _Period.custom;
    });
    _load();
  }

  Future<void> _export() async {
    final Map<String, dynamic>? r = _r;
    if (r == null) return;
    String n(Object? v, [int d = 0]) => v is num ? (d == 0 ? v.round().toString() : v.toStringAsFixed(d)) : '';
    final List<List<String>> board = <List<String>>[
      <String>['رتبه', 'بازاریاب', 'پیگیری', 'مشتری جدید', 'کل مشتری', 'مذاکره', 'پیش‌فاکتور', 'فروش', 'تناژ', 'وصول', 'مجموع امتیاز', 'امتیاز نهایی'],
      for (final dynamic b in r['board'] as List<dynamic>? ?? const <dynamic>[])
        if (b is Map)
          <String>[
            n(b['rank']), '${b['name']}', n((b['counts'] as Map)['follow_ups']), n((b['counts'] as Map)['new_leads']), n(b['total_leads']), n((b['counts'] as Map)['negotiations']),
            n((b['counts'] as Map)['proformas']), n((b['counts'] as Map)['sales']), n((b['counts'] as Map)['tons'], 2), n((b['counts'] as Map)['collections']),
            n((b['score'] as Map)['total']), n((b['score'] as Map)['final']),
          ],
    ];
    final List<List<String>> countries = <List<String>>[
      <String>['کشور', 'کل مشتری', 'مشتری جدید', 'فروش', 'تناژ'],
      for (final dynamic c in r['countries'] as List<dynamic>? ?? const <dynamic>[])
        if (c is Map) <String>[mkCountryName('${c['country']}'), n(c['leads']), n(c['new_leads']), n(c['sales']), n(c['tons'], 2)],
    ];
    final List<List<String>> trend = <List<String>>[
      <String>['دوره', 'پیگیری', 'مشتری جدید', 'فروش', 'تناژ'],
      for (final dynamic t in r['trend'] as List<dynamic>? ?? const <dynamic>[])
        if (t is Map) <String>[_bucketLabel('${t['key']}', '${r['granularity']}'), n(t['follow_ups']), n(t['new_leads']), n(t['sales']), n(t['tons'], 2)],
    ];
    final List<List<String>> stale = <List<String>>[
      <String>['مشتری', 'کشور', 'مرحله', 'مسئول', 'روز بی‌حرکتی'],
      for (final dynamic s in r['stale'] as List<dynamic>? ?? const <dynamic>[])
        if (s is Map) <String>['${s['name']}', mkCountryName('${s['country']}'), kMkStageLabels['${s['stage']}'] ?? '', '${s['owner']}', n(s['idle_days'])],
    ];
    try {
      final file = await ExcelIo.exportSheets(<({String name, List<List<String>> rows})>[
        (name: 'رتبه و امتیاز', rows: board),
        (name: 'روند', rows: trend),
        (name: 'کشورها', rows: countries),
        (name: 'مشتری‌های بی‌حرکت', rows: stale),
      ], filePrefix: 'marketing_report');
      if (mounted) await ExcelIo.saveOrShare(context, file);
    } catch (e) {
      if (mounted) snack(context, mkErr(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? r = _r;
    final DateTimeRange rg = _range();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 32), children: <Widget>[
        _filters(rg),
        const SizedBox(height: 8),
        if (_loading && r == null) const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
        if (_error != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(leading: const Icon(Icons.cloud_off), title: Text(_error!), trailing: TextButton(onPressed: _load, child: const Text('تلاش دوباره'))),
          ),
        if (r != null) ...<Widget>[
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          _Kpis(r: r),
          const SizedBox(height: 10),
          _twoCols(context, _Section(title: 'قیف تبدیل مشتری‌های این دوره', icon: Icons.filter_alt_outlined, child: _Funnel(f: r['funnel'] as Map<String, dynamic>)),
              _Section(title: 'روند فعالیت', icon: Icons.show_chart, child: _Trend(r: r))),
          _Section(title: 'رتبه و امتیاز بازاریاب‌ها', icon: Icons.leaderboard_outlined, child: _Board(r: r)),
          _twoCols(context, _Section(title: 'کشورها', icon: Icons.public, child: _Countries(list: r['countries'] as List<dynamic>)),
              _Section(title: 'منبع آشنایی و نرخ فروش', icon: Icons.campaign_outlined, child: _Sources(list: r['sources'] as List<dynamic>))),
          _twoCols(context, _Section(title: 'دلیل‌های از دست رفتن مشتری', icon: Icons.block, child: _Lost(list: r['lost_reasons'] as List<dynamic>)),
              _Section(title: 'میانگین روز ماندن در هر مرحله', icon: Icons.hourglass_bottom, child: _Aging(list: r['aging'] as List<dynamic>))),
          _Section(title: 'نقشهٔ فعالیت (پیگیری‌ها)', icon: Icons.grid_on, child: _Heatmap(r: r)),
          _twoCols(context, _Section(title: 'پیگیری‌های عقب‌افتاده', icon: Icons.alarm, child: _LeadList(list: r['overdue'] as List<dynamic>, empty: 'پیگیری عقب‌افتاده‌ای نیست 👌', overdue: true)),
              _Section(title: 'مشتری‌های بی‌حرکت', icon: Icons.snooze, child: _LeadList(list: r['stale'] as List<dynamic>, empty: 'همهٔ مشتری‌ها در جریان‌اند 👌'))),
        ],
      ]),
    );
  }

  Widget _filters(DateTimeRange rg) {
    final List<dynamic> staff = (_r?['staff'] as List<dynamic>?) ?? const <dynamic>[];
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Theme.of(context).dividerColor)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
            for (final _Period p in _Period.values)
              ChoiceChip(
                label: Text(_periodLabels[p]!),
                selected: _p == p,
                onSelected: (_) {
                  if (p == _Period.custom) {
                    _pickCustom();
                    return;
                  }
                  setState(() => _p = p);
                  _load();
                },
              ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
            Text('${jalaliDateFromDt(rg.start)} تا ${jalaliDateFromDt(rg.end)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (staff.isNotEmpty)
              DropdownButton<int>(
                value: _staff,
                items: <DropdownMenuItem<int>>[
                  const DropdownMenuItem<int>(value: -1, child: Text('همهٔ بازاریاب‌ها')),
                  for (final dynamic s in staff)
                    if (s is Map) DropdownMenuItem<int>(value: ((s['id'] as num?) ?? 0).toInt(), child: Text('${s['name']}')),
                ],
                onChanged: (int? v) {
                  setState(() => _staff = v ?? -1);
                  _load();
                },
              ),
            DropdownButton<String?>(
              value: _country,
              hint: const Text('همهٔ کشورها'),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(value: null, child: Text('همهٔ کشورها')),
                for (final MapEntry<String, String> e in kMkCountries.entries) DropdownMenuItem<String?>(value: e.key, child: Text('${mkFlag(e.key)} ${e.value}')),
              ],
              onChanged: (String? v) {
                setState(() => _country = v);
                _load();
              },
            ),
            DropdownButton<String?>(
              value: _source,
              hint: const Text('همهٔ منبع‌ها'),
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(value: null, child: Text('همهٔ منبع‌ها')),
                for (final MapEntry<String, String> e in kMkSourceLabels.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
              ],
              onChanged: (String? v) {
                setState(() => _source = v);
                _load();
              },
            ),
            IconButton(tooltip: 'به‌روزرسانی', icon: const Icon(Icons.refresh), onPressed: _load),
            OutlinedButton.icon(onPressed: _r == null ? null : _export, icon: const Icon(Icons.table_view_outlined), label: const Text('خروجی اکسل')),
          ]),
        ]),
      ),
    );
  }
}

Widget _twoCols(BuildContext context, Widget a, Widget b) {
  if (MediaQuery.of(context).size.width < 1000) return Column(children: <Widget>[a, b]);
  // نمودارها اندازهٔ ذاتی ندارند ⇒ بدون IntrinsicHeight، هم‌تراز از بالا
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]);
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: th.dividerColor)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            Icon(icon, size: 20, color: th.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: th.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

double _d(Object? v) => v is num ? v.toDouble() : 0;

// ---------------------------------------------------------------- KPI
class _Kpis extends StatelessWidget {
  const _Kpis({required this.r});
  final Map<String, dynamic> r;
  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final Map<String, dynamic> k = r['kpis'] as Map<String, dynamic>;
    final Map<String, dynamic> cur = k['current'] as Map<String, dynamic>, prev = k['previous'] as Map<String, dynamic>, tgt = k['target'] as Map<String, dynamic>;
    final Map<String, dynamic> score = k['score'] as Map<String, dynamic>;
    final Object? vb = k['value_by_ccy'];
    final Map<String, dynamic> value = vb is Map ? Map<String, dynamic>.from(vb) : <String, dynamic>{}; // سرور قدیمی: [] برای خالی
    final List<Widget> cards = <Widget>[
      MkProgressCard(label: 'پیگیری', value: _d(cur['follow_ups']), previous: _d(prev['follow_ups']), target: _d(tgt['follow_ups']), icon: Icons.call_outlined, color: const Color(0xFF0EA5E9)),
      MkProgressCard(label: 'مشتری جدید', value: _d(cur['new_leads']), previous: _d(prev['new_leads']), target: _d(tgt['new_leads']), icon: Icons.person_add_alt_1_outlined, color: const Color(0xFF64748B)),
      MkProgressCard(label: 'مذاکره', value: _d(cur['negotiations']), previous: _d(prev['negotiations']), target: _d(tgt['negotiations']), icon: Icons.handshake_outlined, color: const Color(0xFF8B5CF6)),
      MkProgressCard(label: 'پیش‌فاکتور', value: _d(cur['proformas']), previous: _d(prev['proformas']), target: _d(tgt['proformas']), icon: Icons.request_quote_outlined, color: const Color(0xFFF59E0B)),
      MkProgressCard(label: 'فروش تأییدشده', value: _d(cur['sales']), previous: _d(prev['sales']), target: _d(tgt['sales']), icon: Icons.emoji_events_outlined, color: const Color(0xFF16A34A)),
      MkProgressCard(label: 'تناژ فروش', value: _d(cur['tons']), previous: _d(prev['tons']), target: _d(tgt['tons']), icon: Icons.local_shipping_outlined, color: const Color(0xFF0F766E), unit: 'تن'),
    ];
    final List<dynamic> pending = (r['pending_sales'] as List<dynamic>?) ?? const <dynamic>[];
    final List<(String, String, IconData, Color)> mini = <(String, String, IconData, Color)>[
      ('امتیاز نهایی تیم', faNum(_d(score['final']), dec: 0), Icons.military_tech_outlined, th.colorScheme.primary),
      ('وصول', faNum(_d(cur['collections']), dec: 0), Icons.account_balance_wallet_outlined, const Color(0xFF15803D)),
      ('نرخ مذاکره ← فروش', k['rate_sale'] == null ? '—' : '${faNum(_d(k['rate_sale']) * 100, dec: 1)}٪', Icons.percent, const Color(0xFF7C3AED)),
      ('مشتری باز در جریان', faNum(_d(k['open_leads']), dec: 0), Icons.groups_2_outlined, const Color(0xFF0369A1)),
      ('پیش‌بینی تناژ (وزن‌دار)', '${faNum(_d(r['forecast_tons']), dec: 1)} تن', Icons.query_stats, const Color(0xFFB45309)),
      ('فروش منتظر تأیید', faNum(pending.length, dec: 0), Icons.hourglass_top, Colors.orange.shade800),
      for (final MapEntry<String, dynamic> e in value.entries) ('ارزش قرارداد ${e.key}', faNum(_d(e.value), dec: 0), Icons.payments_outlined, const Color(0xFF166534)),
    ];
    return LayoutBuilder(builder: (BuildContext c, BoxConstraints bc) {
      final int cols = bc.maxWidth > 1100 ? 6 : (bc.maxWidth > 700 ? 3 : 2);
      return Column(children: <Widget>[
        GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: cols == 2 ? 1.35 : 1.55,
          children: cards,
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          for (final (String, String, IconData, Color) m in mini)
            Container(
              constraints: BoxConstraints(maxWidth: bc.maxWidth),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: m.$4.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: m.$4.withValues(alpha: 0.25))),
              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Icon(m.$3, size: 18, color: m.$4),
                const SizedBox(width: 6),
                Flexible(
                  child: Text.rich(
                    TextSpan(children: <InlineSpan>[
                      TextSpan(text: '${m.$1}: ', style: TextStyle(color: th.hintColor)),
                      TextSpan(text: m.$2, style: TextStyle(fontWeight: FontWeight.w800, color: m.$4)),
                    ]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
        ]),
      ]);
    });
  }
}

// ---------------------------------------------------------------- قیف
class _Funnel extends StatelessWidget {
  const _Funnel({required this.f});
  final Map<String, dynamic> f;
  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    const List<String> steps = <String>['lead', 'contacted', 'negotiation', 'proforma', 'won'];
    final double top = math.max(1, _d(f['lead']));
    if (_d(f['lead']) == 0) return const _NoData(text: 'در این دوره مشتری تازه‌ای ثبت نشده');
    return Column(children: <Widget>[
      for (int i = 0; i < steps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: LayoutBuilder(builder: (BuildContext c, BoxConstraints bc) {
            final double v = _d(f[steps[i]]);
            final double w = math.max(0.12, v / top) * bc.maxWidth;
            final double? conv = i == 0 ? null : mkRate(v, _d(f[steps[i - 1]]));
            final Color col = kMkStageColors[steps[i]]!;
            return Center(
              child: Container(
                width: w,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: <Color>[col.withValues(alpha: 0.85), col]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('${kMkStageLabels[steps[i]]}: ${faNum(v, dec: 0)}${conv == null ? '' : '  (${faNum(conv * 100, dec: 0)}٪)'}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            );
          }),
        ),
      Text('از دست رفته: ${faNum(_d(f['lost']), dec: 0)}  ·  نرخ کل تبدیل به فروش: ${faNum(_d(f['won']) / top * 100, dec: 1)}٪', style: TextStyle(color: th.hintColor, fontSize: 12)),
    ]);
  }
}

class _NoData extends StatelessWidget {
  const _NoData({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text(text, style: TextStyle(color: Theme.of(context).hintColor))));
}

String _bucketLabel(String key, String gran) {
  if (gran == 'month' && key.length == 7) {
    final int m = int.tryParse(key.substring(5)) ?? 1;
    return '${kJalaliMonths[(m - 1).clamp(0, 11)]} ${toFaDigits(key.substring(2, 4))}';
  }
  if (key.length >= 10) {
    final List<int> j = gregorianToJalali(int.parse(key.substring(0, 4)), int.parse(key.substring(5, 7)), int.parse(key.substring(8, 10)));
    return toFaDigits('${j[1]}/${j[2]}');
  }
  return key;
}

// ---------------------------------------------------------------- روند
class _Trend extends StatefulWidget {
  const _Trend({required this.r});
  final Map<String, dynamic> r;
  @override
  State<_Trend> createState() => _TrendState();
}

class _TrendState extends State<_Trend> {
  String _metric = 'follow_ups';
  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final List<Map<String, dynamic>> t = <Map<String, dynamic>>[for (final dynamic x in widget.r['trend'] as List<dynamic>) if (x is Map) Map<String, dynamic>.from(x)];
    final String gran = '${widget.r['granularity']}';
    const Map<String, (String, Color)> metrics = <String, (String, Color)>{
      'follow_ups': ('پیگیری', Color(0xFF0EA5E9)),
      'new_leads': ('مشتری جدید', Color(0xFF8B5CF6)),
      'sales': ('فروش', Color(0xFF16A34A)),
      'tons': ('تناژ', Color(0xFF0F766E)),
    };
    final Color col = metrics[_metric]!.$2;
    final List<FlSpot> spots = <FlSpot>[for (int i = 0; i < t.length; i++) FlSpot(i.toDouble(), _d(t[i][_metric]))];
    final double maxY = spots.fold<double>(0, (double a, FlSpot s) => math.max(a, s.y));
    final int step = math.max(1, (t.length / 7).ceil());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Wrap(spacing: 6, children: <Widget>[
        for (final MapEntry<String, (String, Color)> m in metrics.entries)
          ChoiceChip(label: Text(m.value.$1), selected: _metric == m.key, selectedColor: m.value.$2.withValues(alpha: 0.2), onSelected: (_) => setState(() => _metric = m.key)),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        height: 230,
        child: t.isEmpty
            ? const _NoData(text: 'داده‌ای نیست')
            : LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY <= 0 ? 1 : maxY * 1.2,
                  gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (double v) => FlLine(color: th.dividerColor.withValues(alpha: 0.5), strokeWidth: 1)),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            getTitlesWidget: (double v, TitleMeta m) => Text(toFaDigits(v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1)), style: const TextStyle(fontSize: 10)))),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        interval: 1,
                        getTitlesWidget: (double v, TitleMeta m) {
                          final int i = v.toInt();
                          if (i < 0 || i >= t.length || i % step != 0) return const SizedBox.shrink();
                          return Padding(padding: const EdgeInsets.only(top: 6), child: Text(_bucketLabel('${t[i]['key']}', gran), style: const TextStyle(fontSize: 10)));
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (List<LineBarSpot> s) => <LineTooltipItem>[
                        for (final LineBarSpot x in s)
                          LineTooltipItem('${_bucketLabel('${t[x.x.toInt()]['key']}', gran)}\n${metrics[_metric]!.$1}: ${faNum(x.y, dec: _metric == 'tons' ? 1 : 0)}',
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  lineBarsData: <LineChartBarData>[
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: col,
                      barWidth: 3,
                      dotData: FlDotData(show: t.length <= 31),
                      belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[col.withValues(alpha: 0.30), col.withValues(alpha: 0.0)])),
                    ),
                  ],
                ),
              ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- رتبه
class _Board extends StatelessWidget {
  const _Board({required this.r});
  final Map<String, dynamic> r;
  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final List<Map<String, dynamic>> b = <Map<String, dynamic>>[for (final dynamic x in r['board'] as List<dynamic>) if (x is Map) Map<String, dynamic>.from(x)];
    if (b.isEmpty) return const _NoData(text: 'در این دوره فعالیتی ثبت نشده');
    final double top = math.max(1, b.map((Map<String, dynamic> x) => _d((x['score'] as Map)['final'])).fold<double>(0, math.max));
    const List<String> medals = <String>['🥇', '🥈', '🥉'];
    return Column(children: <Widget>[
      SizedBox(
        height: math.max(140, b.length * 34.0),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: top * 1.15,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (double v, TitleMeta m) {
                    final int i = v.toInt();
                    if (i < 0 || i >= b.length) return const SizedBox.shrink();
                    return Padding(padding: const EdgeInsets.only(top: 6), child: Text('${b[i]['name']}', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis));
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (BarChartGroupData g, int gi, BarChartRodData rod, int ri) =>
                    BarTooltipItem('${b[g.x]['name']}\nامتیاز نهایی: ${faNum(rod.toY, dec: 0)}', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            barGroups: <BarChartGroupData>[
              for (int i = 0; i < b.length; i++)
                BarChartGroupData(x: i, barRods: <BarChartRodData>[
                  BarChartRodData(
                    toY: math.max(0, _d((b[i]['score'] as Map)['final'])),
                    width: 26,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: <Color>[th.colorScheme.primary.withValues(alpha: 0.6), th.colorScheme.primary]),
                  ),
                ]),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 38,
          dataRowMinHeight: 44,
          columns: const <DataColumn>[
            DataColumn(label: Text('رتبه')),
            DataColumn(label: Text('بازاریاب')),
            DataColumn(label: Text('پیگیری'), numeric: true),
            DataColumn(label: Text('مشتری جدید'), numeric: true),
            DataColumn(label: Text('مذاکره'), numeric: true),
            DataColumn(label: Text('پیش‌فاکتور'), numeric: true),
            DataColumn(label: Text('فروش'), numeric: true),
            DataColumn(label: Text('تناژ'), numeric: true),
            DataColumn(label: Text('وصول'), numeric: true),
            DataColumn(label: Text('پیشرفت هدف')),
            DataColumn(label: Text('امتیاز'), numeric: true),
          ],
          rows: <DataRow>[
            for (final Map<String, dynamic> x in b)
              () {
                final Map<String, dynamic> c = Map<String, dynamic>.from(x['counts'] as Map), t = Map<String, dynamic>.from(x['target'] as Map);
                final int rank = ((x['rank'] as num?) ?? 0).toInt();
                double prog(String k) => _d(t[k]) > 0 ? (_d(c[k]) / _d(t[k])).clamp(0, 1).toDouble() : 0;
                final double avg = <double>[prog('follow_ups'), prog('new_leads'), prog('sales'), prog('tons')].reduce((double a, double b) => a + b) / 4;
                return DataRow(cells: <DataCell>[
                  DataCell(Text(rank >= 1 && rank <= 3 ? medals[rank - 1] : toFaDigits('$rank'), style: const TextStyle(fontSize: 18))),
                  DataCell(Text('${x['name']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text(faNum(_d(c['follow_ups']), dec: 0))),
                  DataCell(Text(faNum(_d(c['new_leads']), dec: 0))),
                  DataCell(Text(faNum(_d(c['negotiations']), dec: 0))),
                  DataCell(Text(faNum(_d(c['proformas']), dec: 0))),
                  DataCell(Text(faNum(_d(c['sales']), dec: 0))),
                  DataCell(Text(faNum(_d(c['tons']), dec: 1))),
                  DataCell(Text(faNum(_d(c['collections']), dec: 0))),
                  DataCell(SizedBox(
                    width: 120,
                    child: Row(children: <Widget>[
                      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: avg, minHeight: 8))),
                      const SizedBox(width: 6),
                      Text('${faNum(avg * 100, dec: 0)}٪', style: const TextStyle(fontSize: 11)),
                    ]),
                  )),
                  DataCell(Text(faNum(_d((x['score'] as Map)['final']), dec: 0), style: TextStyle(fontWeight: FontWeight.w900, color: th.colorScheme.primary))),
                ]);
              }(),
          ],
        ),
      ),
      if (r['rank'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('رتبهٔ شما: ${toFaDigits('${r['rank']}')} از ${toFaDigits('${r['team_size']}')}')),
    ]);
  }
}

// ---------------------------------------------------------------- کشورها
class _Countries extends StatelessWidget {
  const _Countries({required this.list});
  final List<dynamic> list;
  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final List<Map<String, dynamic>> l = <Map<String, dynamic>>[for (final dynamic x in list) if (x is Map) Map<String, dynamic>.from(x)].take(10).toList();
    if (l.isEmpty) return const _NoData(text: 'هنوز کشوری ثبت نشده');
    final double maxLeads = math.max(1, l.map((Map<String, dynamic> c) => _d(c['leads'])).fold<double>(0, math.max));
    return Column(children: <Widget>[
      for (final Map<String, dynamic> c in l)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: <Widget>[
            Text(mkFlag('${c['country']}'), style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 6),
            SizedBox(width: 92, child: Text(mkCountryName('${c['country']}'), overflow: TextOverflow.ellipsis)),
            Expanded(
              child: Stack(children: <Widget>[
                Container(height: 22, decoration: BoxDecoration(color: th.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6))),
                FractionallySizedBox(
                  widthFactor: (_d(c['leads']) / maxLeads).clamp(0.02, 1).toDouble(),
                  child: Container(height: 22, decoration: BoxDecoration(color: const Color(0xFF0EA5E9).withValues(alpha: 0.75), borderRadius: BorderRadius.circular(6))),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text('${faNum(_d(c['leads']), dec: 0)} مشتری${_d(c['sales']) > 0 ? '  ·  ${faNum(_d(c['sales']), dec: 0)} فروش' : ''}',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 64, child: Text(_d(c['tons']) > 0 ? '${faNum(_d(c['tons']), dec: 1)} تن' : '—', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold))),
          ]),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- منبع‌ها
const List<Color> _palette = <Color>[Color(0xFF0EA5E9), Color(0xFF8B5CF6), Color(0xFFF59E0B), Color(0xFF16A34A), Color(0xFFEF4444), Color(0xFF14B8A6), Color(0xFFEC4899), Color(0xFF64748B)];

class _Sources extends StatelessWidget {
  const _Sources({required this.list});
  final List<dynamic> list;
  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> l = <Map<String, dynamic>>[for (final dynamic x in list) if (x is Map) Map<String, dynamic>.from(x)];
    if (l.isEmpty) return const _NoData(text: 'در این دوره مشتری تازه‌ای ثبت نشده');
    return _Donut(
      slices: <(String, double, Color, String)>[
        for (int i = 0; i < l.length; i++)
          (
            kMkSourceLabels['${l[i]['source']}'] ?? '${l[i]['source']}',
            _d(l[i]['leads']),
            _palette[i % _palette.length],
            l[i]['win_rate'] == null ? '' : 'نرخ فروش ${faNum(_d(l[i]['win_rate']) * 100, dec: 0)}٪',
          ),
      ],
      center: 'مشتری جدید',
    );
  }
}

class _Lost extends StatelessWidget {
  const _Lost({required this.list});
  final List<dynamic> list;
  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> l = <Map<String, dynamic>>[for (final dynamic x in list) if (x is Map) Map<String, dynamic>.from(x)];
    if (l.isEmpty) return const _NoData(text: 'در این دوره مشتری‌ای از دست نرفته 👌');
    const List<Color> reds = <Color>[Color(0xFFDC2626), Color(0xFFF97316), Color(0xFFEAB308), Color(0xFF9333EA), Color(0xFF0EA5E9), Color(0xFF64748B), Color(0xFF475569)];
    return _Donut(
      slices: <(String, double, Color, String)>[
        for (int i = 0; i < l.length; i++) (kMkLostLabels['${l[i]['reason']}'] ?? '${l[i]['reason']}', _d(l[i]['count']), reds[i % reds.length], ''),
      ],
      center: 'از دست رفته',
    );
  }
}

class _Donut extends StatefulWidget {
  const _Donut({required this.slices, required this.center});
  final List<(String, double, Color, String)> slices;
  final String center;
  @override
  State<_Donut> createState() => _DonutState();
}

class _DonutState extends State<_Donut> {
  int _touched = -1;
  @override
  Widget build(BuildContext context) {
    final double total = widget.slices.fold<double>(0, (double a, (String, double, Color, String) s) => a + s.$2);
    return Row(children: <Widget>[
      SizedBox(
        width: 170,
        height: 170,
        child: Stack(alignment: Alignment.center, children: <Widget>[
          PieChart(PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 46,
            pieTouchData: PieTouchData(touchCallback: (FlTouchEvent e, PieTouchResponse? r) {
              setState(() => _touched = (!e.isInterestedForInteractions || r?.touchedSection == null) ? -1 : r!.touchedSection!.touchedSectionIndex);
            }),
            sections: <PieChartSectionData>[
              for (int i = 0; i < widget.slices.length; i++)
                PieChartSectionData(
                  value: widget.slices[i].$2,
                  color: widget.slices[i].$3,
                  radius: _touched == i ? 40 : 32,
                  title: total > 0 && widget.slices[i].$2 / total >= 0.08 ? '${faNum(widget.slices[i].$2 / total * 100, dec: 0)}٪' : '',
                  titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
            ],
          )),
          Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(faNum(total, dec: 0), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text(widget.center, style: TextStyle(fontSize: 10.5, color: Theme.of(context).hintColor)),
          ]),
        ]),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          for (int i = 0; i < widget.slices.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: <Widget>[
                Container(width: 12, height: 12, decoration: BoxDecoration(color: widget.slices[i].$3, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${widget.slices[i].$1}: ${faNum(widget.slices[i].$2, dec: 0)}${widget.slices[i].$4.isEmpty ? '' : '  ·  ${widget.slices[i].$4}'}',
                      style: TextStyle(fontWeight: _touched == i ? FontWeight.bold : null, fontSize: 12.5)),
                ),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- سن مراحل
class _Aging extends StatelessWidget {
  const _Aging({required this.list});
  final List<dynamic> list;
  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> l = <Map<String, dynamic>>[for (final dynamic x in list) if (x is Map) Map<String, dynamic>.from(x)];
    final double mx = math.max(1, l.map((Map<String, dynamic> a) => _d(a['avg_days'])).fold<double>(0, math.max));
    if (l.every((Map<String, dynamic> a) => a['avg_days'] == null)) return const _NoData(text: 'هنوز داده‌ای برای سن مراحل نیست');
    return SizedBox(
      height: 200,
      child: BarChart(BarChartData(
        maxY: mx * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (double v, TitleMeta m) {
                    final int i = v.toInt();
                    if (i < 0 || i >= l.length) return const SizedBox.shrink();
                    return Padding(padding: const EdgeInsets.only(top: 6), child: Text(kMkStageLabels['${l[i]['stage']}'] ?? '', style: const TextStyle(fontSize: 11)));
                  })),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (BarChartGroupData g, int gi, BarChartRodData rod, int ri) => BarTooltipItem(
                '${kMkStageLabels['${l[g.x]['stage']}']}\nمیانگین ${faNum(rod.toY, dec: 1)} روز\n${faNum(_d(l[g.x]['leads']), dec: 0)} مورد',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
        barGroups: <BarChartGroupData>[
          for (int i = 0; i < l.length; i++)
            BarChartGroupData(x: i, barRods: <BarChartRodData>[
              BarChartRodData(toY: _d(l[i]['avg_days']), width: 30, color: kMkStageColors['${l[i]['stage']}'], borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
            ]),
        ],
      )),
    );
  }
}

// ---------------------------------------------------------------- نقشهٔ حرارتی
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.r});
  final Map<String, dynamic> r;
  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[for (final dynamic x in r['heatmap'] as List<dynamic>) if (x is Map) Map<String, dynamic>.from(x)];
    final List<String> keys = <String>[for (final dynamic t in r['trend'] as List<dynamic>) if (t is Map) '${t['key']}'];
    final String gran = '${r['granularity']}';
    if (rows.isEmpty || keys.isEmpty) return const _NoData(text: 'در این دوره پیگیری‌ای ثبت نشده');
    double mx = 1;
    for (final Map<String, dynamic> row in rows) {
      for (final Object? v in (row['cells'] as Map).values) {
        mx = math.max(mx, _d(v));
      }
    }
    const double cell = 22;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          const SizedBox(width: 110),
          for (final String k in keys) SizedBox(width: cell + 2, child: Text(_bucketLabel(k, gran).split('/').last, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9))),
        ]),
        for (final Map<String, dynamic> row in rows)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: <Widget>[
              SizedBox(width: 110, child: Text('${row['name']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
              for (final String k in keys)
                Tooltip(
                  message: '${row['name']} — ${_bucketLabel(k, gran)}: ${faNum(_d((row['cells'] as Map)[k]), dec: 0)} پیگیری',
                  child: Container(
                    width: cell,
                    height: cell,
                    margin: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: _d((row['cells'] as Map)[k]) == 0
                          ? th.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                          : Color.lerp(const Color(0xFFBBF7D0), const Color(0xFF15803D), _d((row['cells'] as Map)[k]) / mx),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: _d((row['cells'] as Map)[k]) == 0
                        ? null
                        : Center(child: Text(toFaDigits('${_d((row['cells'] as Map)[k]).toInt()}'), style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold))),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- فهرست مشتری‌ها
class _LeadList extends StatelessWidget {
  const _LeadList({required this.list, required this.empty, this.overdue = false});
  final List<dynamic> list;
  final String empty;
  final bool overdue;
  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final List<Map<String, dynamic>> l = <Map<String, dynamic>>[for (final dynamic x in list) if (x is Map) Map<String, dynamic>.from(x)];
    if (l.isEmpty) return _NoData(text: empty);
    return Column(children: <Widget>[
      for (final Map<String, dynamic> x in l.take(12))
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Text(mkFlag('${x['country']}'), style: const TextStyle(fontSize: 20)),
          title: Text('${x['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${x['owner']}  ·  ${overdue ? 'موعد ${mkDate(x['next_followup_at'])}' : '${faNum(_d(x['idle_days']), dec: 0)} روز بدون پیگیری'}'),
          trailing: mkStageChip('${x['stage']}', dense: true),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => MkLeadScreen(uid: '${x['uid']}'))),
        ),
      if (l.length > 12) Text('و ${faNum(l.length - 12, dec: 0)} مورد دیگر', style: TextStyle(color: th.hintColor, fontSize: 12)),
    ]);
  }
}
