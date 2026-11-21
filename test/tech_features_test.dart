// قابلیت‌های فناورانه — قاعدهٔ ۵: با پرچم خاموش (پیش‌فرض) هیچ ویجت جدیدی نمایش داده نمی‌شود و هیچ درخواستی به سرور نمی‌رود.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/anomaly_ui.dart';
import 'package:pesteh_bazar/tech_features.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('flags default off: YieldAssessmentCard renders nothing', (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await t.pumpWidget(_host(const YieldAssessmentCard(source: 'workshop', sourceId: 5)));
    await t.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
    expect(find.textContaining('ارزیابی بازده'), findsNothing);
    expect(TechFeatures.I.isOnSync('anomaly'), isFalse);
    for (final String k in kTechFlagKeys) {
      expect(await TechFeatures.I.isOn(k), isFalse, reason: k);
    }
  });

  testWidgets('TechGate shows child only when the flag is on', (WidgetTester t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await t.pumpWidget(_host(const TechGate(flag: 'anomaly', child: Text('NEW'))));
    await t.pumpAndSettle();
    expect(find.text('NEW'), findsNothing);
    TechFeatures.I.flags.value = <String, bool>{'anomaly': true};
    await t.pump();
    expect(find.text('NEW'), findsOneWidget);
    TechFeatures.I.flags.value = <String, bool>{'anomaly': false};
    await t.pump();
    expect(find.text('NEW'), findsNothing);
  });
}
