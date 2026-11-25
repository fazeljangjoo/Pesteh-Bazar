// v91 p5 — پیوند اختیاری «حساب داخلی» (صندوق / حساب بانکی) روی ردیف پرداخت/دریافت و حرکت صراف.
// انتخاب حساب همیشه اختیاری است؛ متن آزاد «از/به کدام حساب» مثل قبل می‌ماند. سرور (طلایی) سند را روی همان حساب می‌زند.
import 'package:flutter/material.dart';

import 'entity_store.dart';

class InternalAccount {
  final String uid;
  final String name;
  final String kind; // cash | bank
  final String ccy; // IRR | USD | …
  const InternalAccount(this.uid, this.name, this.kind, this.ccy);
  String get label => '${kind == 'cash' ? 'صندوق' : 'بانک'} $name${ccy == 'IRR' ? '' : ' ($ccy)'}';
}

/// صندوق‌ها و حساب‌های بانکیِ فعال (فقط وقتی این موجودیت‌ها برای این حساب کاربری فعال‌اند؛ وگرنه فهرست خالی).
Future<List<InternalAccount>> loadInternalAccounts() async {
  final List<InternalAccount> out = <InternalAccount>[];
  try {
    final List<String> vis = await EntityStore.I.visibleNames();
    for (final (String ent, String kind) in const <(String, String)>[('cash_boxes', 'cash'), ('bank_accounts', 'bank')]) {
      if (!vis.contains(ent)) continue;
      for (final Map<String, dynamic> r in await EntityStore.I.list(ent)) {
        if (r['active'] == false || r['active'] == 0) continue;
        final String c = (r['ccy'] ?? '').toString().trim().toUpperCase();
        out.add(InternalAccount('${r['uid']}', '${r['name'] ?? ''}', kind, (c.isEmpty || c == 'IRT') ? 'IRR' : c));
      }
    }
  } catch (_) {/* پایگاه محلی هنوز آماده نیست */}
  out.sort((InternalAccount a, InternalAccount b) => a.label.compareTo(b.label));
  return out;
}

/// انتخاب‌گر اختیاری حساب داخلی. اگر هیچ صندوق/حسابی تعریف نشده باشد چیزی نشان نمی‌دهد.
/// [onChanged] uid و برچسب حساب انتخاب‌شده را می‌دهد (null = بدون انتخاب).
/// [ccy] (اختیاری) فقط حساب‌های همان ارز را نشان می‌دهد.
class InternalAccountPicker extends StatefulWidget {
  final String? value;
  final void Function(String? uid, InternalAccount? account) onChanged;
  final String label;
  final String? ccy;
  const InternalAccountPicker({super.key, required this.value, required this.onChanged, this.label = 'حساب داخلی ما (اختیاری)', this.ccy});

  @override
  State<InternalAccountPicker> createState() => _InternalAccountPickerState();
}

class _InternalAccountPickerState extends State<InternalAccountPicker> {
  List<InternalAccount>? _all;

  @override
  void initState() {
    super.initState();
    loadInternalAccounts().then((List<InternalAccount> l) {
      if (mounted) setState(() => _all = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<InternalAccount>? all = _all;
    if (all == null || all.isEmpty) return const SizedBox.shrink();
    final List<InternalAccount> list = <InternalAccount>[
      for (final InternalAccount a in all)
        if (widget.ccy == null || a.ccy == widget.ccy || a.uid == widget.value) a,
    ];
    final bool known = widget.value == null || list.any((InternalAccount a) => a.uid == widget.value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String?>(
        value: known ? widget.value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder(), helperText: 'انتخاب حساب اختیاری است'),
        items: <DropdownMenuItem<String?>>[
          const DropdownMenuItem<String?>(value: null, child: Text('— بدون انتخاب —')),
          for (final InternalAccount a in list) DropdownMenuItem<String?>(value: a.uid, child: Text(a.label, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (String? u) {
          InternalAccount? acc;
          for (final InternalAccount a in list) {
            if (a.uid == u) acc = a;
          }
          widget.onChanged(u, acc);
        },
      ),
    );
  }
}
