// v91 p5 — فیلتر فهرست طرف‌حساب‌ها (ارز، نوع، بدهکار/بستانکار، بازهٔ مانده، تاریخ، مرتب‌سازی)
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/ledger.dart';
import 'package:pesteh_bazar/party_filter.dart';

PartyAccount _p(String name, {double sold = 0, double bought = 0, Map<String, double> ccy = const <String, double>{}, Set<String> types = const <String>{}, List<DateTime> dates = const <DateTime>[]}) {
  final PartyAccount a = PartyAccount(name)
    ..sold = sold
    ..bought = bought;
  ccy.forEach(a.addCcy);
  a.types.addAll(types);
  a.dates.addAll(dates);
  return a;
}

void main() {
  final List<PartyAccount> all = <PartyAccount>[
    _p('شرکت الف', sold: 6000000000, ccy: <String, double>{'USD': 10000}, types: <String>{'customer'}, dates: <DateTime>[DateTime(2026, 10, 2)]),
    _p('تأمین‌کننده ب', bought: 8250000000, ccy: <String, double>{'AED': -50000}, types: <String>{'supplier'}, dates: <DateTime>[DateTime(2026, 10, 12)]),
    _p('صرافی امین', sold: 3600000000, ccy: <String, double>{'USD': 6000}, types: <String>{'exchanger'}, dates: <DateTime>[DateTime(2026, 10, 5)]),
    _p('مشتری ریالی', sold: 500000, ccy: <String, double>{'IRR': 500000}, types: <String>{'customer'}, dates: <DateTime>[DateTime(2026, 11, 20)]),
    _p('تسویه‌شده', ccy: <String, double>{'IRR': 0}, dates: <DateTime>[DateTime(2026, 9, 1)]),
  ];
  List<String> names(PartyFilter f) => applyPartyFilter(all, f).map((PartyAccount a) => a.key).toList();

  test('currency filter keeps parties with that currency, sorted by balance in it', () {
    expect(names(const PartyFilter(ccy: 'USD')), <String>['شرکت الف', 'صرافی امین']);
    expect(partyBalanceFor(all[1], 'AED'), -50000);
  });
  test('type filter (exchanger) and side filter', () {
    expect(names(const PartyFilter(type: 'exchanger')), <String>['صرافی امین']);
    expect(names(const PartyFilter(side: 'creditor')), <String>['تأمین‌کننده ب']);
    expect(names(const PartyFilter(side: 'settled')), <String>['تسویه‌شده']);
    expect(names(const PartyFilter(ccy: 'USD', side: 'debtor', minBalance: 7000)), <String>['شرکت الف']);
  });
  test('balance range, date range, name and sort', () {
    expect(names(const PartyFilter(maxBalance: 1000000, side: 'open')), <String>['مشتری ریالی']);
    expect(names(PartyFilter(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 10))), <String>['شرکت الف', 'صرافی امین']);
    expect(names(const PartyFilter(query: 'صرافي')), <String>['صرافی امین']); // ي عربی
    expect(names(const PartyFilter(sort: 'recent')).first, 'مشتری ریالی');
    expect(const PartyFilter(ccy: 'USD', side: 'debtor').activeCount, 2);
    expect(partyCurrencies(all), <String>['IRR', 'AED', 'USD']);
  });
}
