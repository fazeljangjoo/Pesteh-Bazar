import 'package:flutter/material.dart';

import 'db.dart';
import 'utils.dart';
import 'widgets.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('موجودی انبار')),
      body: ValueListenableBuilder<int>(
        valueListenable: AppDb.I.version,
        builder: (_, __, ___) => FutureBuilder<List<Map<String, dynamic>>>(
          future: AppDb.I.lots(),
          builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final lots = s.data!;
            if (lots.isEmpty) return const Center(child: Text('انبار خالی است'));

            // دسته -> نوع -> بارها
            final Map<String, Map<String, List<Map<String, dynamic>>>> g = {};
            double totalKg = 0, totalValue = 0, totalSmall = 0, totalLarge = 0;
            for (final l in lots) {
              final rem = (l['remaining'] as num).toDouble();
              totalKg += rem;
              totalValue += rem * (l['price'] as num).toDouble();
              totalSmall += (l['small_sack_count'] as num).toDouble();
              totalLarge += (l['large_sack_count'] as num).toDouble();
              g
                  .putIfAbsent(l['category_name'] as String, () => {})
                  .putIfAbsent(l['type_name'] as String, () => [])
                  .add(l);
            }

            final children = <Widget>[
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    infoRow('مجموع موجودی', '${faNum(totalKg)} کیلو'),
                    infoRow('ارزش خرید موجودی', '${faNum(totalValue, dec: 0)} تومان'),
                    infoRow('تعداد گونی کل', '${faNum(totalSmall + totalLarge)} عدد'),
                    infoRow('گونی کوچک / بزرگ', '${faNum(totalSmall)} / ${faNum(totalLarge)}'),
                  ]),
                ),
              ),
            ];

            for (final catEntry in g.entries) {
              children.add(sectionTitle(context, catEntry.key));
              for (final e in catEntry.value.entries) {
                final sum = e.value.fold<double>(0, (a, l) => a + (l['remaining'] as num).toDouble());
                final sackSum = e.value.fold<double>(
                    0, (a, l) => a + (l['small_sack_count'] as num) + (l['large_sack_count'] as num));
                children.add(Card(
                  child: ExpansionTile(
                    title: Text(e.key),
                    subtitle: Text('${faNum(sum)} کیلو  •  ${faNum(e.value.length)} بار  •  ${faNum(sackSum)} گونی'),
                    children: [
                      for (final l in e.value)
                        ListTile(
                          dense: true,
                          title: Text('${faNum(l['remaining'] as num)} کیلو مانده'),
                          subtitle: Text(
                              'خرید ${jalaliDate(l['date'] as String)}  •  فی ${faNum(l['price'] as num, dec: 0)}\n'
                              'گونی کوچک ${faNum(l['small_sack_count'] as num)} / بزرگ ${faNum(l['large_sack_count'] as num)}'
                              '${l['ounce'] != null ? '  •  انس ${faNum(l['ounce'] as num)}' : ''}'),
                          isThreeLine: true,
                        ),
                    ],
                  ),
                ));
              }
            }
            return ListView(padding: const EdgeInsets.all(12), children: children);
          },
        ),
      ),
    );
  }
}
