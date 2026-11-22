// فاز ۴ «قابلیت‌های فناورانه» — بهینه‌ساز کوت‌ریزی: آینهٔ Dart هستهٔ سرور (backend/api/blend_opt_calc.php)، خط‌به‌خط با همان ترتیب عملیات
// تا جواب‌ها یکسان باشند. کیس‌های مشترک: test/blend_cases.json (کپی بایت‌به‌بایت backend/api/blend_cases.json).
// simplex دومرحله‌ای با متغیرهای کران‌دار؛ Dantzig و پس از ۲۰ گام تبهگن پیاپی قاعدهٔ Bland (ضدچرخه)؛ گرد کردن به گرم صحیح با مجموع دقیقاً T.

const double kBoTol = 1e-9;
const int kBoMaxIter = 50000;
const int kBoBlandAfter = 20;
const double kBoMinTake = 5.0;
const double kBoAvgTol = 0.001;

const Map<String, String> kBoMetrics = <String, String>{
  'ounce': 'انس', 'gram': 'گرم (درصد مغز)', 'khandan_pct': 'درصد خندان', 'dombest_pct': 'درصد دهن‌بست',
  'tuchin_pct': 'درصد توچین', 'crooked_pct': 'درصد کج', 'defect_pct': 'درصد ایراد', 'moisture_pct': 'درصد رطوبت',
};

const double _inf = double.infinity;

/// همان round() پی‌اچ‌پی (نیمه دور از صفر، با پیش‌گرد)
double boRound(double v, [int dec = 0]) {
  double m = 1;
  for (int i = 0; i < dec; i++) {
    m *= 10;
  }
  final double x = double.parse((v * m).toStringAsPrecision(15));
  final double r = x >= 0 ? (x + 0.5).floorToDouble() : -((-x + 0.5).floorToDouble());
  final double o = r / m;
  return o == 0 ? 0.0 : o;
}

/// تبدیل عدد به رشته مثل PHP (۳۳٫۰ ⇒ «33»)
String boNumStr(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  String s = v.toStringAsPrecision(14);
  if (s.contains('.') && !s.contains('e')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

class BoLp {
  BoLp(this.status, this.y, this.obj, this.iter);
  final String status;
  final List<double>? y;
  final double? obj;
  final int iter;
}

BoLp boSimplex(List<List<double>> a, List<String> rel, List<double> b, List<double> c, List<double> u) {
  final int m = a.length;
  final int n = c.length;
  final List<double> ub = List<double>.from(u);
  final List<double> cost = List<double>.from(c);
  final List<bool> isArt = List<bool>.filled(n, false, growable: true);
  int bigN = n;
  final Map<int, int> slackOf = <int, int>{};
  for (int i = 0; i < m; i++) {
    if (rel[i] != '=') {
      slackOf[i] = bigN++;
      ub.add(_inf);
      cost.add(0.0);
      isArt.add(false);
    }
  }
  final List<int> artOf = <int>[];
  for (int i = 0; i < m; i++) {
    artOf.add(bigN++);
    ub.add(_inf);
    cost.add(0.0);
    isArt.add(true);
  }
  final List<List<double>> rows = <List<double>>[];
  final List<double> rhs = <double>[];
  for (int i = 0; i < m; i++) {
    final List<double> row = List<double>.filled(bigN, 0.0);
    for (int j = 0; j < n; j++) {
      row[j] = a[i][j];
    }
    if (slackOf.containsKey(i)) row[slackOf[i]!] = rel[i] == '<=' ? 1.0 : -1.0;
    double bi = b[i];
    if (bi < 0) {
      for (int j = 0; j < bigN; j++) {
        row[j] = -row[j];
      }
      bi = -bi;
    }
    row[artOf[i]] = 1.0;
    rows.add(row);
    rhs.add(bi);
  }
  final List<int> basis = List<int>.from(artOf);
  final List<double> beta = List<double>.from(rhs);
  final List<bool> atUp = List<bool>.filled(bigN, false);
  int iter = 0;

  String run(List<double> cc) {
    final List<double> d = List<double>.from(cc);
    for (int i = 0; i < m; i++) {
      final double cb = cc[basis[i]];
      if (cb != 0.0) {
        for (int j = 0; j < bigN; j++) {
          d[j] -= cb * rows[i][j];
        }
      }
    }
    final List<bool> inBasis = List<bool>.filled(bigN, false);
    for (final int bj in basis) {
      inBasis[bj] = true;
    }
    int degen = 0;
    while (true) {
      if (++iter > kBoMaxIter) return 'iter_limit';
      int e = -1;
      int dir = 0;
      double best = 0.0;
      final bool bland = degen >= kBoBlandAfter;
      for (int j = 0; j < bigN; j++) {
        if (inBasis[j] || ub[j] <= 0.0) continue;
        double v;
        int dj;
        if (!atUp[j] && d[j] < -kBoTol) {
          v = -d[j];
          dj = 1;
        } else if (atUp[j] && d[j] > kBoTol) {
          v = d[j];
          dj = -1;
        } else {
          continue;
        }
        if (bland) {
          e = j;
          dir = dj;
          break;
        }
        if (v > best) {
          best = v;
          e = j;
          dir = dj;
        }
      }
      if (e < 0) return 'optimal';
      double tMax = ub[e];
      int r = -1;
      bool rToUp = false;
      for (int i = 0; i < m; i++) {
        final double al = dir * rows[i][e];
        double t;
        bool toUp;
        if (al > kBoTol) {
          t = beta[i] / al;
          toUp = false;
        } else if (al < -kBoTol && ub[basis[i]].isFinite) {
          t = (ub[basis[i]] - beta[i]) / (-al);
          toUp = true;
        } else {
          continue;
        }
        if (t < 0) t = 0.0;
        if (t < tMax - kBoTol ||
            (r >= 0 && (t - tMax).abs() <= kBoTol && basis[i] < basis[r]) ||
            (r < 0 && (t - tMax).abs() <= kBoTol && tMax.isFinite && t < tMax)) {
          tMax = t;
          r = i;
          rToUp = toUp;
        }
      }
      if (r < 0 && !tMax.isFinite) return 'unbounded';
      degen = tMax <= kBoTol ? degen + 1 : 0;
      for (int i = 0; i < m; i++) {
        beta[i] -= dir * rows[i][e] * tMax;
      }
      if (r < 0) {
        atUp[e] = !atUp[e];
        continue;
      }
      final double enterVal = (atUp[e] ? ub[e] : 0.0) + dir * tMax;
      final int leave = basis[r];
      atUp[leave] = rToUp;
      inBasis[leave] = false;
      inBasis[e] = true;
      final double piv = rows[r][e];
      final List<int> nz = <int>[];
      for (int j = 0; j < bigN; j++) {
        if (rows[r][j] != 0.0) {
          rows[r][j] /= piv;
          nz.add(j);
        }
      }
      final List<double> pr = List<double>.from(rows[r]);
      for (int i = 0; i < m; i++) {
        if (i == r) continue;
        final double f = rows[i][e];
        if (f == 0.0) continue;
        for (final int j in nz) {
          rows[i][j] -= f * pr[j];
        }
      }
      final double f = d[e];
      if (f != 0.0) {
        for (final int j in nz) {
          d[j] -= f * pr[j];
        }
      }
      basis[r] = e;
      beta[r] = enterVal;
      atUp[e] = false;
    }
  }

  final List<double> c1 = List<double>.filled(bigN, 0.0);
  for (final int x in artOf) {
    c1[x] = 1.0;
  }
  String st = run(c1);
  if (st != 'optimal') return BoLp(st, null, null, iter);
  double infeas = 0.0;
  for (int i = 0; i < m; i++) {
    if (isArt[basis[i]]) infeas += beta[i];
  }
  double scale = 1.0;
  for (final double v in rhs) {
    scale = scale > v.abs() ? scale : v.abs();
  }
  if (infeas > 1e-7 * scale) return BoLp('infeasible', null, null, iter);
  for (int i = 0; i < m; i++) {
    if (!isArt[basis[i]]) continue;
    for (int j = 0; j < bigN; j++) {
      if (isArt[j] || basis.contains(j) || rows[i][j].abs() <= 1e-9) continue;
      final double val = atUp[j] ? ub[j] : 0.0;
      final double piv = rows[i][j];
      for (int k = 0; k < bigN; k++) {
        rows[i][k] /= piv;
      }
      for (int q = 0; q < m; q++) {
        if (q == i) continue;
        final double f = rows[q][j];
        if (f == 0.0) continue;
        for (int k = 0; k < bigN; k++) {
          rows[q][k] -= f * rows[i][k];
        }
      }
      basis[i] = j;
      beta[i] = val;
      atUp[j] = false;
      break;
    }
  }
  for (final int x in artOf) {
    ub[x] = 0.0;
    atUp[x] = false;
  }
  st = run(cost);
  if (st != 'optimal') return BoLp(st, null, null, iter);
  final List<double> y = List<double>.filled(n, 0.0);
  for (int j = 0; j < n; j++) {
    y[j] = atUp[j] ? ub[j] : 0.0;
  }
  for (int i = 0; i < m; i++) {
    if (basis[i] < n) y[basis[i]] = beta[i];
  }
  for (int j = 0; j < n; j++) {
    if (y[j] < 0) y[j] = 0.0;
    if (u[j].isFinite && y[j] > u[j]) y[j] = u[j];
  }
  double obj = 0.0;
  for (int j = 0; j < n; j++) {
    obj += c[j] * y[j];
  }
  return BoLp('optimal', y, obj, iter);
}

double? boNum(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) {
    if (v.isEmpty) return null;
    return double.tryParse(v.trim());
  }
  return null;
}

/// لات آماده (کپی ورودی + کران‌ها)
class BoLot {
  BoLot(this.src, this.lo, this.hi, this.forced);
  final Map<String, dynamic> src;
  final double lo;
  final double hi;
  final bool forced;
  int get id => (src['id'] as num).toInt();
  String? get code => src['code'] as String?;
  double get kg => boNum(src['kg']) ?? 0;
  double? get cost => boNum(src['cost']);
  String get date => '${src['date'] ?? ''}';
  double? q(String k) => src['q'] is Map ? boNum((src['q'] as Map)[k]) : null;
}

class _Prep {
  _Prep(this.use, this.excluded, this.warnings, this.bounds, this.err);
  final List<BoLot> use;
  final List<Map<String, dynamic>> excluded;
  final List<String> warnings;
  final Map<String, List<double?>> bounds;
  final String? err;
}

List<int> _ints(Object? v) => v is List ? v.map((Object? x) => boNum(x)?.toInt() ?? 0).toList() : <int>[];

_Prep _prepare(List<Map<String, dynamic>> lots, Map<String, dynamic> req) {
  final String obj = '${req['objective'] ?? 'cost'}';
  final Map<String, List<double?>> bounds = <String, List<double?>>{};
  final Object? rb = req['bounds'];
  if (rb is Map) {
    for (final MapEntry<dynamic, dynamic> e in rb.entries) {
      final String k = '${e.key}';
      if (!kBoMetrics.containsKey(k)) continue;
      double? lo;
      double? up;
      if (e.value is List) {
        final List<dynamic> l = e.value as List<dynamic>;
        lo = l.isNotEmpty ? boNum(l[0]) : null;
        up = l.length > 1 ? boNum(l[1]) : null;
      } else if (e.value is Map) {
        lo = boNum((e.value as Map)['min']);
        up = boNum((e.value as Map)['max']);
      } else {
        continue;
      }
      if (lo == null && up == null) continue;
      if (lo != null && up != null && lo > up) return _Prep(<BoLot>[], <Map<String, dynamic>>[], <String>[], bounds, 'برای «${kBoMetrics[k]}» حداقل از حداکثر بیشتر است');
      bounds[k] = <double?>[lo, up];
    }
  }
  final List<int> forced = _ints(req['forced']);
  final List<int> forbidden = _ints(req['forbidden']);
  final Map<dynamic, dynamic> per = req['per_lot'] is Map ? req['per_lot'] as Map<dynamic, dynamic> : <dynamic, dynamic>{};
  final double minTake = boNum(req['min_take_kg']) ?? kBoMinTake;
  final List<BoLot> use = <BoLot>[];
  final List<Map<String, dynamic>> excluded = <Map<String, dynamic>>[];
  final List<String> warn = <String>[];
  for (final Map<String, dynamic> l in lots) {
    final int id = (l['id'] as num).toInt();
    final double kg = boNum(l['kg']) ?? 0;
    final String label = '${l['code'] ?? id}';
    if (forbidden.contains(id)) {
      excluded.add(<String, dynamic>{'id': id, 'reason': 'forbidden'});
      continue;
    }
    if (kg <= 0) {
      excluded.add(<String, dynamic>{'id': id, 'reason': 'no_stock'});
      continue;
    }
    if (obj == 'cost' && (boNum(l['cost']) == null || boNum(l['cost'])! <= 0)) {
      excluded.add(<String, dynamic>{'id': id, 'reason': 'no_cost'});
      warn.add('لات $label بها ندارد و کنار گذاشته شد');
      continue;
    }
    final Map<dynamic, dynamic> q = l['q'] is Map ? l['q'] as Map<dynamic, dynamic> : <dynamic, dynamic>{};
    final List<String> miss = <String>[];
    for (final String k in bounds.keys) {
      if (boNum(q[k]) == null) miss.add(kBoMetrics[k]!);
    }
    if (miss.isNotEmpty) {
      excluded.add(<String, dynamic>{'id': id, 'reason': 'missing_metric'});
      warn.add('لات $label مقدار ${miss.join('، ')} ندارد و کنار گذاشته شد');
      continue;
    }
    final Map<dynamic, dynamic> pl = per['$id'] is Map ? per['$id'] as Map<dynamic, dynamic> : (per[id] is Map ? per[id] as Map<dynamic, dynamic> : <dynamic, dynamic>{});
    final double maxP = boNum(pl['max']) ?? _inf;
    final double hi = kg < maxP ? kg : maxP;
    final double minP = boNum(pl['min']) ?? 0.0;
    double lo = minP > 0.0 ? minP : 0.0;
    final bool isForced = forced.contains(id);
    if (isForced && lo <= 0) lo = minTake < hi ? minTake : hi;
    if (lo > hi + 1e-9) return _Prep(<BoLot>[], <Map<String, dynamic>>[], <String>[], bounds, 'حداقل برداشت لات $label از موجودی/حداکثر آن بیشتر است');
    use.add(BoLot(l, lo, hi, isForced));
  }
  use.sort((BoLot a, BoLot b) => a.id.compareTo(b.id));
  return _Prep(use, excluded, warn, bounds, null);
}

class _LpRes {
  _LpRes(this.status, this.x, this.obj, this.iter);
  final String status;
  final List<double>? x;
  final double? obj;
  final int iter;
}

_LpRes _lp(List<BoLot> use, double t, Map<String, List<double?>> bounds, String obj,
    {double margin = 0.0, String? relax, Map<int, double> hiOverride = const <int, double>{}}) {
  final int n = use.length;
  final List<double> lo = List<double>.filled(n, 0.0);
  final List<double> hi = List<double>.filled(n, 0.0);
  final List<double> c = List<double>.filled(n, 0.0);
  final List<String> dates = use.map((BoLot l) => l.date).toList();
  final List<String> sorted = List<String>.from(dates)..sort();
  final Map<String, int> rank = <String, int>{};
  for (int i = 0; i < sorted.length; i++) {
    rank.putIfAbsent(sorted[i], () => i);
  }
  double cmax = 0.0;
  for (final BoLot l in use) {
    final double v = l.cost ?? 0;
    if (v > cmax) cmax = v;
  }
  for (int i = 0; i < n; i++) {
    final BoLot l = use[i];
    lo[i] = l.lo;
    hi[i] = hiOverride.containsKey(i) ? (l.hi < hiOverride[i]! ? l.hi : hiOverride[i]!) : l.hi;
    if (hi[i] < lo[i]) hi[i] = lo[i];
    if (obj == 'cost') {
      c[i] = cmax > 0 ? (l.cost ?? 0) / cmax : 0.0;
    } else if (obj == 'few') {
      c[i] = 1.0 / (l.hi > 1e-6 ? l.hi : 1e-6);
    } else {
      c[i] = (rank[dates[i]]! + 1) / (n > 1 ? n : 1);
    }
  }
  final List<List<double>> a = <List<double>>[];
  final List<String> rel = <String>[];
  final List<double> b = <double>[];
  a.add(List<double>.filled(n, 1.0));
  rel.add('=');
  double sumLo = 0.0;
  for (final double v in lo) {
    sumLo += v;
  }
  b.add(t - sumLo);
  for (final MapEntry<String, List<double?>> be in bounds.entries) {
    final String k = be.key;
    final double? lB = be.value[0];
    final double? uB = be.value[1];
    final bool eq = lB != null && uB != null && (uB - lB).abs() <= 1e-12;
    double? mL = lB;
    double? mU = uB;
    if (!eq && margin > 0) {
      final double w = (lB != null && uB != null) ? (uB - lB) / 4 : margin;
      final double mg = margin < w ? margin : w;
      if (lB != null) mL = lB + mg;
      if (uB != null) mU = uB - mg;
    }
    final List<double> q = use.map((BoLot l) => l.q(k)!).toList();
    if (eq && relax != '$k:L' && relax != '$k:U') {
      final List<double> row = List<double>.filled(n, 0.0);
      double s = 0.0;
      for (int i = 0; i < n; i++) {
        row[i] = q[i] - lB;
        s += (q[i] - lB) * lo[i];
      }
      a.add(row);
      rel.add('=');
      b.add(-s);
      continue;
    }
    if (mU != null && relax != '$k:U') {
      final List<double> row = List<double>.filled(n, 0.0);
      double s = 0.0;
      for (int i = 0; i < n; i++) {
        row[i] = q[i] - mU;
        s += (q[i] - mU) * lo[i];
      }
      a.add(row);
      rel.add('<=');
      b.add(-s);
    }
    if (mL != null && relax != '$k:L') {
      final List<double> row = List<double>.filled(n, 0.0);
      double s = 0.0;
      for (int i = 0; i < n; i++) {
        row[i] = q[i] - mL;
        s += (q[i] - mL) * lo[i];
      }
      a.add(row);
      rel.add('>=');
      b.add(-s);
    }
  }
  final List<double> u = List<double>.generate(n, (int i) => hi[i] - lo[i] > 0.0 ? hi[i] - lo[i] : 0.0);
  if (b[0] < -1e-9) return _LpRes('infeasible', null, null, 0);
  final BoLp r = boSimplex(a, rel, b, c, u);
  if (r.status != 'optimal') return _LpRes(r.status, null, null, r.iter);
  final List<double> x = List<double>.generate(n, (int i) => lo[i] + r.y![i]);
  return _LpRes('optimal', x, r.obj, r.iter);
}

Map<String, double?> boAvgs(List<BoLot> use, List<int> g) {
  int tot = 0;
  for (final int v in g) {
    tot += v;
  }
  final Map<String, double?> o = <String, double?>{};
  for (final String k in kBoMetrics.keys) {
    double s = 0.0;
    int w = 0;
    bool ok = true;
    for (int i = 0; i < use.length; i++) {
      if (g[i] <= 0) continue;
      final double? v = use[i].q(k);
      if (v == null) {
        ok = false;
        break;
      }
      s += v * g[i];
      w += g[i];
    }
    o[k] = (ok && w > 0 && tot > 0) ? boRound(s / w, 4) : null;
  }
  return o;
}

double boViolation(List<BoLot> use, List<int> g, Map<String, List<double?>> bounds) {
  final Map<String, double?> av = boAvgs(use, g);
  double v = 0.0;
  for (final MapEntry<String, List<double?>> e in bounds.entries) {
    final double? a = av[e.key];
    if (a == null) continue;
    final double? lB = e.value[0];
    final double? uB = e.value[1];
    if (uB != null && a > uB + kBoAvgTol) v += a - uB;
    if (lB != null && a < lB - kBoAvgTol) v += lB - a;
  }
  return v;
}

List<int> boRoundGrams(List<BoLot> use, List<double> x, double t, Map<String, List<double?>> bounds) {
  final int tg = boRound(t * 1000).toInt();
  final int n = use.length;
  final List<int> g = List<int>.filled(n, 0);
  final List<double> frac = List<double>.filled(n, 0.0);
  final List<int> loG = List<int>.filled(n, 0);
  final List<int> hiG = List<int>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    loG[i] = (use[i].lo * 1000 - 1e-6).ceil();
    hiG[i] = (use[i].hi * 1000 + 1e-6).floor();
    final double v = (x[i] > 0 ? x[i] : 0.0) * 1000;
    final int fl = (v + 1e-6).floor();
    g[i] = fl < hiG[i] ? fl : hiG[i];
    if (g[i] < loG[i]) g[i] = loG[i];
    frac[i] = v - (v + 1e-6).floorToDouble();
  }
  int rest = tg;
  for (final int v in g) {
    rest -= v;
  }
  final List<int> order = List<int>.generate(n, (int i) => i);
  order.sort((int a, int b) {
    final int c = frac[b].compareTo(frac[a]);
    return c != 0 ? c : a.compareTo(b);
  });
  int guard = 0;
  while (rest != 0 && guard++ < 100000) {
    bool moved = false;
    for (final int i in order) {
      if (rest > 0 && g[i] < hiG[i] && (x[i] > 0 || guard > order.length)) {
        g[i]++;
        rest--;
        moved = true;
      } else if (rest < 0 && g[i] > loG[i]) {
        g[i]--;
        rest++;
        moved = true;
      }
      if (rest == 0) break;
    }
    if (!moved && guard > order.length + 1) break;
  }
  double viol = boViolation(use, g, bounds);
  for (int step = 0; step < 5000 && viol > 0; step++) {
    List<int>? best;
    double bestV = viol;
    for (int i = 0; i < n; i++) {
      if (g[i] <= loG[i]) continue;
      for (int j = 0; j < n; j++) {
        if (i == j || g[j] >= hiG[j] || (g[j] <= 0 && x[j] <= 0)) continue;
        g[i]--;
        g[j]++;
        final double v = boViolation(use, g, bounds);
        g[i]++;
        g[j]--;
        if (v < bestV - 1e-12) {
          bestV = v;
          best = <int>[i, j];
        }
      }
    }
    if (best == null) break;
    g[best[0]]--;
    g[best[1]]++;
    viol = bestV;
  }
  return g;
}

List<int> boSimple(List<BoLot> use, double t) {
  final List<int> idx = List<int>.generate(use.length, (int i) => i);
  idx.sort((int a, int b) {
    final int c = use[a].date.compareTo(use[b].date);
    return c != 0 ? c : use[a].id.compareTo(use[b].id);
  });
  int left = boRound(t * 1000).toInt();
  final List<int> g = List<int>.filled(use.length, 0);
  for (final int i in idx) {
    if (left <= 0) break;
    final int cap = (use[i].hi * 1000 + 1e-6).floor();
    final int take = left < cap ? left : cap;
    g[i] = take;
    left -= take;
  }
  return left > 0 ? <int>[] : g;
}

double? boCost(List<BoLot> use, List<int> g) {
  double s = 0.0;
  for (int i = 0; i < use.length; i++) {
    if (g[i] <= 0) continue;
    final double? c = use[i].cost;
    if (c == null) return null;
    s += c * g[i] / 1000;
  }
  return boRound(s, 2);
}

Map<String, dynamic> _result(List<BoLot> use, List<int> g, Map<String, List<double?>> bounds) {
  final List<Map<String, dynamic>> takes = <Map<String, dynamic>>[];
  int sumG = 0;
  for (int i = 0; i < use.length; i++) {
    sumG += g[i];
    if (g[i] > 0) {
      takes.add(<String, dynamic>{
        'id': use[i].id, 'code': use[i].code, 'kg': g[i] / 1000, 'left_kg': boRound(use[i].kg - g[i] / 1000, 3), 'cost': use[i].cost,
      });
    }
  }
  final double tot = sumG / 1000;
  final double? cost = boCost(use, g);
  final List<int> simple = boSimple(use, tot);
  final double? simpleCost = simple.isNotEmpty ? boCost(use, simple) : null;
  final bool simpleOk = simple.isNotEmpty && boViolation(use, simple, bounds) <= 0;
  final Map<String, double?> av = boAvgs(use, g);
  final Map<String, dynamic> metrics = <String, dynamic>{};
  av.forEach((String k, double? v) {
    metrics[k] = <String, dynamic>{'label': kBoMetrics[k], 'value': v, 'min': bounds[k]?[0], 'max': bounds[k]?[1]};
  });
  return <String, dynamic>{
    'takes': takes,
    'lots_count': takes.length,
    'total_kg': tot,
    'cost_total': cost,
    'cost_per_kg': (cost != null && tot > 0) ? boRound(cost / tot, 2) : null,
    'metrics': metrics,
    'simple': simple.isNotEmpty
        ? <String, dynamic>{
            'cost_total': simpleCost,
            'cost_per_kg': (simpleCost != null && tot > 0) ? boRound(simpleCost / tot, 2) : null,
            'meets_bounds': simpleOk,
            'lots_count': simple.where((int x) => x != 0).length,
          }
        : null,
    'saving': (cost != null && simpleCost != null) ? boRound(simpleCost - cost, 2) : null,
  };
}

Map<String, dynamic> _diagnose(List<BoLot> use, double t, Map<String, List<double?>> bounds, String obj) {
  final List<Map<String, dynamic>> blocking = <Map<String, dynamic>>[];
  for (final MapEntry<String, List<double?>> e in bounds.entries) {
    for (final String side in <String>['L', 'U']) {
      final double? val = side == 'L' ? e.value[0] : e.value[1];
      if (val == null) continue;
      final _LpRes r = _lp(use, t, bounds, obj, relax: '${e.key}:$side');
      if (r.status == 'optimal') {
        blocking.add(<String, dynamic>{
          'kind': 'bound', 'metric': e.key, 'side': side == 'L' ? 'min' : 'max',
          'text': '${side == 'L' ? 'حداقل ' : 'حداکثر '}${kBoMetrics[e.key]} (${boNumStr(val)})',
        });
      }
    }
  }
  if (blocking.isEmpty) blocking.add(<String, dynamic>{'kind': 'combined', 'text': 'ترکیب چند قید با هم مانع است (با آزاد کردن هیچ قید تکی جواب پیدا نشد)'});
  final int n = use.length;
  final List<List<Object>> keys = <List<Object>>[];
  bounds.forEach((String k, List<double?> lu) {
    if (lu[1] != null) keys.add(<Object>[k, 'U', lu[1]!]);
    if (lu[0] != null) keys.add(<Object>[k, 'L', lu[0]!]);
  });
  final int ne = keys.length;
  final List<double> lo = use.map((BoLot l) => l.lo).toList();
  final List<double> c = List<double>.filled(n + ne, 0.0);
  final List<double> u = List<double>.filled(n + ne, 0.0);
  for (int i = 0; i < n; i++) {
    c[i] = 0.0;
    final double v = use[i].hi - lo[i];
    u[i] = v > 0.0 ? v : 0.0;
  }
  for (int e = 0; e < ne; e++) {
    final String k = keys[e][0] as String;
    final List<double> qs = use.map((BoLot l) => l.q(k)!).toList();
    double mx = qs.first, mn = qs.first;
    for (final double v in qs) {
      if (v > mx) mx = v;
      if (v < mn) mn = v;
    }
    final double span = (mx - mn) > 1e-6 ? mx - mn : 1e-6;
    c[n + e] = 1.0 / span;
    u[n + e] = _inf;
  }
  final List<List<double>> a = <List<double>>[];
  final List<String> rel = <String>[];
  final List<double> b = <double>[];
  final List<double> row0 = List<double>.filled(n + ne, 0.0);
  for (int i = 0; i < n; i++) {
    row0[i] = 1.0;
  }
  a.add(row0);
  rel.add('=');
  double sumLo = 0.0;
  for (final double v in lo) {
    sumLo += v;
  }
  b.add(t - sumLo);
  for (int e = 0; e < ne; e++) {
    final String k = keys[e][0] as String;
    final String side = keys[e][1] as String;
    final double val = keys[e][2] as double;
    final List<double> row = List<double>.filled(n + ne, 0.0);
    double s = 0.0;
    for (int i = 0; i < n; i++) {
      row[i] = use[i].q(k)! - val;
      s += row[i] * lo[i];
    }
    if (side == 'U') {
      row[n + e] = -t;
      a.add(row);
      rel.add('<=');
      b.add(-s);
    } else {
      row[n + e] = t;
      a.add(row);
      rel.add('>=');
      b.add(-s);
    }
  }
  final BoLp r = boSimplex(a, rel, b, c, u);
  Map<String, dynamic>? nearest;
  if (r.status == 'optimal') {
    final List<double> x = List<double>.generate(n, (int i) => lo[i] + r.y![i]);
    final List<int> g = boRoundGrams(use, x, t, const <String, List<double?>>{});
    final Map<String, dynamic> res = _result(use, g, bounds);
    final Map<String, dynamic> ms = res['metrics'] as Map<String, dynamic>;
    ms.forEach((String k, dynamic m) {
      final Map<String, dynamic> mm = m as Map<String, dynamic>;
      mm['deviation'] = null;
      final double? v = mm['value'] as double?;
      if (!bounds.containsKey(k) || v == null) return;
      final double? lB = bounds[k]![0];
      final double? uB = bounds[k]![1];
      mm['deviation'] = (uB != null && v > uB) ? boRound(v - uB, 4) : ((lB != null && v < lB) ? boRound(v - lB, 4) : 0.0);
    });
    nearest = res;
  }
  return <String, dynamic>{'status': 'infeasible', 'blocking': blocking, 'nearest': nearest};
}

/// حل کامل (مثل pb_bo_solve). lots: [{id, code?, kg, cost?, date?, q:{metric: value}}]
Map<String, dynamic> boSolve(List<Map<String, dynamic>> lots, Map<String, dynamic> req) {
  final double? t = boNum(req['target_kg']);
  final String obj = '${req['objective'] ?? 'cost'}';
  if (!<String>['cost', 'few', 'oldest'].contains(obj)) return <String, dynamic>{'status': 'invalid', 'message': 'هدف نامعتبر است'};
  if (t == null || t <= 0) return <String, dynamic>{'status': 'invalid', 'message': 'وزن کل هدف را وارد کنید'};
  final _Prep p = _prepare(lots, req);
  if (p.err != null) return <String, dynamic>{'status': 'invalid', 'message': p.err};
  final List<BoLot> use = p.use;
  final double minTake = boNum(req['min_take_kg']) ?? kBoMinTake;
  final Map<String, dynamic> base = <String, dynamic>{
    'objective': obj, 'target_kg': t, 'excluded': p.excluded, 'warnings': List<String>.from(p.warnings), 'used_lots': use.length,
  };
  double avail = 0.0, forcedSum = 0.0;
  for (final BoLot l in use) {
    avail += l.hi;
    forcedSum += l.lo;
  }
  if (avail + 1e-9 < t) {
    return <String, dynamic>{
      ...base,
      'status': 'infeasible',
      'blocking': <Map<String, dynamic>>[
        <String, dynamic>{'kind': 'stock', 'text': 'موجودی لات‌های قابل‌استفاده (${boNumStr(boRound(avail, 3))} کیلو) از وزن هدف کمتر است'},
      ],
      'available_kg': boRound(avail, 3),
      'nearest': null,
    };
  }
  if (forcedSum > t + 1e-9) {
    return <String, dynamic>{
      ...base,
      'status': 'infeasible',
      'blocking': <Map<String, dynamic>>[<String, dynamic>{'kind': 'forced', 'text': 'جمع حداقل برداشت لات‌های اجباری از وزن هدف بیشتر است'}],
      'nearest': null,
    };
  }
  double margin = 0.002;
  _LpRes r = _lp(use, t, p.bounds, obj, margin: margin);
  if (r.status != 'optimal') {
    margin = 0.0;
    r = _lp(use, t, p.bounds, obj);
  }
  if (r.status != 'optimal') return <String, dynamic>{...base, ..._diagnose(use, t, p.bounds, obj)};
  int iter = r.iter;
  final Map<int, double> over = <int, double>{};
  for (int round = 0; round < 10; round++) {
    final Map<int, double> small = <int, double>{};
    for (int i = 0; i < r.x!.length; i++) {
      final double v = r.x![i];
      if (v > 1e-6 && v < minTake - 1e-9 && !use[i].forced && use[i].lo <= 0) small[i] = 0.0;
    }
    if (small.isEmpty) break;
    final _LpRes tr = _lp(use, t, p.bounds, obj, margin: margin, hiOverride: <int, double>{...over, ...small});
    if (tr.status != 'optimal') {
      (base['warnings'] as List<String>).add('برداشت‌های کمتر از ${boNumStr(minTake)} کیلو حذف نشد چون بدون آن‌ها جواب ممکن نبود');
      break;
    }
    over.addAll(small);
    r = tr;
    iter += tr.iter;
  }
  final List<int> g = boRoundGrams(use, r.x!, t, p.bounds);
  if (boViolation(use, g, p.bounds) > 0) (base['warnings'] as List<String>).add('گرد کردن به گرم، میانگین یک شاخص را کمی از کران بیرون برد');
  return <String, dynamic>{...base, ..._result(use, g, p.bounds), 'status': 'optimal', 'iterations': iter};
}

/// مولد شبه‌تصادفی قطعی مشترک با PHP (LCG، پیمانهٔ 2^31)
class BoLcg {
  BoLcg(this.s);
  int s;
  double next() {
    s = (s * 1103515245 + 12345) % 2147483648;
    return s / 2147483648;
  }
}

List<Map<String, dynamic>> boRandomLots(int n, int seed) {
  final BoLcg r = BoLcg(seed);
  String two(int v) => v.toString().padLeft(2, '0');
  final List<Map<String, dynamic>> o = <Map<String, dynamic>>[];
  for (int i = 1; i <= n; i++) {
    final double kg = boRound(50 + r.next() * 950, 3);
    final double cost = boRound(1200000 + r.next() * 800000);
    final int mo = 1 + (r.next() * 10).floor();
    final int dd = 1 + (r.next() * 28).floor();
    final double ounce = boRound(24 + r.next() * 8, 2);
    final double gram = boRound(40 + r.next() * 10, 2);
    final double kh = boRound(70 + r.next() * 28, 2);
    final double mo2 = boRound(3 + r.next() * 4, 2);
    o.add(<String, dynamic>{
      'id': i, 'code': 'R$i', 'kg': kg, 'cost': cost, 'date': '2026-${two(mo)}-${two(dd)}',
      'q': <String, dynamic>{'ounce': ounce, 'gram': gram, 'khandan_pct': kh, 'moisture_pct': mo2},
    });
  }
  return o;
}
