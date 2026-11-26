import 'edit_guard_ui.dart'; // فاز ۳
import 'package:flutter/material.dart';

import 'db.dart';
import 'live_query.dart';
import 'ledger.dart';
import 'loans_ui.dart';
import 'party_master_screen.dart'; // T03.1
import 'party_statement_screen.dart'; // T03.2
import 'crm_ui.dart'; // T03.4
import 'payment_screen.dart';
import 'receipt_screen.dart';
import 'fmt.dart' show Fmt;
import 'utils.dart';
import 'widgets.dart';
import 'party_filter.dart'; // v91 p5
import 'xch_ui.dart'; // v91 p5: صرافان
import 'settle_ui.dart'; // v92: شناسنامهٔ پرداخت/وصول

/// v91 p5: مانده‌های ارزی یک طرف‌حساب به‌صورت متن کوتاه («۱۰٬۰۰۰ USD طلب • ۵۰۰ AED بدهی»)؛ ریال فقط وقتی ارز دیگری هست یا [withRial].
String partyCcyLine(PartyAccount a, {bool withRial = false}) {
  final Map<String, double> m = a.openByCcy;
  final bool foreign = m.keys.any((String k) => k != 'IRR');
  final List<String> parts = <String>[
    for (final MapEntry<String, double> e in m.entries)
      if (e.key != 'IRR' || withRial || foreign)
        '${e.key == 'IRR' ? Fmt.money(e.value.abs(), label: true) : faCcy(e.key, e.value.abs(), dec: 2)} ${e.value > 0 ? 'طلب' : 'بدهی'}',
  ];
  return parts.join('  •  ');
}

/// طرف‌حساب‌ها: برای هر فروشنده/خریدار، جمع خرید و فروش و بدهی/طلب باقی‌مانده
class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key});
  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  String _query = '';
  PartyFilter _f = const PartyFilter(); // v91 p5

  /// v91 p5: پنل فیلترها (ارز، نوع، بدهکار/بستانکار، بازهٔ مانده، بازهٔ تاریخ، مرتب‌سازی)
  Future<void> _openFilters(List<String> ccys) async {
    PartyFilter f = _f;
    final TextEditingController minC = TextEditingController(text: f.minBalance == null ? '' : f.minBalance!.toStringAsFixed(0));
    final TextEditingController maxC = TextEditingController(text: f.maxBalance == null ? '' : f.maxBalance!.toStringAsFixed(0));
    final PartyFilter? res = await showModalBottomSheet<PartyFilter>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) set) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                Text('فیلتر طرف‌حساب‌ها', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: f.ccy,
                  decoration: const InputDecoration(labelText: 'ارز', border: OutlineInputBorder(), helperText: 'با انتخاب ارز، مانده‌ها به همان ارز سنجیده می‌شوند'),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(value: null, child: Text('همهٔ ارزها (معادل ریالی)')),
                    for (final String c in ccys) DropdownMenuItem<String?>(value: c, child: Text(c == 'IRR' ? 'فقط ریالی' : c)),
                  ],
                  onChanged: (String? v) => set(() => f = f.copyWith(ccy: v)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: f.type,
                  decoration: const InputDecoration(labelText: 'نوع طرف‌حساب', border: OutlineInputBorder()),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(value: null, child: Text('همه')),
                    for (final MapEntry<String, String> e in kPartyTypesFa.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (String? v) => set(() => f = f.copyWith(type: v)),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                  for (final MapEntry<String, String> e in const <String, String>{
                    'all': 'همه', 'debtor': 'بدهکار (طلب ما)', 'creditor': 'بستانکار (بدهی ما)', 'open': 'مانده‌دار', 'settled': 'تسویه‌شده',
                  }.entries)
                    ChoiceChip(label: Text(e.value), selected: f.side == e.key, onSelected: (bool _) => set(() => f = f.copyWith(side: e.key))),
                ]),
                const SizedBox(height: 12),
                Row(children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: minC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'حداقل مانده', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: maxC,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'حداکثر مانده', border: OutlineInputBorder()),
                    ),
                  ),
                ]),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('مانده بدون ارز = به واحد ذخیرهٔ برنامه؛ با ارز = به همان ارز (قدرمطلق).', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(height: 8),
                dateField(ctx, 'فعالیت از تاریخ', f.from, (DateTime d) => set(() => f = f.copyWith(from: d))),
                dateField(ctx, 'فعالیت تا تاریخ', f.to, (DateTime d) => set(() => f = f.copyWith(to: d))),
                DropdownButtonFormField<String>(
                  value: f.sort,
                  decoration: const InputDecoration(labelText: 'مرتب‌سازی', border: OutlineInputBorder()),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(value: 'balance', child: Text('بیشترین مانده')),
                    DropdownMenuItem<String>(value: 'recent', child: Text('آخرین فعالیت')),
                    DropdownMenuItem<String>(value: 'name', child: Text('نام')),
                  ],
                  onChanged: (String? v) => set(() => f = f.copyWith(sort: v ?? 'balance')),
                ),
                const SizedBox(height: 12),
                Row(children: <Widget>[
                  TextButton(onPressed: () => Navigator.pop(ctx, const PartyFilter()), child: const Text('پاک کردن همه')),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                        ctx, f.copyWith(minBalance: parseNum(minC.text), maxBalance: parseNum(maxC.text))),
                    child: const Text('اعمال'),
                  ),
                ]),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ),
      ),
    );
    if (res != null && mounted) setState(() => _f = res);
  }

  /// v92: سه تب — طرف‌حساب‌ها (بدون صراف‌های خالص)، صرافان، پرداخت و وصول (شناسنامه‌ها)
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4, // v92 فاز ج: + قرض‌ها
      child: Builder(builder: (BuildContext ctx) {
        final TabController tc = DefaultTabController.of(ctx);
        return AnimatedBuilder(
          animation: tc,
          builder: (BuildContext ctx, Widget? _) => Scaffold(
            appBar: AppBar(
              title: const Text('طرف‌حساب‌ها'),
              actions: <Widget>[
                IconButton(
                  tooltip: 'سن بدهی و مطالبات',
                  icon: const Icon(Icons.hourglass_bottom),
                  onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const PartyAgingScreen())),
                ),
              ],
              bottom: const TabBar(tabs: <Widget>[
                Tab(icon: Icon(Icons.people_alt_outlined), text: 'طرف‌حساب‌ها'),
                Tab(icon: Icon(Icons.currency_exchange), text: 'صرافان'),
                Tab(icon: Icon(Icons.fact_check_outlined), text: 'پرداخت و وصول'),
                Tab(icon: Icon(Icons.handshake_outlined), text: 'قرض‌ها'),
              ]),
            ),
            floatingActionButton: switch (tc.index) {
              1 => FloatingActionButton.extended(
                  heroTag: 'fab_xch',
                  onPressed: () => showXchMoveSheet(context),
                  icon: const Icon(Icons.currency_exchange),
                  label: const Text('تسویه با صراف'),
                ),
              3 => FloatingActionButton.extended(
                  heroTag: 'fab_loan',
                  onPressed: () => showNewLoanDialog(context),
                  icon: const Icon(Icons.handshake_outlined),
                  label: const Text('ثبت قرض'),
                ),
              2 => FloatingActionButton.extended(
                  heroTag: 'fab_stl',
                  onPressed: () => _newSettlement(context),
                  icon: const Icon(Icons.add_card),
                  label: const Text('پرداخت / وصول'),
                ),
              _ => FloatingActionButton.extended(
                  heroTag: 'fab_party',
                  onPressed: () => showNewPartyDialog(context),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('طرف‌حساب جدید'),
                ),
            },
            body: TabBarView(children: <Widget>[_partiesTab(context), const ExchangersBody(), const SettlementsTab(), const LoansTab()]),
          ),
        );
      }),
    );
  }

  Future<void> _newSettlement(BuildContext context) async {
    final String? dir = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ListTile(leading: const Icon(Icons.south_west), title: const Text('وصول از طرف‌حساب'), subtitle: const Text('مشتری پرداخت کرد (مستقیم یا به صراف)'), onTap: () => Navigator.pop(ctx, 'recv')),
          ListTile(leading: const Icon(Icons.north_east), title: const Text('پرداخت به طرف‌حساب'), subtitle: const Text('ما پرداختیم (مستقیم یا از طریق صراف)'), onTap: () => Navigator.pop(ctx, 'pay')),
        ]),
      ),
    );
    if (dir != null && context.mounted) await openSettlementForm(context, dir: dir);
  }

  /// v92: صرافی که خرید/فروش/قرض/شناسنامه ندارد فقط در تب «صرافان» است
  static bool _pureExchanger(PartyAccount a) => a.isExchanger && a.entries.isEmpty && !a.hasLoans && a.settlementUids.isEmpty;

  Widget _partiesTab(BuildContext context) {
    return LiveQuery<List<PartyAccount>>(
        load: loadParties,
        builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('خطا: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final all = snap.data!;
            if (all.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('هنوز طرف‌حسابی نیست.\nبا دکمهٔ «طرف‌حساب جدید» یکی تعریف کنید یا خرید/فروش ثبت کنید.',
                      textAlign: TextAlign.center),
                ),
              );
            }
            double weOwe = 0, theyOwe = 0, loanRecv = 0, loanPay = 0;
            for (final a in all) {
              if (a.weOwe > 0) weOwe += a.weOwe;
              if (a.theyOwe > 0) theyOwe += a.theyOwe;
              if (a.loanReceivable > 0) loanRecv += a.loanReceivable;
              if (a.loanPayable > 0) loanPay += a.loanPayable;
            }
            final list = applyPartyFilter(_f.type == 'exchanger' ? all : all.where((PartyAccount a) => !_pureExchanger(a)).toList(), _f.copyWith(query: _query)); // v91 p5: فیلترها · v92: صراف‌ها در تب خودشان
            final ccys = partyCurrencies(all);
            final String? fc = _f.ccy;
            double fcRecv = 0, fcPay = 0;
            if (fc != null) {
              for (final a in list) {
                final double b = partyBalanceFor(a, fc);
                if (b > 0) fcRecv += b; else fcPay -= b;
              }
            }
            final scheme = Theme.of(context).colorScheme;
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                Card(
                  color: scheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      infoRow('جمع طلب‌ها (از خریدارها)', Fmt.money(theyOwe),
                          valueColor: Colors.green.shade800),
                      infoRow('جمع بدهی‌ها (به فروشنده‌ها)', Fmt.money(weOwe),
                          valueColor: Colors.red.shade800),
                      if (loanRecv > 0.5 || loanPay > 0.5) ...[
                        const Divider(),
                        infoRow('مانده طلب قرضی', Fmt.money(loanRecv),
                            valueColor: Colors.green.shade800),
                        infoRow('مانده بدهی قرضی', Fmt.money(loanPay),
                            valueColor: Colors.red.shade800),
                      ],
                      if (all.any((a) => a.hasLoans))
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: () => exportLoanPdf(context, all: all),
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('PDF دفتر قرض همهٔ طرف‌حساب‌ها'),
                          ),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                const CashFlowCard(),
                const SizedBox(height: 8),
                Row(children: <Widget>[
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'جستجوی نام',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Badge( // v91 p5
                    isLabelVisible: _f.activeCount > 0,
                    label: Text('${_f.activeCount}'),
                    child: IconButton.filledTonal(
                      tooltip: 'فیلترها',
                      icon: const Icon(Icons.filter_list),
                      onPressed: () => _openFilters(ccys),
                    ),
                  ),
                ]),
                if (fc != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(children: <Widget>[
                        infoRow('جمع طلب‌ها ($fc)', fc == 'IRR' ? Fmt.money(fcRecv) : faCcy(fc, fcRecv, dec: 2), valueColor: Colors.green.shade800),
                        infoRow('جمع بدهی‌ها ($fc)', fc == 'IRR' ? Fmt.money(fcPay) : faCcy(fc, fcPay, dec: 2), valueColor: Colors.red.shade800),
                      ]),
                    ),
                  ),
                if (_f.activeCount > 0)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _f = PartyFilter(sort: _f.sort)),
                      icon: const Icon(Icons.clear),
                      label: Text('${faNum(list.length, dec: 0)} مورد • حذف فیلترها'),
                    ),
                  ),
                const SizedBox(height: 8),
                for (final a in list) _tile(context, a),
                const SizedBox(height: 70), // جا برای دکمهٔ شناور
                if (list.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(24), child: Center(child: Text('موردی پیدا نشد'))),
              ],
            );
          },
    );
  }

  Widget _tile(BuildContext context, PartyAccount a) {
    final String? fc = _f.ccy; // v91 p5: با فیلتر ارز، مانده همان ارز نمایش داده می‌شود
    final total = fc == null ? a.totalNet : partyBalanceFor(a, fc);
    final settled = total.abs() < (fc == null || fc == 'IRR' ? 1 : 0.005);
    final String ccyLine = partyCcyLine(a);
    final color = settled
        ? Colors.black54
        : (total > 0 ? Colors.green.shade800 : Colors.red.shade800);
    final lines = <String>[
      if (a.bought > 0) 'خرید ${Fmt.money(a.bought, label: false)}',
      if (a.sold > 0) 'فروش ${Fmt.money(a.sold, label: false)}',
      if (a.loanReceivable.abs() > 0.5) 'طلب قرضی ${Fmt.money(a.loanReceivable, label: false)}',
      if (a.loanPayable.abs() > 0.5) 'بدهی قرضی ${Fmt.money(a.loanPayable, label: false)}',
    ].join('  •  ');
    return Card(
      key: ValueKey('party${a.key}'),
      child: ListTile(
        title: Row(children: <Widget>[
          Flexible(child: Text(a.name)),
          if (a.isExchanger) ...<Widget>[const SizedBox(width: 6), const Icon(Icons.currency_exchange, size: 16)],
        ]),
        subtitle: Text((lines.isEmpty ? 'بدون تراکنش' : lines) + (ccyLine.isEmpty ? '' : '\n$ccyLine')),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(settled ? 'تسویه' : (fc == null || fc == 'IRR' ? Fmt.money(total.abs(), label: false) : faCcy(fc, total.abs(), dec: 2)),
                style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            Text(settled ? '' : (total > 0 ? 'طلب ما' : 'بدهی ما'),
                style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => PartyDetailScreen(partyKeyValue: a.key))),
      ),
    );
  }
}

class PartyDetailScreen extends StatelessWidget {
  final String partyKeyValue;
  const PartyDetailScreen({super.key, required this.partyKeyValue});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppDb.I.version,
      builder: (_, __, ___) => FutureBuilder<List<PartyAccount>>(
        future: loadParties(),
        builder: (context, snap) {
          PartyAccount? a;
          if (snap.hasData) {
            for (final x in snap.data!) {
              if (x.key == partyKeyValue) a = x;
            }
          }
          return Scaffold(
            appBar: AppBar(
              title: Text(partyKeyValue.isEmpty ? 'بدون نام' : partyKeyValue),
              actions: <Widget>[
                if (partyKeyValue.isNotEmpty)
                  IconButton(
                    tooltip: 'یادداشت و پیگیری',
                    icon: const Icon(Icons.support_agent_outlined),
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute<void>(builder: (_) => PartyCrmScreen(partyName: partyKeyValue))),
                  ),
                if (partyKeyValue.isNotEmpty)
                  IconButton(
                    tooltip: 'صورت‌حساب',
                    icon: const Icon(Icons.receipt_long_outlined),
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute<void>(builder: (_) => PartyStatementScreen(partyName: partyKeyValue))),
                  ),
                if (partyKeyValue.isNotEmpty)
                  IconButton(
                    tooltip: 'مشخصات و مانده افتتاحیه',
                    icon: const Icon(Icons.badge_outlined),
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute<bool>(builder: (_) => PartyMasterScreen(partyName: partyKeyValue))),
                  ),
              ],
            ),
            body: a == null
                ? const Center(child: CircularProgressIndicator())
                : _body(context, a),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, PartyAccount a) {
    final scheme = Theme.of(context).colorScheme;
    final settled = a.net.abs() < 1;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (a.bought > 0 || a.sold > 0)
        Card(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              if (a.bought > 0) ...[
                infoRow('جمع خرید از او', Fmt.money(a.bought)),
                infoRow('پرداخت‌شده به او', Fmt.money(a.paid)),
                infoRow('بدهی ما به او', Fmt.money(a.weOwe),
                    valueColor: a.weOwe > 0.5 ? Colors.red.shade800 : null),
              ],
              if (a.bought > 0 && a.sold > 0) const Divider(),
              if (a.sold > 0) ...[
                infoRow('جمع فروش به او', Fmt.money(a.sold)),
                infoRow('دریافت‌شده از او', Fmt.money(a.received)),
                infoRow('طلب ما از او', Fmt.money(a.theyOwe),
                    valueColor: a.theyOwe > 0.5 ? Colors.green.shade800 : null),
              ],
              if (a.bought > 0 && a.sold > 0) ...[
                const Divider(),
                infoRow(
                  settled ? 'تراز نهایی' : (a.net > 0 ? 'تراز نهایی: او به ما بدهکار است' : 'تراز نهایی: ما به او بدهکاریم'),
                  settled ? 'تسویه' : Fmt.money(a.net.abs()),
                ),
              ],
            ]),
          ),
        ),
        if (a.openByCcy.keys.any((String k) => k != 'IRR')) // v91 p5: مانده به ارز سند
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                Text('مانده به تفکیک ارز', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                for (final MapEntry<String, double> e in a.openByCcy.entries)
                  infoRow(
                    e.key == 'IRR' ? 'ریالی' : e.key,
                    '${e.key == 'IRR' ? Fmt.money(e.value.abs()) : faCcy(e.key, e.value.abs(), dec: 2)} ${e.value > 0 ? '(او به ما بدهکار است)' : '(ما به او بدهکاریم)'}',
                    valueColor: e.value > 0 ? Colors.green.shade800 : Colors.red.shade800,
                  ),
              ]),
            ),
          ),
        if (a.isExchanger) ...<Widget>[ // v91 p5: صراف
          XchCard(account: a),
          if (a.xchPositions.isEmpty)
            const Padding(padding: EdgeInsets.all(4), child: Text('این طرف‌حساب صراف است؛ حرکت‌هایش را از «صرافان» ثبت کنید.')),
        ],
        if (a.key.isNotEmpty) PartySettlementsCard(account: a), // v92: وصول/پرداخت با شناسنامه + فهرست شناسنامه‌ها
        const SizedBox(height: 8),
        if (a.key.isNotEmpty) ...[
          _loanBook(context, a),
          const SizedBox(height: 8),
        ],
        CashFlowCard(partyKeyFilter: a.key),
        if (a.entries.isNotEmpty) sectionTitle(context, 'خرید و فروش‌ها'),
        for (final e in a.entries) _entry(context, a, e),
      ],
    );
  }

  /// دفتر قرض و وام این طرف‌حساب (جدا از خرید/فروش؛ در سود و زیان حساب نمی‌شود)
  Widget _loanBook(BuildContext context, PartyAccount a) {
    final scheme = Theme.of(context).colorScheme;
    final net = a.loanNet;
    final settledLoan = net.abs() < 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.handshake_outlined, color: scheme.primary),
            const SizedBox(width: 8),
            Text('دفتر قرض و وام', style: Theme.of(context).textTheme.titleMedium),
          ]),
          const SizedBox(height: 4),
          const Text('این مبالغ در سود و زیان حساب نمی‌شوند.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          if (a.hasLoans) ...[
            if (a.loanGiven > 0) infoRow('قرض دادیم (معادل ریالی)', Fmt.money(a.loanGiven)),
            if (a.loanTaken > 0) infoRow('قرض گرفتیم (معادل ریالی)', Fmt.money(a.loanTaken)),
            if (a.repaidToUs > 0) infoRow('قرض ما را پس داد', Fmt.money(a.repaidToUs)),
            if (a.repaidByUs > 0) infoRow('قرضش را پس دادیم', Fmt.money(a.repaidByUs)),
            for (final l in a.loans) // v92 فاز ج: مانده هر قرض ارزی به ارز خودش
              if (l.isForeign && (l.kind == 'given' || l.kind == 'taken') && l.open > 0.005)
                infoRow('${l.label} ${jalaliDateFromDt(l.date)} — مانده', faCcy(l.ccy, l.open), valueColor: l.kind == 'given' ? Colors.green.shade800 : Colors.red.shade800),
            const Divider(),
            infoRow(
              settledLoan ? 'مانده قرض' : (net > 0 ? 'مانده طلب قرضی (او به ما بدهکار است)' : 'مانده بدهی قرضی (ما به او بدهکاریم)'),
              settledLoan ? 'تسویه' : Fmt.money(net.abs()),
              valueColor: settledLoan ? null : (net > 0 ? Colors.green.shade800 : Colors.red.shade800),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('هنوز قرض یا وامی ثبت نشده.'),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () => showLoanSheet(context, party: a.name, kind: 'given'),
              icon: const Icon(Icons.north_east),
              label: const Text('قرض دادیم'), // v92
            ),
            FilledButton.tonalIcon(
              onPressed: () => showLoanSheet(context, party: a.name, kind: 'taken'),
              icon: const Icon(Icons.south_west),
              label: const Text('قرض گرفتیم'), // v92
            ),
            OutlinedButton.icon(
              onPressed: () {
                // بازپرداخت فقط وقتی معنی دارد که بدهی/طلب قرضی باز داشته باشیم
                if (a.loanReceivable <= 0.5 && a.loanPayable <= 0.5) {
                  snack(context, 'قرض بازی برای بازپرداخت وجود ندارد. برای قرض تازه از «قرض دادیم» یا «قرض گرفتیم» استفاده کنید.');
                  return;
                }
                showLoanSheet(context,
                    party: a.name,
                    kind: a.loanReceivable > 0.5 ? 'repay_in' : 'repay_out',
                    maxIn: a.loanReceivable > 0.5 ? a.loanReceivable : 0,
                    maxOut: a.loanPayable > 0.5 ? a.loanPayable : 0);
              },
              icon: const Icon(Icons.swap_horiz),
              label: const Text('بازپرداخت قرض'), // v92
            ),
            if (a.hasLoans)
              OutlinedButton.icon(
                onPressed: () => exportLoanPdf(context, party: a),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF دفتر قرض'),
              ),
          ]),
          if (a.hasLoans) ...[
            const SizedBox(height: 8),
            for (final l in a.loans) _loanTile(context, l),
          ],
        ]),
      ),
    );
  }

  /// فاز ۳: ویرایش قرض/بازپرداخت؛ محلی ذخیره و در صف همگام‌سازی (loans.update). سررسید پرداخت‌شده ⇒ سرور فقط تاریخ و توضیح را می‌پذیرد.
  Future<void> _editLoan(BuildContext context, LoanEntry l) async {
    final Map<String, dynamic>? v = await showEditDocDialog(context, 'ویرایش ${l.label}', <EditField>[
      if (!l.isForeign) EditField('amount', 'مبلغ', l.amount, kind: EditKind.number), // v92: قرض ارزی ⇒ حذف و ثبت دوباره
      EditField('date', 'تاریخ', l.date.toIso8601String(), kind: EditKind.date),
      EditField('note', 'توضیح', l.note),
    ]);
    if (v == null || !context.mounted) return;
    await saveConfirmed(
      context,
      () => AppDb.I.updateLoanEntry(l.id, amount: (v['amount'] as num?)?.toDouble(), date: DateTime.tryParse('${v['date']}'), note: v['note'] as String?),
      successMsg: 'ویرایش ذخیره شد',
    );
  }

  Widget _loanTile(BuildContext context, LoanEntry l) {
    final color = l.isIn ? Colors.green.shade800 : Colors.deepOrange.shade800;
    return ListTile(
      key: ValueKey('loan${l.id}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(l.isIn ? Icons.south_west : Icons.north_east, color: color),
      title: Text('${l.label} • ${l.isForeign ? faCcy(l.ccy, l.ccyAmount) : Fmt.money(l.amount)}', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      subtitle: Text('${jalaliDateFromDt(l.date)}${l.isForeign ? ' • نرخ ${faNum(l.fxRate, dec: 0)} • معادل ${Fmt.money(l.amount)}' : ''}'
          '${l.realized == 0 ? '' : ' • ${l.realized > 0 ? 'سود' : 'زیان'} تفاوت نرخ ${Fmt.money(l.realized.abs(), from: 'rial')}'}${(l.note ?? '').isEmpty ? '' : '\n${l.note}'}'),
      isThreeLine: (l.note ?? '').isNotEmpty,
      onTap: () => _editLoan(context, l), // فاز ۳: ویرایش امن (loans.update)
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'حذف',
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('حذف این مورد؟'),
              content: Text('${l.label} به مبلغ ${Fmt.money(l.amount)} حذف می‌شود.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
              ],
            ),
          );
          if (ok == true && context.mounted) {
            await saveConfirmed(context, () => AppDb.I.deleteLoanEntry(l.id), successMsg: 'حذف شد');
          }
        },
      ),
    );
  }

  Widget _entry(BuildContext context, PartyAccount a, PartyEntry e) {
    final open = e.isForeign ? e.remainingCcy > 0.005 : e.remaining > 0.5; // v91 p5: فاکتور ارزی با ارز خودش سنجیده می‌شود
    return Card(
      key: ValueKey('${e.isPurchase}${e.id}'),
      child: ListTile(
        leading: Icon(e.isPurchase ? Icons.shopping_cart_outlined : Icons.sell_outlined),
        title: Text('${e.isPurchase ? 'خرید' : 'فروش'} ${e.label} • ${faNum(e.weight)} کیلو (خالص)'),
        subtitle: Text(
          '${jalaliDateFromDt(e.date)}\n'
          '${e.isForeign ? 'مبلغ ${faCcy(e.ccy!, e.totalCcy, dec: 2)} • تسویه‌شده ${faCcy(e.ccy!, e.settledCcy, dec: 2)}'
              '${e.remainingCcy > 0.005 ? ' • مانده ${faCcy(e.ccy!, e.remainingCcy, dec: 2)}' : ' • تسویه کامل'}\nمعادل: ' : ''}' // v91 p5: به ارز سند
          'مبلغ ${Fmt.money(e.total, label: false)} • تسویه‌شده ${Fmt.money(e.settled, label: false)}'
          '${open ? ' • مانده ${Fmt.money(e.remaining, label: false)}' : ' • تسویه کامل'}',
          style: TextStyle(color: open ? Theme.of(context).colorScheme.error : null),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_left),
        onTap: () {
          if (e.isPurchase) {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PaymentScreen(
                        purchaseId: e.id, purchaseLabel: '${e.label} - ${jalaliDateFromDt(e.date)}')));
          } else {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ReceiptScreen(
                        saleId: e.id, saleLabel: '${a.name} - ${jalaliDateFromDt(e.date)}')));
          }
        },
      ),
    );
  }
}
