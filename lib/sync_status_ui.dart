// S7 — نشانگر وضعیت همگام‌سازی («همگام / در حال همگام‌سازی / آفلاین») و نوار «به‌روزرسانی جدید — اعمال».
import 'dart:async';

import 'package:flutter/material.dart';

import 'db.dart';
import 'sync_service.dart';

String syncStatusLabel(SyncStatus s) => switch (s) {
      SyncStatus.synced => 'همگام',
      SyncStatus.syncing => 'در حال همگام‌سازی',
      SyncStatus.offline => 'آفلاین',
    };

Color syncStatusColor(SyncStatus s) => switch (s) {
      SyncStatus.synced => const Color(0xFF2E7D32),
      SyncStatus.syncing => const Color(0xFFEF6C00),
      SyncStatus.offline => const Color(0xFF757575),
    };

/// گلوله + برچسب کوچک؛ هر جا که جا باشد (کارت صفحهٔ اصلی، صفحهٔ همگام‌سازی)
class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncInfo>(
      valueListenable: SyncService.I.info,
      builder: (context, info, _) {
        final s = info.status;
        final c = syncStatusColor(s);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(syncStatusLabel(s), style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        );
      },
    );
  }
}

/// نوار شناور «به‌روزرسانی جدید». فقط وقتی تغییرِ دستگاه دیگر آمده دیده می‌شود.
/// تا وقتی فرم باز است دکمه غیرفعال است (هیچ‌وقت فرم در حال تایپ پاک نمی‌شود)؛ با بسته‌شدن فرم خودکار اعمال می‌شود.
/// v94: نوار بعد از ۳ ثانیه خودش جمع می‌شود (اعمال خودکار سر جایش است)؛ فقط با تغییر وضعیت (فرم باز/بسته) دوباره کوتاه دیده می‌شود.
class RemoteUpdateBanner extends StatefulWidget {
  const RemoteUpdateBanner({super.key});

  @override
  State<RemoteUpdateBanner> createState() => _RemoteUpdateBannerState();
}

class _RemoteUpdateBannerState extends State<RemoteUpdateBanner> {
  static const Duration _show = Duration(seconds: 3);
  Timer? _timer;
  bool _visible = false;
  bool? _lastEditing;

  @override
  void initState() {
    super.initState();
    SyncService.I.remotePending.addListener(_changed);
    AppDb.I.version.addListener(_changed);
    _changed();
  }

  void _changed() {
    final bool pending = SyncService.I.remotePending.value;
    final bool editing = AppDb.I.isEditing;
    if (!pending) {
      _timer?.cancel();
      _lastEditing = null;
      if (_visible && mounted) setState(() => _visible = false);
      return;
    }
    if (_lastEditing == editing) return; // همان وضعیت ⇒ دوباره نشان داده نمی‌شود
    _lastEditing = editing;
    _timer?.cancel();
    _timer = Timer(_show, () {
      if (mounted) setState(() => _visible = false);
    });
    if (mounted) setState(() => _visible = true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    SyncService.I.remotePending.removeListener(_changed);
    AppDb.I.version.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final editing = AppDb.I.isEditing;
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.inverseSurface,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.system_update_alt, size: 18, color: Theme.of(context).colorScheme.onInverseSurface),
          const SizedBox(width: 8),
          Text(
            editing ? 'به‌روزرسانی جدید — بعد از بستن فرم اعمال می‌شود' : 'به‌روزرسانی جدید',
            style: TextStyle(color: Theme.of(context).colorScheme.onInverseSurface, fontSize: 13),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: editing ? null : () => SyncService.I.pollNow(),
            child: const Text('اعمال'),
          ),
        ]),
      ),
    );
  }
}
