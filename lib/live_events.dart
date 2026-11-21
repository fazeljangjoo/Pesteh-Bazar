// فاز ۲ «قابلیت‌های فناورانه» — به‌روزرسانی زنده. پشت پرچم features.events (پیش‌فرض خاموش).
// polling تطبیقی events.since: هر ۵ ثانیه وقتی برنامه در پیش‌زمینه است؛ در پس‌زمینه متوقف؛ خطای شبکه ⇒ فاصله دو برابر تا ۶۰ ثانیه.
// رویداد تازهٔ مرتبط با داده (خرید، فروش، موجودی، کارگاه) ⇒ همان همگام‌سازی موجود (SyncService.syncNow) صدا زده می‌شود تا
// داشبورد و موجودی (که از پایگاه محلی می‌خوانند) خودشان تازه شوند. تعداد هشدار خوانده‌نشده در [unread].
// اعلان اندروید (FCM) اضافه نشده است: Firebase در پروژه نیست (گزارش فاز ۲).
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'sync_service.dart' show SyncService;
import 'tech_features.dart';
import 'warehouse_ui.dart' show StockApi;

/// فاصلهٔ poll بعدی (میلی‌ثانیه). [failures] = شکست‌های پیاپی؛ [foreground] = برنامه در پیش‌زمینه.
/// null = poll نکن (پس‌زمینه یا پرچم خاموش).
int? liveNextDelayMs({required bool foreground, required bool enabled, required int failures}) {
  if (!foreground || !enabled) return null;
  if (failures <= 0) return 5000;
  int d = 5000;
  for (int i = 0; i < failures && d < 60000; i++) {
    d *= 2;
  }
  return d > 60000 ? 60000 : d;
}

/// انواع رویدادی که دادهٔ محلی را کهنه می‌کنند (⇒ syncNow)
const Set<String> kLiveDataTypes = <String>{
  'purchase.created', 'purchase.updated', 'sale.created', 'sale.updated', 'lot.created', 'stock.changed', 'mix.created',
  'workshop.opened', 'workshop.closed', 'workshop.reopened', 'crack.saved',
};

class LiveEvents with WidgetsBindingObserver {
  LiveEvents._();
  static final LiveEvents I = LiveEvents._();

  /// تعداد هشدارهای خوانده‌نشده (برای نشان منو و زنگ)
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  /// هر رویداد تازه (برای صفحه‌هایی مثل فهرست هشدارها که مستقیم از سرور می‌خوانند)
  final StreamController<Map<String, dynamic>> _ctl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get stream => _ctl.stream;

  bool _started = false;
  bool _foreground = true;
  int _failures = 0;
  int _after = 0;
  Timer? _timer;
  bool _busy = false;

  /// چند بار صدا زدن بی‌خطر است. با پرچم خاموش کاری نمی‌کند.
  Future<void> ensureStarted() async {
    if (_started) return;
    if (!await TechFeatures.I.isOn('events')) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    TechFeatures.I.flags.addListener(_onFlags);
    _schedule(immediate: true);
  }

  void _onFlags() {
    if (!TechFeatures.I.isOnSync('events')) {
      _timer?.cancel();
      _timer = null;
      unread.value = 0;
    } else if (_timer == null) {
      _schedule(immediate: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _schedule(immediate: true);
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _schedule({bool immediate = false}) {
    _timer?.cancel();
    final int? d = liveNextDelayMs(foreground: _foreground, enabled: TechFeatures.I.isOnSync('events'), failures: _failures);
    if (d == null) {
      _timer = null;
      return;
    }
    _timer = Timer(Duration(milliseconds: immediate ? 0 : d), _poll);
  }

  Future<void> _poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final Map<String, dynamic> r = await StockApi.call('events.since', <String, dynamic>{'after': _after});
      _failures = 0;
      final int last = (r['last_id'] as num?)?.toInt() ?? _after;
      final bool first = _after == 0;
      _after = last;
      unread.value = (r['unread_alerts'] as num?)?.toInt() ?? unread.value;
      final Object? evs = r['events'];
      bool stale = false;
      if (!first && evs is List) {
        for (final Map<dynamic, dynamic> e in evs.whereType<Map>()) {
          final Map<String, dynamic> m = Map<String, dynamic>.from(e);
          _ctl.add(m);
          if (kLiveDataTypes.contains(m['type'])) stale = true;
        }
      }
      if (stale) unawaited(SyncService.I.syncNow(pull: true));
    } catch (_) {
      _failures++;
    } finally {
      _busy = false;
      _schedule();
    }
  }

  /// بعد از خواندن/بستن هشدار در صفحهٔ هشدارها
  Future<void> refreshUnread() async {
    try {
      final Map<String, dynamic> r = await StockApi.call('alerts.unread');
      unread.value = (r['count'] as num?)?.toInt() ?? 0;
    } catch (_) {}
  }
}
