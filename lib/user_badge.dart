import 'package:flutter/material.dart';

import 'license_service.dart';
import 'perms.dart';
import 'widgets.dart' show confirm;

/// v89: نام کاربر و نقشش زیر نشان اشتراک: کارکن ⇒ «نام — نقش‌ها»؛ مالک ⇒ «مالک».
class UserRoleLine extends StatelessWidget {
  const UserRoleLine({super.key, this.onDark = false});
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: StaffPerms.I.current,
      builder: (BuildContext c, Map<String, dynamic>? s, Widget? _) {
        final String text;
        if (s == null) {
          text = 'مالک';
        } else {
          final String name = '${s['name'] ?? ''}'.trim().isNotEmpty ? '${s['name']}'.trim() : '${s['username'] ?? ''}';
          final String role = StaffPerms.I.roleName.trim();
          text = role.isEmpty ? name : '$name — $role';
        }
        final Color color = onDark ? Colors.white.withValues(alpha: 0.9) : Theme.of(c).hintColor;
        return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(s == null ? Icons.verified_user_outlined : Icons.badge_outlined, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 12))),
        ]);
      },
    );
  }
}

/// v89: خروج کارکن از حساب (برای کارکن «اشتراک من» که دکمهٔ خروج در آن است پنهان است).
Future<void> staffLogout(BuildContext context) async {
  if (!await confirm(context, 'از حساب خارج شوید؟')) return;
  await LicenseService.I.signOut();
  LicenseService.I.sessionInvalid.value++; // LicenseGate دوباره صفحهٔ ورود را نشان می‌دهد
  if (context.mounted) Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
}
