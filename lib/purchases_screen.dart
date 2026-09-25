import 'dart:io';

import 'package:flutter/material.dart';

import 'db.dart';
import 'payment_screen.dart';
import 'pdf_service.dart';
import 'purchase_form.dart';
import 'utils.dart';
import 'widgets.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  String _query = '';

  void _details(BuildContext context, Map<String, dynamic> p) {
    String? pct(String k) => p[k] == null ? null : '${faNum(p[k] as num)}٪';
    final preset = p['category_preset'] as String?;
    final customSpecs = AppDb.decodeCustomSpecs(p['custom_specs'] as String?);
    final rows = <List<String>>[
      ['تاریخ', jalaliDate(p['date'] as String)],
      if (p['seller'] != null) ['فروشنده', p['seller']],
      if (p['ounce'] != null) ['انس', faNum(p['ounce'] as num)],
      ['فی خرید', '${faNum(p['price'] as num, dec: 0)} تومان'],
      ['وزن کل', '${faNum(p['total_weight'] as num)} کیلو'],
      ['گونی کوچک (۱۰۰گ) / بزرگ (۲۰۰گ)',
          '${faNum(p['small_sack_count'] as num)} / ${faNum(p['large_sack_count'] as num)}'],
      ['وزن خالص', '${faNum(p['net_weight'] as num)} کیلو'],
      ['مانده در انبار', '${faNum(p['remaining'] as num)} کیلو'],
      if (preset == 'dombest' && p['gram'] != null) ['گرم', faNum(p['gram'] as num)],
      if (preset == 'dombest' && pct('pct_khandan') != null) ['درصد خندان در دنبست', pct('pct_khandan')!],
      if (preset == 'khandan' && pct('pct_dombest') != null) ['درصد دنبست در خندان', pct('pct_dombest')!],
      if (preset == 'khandan' && pct('pct_tuchin') != null) ['درصد توچین', pct('pct_tuchin')!],
      if ((preset == 'dombest' || preset == 'khandan') && pct('pct_crooked') != null)
        ['درصد کج / ناخالص', pct('pct_crooked')!],
      for (final s in customSpecs) [s['label'] ?? '', s['value'] ?? ''],
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
              Text('${p['category_name']} - ${p['type_name']}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
                    infoRow('کد پسته', p['code'] as String? ?? '-'),
              if (p['photo'] != null && File(p['photo']).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(p['photo']),
                      height: 180, width: double.infinity, fit: BoxFit.cover),
                ),
              const SizedBox(height: 8),
              for (final r in rows) infoRow(r[0], r[1]),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PaymentScreen(
                        purchaseId: p['id'] as int,
                        purchaseLabel: '${p['category_name']} - ${p['type_name']}',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.payments_outlined),
                label: const Text('مدیریت پرداخت'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final file = await PdfService.buildStockCard(
                    code: p['code'] as String? ?? '-',
                    totalWeight: (p['total_weight'] as num).toDouble(),
                    netWeight: (p['net_weight'] as num).toDouble(),
                    smallSacks: (p['small_sack_count'] as num).toDouble(),
                    largeSacks: (p['large_sack_count'] as num).toDouble(),
                  );
                  await PdfService.share(file);
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('دریافت کارتکس A6'),
              ),
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
            final all = s.data!;
            final q = _query.trim().toLowerCase();
            final list = q.isEmpty
                ? all
                : all.where((p) => '${p['code']} ${p['category_name']} ${p['type_name']}'
                    .toLowerCase().contains(q)).toList();
            if (list.isEmpty) {
              return Center(child: Text(all.isEmpty ? 'هنوز خریدی ثبت نشده' : 'نتیجه‌ای پیدا نشد'));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              itemCount: list.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'جستجو با کد، دسته یا نوع',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  );
                }
                final p = list[i - 1];
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
                    title: Text('${p['category_name']} - ${p['type_name']}'),
                    subtitle: Text(
                      'کد ${p['code'] ?? '-'}  •  ${jalaliDate(p['date'] as String)}  •  ${faNum(p['net_weight'] as num)} کیلو خالص\n'
                        'فی ${faNum(p['price'] as num, dec: 0)} تومان'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          Navigator.push(context,
                              MaterialPageRoute(builder: (_) => PurchaseForm(existing: p)));
                        } else if (v == 'del' && await confirm(context, 'این خرید حذف شود؟')) {
                          final ok = await AppDb.I.deletePurchase(p['id'] as int);
                          if (!ok && context.mounted) {
                            snack(context, 'از این خرید فروش انجام شده؛ ابتدا فروش را حذف کنید');
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('ویرایش')),
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
