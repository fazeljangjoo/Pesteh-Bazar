import 'package:flutter/material.dart';

import 'db.dart';
import 'mix_form.dart';
import 'pdf_service.dart';
import 'utils.dart';
import 'widgets.dart';

/// یکسان‌سازی «ي/ك» عربی و «ی/ک» فارسی برای جستجو
String _norm(String s) => toEnDigits(s.replaceAll('ي', 'ی').replaceAll('ك', 'ک')).trim().toLowerCase();

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _query = '';
  bool _showSold = false; // false = موجود | true = فروش رفته (مثل وب)

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
              infoRow('گونی مانده: کوچک / بزرگ',
                  '${faNum((l['small_left'] as num?) ?? 0)} / ${faNum((l['large_left'] as num?) ?? 0)}'),
              if (l['ounce'] != null) infoRow('انس', faNum(l['ounce'] as num)),
              if (l['gram'] != null) infoRow('گرم', faNum(l['gram'] as num)),
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
          future: AppDb.I.inventoryAll(),
          builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final all = s.data!;
            if (all.isEmpty) return const Center(child: Text('انبار خالی است'));

            // «موجود» مثل وب: هنوز وزنی از خودش مانده، یا مقداری از آن داخل مخلوطِ فروش‌نرفته است
            final available = all.where(AppDb.isAvailable).toList();
            final soldOut = all.where((p) => !AppDb.isAvailable(p)).toList();
            final q = _norm(_query);
            bool match(Map<String, dynamic> p) =>
                q.isEmpty ||
                _norm('${p['code']} ${p['category_name']} ${p['type_name']}').contains(q);
            final base = _showSold ? soldOut : available;
            final other = _showSold ? available : soldOut;
            final lots = base.where(match).toList();

            final children = <Widget>[
              SegmentedButton<bool>(
                segments: <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                      value: false, label: Text('موجود (${faNum(available.length, dec: 0)})')),
                  ButtonSegment<bool>(
                      value: true, label: Text('فروش رفته (${faNum(soldOut.length, dec: 0)})')),
                ],
                selected: <bool>{_showSold},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _showSold = v.first),
              ),
              const SizedBox(height: 8),
            ];

            if (!_showSold) {
              double totalKg = 0, totalValue = 0, totalSmall = 0, totalLarge = 0;
              for (final l in available) {
                final rem = (l['remaining'] as num).toDouble();
                totalKg += rem;
                totalValue += rem * (l['price'] as num).toDouble();
                totalSmall += (l['small_left'] as num).toDouble();
                totalLarge += (l['large_left'] as num).toDouble();
              }
              children.add(Card(
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
              ));
            } else {
              double soldKg = 0, soldValue = 0;
              for (final p in soldOut) {
                final w = (p['net_weight'] as num).toDouble();
                soldKg += w;
                soldValue += w * (p['price'] as num).toDouble();
              }
              children.add(Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    infoRow('تعداد خریدهای فروش‌رفته', '${faNum(soldOut.length, dec: 0)} بار'),
                    infoRow('مجموع وزن فروش‌رفته', '${faNum(soldKg)} کیلو'),
                    infoRow('ارزش خرید آن‌ها', '${faNum(soldValue, dec: 0)} تومان'),
                  ]),
                ),
              ));
            }

            children.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'جستجو با کد پسته (مثلاً KH00012 یا MX00003)، نوع یا دسته',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ));

            if (lots.isEmpty) {
              final otherHits = q.isEmpty ? 0 : other.where(match).length;
              children.add(Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: Text(q.isNotEmpty
                        ? 'نتیجه‌ای پیدا نشد'
                        : (_showSold
                            ? 'هنوز هیچ خریدی به‌طور کامل فروش نرفته است'
                            : 'هیچ جنسی در انبار موجود نیست'))),
              ));
              if (otherHits > 0) {
                children.add(OutlinedButton(
                  onPressed: () => setState(() => _showSold = !_showSold),
                  child: Text(
                      '${faNum(otherHits, dec: 0)} مورد در بخش «${_showSold ? 'موجود' : 'فروش رفته'}» پیدا شد — نمایش'),
                ));
              }
            } else {
              // دسته -> نوع -> بارها
              final Map<String, Map<String, List<Map<String, dynamic>>>> g = {};
              for (final l in lots) {
                g
                    .putIfAbsent(l['category_name'] as String, () => {})
                    .putIfAbsent(l['type_name'] as String, () => [])
                    .add(l);
              }
              for (final catEntry in g.entries) {
                children.add(sectionTitle(context, catEntry.key));
                for (final e in catEntry.value.entries) {
                  final sumRem =
                      e.value.fold<double>(0, (a, l) => a + (l['remaining'] as num).toDouble());
                  final sumNet =
                      e.value.fold<double>(0, (a, l) => a + (l['net_weight'] as num).toDouble());
                  children.add(Card(
                    child: ExpansionTile(
                      // هنگام جستجو نتیجه‌ها باز نمایش داده می‌شوند
                      key: PageStorageKey('${_showSold}/${catEntry.key}/${e.key}/${q.isNotEmpty}'),
                      initiallyExpanded: q.isNotEmpty,
                      title: Text(e.key),
                      subtitle: Text(
                          '${faNum(_showSold ? sumNet : sumRem)} کیلو  •  ${faNum(e.value.length, dec: 0)} بار'),
                      children: [for (final l in e.value) _lotTile(context, l)],
                    ),
                  ));
                }
              }
            }
            children.add(const SizedBox(height: 72));
            return ListView(padding: const EdgeInsets.all(12), children: children);
          },
        ),
      ),
    );
  }

  Widget _lotTile(BuildContext context, Map<String, dynamic> l) {
    final isMix = (l['is_mix'] as int? ?? 0) == 1;
    final net = (l['net_weight'] as num).toDouble();
    final rem = (l['remaining'] as num).toDouble();
    final soldW = net - rem < 0 ? 0.0 : net - rem;
    final codes = ((l['in_mix_codes'] as List?) ?? const []).cast<String>();
    final sold = !AppDb.isAvailable(l);
    final lines = <String>[
      'کد پسته: ${l['code'] ?? '-'}',
      'خرید ${jalaliDate(l['date'] as String)}  •  فی ${faNum(l['price'] as num, dec: 0)}',
      if (!sold && soldW > 1e-6) 'از ${faNum(net)} کیلو خریداری‌شده، ${faNum(soldW)} کیلو فروخته/مصرف شده',
      if (codes.isNotEmpty)
        '🔀 ${rem <= 1e-6 ? 'کل موجودی آن' : 'بخشی از آن'} داخل مخلوط ${codes.join('، ')} است (هنوز کامل فروش نرفته)',
      if (!sold)
        'گونی مانده: کوچک ${faNum(l['small_left'] as num)} / بزرگ ${faNum(l['large_left'] as num)}'
            '${l['ounce'] != null ? '  •  انس ${faNum(l['ounce'] as num)}' : ''}'
            '${l['gram'] != null ? '  •  گرم ${faNum(l['gram'] as num)}' : ''}',
    ];
    return ListTile(
      dense: true,
      onTap: isMix ? () => _showMixDetails(context, l) : null,
      leading: isMix
          ? const Tooltip(
              message: 'مخلوط (کوت‌ریزی) — از چند جنس ساخته شده', child: Icon(Icons.merge_type))
          : null,
      title: Text(sold
          ? '${faNum(net)} کیلو  •  فروش رفت${isMix ? '  •  مخلوط' : ''}'
          : '${faNum(rem)} کیلو مانده${isMix ? '  •  مخلوط' : ''}'),
      subtitle: Text(lines.join('\n')),
      isThreeLine: lines.length >= 3,
    );
  }
}
