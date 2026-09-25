import 'package:flutter/material.dart';

import 'db.dart';
import 'receipt_screen.dart';
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
                final id = sale['id'] as int;
                final items = sale['items'] as List;
                final net = (sale['net_weight'] as num).toDouble();
                final price = (sale['price'] as num).toDouble();
                final revenue = net * price;
                final total = (sale['total_weight'] as num).toDouble();
                final tare = total - net < 0 ? 0.0 : total - net;
                final small = (sale['small_sack_count'] as num).toDouble();
                final large = (sale['large_sack_count'] as num).toDouble();
                final sackCounts = (small + large) > 0
                    ? '  (${faNum(small)} کوچک / ${faNum(large)} بزرگ)'
                    : '';
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
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'edit') {
                                Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => SaleForm(editSaleId: id)));
                              } else if (v == 'del') {
                                if (await confirm(context,
                                    'این فروش حذف شود؟ وزن‌ها به انبار برمی‌گردند.')) {
                                  await AppDb.I.deleteSale(id);
                                }
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                              PopupMenuItem(value: 'del', child: Text('حذف')),
                            ],
                          ),
                        ]),
                        Text(comp),
                        const SizedBox(height: 8),
                        infoRow('وزن کل (با گونی)', '${faNum(total)} کیلو'),
                        infoRow('وزن گونی‌ها', '${faNum(tare)} کیلو$sackCounts'),
                        infoRow('وزن خالص پسته', '${faNum(net)} کیلو'),
                        infoRow('فی فروش', '${faNum(price, dec: 0)} تومان'),
                        infoRow('مبلغ فروش', '${faNum(revenue, dec: 0)} تومان'),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonalIcon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReceiptScreen(
                                  saleId: id,
                                  saleLabel: sale['buyer'] != null
                                      ? '${sale['buyer']}'
                                      : jalaliDate(sale['date'] as String),
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.request_quote_outlined),
                            label: const Text('وصول مطالبات'),
                          ),
                        ),
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
