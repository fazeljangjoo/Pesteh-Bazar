// «قابلیت‌های فناورانه» — ورودی‌های منو. main.dart فقط techMenuTiles(...) را صدا می‌زند؛ فازهای بعد فقط همین فایل را تغییر می‌دهند.
// «قابلیت‌های هوشمند» (روشن/خاموش کردن پرچم‌ها) فقط برای settings.manage؛ بقیهٔ ورودی‌ها فقط وقتی پرچم مربوط روشن است.
import 'package:flutter/material.dart';

import 'anomaly_ui.dart' show AnomalyListScreen;
import 'perms.dart' show StaffPerms;
import 'tech_features.dart';

/// [open] صفحه را باز می‌کند (main.dart: بستن منو + push در Navigator داخلی ویندوز).
List<Widget> techMenuTiles(BuildContext context, void Function(Widget screen) open) {
  return <Widget>[
    if (StaffPerms.I.can('settings.manage'))
      ListTile(
        leading: const Icon(Icons.auto_awesome_outlined),
        title: const Text('قابلیت‌های هوشمند'),
        subtitle: const Text('روشن/خاموش برای کل شرکت (پیش‌فرض خاموش)', style: TextStyle(fontSize: 11.5)),
        onTap: () => open(const TechSettingsScreen()),
      ),
    if (StaffPerms.I.can('workshop.view') || StaffPerms.I.can('workshop.manage'))
      TechGate(
        flag: 'anomaly',
        child: ListTile(
          leading: const Icon(Icons.query_stats_outlined),
          title: const Text('هشدارهای بازده'),
          subtitle: const Text('افت و سالم غیرعادی کارگاه و خط شکست', style: TextStyle(fontSize: 11.5)),
          onTap: () => open(const AnomalyListScreen()),
        ),
      ),
  ];
}
