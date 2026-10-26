import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'pay_service.dart';

/// کلید ناوبری سراسری، برای نمایش پیام بعد از بازگشت از درگاه
final GlobalKey<NavigatorState> payNavigatorKey = GlobalKey<NavigatorState>();

StreamSubscription<Uri>? _payLinkSub;

/// گوش دادن به لینک بازگشت: pestehbazar://pay?result=ok|warn|bad&order=...
/// فعال‌سازی فقط با verify سرور انجام می‌شود (pay.check_payment)؛ این فایل چیزی را خودش تأیید نمی‌کند.
void initPayDeepLinks() {
  _payLinkSub?.cancel();
  _payLinkSub = AppLinks().uriLinkStream.listen((uri) {
    if (uri.scheme != 'pestehbazar' || uri.host != 'pay') return;
    _handlePayLink();
  }, onError: (_) {});
}

Future<void> _handlePayLink() async {
  try {
    final id = await PayService.I.pendingOrderId();
    if (id == null) return;
    final r = await PayService.I.call('pay.check_payment', {'order_id': id});
    final res = r['result'];
    String msg;
    if (res == 'paid') {
      await PayService.I.clearPendingOrder();
      msg = 'پرداخت شما تأیید شد و اشتراک فعال است.';
    } else if (res == 'review') {
      await PayService.I.clearPendingOrder();
      msg = 'پول شما دریافت شد ولی فعال‌سازی خودکار انجام نشد. ادمین بررسی می‌کند.';
    } else if (res == 'pending') {
      msg = 'پرداخت هنوز تأیید نشده است. چند دقیقه بعد «بررسی پرداخت» را بزنید.';
    } else {
      await PayService.I.clearPendingOrder();
      msg = 'این پرداخت تأیید نشد. اگر پول کم شده، با پشتیبانی تماس بگیرید.';
    }
    final ctx = payNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
    }
  } catch (_) {}
}
