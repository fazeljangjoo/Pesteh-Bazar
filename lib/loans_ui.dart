import 'package:flutter/material.dart';

import 'charts.dart';
import 'db.dart';
import 'ledger.dart';
import 'utils.dart';
import 'widgets.dart';

// ============================================================================
// کارت «گردش واریزی و برداشت» (نمودار میله‌ای در بازهٔ تاریخِ انتخابی)
// ============================================================================
class CashFlowCard extends StatefulWidget {
  /// اگر مقدار داشته باشد فقط همان طرف‌حساب نمایش داده می‌شود
  final String? partyKeyFilter;
  const CashFlowCard({super.key, this.partyKeyFilter});

  @override
  State<CashFlowCard> createState() => _CashFlowCardState();
}

class _CashFlowCardState extends State<CashFlowCard> {
  late DateTime _from;
  late DateTime _to;
  bool _withLoans = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final j = gregorianToJalali(now.year, now.month, now.day);
    _from = jalaliToGregorian(j[0], j[1], 1);
    _to = jalaliToGregorian(j[0], j[1], daysInJalaliMonth(j[0], j[1]));
  }

  @override
  Widget build(BuildContext context) {
    return ChartCard(
      title: 'گردش واریزی و برداشت',
      subtitle: 'فقط تراکنش‌های انجام‌شده • از ${jalaliDateFromDt(_from)} تا ${jalaliDateFromDt(_to)}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final d = await pickDate(context, initial: _from);
                if (d != null) setState(() => _from = d);
              },
              child: Text('از: ${jalaliDateFromDt(_from)}'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final d = await pickDate(context, initial: _to);
                if (d != null) setState(() => _to = d);
              },
              child: Text('تا: ${jalaliDateFromDt(_to)}'),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilterChip(
            label: const Text('با احتساب قرض و وام'),
            selected: _withLoans,
            onSelected: (v) => setState(() => _withLoans = v),
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<CashFlow>>(
          future: _to.isBefore(_from)
              ? Future.value(<CashFlow>[])
              : loadCashFlows(
                  from: _from, to: _to, partyKeyFilter: widget.partyKeyFilter, includeLoans: _withLoans),
          builder: (context, snap) {
            if (snap.hasError) return ChartEmpty('خطا در بارگذاری: ${snap.error}');
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (_to.isBefore(_from)) return const ChartEmpty('تاریخ «تا» باید بعد از «از» باشد');
            final rows = snap.data!;
            final buckets = buildBuckets(_from, _to);
            final ins = List<double>.filled(buckets.length, 0);
            final outs = List<double>.filled(buckets.length, 0);
            double totalIn = 0, totalOut = 0;
            for (final r in rows) {
              if (r.isIn) {
                totalIn += r.amount;
              } else {
                totalOut += r.amount;
              }
              for (var i = 0; i < buckets.length; i++) {
                if (buckets[i].contains(r.date)) {
                  if (r.isIn) {
                    ins[i] += r.amount;
                  } else {
                    outs[i] += r.amount;
                  }
                  break;
                }
              }
            }
            if (rows.isEmpty) return const ChartEmpty('در این بازه تراکنشی انجام نشده');
            final net = totalIn - totalOut;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GroupedBarChart(
                groups: [
                  for (var i = 0; i < buckets.length; i++)
                    BarGroup(buckets[i].label, buckets[i].fullLabel, [ins[i], outs[i]]),
                ],
                series: const [
                  BarSeries('واریزی', kGainColor),
                  BarSeries('برداشت', Color(0xFFD9822B)),
                ],
                format: (v) => '${faCompact(v)} تومان',
              ),
              const SizedBox(height: 12),
              Row(children: [
                MiniStat(label: 'جمع واریزی', value: faCompact(totalIn), color: kGainColor),
                MiniStat(label: 'جمع برداشت', value: faCompact(totalOut), color: const Color(0xFFD9822B)),
                MiniStat(label: 'خالص', value: faCompact(net), color: net >= 0 ? kGainColor : kLossColor),
              ]),
            ]);
          },
        ),
      ]),
    );
  }
}

// ============================================================================
// ثبت قرض / بازپرداخت
// ============================================================================
Future<void> showLoanSheet(BuildContext context, {required String party, required String kind}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LoanSheet(party: party, kind: kind),
  );
}

class _LoanSheet extends StatefulWidget {
  final String party;
  final String kind;
  const _LoanSheet({required this.party, required this.kind});
  @override
  State<_LoanSheet> createState() => _LoanSheetState();
}

class _LoanSheetState extends State<_LoanSheet> with EditGuard<_LoanSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  late String _kind;
  bool _busy = false;

  bool get _isRepay => widget.kind == 'repay_in' || widget.kind == 'repay_out';

  @override
  void initState() {
    super.initState();
    _kind = widget.kind;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _title => _isRepay ? 'ثبت بازپرداخت' : (_kind == 'given' ? 'اعطای قرض' : 'دریافت قرض');

  String get _hint => switch (_kind) {
        'given' => 'پولی که به ${widget.party} قرض می‌دهید',
        'taken' => 'پولی که از ${widget.party} قرض می‌گیرید',
        'repay_in' => 'پولی که ${widget.party} به شما پس می‌دهد',
        _ => 'پولی که شما به ${widget.party} پس می‌دهید',
      };

  Future<void> _save() async {
    final amt = parseNum(_amount.text) ?? 0;
    if (amt <= 0) {
      snack(context, 'مبلغ را وارد کنید');
      return;
    }
    setState(() => _busy = true);
    final note = _note.text.trim();
    final ok = await saveConfirmed(
      context,
      () => AppDb.I.addLoanEntry(
        party: widget.party,
        kind: _kind,
        amount: amt,
        date: _date,
        note: note.isEmpty ? null : note,
      ),
      successMsg: '${kLoanKindLabel[_kind]} با موفقیت ثبت شد',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(widget.party, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            if (_isRepay) ...[
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'repay_in', label: Text('او به ما پس داد')),
                  ButtonSegment<String>(value: 'repay_out', label: Text('ما به او پس دادیم')),
                ],
                selected: <String>{_kind},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
              const SizedBox(height: 12),
            ],
            numField(_amount, 'مبلغ (تومان)', required: true, thousands: true, hint: _hint),
            dateField(context, 'تاریخ', _date, (d) => setState(() => _date = d)),
            textField(_note, 'توضیحات (اختیاری)'),
            const Text('این مبلغ در سود و زیان حساب نمی‌شود.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('ثبت'),
            ),
          ]),
        ),
      ),
    );
  }
}

// ============================================================================
// تعریف طرف‌حساب جدید
// ============================================================================
Future<void> showNewPartyDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _NewPartyDialog());
}

class _NewPartyDialog extends StatefulWidget {
  const _NewPartyDialog();
  @override
  State<_NewPartyDialog> createState() => _NewPartyDialogState();
}

class _NewPartyDialogState extends State<_NewPartyDialog> with EditGuard<_NewPartyDialog> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      snack(context, 'نام طرف‌حساب را وارد کنید');
      return;
    }
    setState(() => _busy = true);
    final name = _name.text.trim();
    final ok = await saveConfirmed(context, () => AppDb.I.addParty(name),
        successMsg: 'طرف‌حساب «$name» با موفقیت تعریف شد');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('طرف‌حساب جدید'),
      content: TextField(
        controller: _name,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'نام طرف‌حساب', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('تعریف')),
      ],
    );
  }
}
