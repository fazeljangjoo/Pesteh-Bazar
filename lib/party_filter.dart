// v91 p5 — فیلتر فهرست طرف‌حساب‌ها (خالص؛ بدون UI): نام، ارز، نوع (از جمله صراف)، بدهکار/بستانکار، بازهٔ مانده، بازهٔ تاریخ، مرتب‌سازی.
import 'ledger.dart';

class PartyFilter {
  final String query;

  /// null = همهٔ ارزها (مانده = معادل ریالی کل)؛ 'IRR' = فقط ماندهٔ ریالی؛ کد ارز = مانده به همان ارز
  final String? ccy;

  /// null = همه؛ کلید نوع طرف‌حساب (customer, supplier, broker, …, exchanger)
  final String? type;

  /// all | debtor (او بدهکار) | creditor (ما بدهکار) | open (مانده‌دار) | settled (تسویه)
  final String side;

  /// بازهٔ قدرمطلق مانده (به ارز انتخابی؛ بدون ارز = واحد نمایش ذخیره)
  final double? minBalance;
  final double? maxBalance;

  /// فقط طرف‌هایی که در این بازه رویدادی داشته‌اند
  final DateTime? from;
  final DateTime? to;

  /// balance | name | recent
  final String sort;

  const PartyFilter({
    this.query = '',
    this.ccy,
    this.type,
    this.side = 'all',
    this.minBalance,
    this.maxBalance,
    this.from,
    this.to,
    this.sort = 'balance',
  });

  PartyFilter copyWith({
    String? query,
    Object? ccy = _keep,
    Object? type = _keep,
    String? side,
    Object? minBalance = _keep,
    Object? maxBalance = _keep,
    Object? from = _keep,
    Object? to = _keep,
    String? sort,
  }) =>
      PartyFilter(
        query: query ?? this.query,
        ccy: ccy == _keep ? this.ccy : ccy as String?,
        type: type == _keep ? this.type : type as String?,
        side: side ?? this.side,
        minBalance: minBalance == _keep ? this.minBalance : minBalance as double?,
        maxBalance: maxBalance == _keep ? this.maxBalance : maxBalance as double?,
        from: from == _keep ? this.from : from as DateTime?,
        to: to == _keep ? this.to : to as DateTime?,
        sort: sort ?? this.sort,
      );

  static const Object _keep = Object();

  /// چند فیلتر (جز نام و مرتب‌سازی) فعال است
  int get activeCount =>
      (ccy != null ? 1 : 0) +
      (type != null ? 1 : 0) +
      (side != 'all' ? 1 : 0) +
      (minBalance != null || maxBalance != null ? 1 : 0) +
      (from != null || to != null ? 1 : 0);
}

/// مانده‌ای که فیلتر روی آن کار می‌کند: با ارز ⇒ مانده همان ارز؛ بدون ارز ⇒ تراز کل (معادل ریالی، واحد ذخیره).
double partyBalanceFor(PartyAccount a, String? ccy) => ccy == null ? a.totalNet : (a.byCcy[ccy] ?? 0);

double _tol(String? ccy) => (ccy == null || ccy == 'IRR') ? 0.5 : 0.005;

List<PartyAccount> applyPartyFilter(List<PartyAccount> all, PartyFilter f) {
  final String q = partyKey(f.query);
  final DateTime? from = f.from == null ? null : DateTime(f.from!.year, f.from!.month, f.from!.day);
  final DateTime? toEx = f.to == null ? null : DateTime(f.to!.year, f.to!.month, f.to!.day + 1);
  final List<PartyAccount> out = <PartyAccount>[];
  for (final PartyAccount a in all) {
    if (q.isNotEmpty && !a.key.contains(q)) continue;
    if (f.type != null && !(f.type == 'exchanger' ? a.isExchanger : a.types.contains(f.type))) continue;
    if (f.ccy != null && !a.byCcy.containsKey(f.ccy)) continue;
    final double b = partyBalanceFor(a, f.ccy);
    final double t = _tol(f.ccy);
    switch (f.side) {
      case 'debtor':
        if (b <= t) continue;
        break;
      case 'creditor':
        if (b >= -t) continue;
        break;
      case 'open':
        if (b.abs() <= t) continue;
        break;
      case 'settled':
        if (b.abs() > t) continue;
        break;
    }
    if (f.minBalance != null && b.abs() < f.minBalance!) continue;
    if (f.maxBalance != null && b.abs() > f.maxBalance!) continue;
    if (from != null || toEx != null) {
      final bool any = a.dates.any((DateTime d) => (from == null || !d.isBefore(from)) && (toEx == null || d.isBefore(toEx)));
      if (!any) continue;
    }
    out.add(a);
  }
  switch (f.sort) {
    case 'name':
      out.sort((PartyAccount x, PartyAccount y) => x.key.compareTo(y.key));
      break;
    case 'recent':
      out.sort((PartyAccount x, PartyAccount y) {
        final DateTime? dx = x.lastDate, dy = y.lastDate;
        if (dx == null && dy == null) return 0;
        if (dx == null) return 1;
        if (dy == null) return -1;
        return dy.compareTo(dx);
      });
      break;
    default:
      out.sort((PartyAccount x, PartyAccount y) => partyBalanceFor(y, f.ccy).abs().compareTo(partyBalanceFor(x, f.ccy).abs()));
  }
  return out;
}

/// ارزهایی که دست‌کم یک طرف‌حساب در آن رویداد دارد (برای فهرست انتخاب)
List<String> partyCurrencies(List<PartyAccount> all) {
  final Set<String> s = <String>{};
  for (final PartyAccount a in all) {
    s.addAll(a.byCcy.keys);
  }
  final List<String> l = s.toList()..sort();
  l.remove('IRR');
  return <String>[if (s.contains('IRR')) 'IRR', ...l];
}
