// فاز ۲ — polling تطبیقی به‌روزرسانی زنده: ۵ ثانیه در پیش‌زمینه، توقف در پس‌زمینه یا با پرچم خاموش، دو برابر شدن تا ۶۰ ثانیه با خطا.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/alerts_ui.dart';
import 'package:pesteh_bazar/live_events.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('poll delay', () {
    expect(liveNextDelayMs(foreground: true, enabled: true, failures: 0), 5000);
    expect(liveNextDelayMs(foreground: false, enabled: true, failures: 0), isNull);
    expect(liveNextDelayMs(foreground: true, enabled: false, failures: 0), isNull);
    expect(liveNextDelayMs(foreground: true, enabled: true, failures: 1), 10000);
    expect(liveNextDelayMs(foreground: true, enabled: true, failures: 2), 20000);
    expect(liveNextDelayMs(foreground: true, enabled: true, failures: 3), 40000);
    expect(liveNextDelayMs(foreground: true, enabled: true, failures: 4), 60000);
    expect(liveNextDelayMs(foreground: true, enabled: true, failures: 50), 60000);
  });

  test('data events trigger a local sync; alert events do not', () {
    expect(kLiveDataTypes.contains('sale.created'), isTrue);
    expect(kLiveDataTypes.contains('stock.changed'), isTrue);
    expect(kLiveDataTypes.contains('alert.raised'), isFalse);
  });

  testWidgets('flag off: alerts bell renders nothing', (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: LiveAlertsBell())));
    await t.pumpAndSettle();
    expect(find.byType(IconButton), findsNothing);
  });
}
