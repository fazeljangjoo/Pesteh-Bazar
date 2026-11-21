// فاز ۱ «قابلیت‌های فناورانه» — کارت «ارزیابی بازده» و فهرست «هشدارهای بازده». پشت پرچم features.anomaly (پیش‌فرض خاموش).
// عملیات بسته/گزارش ذخیره‌شده ⇒ ارزیابی سرور (anomaly.for). عملیات باز/فرم در حال ویرایش ⇒ نمایش زنده با آینهٔ Dart (anomaly_calc.dart)
// روی سابقه‌ای که سرور می‌دهد (anomaly.history). خطای شبکه/سرور فقط کارت را پنهان می‌کند؛ هیچ عملیات اصلی را متوقف نمی‌کند.
import 'package:flutter/material.dart';

import 'anomaly_calc.dart';
import 'perms.dart' show StaffPerms;
import 'tech_features.dart';
import 'utils.dart' show jalaliDate;
import 'warehouse_ui.dart' show StockApi, StockApiException;

Color anLevelColor(BuildContext context, String level) {
  switch (level) {
    case 'high':
      return Colors.red;
    case 'warn':
      return Colors.orange;
    case 'low_loss':
      return Colors.purple;
    case 'normal':
      return Colors.green;
    default:
      return Theme.of(context).colorScheme.outline;
  }
}

IconData anLevelIcon(String level) {
  switch (level) {
    case 'high':
      return Icons.error_outline;
    case 'warn':
      return Icons.warning_amber_outlined;
    case 'low_loss':
      return Icons.help_outline;
    case 'normal':
      return Icons.check_circle_outline;
    default:
      return Icons.hourglass_empty;
  }
}

/// کارت «ارزیابی بازده». [sourceId] = شناسهٔ سرور (null ⇒ هنوز ثبت نشده ⇒ فقط زنده).
/// [live] = true ⇒ مقادیر [values] با سابقهٔ سرور و آینهٔ Dart زنده ارزیابی می‌شوند (فرم قبل از بستن/ثبت).
class YieldAssessmentCard extends StatelessWidget {
  const YieldAssessmentCard({super.key, required this.source, this.sourceId, this.live = false, this.values = const <String, Object?>{},
      this.opType, this.pistachioType});
  final String source; // workshop | crack
  final int? sourceId;
  final bool live;
  final Map<String, Object?> values;
  final String? opType;
  final String? pistachioType;

  @override
  Widget build(BuildContext context) => TechGate(
      flag: 'anomaly',
      child: _YieldBody(
          key: ValueKey<String>('$source/$sourceId/$live/$opType/$pistachioType'),
          source: source, sourceId: sourceId, live: live, values: values, opType: opType, pistachioType: pistachioType));
}

class _YieldBody extends StatefulWidget {
  const _YieldBody({super.key, required this.source, this.sourceId, required this.live, required this.values, this.opType, this.pistachioType});
  final String source;
  final int? sourceId;
  final bool live;
  final Map<String, Object?> values;
  final String? opType;
  final String? pistachioType;

  @override
  State<_YieldBody> createState() => _YieldBodyState();
}

class _YieldBodyState extends State<_YieldBody> {
  Map<String, dynamic>? _server; // anomaly.for
  Map<String, dynamic>? _hist; // anomaly.history
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.live) {
        final Map<String, dynamic> r = await StockApi.call('anomaly.history', <String, dynamic>{
          'source': widget.source,
          if (widget.sourceId != null) 'id': widget.sourceId,
          if (widget.sourceId == null) 'op_type': widget.opType ?? '',
          if (widget.sourceId == null) 'pistachio_type': widget.pistachioType ?? '',
        });
        if (mounted) setState(() => _hist = r);
      } else if (widget.sourceId != null) {
        final Map<String, dynamic> r = await StockApi.call('anomaly.for', <String, dynamic>{'source': widget.source, 'source_id': widget.sourceId});
        if (mounted) setState(() => _server = r);
      }
    } on StockApiException {
      if (mounted) setState(() => _failed = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  List<_Line> _lines() {
    if (widget.live) {
      final Map<String, dynamic>? h = _hist;
      if (h == null) return <_Line>[];
      final Map<String, List<Object?>> hs = <String, List<Object?>>{};
      final Object? raw = h['history'];
      if (raw is Map) {
        raw.forEach((dynamic k, dynamic v) => hs['$k'] = v is List ? v.cast<Object?>() : <Object?>[]);
      }
      final List<AnRow> rows = anEvaluate(widget.source, widget.values, hs, '${h['kind_label'] ?? 'همین نوع'}');
      return rows.map((AnRow r) => _Line(r.label, r.eval.level, r.text)).toList();
    }
    final Map<String, dynamic>? s = _server;
    if (s == null) return <_Line>[];
    final Object? rows = s['rows'];
    if (rows is! List) return <_Line>[];
    return rows.whereType<Map>().map((Map r) => _Line('${r['label']}', '${r['level']}', '${r['text']}')).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    if (_server == null && _hist == null) {
      return const Card(child: ListTile(leading: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)), title: Text('ارزیابی بازده…')));
    }
    final List<_Line> ls = _lines();
    if (ls.isEmpty) return const SizedBox.shrink();
    const Map<String, int> rank = <String, int>{'insufficient': 0, 'normal': 1, 'low_loss': 2, 'warn': 3, 'high': 4};
    String worst = 'insufficient';
    for (final _Line l in ls) {
      if ((rank[l.level] ?? 0) > (rank[worst] ?? 0)) worst = l.level;
    }
    final Color c = anLevelColor(context, worst);
    return Card(
      color: c.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Icon(anLevelIcon(worst), color: c),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.live ? 'ارزیابی بازده (پیش‌نمایش زنده)' : 'ارزیابی بازده', style: const TextStyle(fontWeight: FontWeight.bold))),
            Text(kAnLevelLabels[worst] ?? worst, style: TextStyle(color: c)),
          ]),
          const SizedBox(height: 6),
          for (final _Line l in ls)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Icon(anLevelIcon(l.level), size: 18, color: anLevelColor(context, l.level)),
                const SizedBox(width: 6),
                Expanded(child: Text(l.text)),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _Line {
  const _Line(this.label, this.level, this.text);
  final String label;
  final String level;
  final String text;
}

/// فهرست «هشدارهای بازده» با فیلتر سطح، منبع/کارگاه و تاریخ؛ «بررسی شد» با دلیل اجباری.
class AnomalyListScreen extends StatefulWidget {
  const AnomalyListScreen({super.key});

  @override
  State<AnomalyListScreen> createState() => _AnomalyListScreenState();
}

class _AnomalyListScreenState extends State<AnomalyListScreen> {
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  String _level = '';
  String _source = '';
  String _from = '';
  String _to = '';
  bool _dismissed = false;

  static const Map<String, String> _levels = <String, String>{'': 'همهٔ سطح‌ها', 'high': 'هشدار جدی', 'warn': 'هشدار', 'low_loss': 'افت خیلی کم'};
  static const Map<String, String> _sources = <String, String>{'': 'همهٔ کارگاه‌ها', 'workshop': 'کارگاه داخلی', 'crack': 'خط شکست'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> r = await StockApi.call('anomaly.list', <String, dynamic>{
        if (_level.isNotEmpty) 'level': _level,
        if (_source.isNotEmpty) 'source': _source,
        if (_from.isNotEmpty) 'from': _from,
        if (_to.isNotEmpty) 'to': _to,
        if (_dismissed) 'include_dismissed': 1,
      });
      final Object? it = r['items'];
      if (!mounted) return;
      setState(() {
        _items = it is List ? it.whereType<Map>().map((Map m) => Map<String, dynamic>.from(m)).toList() : <Map<String, dynamic>>[];
        _loading = false;
      });
    } on StockApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickDate(bool from) async {
    final DateTime now = DateTime.now();
    final DateTime? d = await showDatePicker(context: context, firstDate: DateTime(now.year - 2), lastDate: now, initialDate: now);
    if (d == null) return;
    final String s = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    setState(() => from ? _from = s : _to = s);
    _load();
  }

  Future<void> _dismiss(Map<String, dynamic> it) async {
    final TextEditingController c = TextEditingController();
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('بررسی شد'),
        content: TextField(controller: c, autofocus: true, maxLength: 500, decoration: const InputDecoration(labelText: 'دلیل (اجباری)')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('ثبت')),
        ],
      ),
    );
    if (reason == null) return;
    if (reason.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('دلیل «بررسی شد» را بنویسید')));
      return;
    }
    try {
      await StockApi.call('anomaly.dismiss', <String, dynamic>{'id': it['id'], 'reason': reason});
      await _load();
    } on StockApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canDismiss = StaffPerms.I.can('workshop.manage');
    return Scaffold(
      appBar: AppBar(title: const Text('هشدارهای بازده'), actions: <Widget>[IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'به‌روزرسانی')]),
      body: Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
            DropdownButton<String>(
              value: _level,
              items: _levels.entries.map((MapEntry<String, String> e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
              onChanged: (String? v) {
                setState(() => _level = v ?? '');
                _load();
              },
            ),
            DropdownButton<String>(
              value: _source,
              items: _sources.entries.map((MapEntry<String, String> e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value))).toList(),
              onChanged: (String? v) {
                setState(() => _source = v ?? '');
                _load();
              },
            ),
            ActionChip(label: Text(_from.isEmpty ? 'از تاریخ' : 'از ${jalaliDate(_from)}'), onPressed: () => _pickDate(true)),
            ActionChip(label: Text(_to.isEmpty ? 'تا تاریخ' : 'تا ${jalaliDate(_to)}'), onPressed: () => _pickDate(false)),
            if (_from.isNotEmpty || _to.isNotEmpty)
              IconButton(
                  tooltip: 'حذف فیلتر تاریخ',
                  onPressed: () {
                    setState(() {
                      _from = '';
                      _to = '';
                    });
                    _load();
                  },
                  icon: const Icon(Icons.clear)),
            FilterChip(
              label: const Text('بررسی‌شده‌ها هم'),
              selected: _dismissed,
              onSelected: (bool v) {
                setState(() => _dismissed = v);
                _load();
              },
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _items.isEmpty
                      ? const Center(child: Text('هشداری نیست'))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (BuildContext context, int i) {
                            final Map<String, dynamic> it = _items[i];
                            final String level = '${it['level']}';
                            final bool done = it['dismissed_at'] != null;
                            final String where = it['source'] == 'crack'
                                ? 'خط شکست${'${it['line_code'] ?? ''}'.isEmpty ? '' : ' ${it['line_code']}'}'
                                : 'کارگاه داخلی (عملیات ${it['source_id']})';
                            return Card(
                              child: ListTile(
                                leading: Icon(anLevelIcon(level), color: anLevelColor(context, level)),
                                title: Text('${it['level_label'] ?? level} — ${it['label']}'),
                                subtitle: Text([
                                  '${it['text']}',
                                  '$where${'${it['pistachio_type'] ?? ''}'.isEmpty ? '' : ' • ${it['pistachio_type']}'}${it['op_date'] == null ? '' : ' • ${jalaliDate('${it['op_date']}')}'}',
                                  if (done) 'بررسی شد: ${it['dismiss_reason'] ?? ''}',
                                ].join('\n')),
                                isThreeLine: true,
                                trailing: (!done && canDismiss)
                                    ? TextButton(onPressed: () => _dismiss(it), child: const Text('بررسی شد'))
                                    : null,
                              ),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
