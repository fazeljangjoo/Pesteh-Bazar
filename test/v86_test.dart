import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/workshop_calc.dart';
import 'package:pesteh_bazar/ws_shifts_ui.dart' show toEnClock;

void main() {
  test('shift minutes, overnight and totals', () {
    expect(wsShiftMinutes('08:00', '16:30'), 510);
    expect(wsShiftMinutes('22:00', '06:00'), 480); // شب: عبور از نیمه‌شب
    expect(wsShiftMinutes('8:0', '9:00'), isNull);
    final WsShiftTotals t = wsShiftTotals(<Map<String, dynamic>>[
      <String, dynamic>{'shift': 'morning', 'start': '06:00', 'end': '14:00'},
      <String, dynamic>{'shift': 'night', 'start': '22:00', 'end': '06:15'},
    ]);
    expect(t.minutes, 480 + 495);
    expect(t.count, 2);
    expect(t.byShift['night'], 1);
    expect(wsHm(975), '16 ساعت و 15 دقیقه');
  });

  test('persian clock input', () {
    expect(toEnClock('۸:۵'), '08:05');
    expect(toEnClock('22.30'), '22:30');
  });
}
