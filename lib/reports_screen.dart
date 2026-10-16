import 'package:flutter/material.dart';

import 'charts.dart';
import 'db.dart';
import 'license_service.dart';
import 'pdf_service.dart';
import 'utils.dart';
import 'widgets.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime? _from;
  DateTime? _to;
  String _q = ''; // جستجوی کد پسته در گزارش سود
  int _chartMode = 0; // 0 = میله‌ای (سود در طول زمان) | 1 = کروی (سهم هر نوع پسته از سود)

  /// بازهٔ مؤثر گزارش سود: اگر کاربر تاریخی انتخاب نکرده باشد، ماه جاری شمسی
  (DateTime?, DateTime?) _effectiveRange() {
    if (_from != null || _to != null) return (_from, _to);
    final now = DateTime.now();
    final j = gregorianToJalali(now.year, now.month, now.day);
    return (jalaliToGregorian(j[0], j[1], 1), jalaliToGregorian(j[0], j[1], daysInJalaliMonth(j[0], j[1])));
  }

  String _profitPeriodLabel() {
    final r = _effectiveRange();
    final f = r.$1 == null ? '...' : jalaliDateFromDt(r.$1!);
    final t = r.$2 == null ? '...' : jalaliDateFromDt(r.$2!);
    return '${(_from == null && _to == null) ? 'ماه جاری' : 'بازهٔ انتخابی'}: از $f تا $t';
  }

  String _periodLabel() {
    if (_from == null && _to == null) return 'همه‌ی بازه‌ها';
    final f = _from == null ? '...' : jalaliDateFromDt(_from!);
    final t = _to == null ? '...' : jalaliDateFromDt(_to!);
    return 'از $f تا $t';
  }

  Future<void> _exportGlobal({required bool isPayments}) async {
    try {
      final rows = isPayments
          ? await AppDb.I.allPaymentTransactions(from: _from, to: _to)
          : await AppDb.I.allReceiptTransactions(from: _from, to: _to);
      final total = rows.fold<double>(0, (s, r) => s + (r['amount'] as num).toDouble());
      final table = <List<String>>[
        ['وضعیت', 'نوع', 'کد پسته', 'تاریخ', 'مبلغ (تومان)', isPayments ? 'فروشنده' : 'خریدار'],
        for (final r in rows)
          [
            (r['paid'] as int) == 1 ? 'تسویه‌شده' : 'باقیمانده',
            r['kind'] as String,
            '${r['code'] ?? '-'}',
            jalaliDate(r['date'] as String),
            faNum(r['amount'] as num, dec: 0),
            '${r['name'] ?? '-'}',
          ],
      ];
      final file = await PdfService.buildGlobalReport(
        title: isPayments ? 'گزارش کلی تراکنش‌های پرداخت' : 'گزارش کلی تراکنش‌های دریافت وجه',
        periodLabel: _periodLabel(),
        grandTotal: total,
        tableRows: table,
      );
      await PdfService.share(file);
    } catch (e) {
      if (mounted) snack(context, 'خطا در ساخت PDF: $e');
    }
  }

  /// کارت نمودار سود و زیان: یک نمودار در هر لحظه (میله‌ای یا کروی) تا شلوغ نشود
  Widget _chartCard(BuildContext context, List<TimeBucket> buckets, List<double> bucketProfit,
      Map<String, double> byType) {
    final groups = <BarGroup>[
      for (var i = 0; i < buckets.length; i++) BarGroup(buckets[i].label, buckets[i].fullLabel, [bucketProfit[i]]),
    ];
    final hasBarData = bucketProfit.any((v) => v != 0);
    final positive = <String, double>{
      for (final e in byType.entries)
        if (e.value > 0) e.key: e.value,
    };
    final losers = byType.entries.where((e) => e.value < 0).toList()..sort((a, b) => a.value.compareTo(b.value));
    final Widget body;
    if (_chartMode == 0) {
      body = hasBarData
          ? GroupedBarChart(
              groups: groups,
              series: const [BarSeries('سود / زیان', kGainColor, negativeColor: kLossColor)],
              format: (v) => '${faCompact(v)} تومان',
            )
          : const ChartEmpty('در این بازه سود یا زیانی ثبت نشده');
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (positive.isEmpty)
          const ChartEmpty('در این بازه نوعی سود نکرده است')
        else
          Center(
            child: DonutChart(
              slices: topSlices(positive),
              centerTitle: 'جمع سود انواع سودده',
              format: (v) => faCompact(v),
            ),
          ),
        if (losers.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final e in losers.take(3))
            Text('زیان‌ده: ${e.key}  ${faCompact(e.value)} تومان',
                style: const TextStyle(color: kLossColor, fontSize: 12.5)),
        ],
      ]);
    }
    return ChartCard(
      title: 'نمودار سود و زیان',
      subtitle: _profitPeriodLabel(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<int>(
          segments: const <ButtonSegment<int>>[
            ButtonSegment<int>(value: 0, label: Text('میله‌ای'), icon: Icon(Icons.bar_chart)),
            ButtonSegment<int>(value: 1, label: Text('کروی'), icon: Icon(Icons.donut_large)),
          ],
          selected: <int>{_chartMode},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _chartMode = v.first),
        ),
        const SizedBox(height: 14),
        body,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش سود و زیان')),
      body: ValueListenableBuilder<int>(
        valueListenable: AppDb.I.version,
        builder: (_, __, ___) => FutureBuilder<List<Map<String, dynamic>>>(
          future: AppDb.I.sales(),
          builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final scheme = Theme.of(context).colorScheme;
            final all = s.data!;
            if (all.isEmpty) return const Center(child: Text('هنوز فروشی ثبت نشده'));
            final range = _effectiveRange();
            final q = toEnDigits(_q).trim().toLowerCase();
            final list = all.where((sale) {
              final dt = DateTime.parse(sale['date'] as String);
              if (range.$1 != null && dt.isBefore(range.$1!)) return false;
              if (range.$2 != null && !dt.isBefore(range.$2!.add(const Duration(days: 1)))) return false;
              if (q.isNotEmpty) {
                final codes = (sale['items'] as List).map((it) => '${it['code'] ?? ''}'.toLowerCase());
                if (!codes.any((c) => c.contains(q))) return false;
              }
              return true;
            }).toList();

            double totalRevenue = 0, totalCost = 0;
            final fx = LicenseService.I.isFx.value;
            double usdRevenue = 0, usdCost = 0;
            var usdMissing = 0; // فروش‌هایی که سود دلاری‌شان قابل محاسبه نیست
            final Map<String, double> byType = {}; // "دسته - نوع" -> سود
            final rows = <Widget>[];
            for (final sale in list) {
              final items = sale['items'] as List;
              for (final it in items) {
                final key = '${it['category_name']} - ${it['type_name']}';
                final w = (it['weight'] as num).toDouble();
                final rev = w * (sale['price'] as num).toDouble();
                final cost = w * (it['cost_price'] as num).toDouble();
                byType[key] = (byType[key] ?? 0) + (rev - cost);
              }
              final net = (sale['net_weight'] as num).toDouble();
              final price = (sale['price'] as num).toDouble();
              final revenue = net * price;
              final cost = items.fold<double>(
                  0, (a, it) => a + (it['weight'] as num) * (it['cost_price'] as num));
              final profit = revenue - cost;
              totalRevenue += revenue;
              totalCost += cost;
              final usd = fx ? saleUsd(sale) : null;
              if (fx) {
                if (usd == null) {
                  usdMissing++;
                } else {
                  usdRevenue += usd.revenue;
                  usdCost += usd.cost;
                }
              }
              final comp = items
                  .map((it) => '${it['type_name']}${it['code'] != null ? ' (کد ${it['code']})' : ''} ${faNum(it['weight'] as num)}')
                  .join(' + ');
              rows.add(Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${jalaliDate(sale['date'] as String)}'
                        '${sale['buyer'] != null ? '  •  ${sale['buyer']}' : ''}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(comp),
                      const SizedBox(height: 8),
                      infoRow('مبلغ فروش', '${faNum(revenue, dec: 0)} تومان'),
                      infoRow('بهای خرید', '${faNum(cost, dec: 0)} تومان'),
                      infoRow('سود / زیان', '${faNum(profit, dec: 0)} تومان'),
                      if (fx && usd != null) ...[
                        infoRow('مبلغ فروش (دلار)', faUsd(usd.revenue)),
                        infoRow('بهای خرید (دلار)', faUsd(usd.cost)),
                        infoRow('سود / زیان دلاری', faUsd(usd.profit),
                            valueColor: usd.profit >= 0 ? Colors.green.shade800 : scheme.error),
                      ] else if (fx)
                        const Text('سود دلاری: قیمت دلار یا فی دلاریِ خرید ثبت نشده',
                            style: TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
              ));
            }

            final totalProfit = totalRevenue - totalCost;

            // ---- داده‌ی نمودار: سود هر روز (بازه تا ۳۱ روز) یا هر ماه شمسی ----
            DateTime? cFrom = range.$1;
            DateTime? cTo = range.$2;
            if (list.isNotEmpty) {
              DateTime dtOf(Map<String, dynamic> x) => DateTime.parse(x['date'] as String);
              cFrom ??= list.map(dtOf).reduce((a, b) => a.isBefore(b) ? a : b);
              cTo ??= list.map(dtOf).reduce((a, b) => a.isAfter(b) ? a : b);
            }
            final buckets = (cFrom != null && cTo != null) ? buildBuckets(cFrom, cTo) : <TimeBucket>[];
            final bucketProfit = List<double>.filled(buckets.length, 0);
            for (final sale in list) {
              final dt = DateTime.parse(sale['date'] as String);
              final its = sale['items'] as List;
              final rev = (sale['net_weight'] as num).toDouble() * (sale['price'] as num).toDouble();
              final cst = its.fold<double>(0, (a, it) => a + (it['weight'] as num) * (it['cost_price'] as num));
              for (var i = 0; i < buckets.length; i++) {
                if (buckets[i].contains(dt)) {
                  bucketProfit[i] += rev - cst;
                  break;
                }
              }
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_profitPeriodLabel(), style: Theme.of(context).textTheme.bodySmall),
                ),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'جستجو با کد پسته (مثلاً KH00012)',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      infoRow('مجموع فروش', '${faNum(totalRevenue, dec: 0)} تومان'),
                      infoRow('مجموع بهای خرید', '${faNum(totalCost, dec: 0)} تومان'),
                      infoRow('مجموع سود / زیان', '${faNum(totalProfit, dec: 0)} تومان'),
                      if (fx) ...[
                        const Divider(),
                        infoRow('مجموع فروش (دلار)', faUsd(usdRevenue)),
                        infoRow('مجموع بهای خرید (دلار)', faUsd(usdCost)),
                        infoRow('مجموع سود / زیان دلاری', faUsd(usdRevenue - usdCost),
                            valueColor: (usdRevenue - usdCost) >= 0 ? Colors.green.shade800 : scheme.error),
                        if (usdMissing > 0)
                          Text('${faNum(usdMissing, dec: 0)} فروش به‌دلیل نبودنِ قیمت دلار یا فی دلاریِ خرید در جمع دلاری نیامده است',
                              style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                _chartCard(context, buckets, bucketProfit, byType),
                if (byType.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        sectionTitle(context, 'سود به تفکیک نوع پسته (بازهٔ انتخاب‌شده)'),
                        for (final e in (byType.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value))))
                          infoRow(e.key, '${faNum(e.value, dec: 0)} تومان',
                              valueColor: e.value >= 0 ? Colors.green.shade800 : scheme.error),
                      ]),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      sectionTitle(context, 'بازهٔ گزارش و خروجی PDF تراکنش‌ها'),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final d = await pickDate(context, initial: _from ?? DateTime.now());
                              if (d != null) setState(() => _from = d);
                            },
                            child: Text('از: ${_from == null ? '—' : jalaliDateFromDt(_from!)}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final d = await pickDate(context, initial: _to ?? DateTime.now());
                              if (d != null) setState(() => _to = d);
                            },
                            child: Text('تا: ${_to == null ? '—' : jalaliDateFromDt(_to!)}'),
                          ),
                        ),
                        if (_from != null || _to != null)
                          IconButton(
                            onPressed: () => setState(() {
                              _from = null;
                              _to = null;
                            }),
                            icon: const Icon(Icons.close),
                            tooltip: 'حذف فیلتر بازه',
                          ),
                      ]),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: () => _exportGlobal(isPayments: true),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('گزارش کلی تراکنش‌های پرداخت (خرید)'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: () => _exportGlobal(isPayments: false),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('گزارش کلی تراکنش‌های دریافت (فروش)'),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                ...rows,
              ],
            );
          },
        ),
      ),
    );
  }
}
