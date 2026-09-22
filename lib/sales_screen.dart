import 'package:flutter/material.dart';

import 'db.dart';
import 'sale_form.dart';
import 'utils.dart';
import 'widgets.dart';

class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فروش')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SaleForm())),
        icon: const Icon(Icons.add),
        label: const Text('فروش جدید'),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: AppDb.I.version,
        builder: (_, __, ___) => FutureBuilder<List<Map<String, dynamic>>>(
          future: AppDb.I.sales(),
          builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final list = s.data!;
            if (list.isEmpty) return const Center(child: Text('هنوز فروشی ثبت نشده'));
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final sale = list[i];
                final items = sale['items'] as List;
                final net = (sale['net_weight'] as num).toDouble();
                final price = (sale['price'] as num).toDouble();
                final revenue = net * price;
                final comp = items
                    .map((it) => '${it['type_name']} ${faNum(it['weight'] as num)}')
                    .join(' + ');
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              '${jalaliDate(sale['date'] as String)}'
                              '${sale['buyer'] != null ? '  •  ${sale['buyer']}' : ''}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (await confirm(context,
                                  'این فروش حذف شود؟ وزن‌ها به انبار برمی‌گردند.')) {
                                await AppDb.I.deleteSale(sale['id'] as int);
                              }
                            },
                          ),
                        ]),
                        Text(comp),
                        const SizedBox(height: 8),
                        infoRow('وزن کل / خالص',
                            '${faNum(sale['total_weight'] as num)} / ${faNum(net)} کیلو'),
                        infoRow('گونی کوچک / بزرگ',
                            '${faNum(sale['small_sack_count'] as num)} / ${faNum(sale['large_sack_count'] as num)}'),
                        infoRow('فی فروش', '${faNum(price, dec: 0)} تومان'),
                        infoRow('مبلغ فروش', '${faNum(revenue, dec: 0)} تومان'),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
