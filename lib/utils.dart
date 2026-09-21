/// تبدیل ارقام فارسی/عربی به انگلیسی و پاکسازی جداکننده‌ها
String toEnDigits(String s) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  const ar = '٠١٢٣٤٥٦٧٨٩';
  var out = s;
  for (var i = 0; i < 10; i++) {
    out = out.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
  }
  return out
      .replaceAll('٫', '.')
      .replaceAll('/', '.')
      .replaceAll('٬', '')
      .replaceAll(',', '');
}

double? parseNum(String? s) {
  if (s == null) return null;
  final t = toEnDigits(s.trim());
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

String toFaDigits(String s) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  return s.replaceAllMapped(RegExp(r'\d'), (m) => fa[int.parse(m[0]!)]);
}

/// عدد با جداکننده هزارگان و ارقام فارسی
String faNum(num v, {int dec = 2}) {
  var s = v.toStringAsFixed(dec);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  final parts = s.split('.');
  final neg = parts[0].startsWith('-');
  final ip = neg ? parts[0].substring(1) : parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < ip.length; i++) {
    if (i > 0 && (ip.length - i) % 3 == 0) buf.write(',');
    buf.write(ip[i]);
  }
  final result =
      '${neg ? '-' : ''}$buf${parts.length > 1 ? '.${parts[1]}' : ''}';
  return toFaDigits(result).replaceAll(',', '٬').replaceAll('.', '٫');
}

/// عدد ساده (بدون جداکننده) برای پر کردن فیلدها
String plain(num v) {
  var s = v.toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s;
}

List<int> gregorianToJalali(int gy, int gm, int gd) {
  const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 +
      (365 * gy) +
      ((gy2 + 3) ~/ 4) -
      ((gy2 + 99) ~/ 100) +
      ((gy2 + 399) ~/ 400) +
      gd +
      gdm[gm - 1];
  var jy = -1595 + (33 * (days ~/ 12053));
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  final jm = days < 186 ? 1 + days ~/ 31 : 7 + (days - 186) ~/ 30;
  final jd = 1 + (days < 186 ? days % 31 : (days - 186) % 30);
  return [jy, jm, jd];
}

/// تاریخ شمسی از رشته ISO
String jalaliDate(String iso) {
  final d = DateTime.parse(iso);
  final j = gregorianToJalali(d.year, d.month, d.day);
  final m = j[1].toString().padLeft(2, '0');
  final day = j[2].toString().padLeft(2, '0');
  return toFaDigits('${j[0]}/$m/$day');
}
