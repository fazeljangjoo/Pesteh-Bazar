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
      // v91: به‌جای فهرست کشویی بلند ⇒ کادر انتخاب + پنجرهٔ جست‌وجو با ردیف‌های فشرده (با زیاد شدن خریدها فرم بلند نمی‌شود)
      InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () async {
          final int? v = await showDialog<int>(context: context, builder: (_) => _SaleLotSearchDialog(lots: lots, selectedId: selectedId));
          if (v != null) onSelect(v);
        },
        child: InputDecorator(
          isEmpty: e == null,
          decoration: const InputDecoration(
            labelText: 'لات',
            hintText: 'لمس کنید و لات را جست‌وجو کنید',
            border: OutlineInputBorder(),
            suffixIcon: Icon(Icons.search),
          ),
          child: e == null ? null : Text('${who(e)}  ·  ${e['code'] ?? ''}  ·  ${faNum(_n(e['remaining']))} کیلو', overflow: TextOverflow.ellipsis, maxLines: 1),
        ),
      ),
      if (e != null)
        Container(
          margin: const EdgeInsets.only(top: 6, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: th.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: th.dividerColor),
          ),
          child: Wrap(spacing: 14, runSpacing: 2, children: <Widget>[
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

/// v91: پنجرهٔ جست‌وجوی لات فروش — جست‌وجو در فروشنده/نام کوت، کد، دسته، نوع؛ هر لات یک ردیف فشرده.
class _SaleLotSearchDialog extends StatefulWidget {
  const _SaleLotSearchDialog({required this.lots, required this.selectedId});
  final List<Map<String, dynamic>> lots;
  final int? selectedId;

  @override
  State<_SaleLotSearchDialog> createState() => _SaleLotSearchDialogState();
}

class _SaleLotSearchDialogState extends State<_SaleLotSearchDialog> {
  String _q = '';

  static String _norm(String s) => toEnDigits(s).replaceAll('ي', 'ی').replaceAll('ك', 'ک').toLowerCase().trim();

  bool _match(Map<String, dynamic> x) {
    if (_q.isEmpty) return true;
    final String hay = _norm('${SaleLotPicker.who(x)} ${x['code'] ?? ''} ${x['category_name'] ?? ''} ${x['type_name'] ?? ''} ${x['seller'] ?? ''}');
    return _norm(_q).split(RegExp(r'\s+')).every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData th = Theme.of(context);
    final List<Map<String, dynamic>> list = widget.lots.where(_match).toList();
    final Size sz = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: sz.height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'فروشنده، کد، دسته یا نوع…',
                border: OutlineInputBorder(),
              ),
              onChanged: (String v) => setState(() => _q = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('${faNum(list.length, dec: 0)} لات از ${faNum(widget.lots.length, dec: 0)}', style: TextStyle(fontSize: 12, color: th.hintColor)),
            ),
          ),
          Flexible(
            child: list.isEmpty
                ? const Padding(padding: EdgeInsets.all(24), child: Text('لاتی پیدا نشد'))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext c, int i) {
                      final Map<String, dynamic> x = list[i];
                      final String meta = <String>[
                        '${x['category_name'] ?? ''} ${x['type_name'] ?? ''}'.trim(),
                        if (x['ounce'] != null) 'انس ${faNum(x['ounce'] as num, dec: 2)}',
                        if (x['gram'] != null) 'گرم ${faNum(x['gram'] as num, dec: 2)}',
                      ].where((String s) => s.isNotEmpty).join('  ·  ');
                      return ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -3),
                        selected: x['id'] == widget.selectedId,
                        title: Text('${SaleLotPicker.who(x)}  ·  ${x['code'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: meta.isEmpty ? null : Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
                        trailing: Text('${faNum(SaleLotPicker._n(x['remaining']))} کیلو', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                        onTap: () => Navigator.pop(context, x['id'] as int),
                      );
                    },
                  ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
          ),
        ]),
      ),
    );
  }
}
