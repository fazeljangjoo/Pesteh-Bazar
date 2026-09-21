import 'dart:io';

import 'package:flutter/material.dart';

import 'db.dart';
import 'purchase_form.dart';
import 'utils.dart';
import 'widgets.dart';

class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});

  void _details(BuildContext context, Map<String, dynamic> p) {
    String? pct(String k) => p[k] == null ? null : '${faNum(p[k] as num)}٪';
    final rows = <List<String>>[
      ['تاریخ', jalaliDate(p['date'])],
      if (p['seller'] != null) ['فروشنده', p['seller']],
      if (p['ounce'] != null) ['انس', faNum(p['ounce'] as num)],
      ['فی خرید', '${faNum(p['price'] as num, dec: 0)} تومان'],
      ['وزن کل', '${faNum(p['total_weight'] as num)} کیلو'],
      ['گونی', '${faNum(p['sack_count'] as num)} عدد × ${faNum(p['sack_weight'] as num)} کیلو'],
      ['وزن خالص', '${faNum(p['net_weight'] as num)} کیلو'],
      ['مانده در انبار', '${faNum(p['remaining'] as num)} کیلو'],
      if (p['gram'] != null) ['گرم', faNum(p['gram'] as num)],
      if (pct('pct_khandan') != null) ['درصد خندان در دنبست', pct('pct_khandan')!],
      if (pct('pct_dombest') != null) ['درصد دنبست در خندان', pct('pct_dombest')!],
      if (pct('pct_tuchin') != null) ['درصد توچین', pct('pct_tuchin')!],
      if (pct('pct_crooked') != null) ['درصد کج / ناخالص', pct('pct_crooked')!],
      if (p['note'] != null) ['توضیحات', p['note']],
    ];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${kCategories[p['category']]} - ${p['type_name']}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (p['photo'] != null && File(p['photo']).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(p['photo']),
                      height: 180, width: double.infinity, fit: BoxFit.cover),
                ),
              const SizedBox(height: 8),
              for (final r in rows) infoRow(r[0], r[1]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('خرید')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const PurchaseForm())),
        icon: const Icon(Icons.add),
        label: const Text('خرید جدید'),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: AppDb.I.version,
        builder: (_, __, ___) => FutureBuilder<List<Map<String, dynamic>>>(
          future: AppDb.I.purchases(),
          builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final list = s.data!;
            if (list.isEmpty) {
              return const Center(child: Text('هنوز خریدی ثبت نشده'));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final p = list[i];
                final photo = p['photo'] as String?;
                return Card(
                  child: ListTile(
                    onTap: () => _details(context, p),
                    leading: (photo != null && File(photo).existsSync())
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(File(photo), width: 52, height: 52, fit: BoxFit.cover),
                          )
                        : const CircleAvatar(child: Icon(Icons.grass)),
                    title: Text('${kCategories[p['category']]} - ${p['type_name']}'),
                    subtitle: Text(
                        '${jalaliDate(p['date'])}  •  ${faNum(p['net_weight'] as num)} کیلو خالص\n'
                        'فی ${faNum(p['price'] as num, dec: 0)} تومان'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'del' && await confirm(context, 'این خرید حذف شود؟')) {
                          final ok = await AppDb.I.deletePurchase(p['id'] as int);
                          if (!ok && context.mounted) {
                            snack(context, 'از این خرید فروش انجام شده؛ ابتدا فروش را حذف کنید');
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'del', child: Text('حذف')),
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
