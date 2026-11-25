import 'package:flutter/material.dart';

import 'utils.dart' show faNum, jalaliDate;
import 'widgets.dart' show JalaliDateField;
import 'workshop_calc.dart';

/// v91 p4 — «شکست مجدد نشکن» در همان فرم عملیات شکست کارگاه داخلی (فایل مشترک اندروید و ویندوز).
/// [detail] = پاسخ workshop.get (+ صف آفلاین): outputs (با round)، recracks، shifts.
/// [onRecrack] (kg, تاریخ ISO) و [onUndo] (دور) اکشن‌های workshop.recrack / workshop.recrack_undo را می‌فرستند.
/// قواعد (نشکن کافی، فقط عملیات باز، لغو فقط آخرین دورِ بی‌خروجی و بی‌شیفت) = wsFlowCheck (آینهٔ pb_ws_flow_check سرور).
class WsRecrackCard extends StatelessWidget {
  const WsRecrackCard({super.key, required this.detail, required this.onRecrack, required this.onUndo, this.editable = true});
  final Map<String, dynamic> detail;
  final Future<void> Function(double kg, String date) onRecrack;
  final Future<void> Function(int round) onUndo;
  final bool editable;

  List<dynamic> get _outs => detail['outputs'] as List<dynamic>? ?? const <dynamic>[];
  int get _round => (detail['recracks'] as List<dynamic>? ?? const <dynamic>[]).length;
  bool get _open => detail['status'] == kWsOpen;

  static String _kg(num v) => faNum(v, dec: 3);

  /// آیا کادر نمایش داده شود (عملیات شکست با نشکن یا با دور شکست مجدد).
  static bool shown(Map<String, dynamic> d) =>
      d['op_type'] == 'crack' && (wsUncrackedG(d['outputs'] as List<dynamic>? ?? const <dynamic>[]) > 0 || (d['recracks'] as List<dynamic>? ?? const <dynamic>[]).isNotEmpty);

  Future<void> _recrack(BuildContext context) async {
    final int availG = wsUncrackedG(_outs);
    final Map<String, dynamic>? r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RecrackDialog(availG: availG, round: _round + 1, status: detail['status'] as String?),
    );
    if (r == null) return;
    await onRecrack(r['kg'] as double, r['date'] as String);
  }

  Future<void> _undo(BuildContext context) async {
    final int r = _round;
    final bool busy = _outs.any((dynamic o) => wsRoundOf(o) == r) || (detail['shifts'] as List<dynamic>? ?? const <dynamic>[]).any((dynamic x) => wsRoundOf(x) == r);
    final String? err = wsFlowCheck(detail['status'] as String?, 'recrack_undo', rounds: r, round: r, busy: busy);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(kWsFlowErrors[err] ?? err)));
      return;
    }
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: Text('«${wsRoundLabel(r)}» لغو شود؟'),
            content: const Text('نشکنِ برداشته‌شده به خروجی‌ها برمی‌گردد.'),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('لغو دور')),
            ],
          ),
        ) ??
        false;
    if (ok) await onUndo(r);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final double avail = wsUncrackedG(_outs) / 1000;
    final List<WsRound> rs = wsRecrackRounds(detail);
    final bool can = editable && _open;
    Widget kv(String k, String v, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: <Widget>[
            Expanded(child: Text(k)),
            Flexible(child: Text(v, textAlign: TextAlign.end, style: TextStyle(fontWeight: strong ? FontWeight.bold : null))),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text('شکست مجدد نشکن', style: th.textTheme.titleMedium),
          const SizedBox(height: 4),
          kv('نشکن موجود (قابل شکست مجدد)', '${_kg(avail)} کیلو', strong: true),
          for (final WsRound w in rs.skip(1))
            kv(
              '${wsRoundLabel(w.round)}${w.date == null ? '' : ' (${jalaliDate(w.date!)})'}: ${_kg(w.kg)} کیلو نشکن',
              'مغز ${_kg(w.kernelKg)} • پوست ${_kg(w.hullKg)} • نشکن ${_kg(w.uncrackedKg)}${w.shifts > 0 ? ' • ${faNum(w.shifts, dec: 0)} شیفت' : ''}',
            ),
          if (rs.length > 1) kv('جمع نشکنِ دوباره شکسته‌شده', '${_kg(rs.fold<double>(0, (double a, WsRound w) => a + w.kg))} کیلو'),
          Text(
            'نشکنِ دوباره شکسته‌شده از نشکن قبلی کم می‌شود؛ مغز و پوست تازه به مغز و پوست قبلی اضافه می‌شوند و نشکنِ باقی‌مانده دوباره ثبت می‌شود. '
            'وزن ورودی دوباره شمرده نمی‌شود: ضایعات = ورودی − (Σ مغز + Σ پوست + نشکن نهایی).',
            style: TextStyle(fontSize: 12, color: th.hintColor),
          ),
          if (can && _round > 0) Text('شیفت‌ها و خروجی‌های تازه برای «${wsRoundLabel(_round)}» ثبت می‌شوند.', style: TextStyle(fontSize: 12, color: th.colorScheme.primary)),
          if (can)
            Wrap(spacing: 8, children: <Widget>[
              if (avail > 0) FilledButton.tonalIcon(onPressed: () => _recrack(context), icon: const Icon(Icons.replay), label: const Text('شکست مجدد نشکن')),
              if (_round > 0) TextButton.icon(onPressed: () => _undo(context), icon: const Icon(Icons.undo), label: Text('لغو ${wsRoundLabel(_round)}')),
            ]),
        ]),
      ),
    );
  }
}

class _RecrackDialog extends StatefulWidget {
  const _RecrackDialog({required this.availG, required this.round, required this.status});
  final int availG;
  final int round;
  final String? status;

  @override
  State<_RecrackDialog> createState() => _RecrackDialogState();
}

class _RecrackDialogState extends State<_RecrackDialog> {
  late final TextEditingController _kg = TextEditingController(text: '${widget.availG / 1000}');
  DateTime _date = DateTime.now();
  String? _err;

  @override
  void dispose() {
    _kg.dispose();
    super.dispose();
  }

  static double _parse(String s) {
    const String fa = '۰۱۲۳۴۵۶۷۸۹';
    final StringBuffer b = StringBuffer();
    for (final int r in s.trim().runes) {
      final String ch = String.fromCharCode(r);
      final int i = fa.indexOf(ch);
      b.write(i >= 0 ? '$i' : (ch == '٫' || ch == '/' ? '.' : (ch == ',' || ch == '٬' ? '' : ch)));
    }
    return double.tryParse(b.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('شکست مجدد نشکن — ${wsRoundLabel(widget.round)}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text('نشکن موجود: ${faNum(widget.availG / 1000, dec: 3)} کیلو'),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey<String>('ws-recrack-kg'),
              controller: _kg,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'وزن نشکنی که دوباره شکسته می‌شود (کیلو)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            JalaliDateField(label: 'تاریخ', value: _date, onChanged: (DateTime d) => setState(() => _date = d)),
            const SizedBox(height: 8),
            const Text('پس از ثبت، شیفت‌ها و خروجی‌های این دور (مغز، پوست، نشکن باقی‌مانده) را در همین فرم وارد کنید.', style: TextStyle(fontSize: 12)),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_err!, style: const TextStyle(color: Colors.red))),
          ]),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(
          onPressed: () {
            final double kg = _parse(_kg.text);
            final String? e = wsFlowCheck(widget.status, 'recrack', crack: true, availG: widget.availG, kgG: wsGrams(kg));
            if (e != null) return setState(() => _err = kWsFlowErrors[e] ?? e);
            Navigator.pop(context, <String, dynamic>{
              'kg': kg,
              'date': '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
            });
          },
          child: const Text('ثبت شکست مجدد'),
        ),
      ],
    );
  }
}
