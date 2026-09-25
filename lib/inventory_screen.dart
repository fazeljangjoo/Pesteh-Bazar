import 'package:flutter/material.dart';

import 'db.dart';
import 'mix_form.dart';
import 'pdf_service.dart';
import 'utils.dart';
import 'widgets.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  Future<void> _showMixDetails(BuildContext context, Map<String, dynamic> l) async {
    final sources = await AppDb.I.mixSourcesOf(l['id'] as int);
    final rem = (l['remaining'] as num).toDouble();
    final net = (l['net_weight'] as num).toDouble();
    final canUndo = rem >= net - 1e-6; // یعنی هنوز چیزی از این مخلوط فروخته نشده
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l['category_name']} - ${l['type_name']}',
                  style: Theme.of(ctx).textTheme.titleMedium),
                infoRow('کد پسته', l['code'] as String? ?? '-'),
              const SizedBox(height: 4),
              const Text('این جنس از ترکیب چند بار انبار ساخته شده:',
                  style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              for (final s in sources)
                Card(
                  child: ListTile(
                    dense: true,
                    title: Text('${s['category_name']} - ${s['type_name']}'),
                    subtitle: Text('${faNum(s['weight'] as num)} کیلو  •  '
                        '${jalaliDate(s['source_date'] as String)}'),
                  ),
                ),
              const SizedBox(height: 8),
              infoRow('وزن خالص این مخلوط', '${faNum(net)} کیلو'),
              infoRow('مانده فعلی', '${faNum(rem)} کیلو'),
              if (l['note'] != null && (l['note'] as String).isNotEmpty)
                infoRow('توضیحات', l['note'] as String),
              const SizedBox(height: 12),
              if (canUndo)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => MixForm(existing: l)));
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('ویرایش مخلوط'),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  final file = await PdfService.buildStockCard(
                    code: l['code'] as String? ?? '-',
                    totalWeight: (l['total_weight'] as num).toDouble(),
                    netWeight: net,
                    smallSacks: (l['small_sack_count'] as num).toDouble(),
                    largeSacks: (l['large_sack_count'] as num).toDouble(),
                  );
                  await PdfService.share(file);
                },
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('دریافت کارتکس A6'),
              ),
              if (canUndo)
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await confirm(ctx,
                        'این مخلوط حذف شود و وزن/گونیِ برداشته‌شده به بارهای مبدأ برگردد؟');
                    if (!ok) return;
                    final done = await AppDb.I.deleteMix(l['id'] as int);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      if (!done) {
                        snack(context, 'از این مخلوط فروش انجام شده؛ حذف امکان‌پذیر نیست');
                      }
                    }
                  },
                  icon: const Icon(Icons.undo),
                  label: const Text('حذف مخلوط و بازگرداندن به انبار'),
                )
              else
                const Text('چون بخشی از این مخلوط فروخته شده، دیگر قابل حذف نیست.',
                    style: TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('موجودی انبار')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const MixForm())),
        icon: const Icon(Icons.merge_type),
        label: const Text('ساخت مخلوط'),
      ),
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
              totalSmall += (l['small_left'] as num).toDouble();
              totalLarge += (l['large_left'] as num).toDouble();
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
                    0, (a, l) => a + (l['small_left'] as num) + (l['large_left'] as num));
                children.add(Card(
                  child: ExpansionTile(
                    title: Text(e.key),
                    subtitle: Text('${faNum(sum)} کیلو  •  ${faNum(e.value.length)} بار  •  ${faNum(sackSum)} گونی'),
                    children: [
                      for (final l in e.value)
                        ListTile(
                          dense: true,
                          onTap: (l['is_mix'] as int? ?? 0) == 1
                              ? () => _showMixDetails(context, l)
                              : null,
                          leading: (l['is_mix'] as int? ?? 0) == 1
                              ? const Tooltip(
                                  message: 'مخلوط (کوت‌ریزی) — از چند جنس ساخته شده',
                                  child: Icon(Icons.merge_type))
                              : null,
                          title: Text('${faNum(l['remaining'] as num)} کیلو مانده'
                              '${(l['is_mix'] as int? ?? 0) == 1 ? '  •  مخلوط' : ''}'),
                          subtitle: Text(
                              'خرید ${jalaliDate(l['date'] as String)}  •  فی ${faNum(l['price'] as num, dec: 0)}\n'
                              'گونی مانده: کوچک ${faNum(l['small_left'] as num)} / بزرگ ${faNum(l['large_left'] as num)}${l['sacks_estimated'] == true ? ' (تقریبی)' : ''}'
                              '${l['ounce'] != null ? '  •  انس ${faNum(l['ounce'] as num)}' : ''}'),
                          isThreeLine: true,
                        ),
                    ],
                  ),
                ));
              }
            }
            children.add(const SizedBox(height: 72));
            return ListView(padding: const EdgeInsets.all(12), children: children);
          },
        ),
      ),
    );
  }
}
