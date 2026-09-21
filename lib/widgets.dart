import 'package:flutter/material.dart';

import 'utils.dart';

Widget numField(
  TextEditingController c,
  String label, {
  bool required = false,
  String? suffix,
  double? max,
  VoidCallback? onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => onChanged?.call(),
      validator: (v) {
        if ((v ?? '').trim().isEmpty) return required ? 'الزامی است' : null;
        final n = parseNum(v);
        if (n == null || n < 0) return 'عدد معتبر وارد کنید';
        if (max != null && n > max) return 'حداکثر ${faNum(max)}';
        return null;
      },
    ),
  );
}

Widget textField(TextEditingController c, String label, {int lines = 1}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      maxLines: lines,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    ),
  );
}

Widget sectionTitle(BuildContext context, String t) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Text(t,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );

Widget infoRow(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(k, style: const TextStyle(color: Colors.black54))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );

void snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<bool> confirm(BuildContext context, String msg) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
      ],
    ),
  );
  return r ?? false;
}
