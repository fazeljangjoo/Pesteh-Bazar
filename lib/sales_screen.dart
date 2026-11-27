import 'package:flutter/material.dart';
import 'fmt.dart' show Fmt;

import 'db.dart';
import 'doc_drafts.dart' show DraftsScreen;
import 'form_settings.dart' show FormSettingsLocal;
import 'list_filter.dart';
import 'live_query.dart';
import 'license_service.dart';
import 'sale_form.dart';
import 'utils.dart';

/// یکسان‌سازی «ي/ك» عربی و «ی/ک» فارسی برای جستجو
String _norm(String s) => toEnDigits(s.replaceAll('ي', 'ی').replaceAll('ك', 'ک')).trim().toLowerCase();

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  String _query = '';
  // پیش‌فرض: سال پسته‌ای جاری (۱ مهر تا ۳۱ شهریور سال بعد)، جدیدترین اول
  DocListFilter _filter = DocListFilter.defaults();

  /// کد پسته‌ی فروش (هر فروش فقط یک قلم دارد)
  static String _codeOf(Map<String, dynamic> sale) {
    final items = sale['items'] as List;
    if (items.isEmpty) return '-';
    return (items.first['code'] as String?) ?? '-';
  }

  static bool _matches(Map<String, dynamic> sale, String q) {
    if (q.isEmpty) return true;
    final items = sale['items'] as List;
    final it = items.isEmpty ? const <String, dynamic>{} : items.first as Map;
    final hay = _norm('${it['code']} ${it['category_name']} ${it['type_name']} ${sale['buyer'] ?? ''}');
    return hay.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فروش'),
        actions: <Widget>[
          FutureBuilder<bool>(
            future: FormSettingsLocal.isOn('draft'), // S35.T35.9b
            builder: (BuildContext c, AsyncSnapshot<bool> s) => s.data == true
                ? IconButton(
                    tooltip: 'پیش‌نویس‌ها',
                    icon: const Icon(Icons.edit_note),
                    onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const DraftsScreen(docType: 'sale'))),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SaleForm())),
        icon: const Icon(Icons.add),
        label: const Text('فروش جدید'),
      ),
      body: LiveQuery<List<Map<String, dynamic>>>(
        tab: 2,
        load: AppDb.I.sales,
        builder: (context, s) {
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final all = s.data!;
            if (all.isEmpty) return const Center(child: Text('هنوز فروشی ثبت نشده'));
            final q = _norm(_query);
            final list = _filter.apply(all.where((sale) => _matches(sale, q)).toList());
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              itemCount: list.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(children: [
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'جستجو با کد پسته، نوع، دسته یا خریدار',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      const SizedBox(height: 8),
                      DocListFilterBar(
                        value: _filter,
                        onChanged: (f) => setState(() => _filter = f),
                        shown: list.length,
                        total: all.length,
                      ),
                      if (list.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: Text('نتیجه‌ای پیدا نشد'),
                        ),
                    ]),
                  );
                }
                final sale = list[i - 1];
                final id = sale['id'] as int;
                final items = sale['items'] as List;
                final net = (sale['net_weight'] as num).toDouble();
                final price = (sale['price'] as num).toDouble();
                final revenue = net * price;
                final total = (sale['total_weight'] as num).toDouble();
                final tare = total - net < 0 ? 0.0 : total - net;
                final small = (sale['small_sack_count'] as num).toDouble();
                final large = (sale['large_sack_count'] as num).toDouble();
                final comp = items
                    .map((it) => '${it['category_name']} - ${it['type_name']}')
                    .join(' + ');
                final fx = LicenseService.I.isFx.value;
                final usd = fx ? saleUsd(sale) : null;
                final rate = (sale['usd_rate'] as num?)?.toDouble();
                // v96: ردیف فشرده مثل فهرست خریدها (بارکد و جزئیات کامل در صفحهٔ همان فروش)
                final String buyer = (sale['buyer'] ?? '').toString().trim();
                final bool docCcy = (sale['ccy'] ?? '').toString().isNotEmpty && sale['ccy'] != 'IRT';
                final List<String> extra = <String>[
                  if (small + large > 0) 'گونی ${faNum(small)} کوچک / ${faNum(large)} بزرگ',
                  if (tare > 0) 'وزن گونی‌ها ${faNum(tare)} کیلو',
                  if (sale['labor_cost'] != null) 'کارگر ${Fmt.money(sale['labor_cost'] as num)}',
                  if (sale['transport_cost'] != null) 'حمل ${Fmt.money(sale['transport_cost'] as num)}',
                  if (fx && usd != null) 'به دلار ${faUsd(usd.revenue)}',
                  if (fx && rate != null && usd == null) 'دلار روز ${faNum(rate, dec: 0)}',
                ];
                return Card(
                  child: ListTile(
                    onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SaleForm(editSaleId: id, locked: true, doc: sale))), // v91 p3: جزئیات = همان فرم فروش به حالت قفل
                    leading: const CircleAvatar(child: Icon(Icons.sell_outlined)),
                    title: Text.rich(TextSpan(children: <InlineSpan>[
                      TextSpan(text: 'خریدار: ${buyer.isEmpty ? '—' : buyer}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (comp.isNotEmpty) TextSpan(text: '  •  $comp'),
                    ])),
                    subtitle: Text(
                        'کد ${_codeOf(sale)}  •  ${jalaliDate(sale['date'] as String)}  •  ${faNum(net)} کیلو (خالص)\n'
                        'فی ${Fmt.money(price)}  •  مبلغ ${Fmt.money(revenue)}'
                        '${docCcy ? '  [${faCcy('${sale['ccy']}', (sale['total_ccy'] as num?) ?? 0, dec: 2)} • نرخ ${faNum((sale['fx_rate'] as num?) ?? 0, dec: 0)}]' : ''}'
                        '${extra.isEmpty ? '' : '\n${extra.join('  •  ')}'}'),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_left), // کارها در پایین فرم جزئیات
                  ),
                );
              },
            );
          },
      ),
    );
  }
}
