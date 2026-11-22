import 'package:flutter/material.dart';

import 'utils.dart';

/// v87 — انتخاب لات فروش مثل فرم خط شکست (فایل مشترک اندروید و ویندوز): به‌جای فهرست همهٔ لات‌ها یک فهرست کشویی
/// (فروشنده/نام کوت، کد، دسته و نوع، انس، گرم، مانده) و بعد از انتخاب کادر مشخصات لات.
class SaleLotPicker extends StatelessWidget {
  const SaleLotPicker({super.key, required this.lots, required this.selectedId, required this.onSelect, this.whNames = const <String, String>{}, this.showUsd = false});
  final List<Map<String, dynamic>> lots;
  final int? selectedId;
  final ValueChanged<int> onSelect;
  final Map<String, String> whNames;
  final bool showUsd;

  static double _n(dynamic v) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

  static String who(Map<String, dynamic> e) {
    if (_n(e['is_mix']) == 1) return 'کوت: ${e['type_name'] ?? ''}';
    final String s = '${e['seller'] ?? ''}'.trim();
    return s.isNotEmpty ? s : '${e['category_name'] ?? ''} ${e['type_name'] ?? ''}'.trim();
  }

  Map<String, dynamic>? get _sel {
    for (final Map<String, dynamic> e in lots) {
      if (e['id'] == selectedId) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final Map<String, dynamic>? e = _sel;
    Widget kv(String k, String v) => Text.rich(
          TextSpan(children: <InlineSpan>[TextSpan(text: '$k: ', style: TextStyle(color: th.hintColor)), TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w600))]),
          style: const TextStyle(fontSize: 12.5),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      DropdownButtonFormField<int>(
        key: ValueKey<String>('sale-lot-${lots.length}-$selectedId'),
        initialValue: e == null ? null : selectedId,
        isExpanded: true,
        itemHeight: 56,
        hint: const Text('لات را انتخاب کنید'),
        decoration: const InputDecoration(labelText: 'لات', border: OutlineInputBorder()),
        selectedItemBuilder: (_) => <Widget>[
          for (final Map<String, dynamic> x in lots) Align(alignment: AlignmentDirectional.centerStart, child: Text('${who(x)}  ·  ${x['code'] ?? ''}', overflow: TextOverflow.ellipsis)),
        ],
        items: <DropdownMenuItem<int>>[
          for (final Map<String, dynamic> x in lots)
            DropdownMenuItem<int>(
              value: x['id'] as int,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(who(x), overflow: TextOverflow.ellipsis),
                Text(
                  '${x['code'] ?? ''}  ·  ${x['category_name'] ?? ''} ${x['type_name'] ?? ''}'
                  '${x['ounce'] == null ? '' : '  ·  انس ${faNum(x['ounce'] as num, dec: 2)}'}'
                  '${x['gram'] == null ? '' : '  ·  گرم ${faNum(x['gram'] as num, dec: 2)}'}'
                  '  ·  ${faNum(_n(x['remaining']))} کیلو',
                  style: TextStyle(fontSize: 11, color: th.hintColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
        ],
        onChanged: (int? v) {
          if (v != null) onSelect(v);
        },
      ),
      if (e != null)
        Container(
          margin: const EdgeInsets.only(top: 6, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: th.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: th.dividerColor),
          ),
          child: Wrap(spacing: 16, runSpacing: 4, children: <Widget>[
            kv(_n(e['is_mix']) == 1 ? 'نام لات (کوت)' : 'فروشنده / نام لات', _n(e['is_mix']) == 1 ? '${e['type_name'] ?? ''}' : who(e)),
            kv('کد', '${e['code'] ?? '-'}'),
            kv('دسته و نوع', '${e['category_name'] ?? ''} ${e['type_name'] ?? ''}'.trim()),
            if ('${e['date'] ?? ''}'.isNotEmpty) kv('تاریخ', jalaliDate('${e['date']}')),
            kv('انس', e['ounce'] == null ? '—' : faNum(e['ounce'] as num, dec: 2)),
            kv('گرم', e['gram'] == null ? '—' : faNum(e['gram'] as num, dec: 2)),
            kv('عدل کوچک', faNum(_n(e['small_left']), dec: 0)),
            kv('عدل بزرگ', faNum(_n(e['large_left']), dec: 0)),
            kv('وزن خالص در انبار', '${faNum(_n(e['remaining']))} کیلو'),
            if (e['price'] != null) kv('فی خرید', faNum(e['price'] as num, dec: 0)),
            if (showUsd && e['price_usd'] != null) kv('فی دلاری', faUsd(e['price_usd'] as num, dec: 4)),
            if ((whNames[e['warehouse_uid']] ?? '').isNotEmpty) kv('انبار', whNames[e['warehouse_uid']]!),
          ]),
        ),
    ]);
  }
}
