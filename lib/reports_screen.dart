import 'package:flutter/material.dart';

import 'db.dart';
import 'utils.dart';
import 'widgets.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

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
