// فاز ۱ «قابلیت‌های فناورانه» — تشخیص ناهنجاری افت و بازده: آینهٔ Dart هستهٔ ریاضی سرور (backend/api/anomaly_calc.php).
// برای نمایش زنده قبل از بستن عملیات. کیس‌های مشترک: test/anomaly_cases.json (کپی بایت‌به‌بایت backend/api/anomaly_cases.json).
// درصدها روی هزارم درصد صحیح (int) گرد می‌شوند؛ آستانه‌ها روی |z| گرد شده به هزارم (int) مقایسه می‌شوند.

const int kAnMinSample = 8;
const int kAnMaxSample = 30;
const int _zWarn = 2500;
const int _zHigh = 3500;
const int _fallbackPp = 2000;

/// شاخص‌ها: منبع ⇒ (کلید ⇒ [برچسب، جهت]). ترتیب = ترتیب نمایش (همان PB_AN_METRICS).
const Map<String, Map<String, List<String>>> kAnMetrics = <String, Map<String, List<String>>>{
  'workshop': <String, List<String>>{
    'loss_pct': <String>['افت', 'up_bad'],
    'sound_pct': <String>['سالم', 'down_bad'],
  },
  'crack': <String, List<String>>{
    'loss_pct': <String>['افت (ورودی − مغز)', 'up_bad'],
    'real_loss_pct': <String>['افت واقعی', 'up_bad'],
    'shortfall_pct': <String>['کسری مغز نسبت به برآورد', 'up_bad'],
    'sound_pct_input': <String>['سالم نسبت به ورودی', 'down_bad'],
    'sound_pct_kernel': <String>['سالم نسبت به مغز', 'down_bad'],
  },
};

const Map<String, String> kAnLevelLabels = <String, String>{
  'high': 'هشدار جدی', 'warn': 'هشدار', 'low_loss': 'احتمال ثبت ناقص خروجی', 'normal': 'عادی', 'insufficient': 'سابقهٔ کافی نیست',
};

/// همان round() پی‌اچ‌پی (نیمه دور از صفر) با پیش‌گرد برای خنثی کردن خطای دودویی.
double _phpRound(double v, int dec) {
  final double m = _pow10(dec);
  final double x = v * m;
  final double pre = double.parse(x.toStringAsPrecision(15));
  final double r = pre >= 0 ? (pre + 0.5).floorToDouble() : -((-pre + 0.5).floorToDouble());
  return r / m;
}

double _pow10(int n) {
  double r = 1;
  for (int i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

int _phpRoundInt(double v) => _phpRound(v, 0).toInt();

int? anMp(Object? v) {
  if (v == null) return null;
  double? d;
  if (v is num) {
    d = v.toDouble();
  } else {
    d = double.tryParse('$v');
  }
  if (d == null) return null;
  return _phpRoundInt(d * 1000);
}

double anMedian(List<int> xs) {
  if (xs.isEmpty) return 0;
  final List<int> s = List<int>.from(xs)..sort();
  final int m = s.length ~/ 2;
  return s.length.isOdd ? s[m].toDouble() : (s[m - 1] + s[m]) / 2.0;
}

double _medianD(List<double> xs) {
  if (xs.isEmpty) return 0;
  final List<double> s = List<double>.from(xs)..sort();
  final int m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2.0;
}

/// نتیجهٔ ارزیابی یک شاخص (کلیدها مثل خروجی pb_an_eval).
class AnEval {
  const AnEval({required this.level, this.value, this.median, this.mad, this.z, required this.sampleSize, this.ratio, required this.scale});
  final String level;
  final double? value;
  final double? median;
  final double? mad;
  final double? z;
  final int sampleSize;
  final double? ratio;
  final String scale;

  Map<String, Object?> toMap() => <String, Object?>{
        'level': level, 'value': value, 'median': median, 'mad': mad, 'z': z, 'sample_size': sampleSize, 'ratio': ratio, 'scale': scale,
      };
}

AnEval anEval(Object? x, List<Object?> history, String dir) {
  final int? xv = anMp(x);
  final List<int> hs = <int>[];
  for (final Object? h in history) {
    final int? v = anMp(h);
    if (v != null) hs.add(v);
  }
  final List<int> h30 = hs.length > kAnMaxSample ? hs.sublist(0, kAnMaxSample) : hs;
  final int n = h30.length;
  if (xv == null || n < kAnMinSample) {
    return AnEval(level: 'insufficient', value: xv == null ? null : xv / 1000, sampleSize: n, scale: 'none');
  }
  final double med = anMedian(h30);
  final List<double> dev = h30.map((int h) => (h - med).abs()).toList();
  final double mad = _medianD(dev);
  final double d = xv - med;
  double? z;
  String scale = 'mad';
  if (mad > 0) {
    z = 0.6745 * d / mad;
  } else {
    final double mean = dev.fold<double>(0, (double a, double b) => a + b) / n;
    if (mean > 0) {
      z = d / (1.253314 * mean);
      scale = 'meanad';
    } else {
      scale = 'pp';
    }
  }
  String level = 'normal';
  if (z != null) {
    final int zi = _phpRoundInt(z * 1000);
    if (dir == 'up_bad') {
      if (zi >= _zHigh) {
        level = 'high';
      } else if (zi >= _zWarn) {
        level = 'warn';
      } else if (zi <= -_zHigh) {
        level = 'low_loss';
      }
    } else {
      if (zi <= -_zHigh) {
        level = 'high';
      } else if (zi <= -_zWarn) {
        level = 'warn';
      }
    }
  } else {
    final int di = _phpRoundInt(d);
    if (dir == 'up_bad') {
      if (di > _fallbackPp) {
        level = 'warn';
      } else if (di < -_fallbackPp) {
        level = 'low_loss';
      }
    } else if (di < -_fallbackPp) {
      level = 'warn';
    }
  }
  return AnEval(
    level: level,
    value: xv / 1000,
    median: _phpRound(med / 1000, 3),
    mad: _phpRound(mad / 1000, 3),
    z: z == null ? null : _phpRound(z, 3),
    sampleSize: n,
    ratio: med != 0 ? _phpRound(xv / med, 2) : null,
    scale: scale,
  );
}

const Map<String, String> _faDigits = <String, String>{
  '.': '٫', '-': '−', '0': '۰', '1': '۱', '2': '۲', '3': '۳', '4': '۴', '5': '۵', '6': '۶', '7': '۷', '8': '۸', '9': '۹',
};

/// همان pb_an_fa: حداکثر dec رقم اعشار، صفرهای انتهایی حذف، ارقام فارسی و «٫».
String anFa(double v, [int dec = 1]) {
  String s = _phpRound(v, dec).toStringAsFixed(dec);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  if (s == '-0') s = '0';
  return s.split('').map((String c) => _faDigits[c] ?? c).join();
}

String anExplain(String label, AnEval r, [String kindLabel = 'همین نوع']) {
  final String n = anFa(r.sampleSize.toDouble(), 0);
  if (r.level == 'insufficient') return 'سابقهٔ کافی نیست ($n عملیات مشابه؛ حداقل ۸ لازم است).';
  final String v = anFa(r.value ?? 0, 2);
  final String m = anFa(r.median ?? 0, 2);
  String base = '$label این عملیات $v٪ است؛ میانهٔ $n عملیات اخیر $kindLabel $m٪.';
  final double? ratio = r.ratio;
  if (ratio != null && ratio > 0 && (r.level == 'warn' || r.level == 'high' || r.level == 'low_loss')) {
    base = '$label این عملیات ${anFa(ratio, 1)} برابر میانهٔ $n عملیات اخیر $kindLabel است ($v٪ در برابر $m٪).';
  }
  switch (r.level) {
    case 'high':
      return '$base غیرعادی و جدی است؛ بررسی شود.';
    case 'warn':
      return '$base بیش از حد معمول فاصله دارد.';
    case 'low_loss':
      return '$base افت به‌طور غیرعادی کم است؛ احتمال ثبت ناقص خروجی.';
    default:
      return '$base در محدودهٔ عادی است.';
  }
}

/// یک ردیف ارزیابی شاخص (مثل خروجی pb_an_evaluate).
class AnRow {
  const AnRow({required this.metric, required this.label, required this.dir, required this.eval, required this.text});
  final String metric;
  final String label;
  final String dir;
  final AnEval eval;
  final String text;
}

List<AnRow> anEvaluate(String source, Map<String, Object?> values, Map<String, List<Object?>> histories, [String kindLabel = 'همین نوع']) {
  final List<AnRow> out = <AnRow>[];
  final Map<String, List<String>> ms = kAnMetrics[source] ?? const <String, List<String>>{};
  for (final MapEntry<String, List<String>> e in ms.entries) {
    if (!values.containsKey(e.key) || values[e.key] == null) continue;
    final AnEval r = anEval(values[e.key], histories[e.key] ?? const <Object?>[], e.value[1]);
    out.add(AnRow(metric: e.key, label: e.value[0], dir: e.value[1], eval: r, text: anExplain(e.value[0], r, kindLabel)));
  }
  return out;
}

const Map<String, int> _rank = <String, int>{'insufficient': 0, 'normal': 1, 'low_loss': 2, 'warn': 3, 'high': 4};

String anWorst(List<AnRow> rows) {
  String w = 'insufficient';
  for (final AnRow r in rows) {
    if ((_rank[r.eval.level] ?? 0) > (_rank[w] ?? 0)) w = r.eval.level;
  }
  return w;
}
