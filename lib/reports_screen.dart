import 'package:flutter/material.dart';

import 'db.dart';
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
        ['وضعیت', 'نوع', isPayments ? 'خرید' : 'خریدار', 'تاریخ', 'مبلغ (تومان)'],
        for (final r in rows)
          [
            (r['paid'] as int) == 1 ? 'تسویه‌شده' : 'باقیمانده',
            r['kind'] as String,
            r['label'] as String,
            jalaliDate(r['date'] as String),
            faNum(r['amount'] as num, dec: 0),
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
            final list = s.data!;
            if (list.isEmpty) return const Center(child: Text('هنوز فروشی ثبت نشده'));

            double totalRevenue = 0, totalCost = 0;
            final rows = <Widget>[];
            for (final sale in list) {
              final items = sale['items'] as List;
              final net = (sale['net_weight'] as num).toDouble();
              final price = (sale['price'] as num).toDouble();
              final revenue = net * price;
              final cost = items.fold<double>(
                  0, (a, it) => a + (it['weight'] as num) * (it['cost_price'] as num));
              final profit = revenue - cost;
              totalRevenue += revenue;
              totalCost += cost;
              final comp = items
                  .map((it) => '${it['type_name']} ${faNum(it['weight'] as num)}')
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
                    ],
                  ),
                ),
              ));
            }

            final totalProfit = totalRevenue - totalCost;
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      infoRow('مجموع فروش', '${faNum(totalRevenue, dec: 0)} تومان'),
                      infoRow('مجموع بهای خرید', '${faNum(totalCost, dec: 0)} تومان'),
                      infoRow('مجموع سود / زیان', '${faNum(totalProfit, dec: 0)} تومان'),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      sectionTitle(context, 'خروجی PDF تراکنش‌ها'),
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
