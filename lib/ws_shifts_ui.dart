import 'package:flutter/material.dart';

import 'utils.dart' show faNum, jalaliDate, toFaDigits;
import 'widgets.dart' show JalaliDateField;
import 'workshop_calc.dart';

/// v86 — شیفت‌های عملیات «شکست» (کارگاه داخلی و فراوری امانی؛ فایل مشترک اندروید و ویندوز).
/// هر شیفت: نوع (صبح / عصر / شب)، تاریخ شیفت، نام اپراتور، ساعت شروع و پایان (ساعت ۲۴ساعتهٔ «اپراتور دستگاه»:
/// صفحهٔ ساعت یا ورود دستی). مدت هر شیفت و کادر «جمع ساعات و جمع شیفت‌ها» روبه‌روی همین بخش.
/// [onSave] کل فهرست را ذخیره می‌کند ({shift, date, operator, start, end}).

String _hm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
TimeOfDay? _tod(String? s) {
  final int? m = wsClockMin(s);
  return m == null ? null : TimeOfDay(hour: m ~/ 60, minute: m % 60);
}

/// ساعت ۲۴ساعته (صفحهٔ ساعت + ورود دستی با آیکن صفحه‌کلید)؛ همان ساعت فرم خط شکست.
Future<String?> pickClock(BuildContext context, String? current, {String? help}) async {
  final TimeOfDay? t = await showTimePicker(
    context: context,
    helpText: help,
    initialTime: _tod(current) ?? TimeOfDay.now(),
    builder: (BuildContext c, Widget? w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w ?? const SizedBox()),
  );
  return t == null ? null : _hm(t);
}

/// متن «جمع ساعات و شیفت‌ها» (برای کادر و گزارش PDF).
List<List<String>> wsShiftReportRows(List<Map<String, dynamic>> shifts) {
  if (shifts.isEmpty) return const <List<String>>[];
  final WsShiftTotals t = wsShiftTotals(shifts);
  return <List<String>>[
    for (final Map<String, dynamic> r in shifts)
      <String>[
        'شیفت ${kWsShiftLabels['${r['shift']}'] ?? ''} ${jalaliDate('${r['date'] ?? ''}')}${'${r['operator'] ?? ''}'.isEmpty ? '' : ' — ${r['operator']}'}${wsRoundOf(r) > 0 ? ' (${wsRoundLabel(wsRoundOf(r))})' : ''}', // v91 p4
        '${toFaDigits('${r['start'] ?? ''}')} تا ${toFaDigits('${r['end'] ?? ''}')} = ${toFaDigits(wsHm(wsShiftMinutes('${r['start']}', '${r['end']}') ?? 0))}',
      ],
    <String>['جمع ساعات شیفت‌ها', toFaDigits(wsHm(t.minutes)), 'b'],
    <String>['جمع شیفت‌ها', '${faNum(t.count, dec: 0)} (${kWsShiftLabels.entries.map((MapEntry<String, String> e) => '${e.value} ${faNum(t.byShift[e.key] ?? 0, dec: 0)}').join('، ')})', 'b'],
  ];
}

class WsShiftsCard extends StatelessWidget {
  const WsShiftsCard({super.key, required this.shifts, required this.onSave, this.editable = true, this.hint, this.round = 0});
  final List<Map<String, dynamic>> shifts;
  final Future<void> Function(List<Map<String, dynamic>> shifts) onSave;
  final bool editable;
  final String? hint;

  /// v91 p4: دور جاری شکست (شکست مجدد نشکن)؛ شیفت تازه با همین دور ذخیره می‌شود، ویرایش دور شیفت را عوض نمی‌کند.
  final int round;

  Future<void> _edit(BuildContext context, [int? i]) async {
    final Map<String, dynamic>? r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ShiftDialog(row: i == null ? null : shifts[i], last: shifts.isEmpty ? null : shifts.last),
    );
    if (r == null) return;
    final List<Map<String, dynamic>> next = <Map<String, dynamic>>[...shifts];
    final int rd = i == null ? round : wsRoundOf(shifts[i]); // v91 p4
    if (rd > 0) r['round'] = rd;
    if (i == null) {
      next.add(r);
    } else {
      next[i] = r;
    }
    await onSave(next);
  }

  Future<void> _delete(BuildContext context, int i) async {
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: const Text('حذف شیفت؟'),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await onSave(<Map<String, dynamic>>[...shifts]..removeAt(i));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final WsShiftTotals t = wsShiftTotals(shifts);
    final Widget list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Row(children: <Widget>[
        Expanded(child: Text('شیفت‌های شکست', style: th.textTheme.titleMedium)),
        if (editable) TextButton.icon(onPressed: () => _edit(context), icon: const Icon(Icons.add_alarm), label: const Text('افزودن شیفت')),
      ]),
      if (hint != null) Text(hint!, style: TextStyle(fontSize: 12, color: th.hintColor)),
      if (shifts.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('هنوز شیفتی ثبت نشده (شیفت، تاریخ، اپراتور، ساعت شروع و پایان).')),
      for (int i = 0; i < shifts.length; i++)
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(shifts[i]['shift'] == 'night' ? Icons.nightlight_round : (shifts[i]['shift'] == 'evening' ? Icons.wb_twilight : Icons.wb_sunny_outlined)),
          title: Text('شیفت ${kWsShiftLabels['${shifts[i]['shift']}'] ?? ''}  •  ${jalaliDate('${shifts[i]['date'] ?? ''}')}'
              '${'${shifts[i]['operator'] ?? ''}'.isEmpty ? '' : '  •  ${shifts[i]['operator']}'}'
              '${wsRoundOf(shifts[i]) > 0 ? '  •  ${wsRoundLabel(wsRoundOf(shifts[i]))}' : ''}'), // v91 p4
          subtitle: Text('${toFaDigits('${shifts[i]['start'] ?? ''}')} تا ${toFaDigits('${shifts[i]['end'] ?? ''}')}  =  '
              '${toFaDigits(wsHm(wsShiftMinutes('${shifts[i]['start']}', '${shifts[i]['end']}') ?? 0))}'),
          onTap: editable ? () => _edit(context, i) : null,
          trailing: editable ? IconButton(tooltip: 'حذف', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(context, i)) : null,
        ),
    ]);
    final Widget totals = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: th.colorScheme.primaryContainer.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
        const Text('گزارش شیفت‌ها', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('جمع ساعات: ${toFaDigits(wsHm(t.minutes))}', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('جمع شیفت‌ها: ${faNum(t.count, dec: 0)}'),
        for (final MapEntry<String, String> e in kWsShiftLabels.entries) Text('  ${e.value}: ${faNum(t.byShift[e.key] ?? 0, dec: 0)}', style: TextStyle(color: th.hintColor)),
      ]),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (BuildContext c, BoxConstraints bc) => bc.maxWidth >= 620
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Expanded(child: list), const SizedBox(width: 12), SizedBox(width: 230, child: totals)])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[list, const SizedBox(height: 8), totals]),
        ),
      ),
    );
  }
}

class _ShiftDialog extends StatefulWidget {
  const _ShiftDialog({this.row, this.last});
  final Map<String, dynamic>? row;
  final Map<String, dynamic>? last;

  @override
  State<_ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends State<_ShiftDialog> {
  late String _shift = '${widget.row?['shift'] ?? _guess()}';
  late DateTime _date = DateTime.tryParse('${widget.row?['date'] ?? ''}') ?? DateTime.now();
  late final TextEditingController _op = TextEditingController(text: '${widget.row?['operator'] ?? widget.last?['operator'] ?? ''}');
  late final TextEditingController _start = TextEditingController(text: '${widget.row?['start'] ?? ''}');
  late final TextEditingController _end = TextEditingController(text: '${widget.row?['end'] ?? ''}');
  String? _err;

  static String _guess() {
    final int h = DateTime.now().hour;
    return h >= 6 && h < 14 ? 'morning' : (h >= 14 && h < 22 ? 'evening' : 'night');
  }

  @override
  void dispose() {
    _op.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Widget _clock(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: TextInputType.datetime,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: label,
          hintText: '08:00',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: 'ساعت',
            icon: const Icon(Icons.schedule),
            onPressed: () async {
              final String? v = await pickClock(context, c.text, help: label);
              if (v != null) setState(() => c.text = v);
            },
          ),
        ),
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final String s0 = toEnClock(_start.text), e0 = toEnClock(_end.text);
    final int? mins = wsShiftMinutes(s0, e0);
    return AlertDialog(
      title: Text(widget.row == null ? 'شیفت تازه' : 'ویرایش شیفت'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            SegmentedButton<String>(
              segments: <ButtonSegment<String>>[
                for (final MapEntry<String, String> e in kWsShiftLabels.entries) ButtonSegment<String>(value: e.key, label: Text(e.value)),
              ],
              selected: <String>{_shift},
              onSelectionChanged: (Set<String> v) => setState(() => _shift = v.first),
            ),
            const SizedBox(height: 10),
            JalaliDateField(label: 'تاریخ شیفت', value: _date, onChanged: (DateTime d) => setState(() => _date = d)),
            const SizedBox(height: 10),
            TextField(controller: _op, maxLength: 100, decoration: const InputDecoration(labelText: 'نام اپراتور', border: OutlineInputBorder())),
            Row(children: <Widget>[
              Expanded(child: _clock(_start, 'ساعت شروع')),
              const SizedBox(width: 8),
              Expanded(child: _clock(_end, 'ساعت پایان')),
            ]),
            const SizedBox(height: 8),
            Text(mins == null ? 'مدت شیفت: —' : 'مدت شیفت: ${toFaDigits(wsHm(mins))}${wsClockMin(e0)! < wsClockMin(s0)! ? ' (عبور از نیمه‌شب)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_err!, style: const TextStyle(color: Colors.red))),
          ]),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(
          onPressed: () {
            final String s = toEnClock(_start.text), e = toEnClock(_end.text);
            if (wsShiftMinutes(s, e) == null) return setState(() => _err = 'ساعت شروع و پایان را به شکل ۰۸:۰۰ وارد کنید');
            Navigator.pop(context, <String, dynamic>{
              'shift': _shift,
              'date': '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
              'operator': _op.text.trim(),
              'start': s,
              'end': e,
            });
          },
          child: const Text('ذخیره'),
        ),
      ],
    );
  }
}

/// ارقام فارسی ⇒ لاتین و «۸:۵» ⇒ «08:05».
String toEnClock(String s) {
  const String fa = '۰۱۲۳۴۵۶۷۸۹';
  final StringBuffer b = StringBuffer();
  for (final int r in s.trim().runes) {
    final String ch = String.fromCharCode(r);
    final int i = fa.indexOf(ch);
    b.write(i >= 0 ? '$i' : ch);
  }
  final RegExpMatch? m = RegExp(r'^(\d{1,2})[:.](\d{1,2})$').firstMatch(b.toString());
  if (m == null) return b.toString();
  return '${m.group(1)!.padLeft(2, '0')}:${m.group(2)!.padLeft(2, '0')}';
}
