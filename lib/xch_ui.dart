// v91 p5 — صراف: فهرست صرافان (مانده به تفکیک ارز، نرخ میانگین دفتری، سود/زیان تحقق‌یافته)، ریز حرکت‌ها، و فرم ثبت حرکت.
// داده: موجودیت `xch_moves` (EntityStore ⇒ ذخیرهٔ محلی + صف همگام‌سازی). محاسبه: xch_calc.dart (همان الگوریتم سرور).
import 'package:flutter/material.dart';

import 'db.dart';
import 'entity_store.dart';
import 'fmt.dart' show Fmt;
import 'fx_local.dart';
import 'ledger.dart';
import 'treasury_link.dart';
import 'utils.dart';
import 'widgets.dart';
import 'xch_calc.dart';
import 'settle_data.dart'; // v92
import 'settle_ui.dart'; // v92

/// مبلغ به ارز خودش (IRR = ریال)
String xchAmount(String ccy, num v, {bool sign = false}) {
  final String s = ccy == 'IRR' ? Fmt.money(sign ? v : v.abs(), from: 'rial') : faCcy(ccy, sign ? v : v.abs(), dec: 2);
  return s;
}

String xchRial(num v) => Fmt.money(v, from: 'rial');

Color _sideColor(num v) => v > 0 ? Colors.green.shade800 : (v < 0 ? Colors.red.shade800 : Colors.black54);

class _XchData {
  final List<XchMove> moves;
  final List<PartyAccount> parties;
  const _XchData(this.moves, this.parties);
  List<PartyAccount> get exchangers => parties.where((PartyAccount a) => a.isExchanger && a.key.isNotEmpty).toList()..sort((PartyAccount a, PartyAccount b) => a.key.compareTo(b.key));
}

Future<_XchData> _load() async => _XchData((await loadStlState()).xmoves, await loadParties()); // v92: + مراحل صرافی شناسنامه‌ها

/// فهرست صرافان
class ExchangersScreen extends StatelessWidget {
  const ExchangersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('صرافان')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showXchMoveSheet(context),
        icon: const Icon(Icons.currency_exchange),
        label: const Text('تسویه با صراف'),
      ),
      body: const ExchangersBody(),
    );
  }
}

/// v92: بدنهٔ فهرست صرافان (در تب «صرافان» طرف‌حساب‌ها هم استفاده می‌شود)
class ExchangersBody extends StatelessWidget {
  const ExchangersBody({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
        valueListenable: AppDb.I.version,
        builder: (BuildContext _, int __, Widget? ___) => FutureBuilder<_XchData>(
          future: _load(),
          builder: (BuildContext context, AsyncSnapshot<_XchData> snap) {
            if (snap.hasError) return Center(child: Text('خطا: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final List<PartyAccount> ex = snap.data!.exchangers;
            final Map<String, double> totRecv = <String, double>{}, totPay = <String, double>{};
            int realized = 0;
            for (final PartyAccount a in ex) {
              realized += a.xchRealized;
              for (final XchPosition p in a.xchPositions) {
                if (p.q4 > 0) totRecv[p.ccy] = (totRecv[p.ccy] ?? 0) + p.amount;
                if (p.q4 < 0) totPay[p.ccy] = (totPay[p.ccy] ?? 0) - p.amount;
              }
            }
            return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: <Widget>[
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                    const Text('صراف چیست؟', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('وقتی طرف‌حساب پول را به صراف می‌دهد (در «پرداخت و وصول» به‌عنوان مرحلهٔ «از طریق صراف»)، بدهی طرف‌حساب تسویه و صراف به همان ارزِ واریز به ما بدهکار می‌شود؛ '
                        'وقتی صراف به طرف‌حساب ما می‌پردازد، ما به صراف بدهکار می‌شویم. هر واریز جدا دنبال می‌شود تا صراف (به هر ارزی) با ما تسویه کند؛ تسویه به نرخ دیگر، سود/زیان تفاوت نرخ می‌سازد.',
                        style: TextStyle(fontSize: 12)),
                    const Divider(),
                    for (final MapEntry<String, double> e in totRecv.entries) infoRow('طلب از صرافان (${e.key})', xchAmount(e.key, e.value), valueColor: Colors.green.shade800),
                    for (final MapEntry<String, double> e in totPay.entries) infoRow('بدهی به صرافان (${e.key})', xchAmount(e.key, e.value), valueColor: Colors.red.shade800),
                    infoRow('سود/زیان تحقق‌یافتهٔ تفاوت نرخ', '${realized < 0 ? 'زیان ' : 'سود '}${xchRial(realized.abs())}', valueColor: _sideColor(realized)),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              if (ex.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('هنوز صرافی ثبت نشده است. با «ثبت حرکت صراف» شروع کنید؛ صراف خودکار به طرف‌حساب‌ها (با نوع «صراف») اضافه می‌شود.', textAlign: TextAlign.center),
                ),
              for (final PartyAccount a in ex) XchCard(account: a),
            ]);
          },
        ),
    );
  }
}

/// کارت یک صراف: مانده هر ارز + نرخ میانگین + سود/زیان
class XchCard extends StatelessWidget {
  final PartyAccount account;
  final bool tappable;
  const XchCard({super.key, required this.account, this.tappable = true});

  @override
  Widget build(BuildContext context) {
    final List<XchPosition> pos = account.xchPositions.where((XchPosition p) => p.q4 != 0 || p.realized != 0).toList()
      ..sort((XchPosition a, XchPosition b) => a.ccy.compareTo(b.ccy));
    return Card(
      child: InkWell(
        onTap: tappable ? () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ExchangerDetailScreen(exchanger: account.key))) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Row(children: <Widget>[
              const Icon(Icons.currency_exchange),
              const SizedBox(width: 8),
              Expanded(child: Text(account.name, style: Theme.of(context).textTheme.titleMedium)),
              if (tappable) const Icon(Icons.chevron_left),
            ]),
            if (pos.isEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('تسویه (بدون مانده)')),
            for (final XchPosition p in pos)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: <Widget>[
                  Expanded(
                    child: Text(
                      p.q4 == 0
                          ? '${p.ccy}: تسویه'
                          : '${p.ccy}: ${p.q4 > 0 ? 'او به ما بدهکار است' : 'ما به او بدهکاریم'} • نرخ میانگین ${faNum(p.avgRate ?? 0, dec: 0)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(p.q4 == 0 ? '' : xchAmount(p.ccy, p.amount), style: TextStyle(fontWeight: FontWeight.w700, color: _sideColor(p.q4))),
                ]),
              ),
            if (account.xchRealized != 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${account.xchRealized > 0 ? 'سود' : 'زیان'} تحقق‌یافتهٔ تفاوت نرخ: ${xchRial(account.xchRealized.abs())}',
                    style: TextStyle(fontSize: 12, color: _sideColor(account.xchRealized))),
              ),
          ]),
        ),
      ),
    );
  }
}

/// ریز حرکت‌های یک صراف (با مانده پس از هر حرکت و سود/زیان)
class ExchangerDetailScreen extends StatelessWidget {
  final String exchanger;
  const ExchangerDetailScreen({super.key, required this.exchanger});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('صراف: $exchanger')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showXchMoveSheet(context, exchanger: exchanger),
        icon: const Icon(Icons.add),
        label: const Text('ثبت حرکت'),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: AppDb.I.version,
        builder: (BuildContext _, int __, Widget? ___) => FutureBuilder<_XchData>(
          future: _load(),
          builder: (BuildContext context, AsyncSnapshot<_XchData> snap) {
            if (snap.hasError) return Center(child: Text('خطا: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final List<XchMove> all = snap.data!.moves;
            final XchRun run = xchRun(all);
            PartyAccount? acc;
            for (final PartyAccount a in snap.data!.parties) {
              if (a.key == exchanger) acc = a;
            }
            final List<int> idx = <int>[for (int i = all.length - 1; i >= 0; i--) if (all[i].exchanger == exchanger) i];
            final List<(XchPosition, XchLot)> lots = <(XchPosition, XchLot)>[
              for (final XchPosition p in run.positions.values)
                if (p.exchanger == exchanger)
                  for (final XchLot l in p.lots) (p, l),
            ];
            final Map<String, XchMove> bySrc = <String, XchMove>{for (final XchMove m in all) m.lotId: m};
            return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: <Widget>[
              if (acc != null) XchCard(account: acc, tappable: false),
              if (lots.isNotEmpty) ...<Widget>[ // v92: واریزها/پرداخت‌های باز نزد این صراف
                sectionTitle(context, 'واریزها و پرداخت‌های باز (هنوز تسویه‌نشده)'),
                Card(
                  child: Column(children: <Widget>[
                    for (final (XchPosition p, XchLot l) in lots)
                      ListTile(
                        dense: true,
                        title: Text(bySrc[l.id]?.isLeg ?? false
                            ? '${bySrc[l.id]!.kind == 'leg_in' ? 'واریز' : 'پرداخت به'} «${bySrc[l.id]!.party}» — شناسنامهٔ ${bySrc[l.id]!.refNo ?? ''}'
                            : (l.q > 0 ? 'پیش‌پرداخت ما به صراف' : 'پیش‌دریافت از صراف')),
                        subtitle: Text('${jalaliDate(l.date)} • ارزش دفتری ${xchRial(l.b.abs())}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                          Text(xchAmount(p.ccy, l.amount), style: TextStyle(fontWeight: FontWeight.w700, color: _sideColor(l.q))),
                          const SizedBox(width: 8),
                          TextButton( // v94: همین مورد را با صراف تسویه کن (پیش‌پر)
                            onPressed: () => showXchMoveSheet(context, exchanger: exchanger, prefill: xchPrefillFor(p.ccy, l)),
                            child: Text(l.q < 0 ? 'پرداخت به صراف' : 'دریافت از صراف'),
                          ),
                        ]),
                        onTap: (bySrc[l.id]?.isLeg ?? false)
                            ? () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SettlementTrailScreen(uid: bySrc[l.id]!.stlUid)))
                            : null,
                      ),
                  ]),
                ),
              ],
              if (idx.isNotEmpty) sectionTitle(context, 'حرکت‌ها (جدیدترین اول)'),
              if (idx.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('حرکتی ثبت نشده است'))),
              for (final int i in idx) _moveTile(context, all, all[i], run.results[i]),
            ]);
          },
        ),
      ),
    );
  }

  Widget _moveTile(BuildContext context, List<XchMove> all, XchMove m, XchResult r) {
    if (m.isLeg) { // v92: مرحلهٔ صرافی یک شناسنامه ⇒ باز کردن شناسنامه
      return Card(
        child: ListTile(
          leading: const Icon(Icons.fact_check_outlined),
          title: Text(m.kind == 'leg_in'
              ? '«${m.party}» ${xchAmount(m.ccy, m.amountCcy)} به صراف داد'
              : 'صراف ${xchAmount(m.ccy, m.amountCcy)} به «${m.party}» داد'),
          subtitle: Text('${jalaliDate(m.date)} • شناسنامهٔ ${m.refNo ?? ''} • ارزش ${xchRial(m.value)}\n'
              '${r.q4After == 0 ? 'مانده ${m.ccy}: تسویه' : 'مانده ${m.ccy}: ${xchAmount(m.ccy, r.balanceAfter)} ${r.q4After > 0 ? '(طلب ما)' : '(بدهی ما)'}'}'
              '${r.realized == 0 ? '' : ' • ${r.realized > 0 ? 'سود' : 'زیان'} ${xchRial(r.realized.abs())}'}'),
          isThreeLine: true,
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SettlementTrailScreen(uid: m.stlUid))),
        ),
      );
    }
    final String what = switch (m.kind) {
      'cust_paid' => '«${m.party}» ${xchAmount(m.ccy, m.amountCcy)} به صراف داد (فروش #${m.docId})',
      'paid_seller' => 'صراف ${xchAmount(m.ccy, m.amountCcy)} به «${m.party}» داد (خرید #${m.docId})',
      'xch_paid_us' => 'صراف به ما داد: ${xchAmount(m.payCcy, m.payAmount)}${m.payCcy == m.ccy ? '' : ' بابت ${xchAmount(m.ccy, m.amountCcy)}'}',
      _ => 'ما به صراف دادیم: ${xchAmount(m.payCcy, m.payAmount)}${m.payCcy == m.ccy ? '' : ' بابت ${xchAmount(m.ccy, m.amountCcy)}'}',
    };
    final String rate = m.isSettle
        ? (m.ccy == 'IRR' ? '' : 'نرخ فاکتور ${faNum(m.docRate, dec: 0)}')
        : (m.payCcy == 'IRR' ? '' : 'نرخ ${m.payCcy}: ${faNum(m.payRate, dec: 0)}');
    final String bal = r.q4After == 0 ? 'مانده ${m.ccy}: تسویه' : 'مانده ${m.ccy}: ${xchAmount(m.ccy, r.balanceAfter)} ${r.q4After > 0 ? '(طلب ما)' : '(بدهی ما)'}';
    return Card(
      child: ListTile(
        title: Text(what),
        subtitle: Text('${jalaliDate(m.date)}${rate.isEmpty ? '' : ' • $rate'}\n$bal'
            '${r.realized == 0 ? '' : '\n${r.realized > 0 ? 'سود' : 'زیان'} تفاوت نرخ: ${xchRial(r.realized.abs())}'}'
            '${(m.note ?? '').isEmpty ? '' : '\n${m.note}'}'),
        isThreeLine: true,
        onTap: () => showXchMoveSheet(context, existing: m),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'حذف',
          onPressed: () async {
            final bool? ok = await showDialog<bool>(
              context: context,
              builder: (BuildContext ctx) => AlertDialog(
                title: const Text('حذف این حرکت؟'),
                content: const Text('مانده صراف و طرف‌حساب و سود/زیان حرکت‌های بعدی دوباره حساب می‌شود.'),
                actions: <Widget>[
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                ],
              ),
            );
            if (ok == true && context.mounted) {
              await saveConfirmed(context, () => EntityStore.I.delete('xch_moves', m.uid), successMsg: 'حذف شد');
            }
          },
        ),
      ),
    );
  }
}

/// v94: پیش‌پر کردن فرم تسویه با صراف برای یک لات باز (مثلاً «صراف به فروشنده داد» ⇒ «ما به صراف دادیم» همان مبلغ).
typedef XchPrefill = ({String kind, String ccy, double amount, String link});

/// v94: لات باز ⇒ نوع تسویه: بدهی ما به صراف (q<0) ⇒ «ما به صراف دادیم»؛ طلب ما (q>0) ⇒ «صراف به ما داد».
XchPrefill xchPrefillFor(String ccy, XchLot l) => (kind: l.q < 0 ? 'we_paid_xch' : 'xch_paid_us', ccy: ccy, amount: l.amount.abs(), link: l.id);

/// فرم ثبت/ویرایش حرکت صراف
Future<void> showXchMoveSheet(BuildContext context, {String? exchanger, XchMove? existing, XchPrefill? prefill}) async {
  if (!await EntityStore.I.isVisible('xch_moves')) {
    if (context.mounted) snack(context, 'بخش صراف هنوز روی سرور فعال نشده است؛ پس از به‌روزرسانی سرور و همگام‌سازی در دسترس است.');
    return;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext _) => XchMoveForm(exchanger: exchanger, existing: existing, prefill: prefill),
  );
}

/// یک فاکتور باز برای انتخاب در تسویه از طریق صراف
class _OpenDoc {
  final PartyEntry e;
  final String party;
  final double openCcy; // به ارز سند (برای ریالی: ریال)
  final String ccy;
  const _OpenDoc(this.e, this.party, this.openCcy, this.ccy);
  String get label => '${e.isPurchase ? 'خرید' : 'فروش'} #${e.id} — $party — مانده ${xchAmount(ccy, openCcy)}';
}

class XchMoveForm extends StatefulWidget {
  final String? exchanger;
  final XchMove? existing;
  final XchPrefill? prefill; // v94
  const XchMoveForm({super.key, this.exchanger, this.existing, this.prefill});
  @override
  State<XchMoveForm> createState() => _XchMoveFormState();
}

class _XchMoveFormState extends State<XchMoveForm> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late String _kind;
  late final TextEditingController _ex;
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _pay = TextEditingController();
  final TextEditingController _rate = TextEditingController();
  final TextEditingController _note = TextEditingController();
  DateTime _date = DateTime.now();
  String _ccy = 'IRR';
  String _payCcy = 'IRR';
  String? _acct;
  _OpenDoc? _doc;
  double _docRate = 0;
  List<String> _ccys = <String>['IRR'];
  List<_OpenDoc> _docs = <_OpenDoc>[];
  List<String> _names = <String>[];
  List<XchMove> _moves = <XchMove>[];
  bool _saving = false;
  bool _stlOn = false; // v92: سرور شناسنامه دارد ⇒ «مشتری به صراف داد / صراف به فروشنده داد» از شناسنامه ثبت می‌شود
  final List<String> _links = <String>[]; // v92: لات‌هایی که این تسویه اول می‌بندد (به ترتیب انتخاب)

  bool get _settle => _kind == 'cust_paid' || _kind == 'paid_seller';

  @override
  void initState() {
    super.initState();
    final XchMove? m = widget.existing;
    _kind = m?.kind ?? 'xch_paid_us';
    if (m != null) _links.addAll(m.links.map((XchLink l) => l.lot));
    _ex = TextEditingController(text: m?.exchanger ?? widget.exchanger ?? '');
    if (m != null) {
      _date = DateTime.tryParse(m.date) ?? DateTime.now();
      _ccy = m.ccy;
      _payCcy = m.payCcy;
      _amount.text = _num(m.amountCcy);
      if (!m.isSettle) {
        _pay.text = _num(m.payAmount);
        if (m.payRate > 0 && m.payCcy != 'IRR') _rate.text = _num(m.payRate);
      }
      _acct = m.cashBox ?? m.bankAccount;
      _acctKind = m.cashBox != null ? 'cash' : (m.bankAccount != null ? 'bank' : null);
      _note.text = m.note ?? '';
      _docRate = m.docRate;
    }
    final XchPrefill? pf = widget.prefill;
    if (m == null && pf != null) { // v94: تسویهٔ همان مبلغ با صراف، پیوند به همان لات
      _kind = pf.kind;
      _ccy = pf.ccy;
      _payCcy = pf.ccy;
      _amount.text = _num(double.parse(pf.amount.toStringAsFixed(pf.ccy == 'IRR' ? 0 : 4)));
      _pay.text = _amount.text;
      _links.add(pf.link);
    }
    _init();
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _init() async {
    final List<Map<String, dynamic>> cur = await FxLocal.loadCurrencies().catchError((Object _) => <Map<String, dynamic>>[]);
    final List<PartyAccount> parties = await loadParties();
    final List<XchMove> moves = (await loadStlState()).xmoves; // v92: + مراحل صرافی شناسنامه‌ها
    final bool stlOn = await settlementsAvailable();
    final double mult = AppDb.I.moneyUnit == 'rial' ? 1 : 10;
    final List<_OpenDoc> docs = <_OpenDoc>[];
    for (final PartyAccount a in parties) {
      for (final PartyEntry e in a.entries) {
        if (e.id <= 0) continue; // هنوز به سرور نرفته
        final double open = e.isForeign ? e.remainingCcy : e.remaining * mult;
        final bool mine = widget.existing != null && widget.existing!.docId == e.id && (widget.existing!.docType == 'purchase') == e.isPurchase;
        if (open > (e.isForeign ? 0.005 : 0.5) || mine) {
          docs.add(_OpenDoc(e, a.name, open + (mine ? widget.existing!.amountCcy : 0), e.ccy ?? 'IRR'));
        }
      }
    }
    docs.sort((_OpenDoc a, _OpenDoc b) => b.e.date.compareTo(a.e.date));
    if (!mounted) return;
    setState(() {
      _ccys = <String>['IRR', for (final Map<String, dynamic> c in cur) if (c['is_base'] != true && c['active'] == true && '${c['code']}'.isNotEmpty) '${c['code']}'];
      for (final String c in <String>[_ccy, _payCcy]) {
        if (!_ccys.contains(c)) _ccys.add(c);
      }
      _docs = docs;
      _names = <String>[for (final PartyAccount a in parties) if (a.key.isNotEmpty) a.key];
      _moves = moves;
      _stlOn = stlOn;
      final XchMove? m = widget.existing;
      if (m != null && m.isSettle) {
        for (final _OpenDoc d in docs) {
          if (d.e.id == m.docId && d.e.isPurchase == (m.docType == 'purchase')) _doc = d;
        }
      }
    });
  }

  List<_OpenDoc> get _docChoices => <_OpenDoc>[for (final _OpenDoc d in _docs) if (d.e.isPurchase == (_kind == 'paid_seller')) d];

  Future<void> _pickDoc(_OpenDoc? d) async {
    setState(() {
      _doc = d;
      if (d != null) {
        _ccy = d.ccy;
        _amount.text = _num(double.parse(d.openCcy.toStringAsFixed(d.ccy == 'IRR' ? 0 : 4)));
      }
    });
    if (d == null) return;
    double rate = 1;
    if (d.ccy != 'IRR') {
      final List<Map<String, Object?>> r = await (await AppDb.I.db)
          .rawQuery('SELECT fx_rate FROM ${d.e.isPurchase ? 'purchases' : 'sales'} WHERE id = ?', <Object?>[d.e.id]);
      rate = r.isEmpty ? 0 : ((r.first['fx_rate'] as num?) ?? 0).toDouble();
    }
    if (mounted) setState(() => _docRate = rate);
  }

  Future<void> _prefillRate() async {
    if (_payCcy == 'IRR' || _rate.text.trim().isNotEmpty) return;
    final ({double rate, String date})? r = await FxLocal.rateAt(_payCcy, fxIsoDate(_date));
    if (r != null && mounted) setState(() => _rate.text = _num(r.rate));
  }

  XchMove? _candidate() {
    final double amt = parseNum(_amount.text) ?? 0;
    final double pay = parseNum(_pay.text) ?? 0;
    final String ex = xchPartyKey(_ex.text);
    if (ex.isEmpty) return null;
    if (_settle) {
      if (_doc == null || amt <= 0) return null;
      return XchMove(
        uid: widget.existing?.uid ?? '',
        date: fxIsoDate(_date),
        kind: _kind,
        exchanger: ex,
        party: xchPartyKey(_doc!.party),
        docType: _doc!.e.isPurchase ? 'purchase' : 'sale',
        docId: _doc!.e.id,
        ccy: _ccy,
        amountCcy: amt,
        docRate: _ccy == 'IRR' ? 1 : _docRate,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
    }
    final bool same = _payCcy == _ccy;
    final double a = same ? pay : amt;
    if (a <= 0 || pay <= 0) return null;
    final double rate = _payCcy == 'IRR' ? 1 : (parseNum(_rate.text) ?? 0);
    return XchMove(
      uid: widget.existing?.uid ?? '',
      date: fxIsoDate(_date),
      kind: _kind,
      exchanger: ex,
      ccy: _ccy,
      amountCcy: a,
      payCcy: _payCcy,
      payAmount: pay,
      payRate: rate,
      cashBox: _acctKind == 'cash' ? _acct : null,
      bankAccount: _acctKind == 'bank' ? _acct : null,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      links: <XchLink>[for (final String l in _links) XchLink(l)],
    );
  }

  /// v92: لات‌های بازِ همین صراف و ارز که این تسویه می‌تواند ببندد
  List<(XchLot, XchMove?)> _openLots() {
    final String ex = xchPartyKey(_ex.text);
    if (ex.isEmpty || _settle) return const <(XchLot, XchMove?)>[];
    final List<XchMove> others = <XchMove>[for (final XchMove m in _moves) if (widget.existing == null || m.uid != widget.existing!.uid || m.isLeg) m];
    final XchRun run = xchRun(others);
    final XchPosition? p = run.positions['$ex\u001f$_ccy'];
    if (p == null) return const <(XchLot, XchMove?)>[];
    final bool wantPos = _kind == 'xch_paid_us'; // صراف به ما داد ⇒ طلب‌های ما (لات +) بسته می‌شود
    final Map<String, XchMove> src = <String, XchMove>{for (final XchMove m in others) m.lotId: m};
    return <(XchLot, XchMove?)>[for (final XchLot l in p.lots) if ((l.q > 0) == wantPos) (l, src[l.id])];
  }

  Widget _lotsPicker() {
    final List<(XchLot, XchMove?)> lots = _openLots();
    if (lots.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: _links.isNotEmpty,
      title: Text(_links.isEmpty ? 'بابت کدام واریزها؟ (خودکار: قدیمی‌ترین اول)' : 'بابت ${faNum(_links.length, dec: 0)} واریز انتخاب‌شده', style: const TextStyle(fontSize: 13)),
      children: <Widget>[
        for (final (XchLot l, XchMove? m) in lots)
          CheckboxListTile(
            dense: true,
            value: _links.contains(l.id),
            onChanged: (bool? v) => setState(() => v == true ? _links.add(l.id) : _links.remove(l.id)),
            title: Text(m != null && m.isLeg ? '«${m.party}» — شناسنامهٔ ${m.refNo ?? ''}' : 'حرکت ${jalaliDate(l.date)}'),
            subtitle: Text('${jalaliDate(l.date)} • ${xchAmount(_ccy, l.amount)} • نرخ دفتری ${faNum((l.b / (l.amount == 0 ? 1 : l.amount)).abs(), dec: 0)}'),
          ),
        const Text('واریزهای انتخاب‌شده اول بسته می‌شوند (به ترتیب انتخاب)؛ باقی از قدیمی‌ترین.', style: TextStyle(fontSize: 11)),
      ],
    );
  }

  String? _acctKind;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final XchMove? m = _candidate();
    if (m == null) {
      snack(context, _settle ? 'صراف، فاکتور و مبلغ را کامل کنید' : 'صراف و مبلغ‌ها را کامل کنید');
      return;
    }
    if (_settle && m.amountCcy > (_doc!.openCcy + (m.ccy == 'IRR' ? 10 : 0.005))) {
      snack(context, 'مبلغ تسویه از ماندهٔ فاکتور بیشتر است');
      return;
    }
    if (!m.isSettle && m.payCcy != 'IRR' && m.payRate <= 0) {
      snack(context, 'نرخ ریالی ارز پرداخت را وارد کنید');
      return;
    }
    if (m.exchanger == m.party) {
      snack(context, 'صراف و طرف‌حساب فاکتور نمی‌توانند یکی باشند');
      return;
    }
    setState(() => _saving = true);
    final Map<String, dynamic> data = <String, dynamic>{
      'date': m.date,
      'kind': m.kind,
      'exchanger': m.exchanger,
      'party': m.party,
      'doc_type': m.docType,
      'doc_id': m.docId,
      'ccy': m.ccy,
      'amount_ccy': m.amountCcy,
      'doc_rate': m.isSettle ? m.docRate : null,
      'pay_ccy': m.isSettle ? null : m.payCcy,
      'pay_amount': m.isSettle ? null : m.payAmount,
      'pay_rate': m.isSettle ? null : m.payRate,
      'cash_box': m.cashBox,
      'bank_account': m.bankAccount,
      'note': m.note,
      'links': m.isSettle || m.links.isEmpty ? null : <Map<String, dynamic>>[for (final XchLink l in m.links) l.toJson()], // v92
    };
    try {
      await EntityStore.I.save('xch_moves', data, uid: widget.existing?.uid);
      if (mounted) {
        Navigator.pop(context);
        snack(context, 'حرکت صراف ثبت شد');
      }
    } on ArgumentError catch (e) {
      if (mounted) snack(context, '${e.message}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _numField(TextEditingController c, String label, {String? helper}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, helperText: helper, border: const OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
      );

  Widget _ccyDrop(String label, String value, ValueChanged<String> on) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          value: _ccys.contains(value) ? value : null,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          items: <DropdownMenuItem<String>>[for (final String c in _ccys) DropdownMenuItem<String>(value: c, child: Text(c == 'IRR' ? 'ریال (IRR)' : c))],
          onChanged: (String? v) {
            if (v != null) on(v);
          },
        ),
      );

  Widget _preview() {
    final XchMove? m = _candidate();
    if (m == null) return const SizedBox.shrink();
    final XchResult r = xchPreview(_moves, m);
    final String bal = r.q4After == 0
        ? 'بعد از این حرکت، مانده ${m.ccy} صراف تسویه می‌شود.'
        : 'بعد از این حرکت: ${r.q4After > 0 ? 'صراف به ما' : 'ما به صراف'} ${xchAmount(m.ccy, r.balanceAfter)} بدهکار${r.q4After > 0 ? ' است' : 'یم'}.';
    final List<String> lines = <String>[
      if (m.isSettle) '«${m.party}» به ارز فاکتور (${xchAmount(m.ccy, m.amountCcy)}) تسویه می‌شود؛ مبلغ دفتری ${xchRial(r.dr.abs())}.',
      if (!m.isSettle && m.payCcy != m.ccy)
        'نرخ ضمنی: هر ۱ ${m.ccy} = ${faNum(m.payAmount / m.amountCcy, dec: 4)} ${m.payCcy == 'IRR' ? 'ریال' : m.payCcy}',
      if (!m.isSettle) 'ارزش ریالی این پرداخت: ${xchRial(r.dr.abs())}؛ مبلغ دفتری تسویه‌شده: ${xchRial(r.db.abs())}',
      bal,
      if (r.realized != 0) '${r.realized > 0 ? 'سود' : 'زیان'} تحقق‌یافتهٔ تفاوت نرخ: ${xchRial(r.realized.abs())}',
    ];
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          const Text('پیش‌نمایش', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final String l in lines) Padding(padding: const EdgeInsets.only(top: 4), child: Text(l)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool same = _payCcy == _ccy;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Text(widget.existing == null ? 'ثبت حرکت صراف' : 'ویرایش حرکت صراف', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_stlOn && widget.existing == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('واریز طرف‌حساب به صراف، یا پرداخت صراف به طرف‌حساب، از «پرداخت و وصول» (شناسنامه) ثبت می‌شود؛ اینجا فقط تسویهٔ خود صراف با ما.',
                      style: TextStyle(fontSize: 12)),
                ),
              Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                for (final MapEntry<String, String> e in kXchKindsFa.entries)
                  if (!(_stlOn && widget.existing == null && (e.key == 'cust_paid' || e.key == 'paid_seller')))
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _kind == e.key,
                    onSelected: widget.existing != null
                        ? null
                        : (bool _) => setState(() {
                              _kind = e.key;
                              _doc = null;
                            }),
                  ),
              ]),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(kXchKindsHelp[_kind] ?? '', style: const TextStyle(fontSize: 12))),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Autocomplete<String>(
                  initialValue: TextEditingValue(text: _ex.text),
                  optionsBuilder: (TextEditingValue v) {
                    final String q = xchPartyKey(v.text);
                    if (q.isEmpty) return const Iterable<String>.empty();
                    return _names.where((String n) => n.contains(q)).take(8);
                  },
                  onSelected: (String v) => setState(() => _ex.text = v),
                  fieldViewBuilder: (BuildContext c, TextEditingController t, FocusNode f, VoidCallback _) => TextFormField(
                    controller: t,
                    focusNode: f,
                    decoration: const InputDecoration(labelText: 'نام صراف', border: OutlineInputBorder()),
                    validator: (String? v) => xchPartyKey(v).isEmpty ? 'نام صراف الزامی است' : null,
                    onChanged: (String v) => setState(() => _ex.text = v),
                  ),
                ),
              ),
              dateField(context, 'تاریخ', _date, (DateTime d) => setState(() => _date = d)),
              if (_settle) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<_OpenDoc>(
                    value: _docChoices.contains(_doc) ? _doc : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: _kind == 'cust_paid' ? 'فاکتور فروشِ تسویه‌شونده' : 'فاکتور خریدِ تسویه‌شونده', border: const OutlineInputBorder()),
                    items: <DropdownMenuItem<_OpenDoc>>[
                      for (final _OpenDoc d in _docChoices) DropdownMenuItem<_OpenDoc>(value: d, child: Text(d.label, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: widget.existing != null ? null : _pickDoc,
                    validator: (_OpenDoc? d) => d == null ? 'فاکتور را انتخاب کنید' : null,
                  ),
                ),
                if (_docChoices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('فاکتور بازی پیدا نشد (فاکتورهای همگام‌نشده هنوز قابل انتخاب نیستند).', style: TextStyle(fontSize: 12)),
                  ),
                _numField(_amount, 'مبلغ تسویه ${_ccy == 'IRR' ? '(ریال)' : '($_ccy)'}', helper: 'به ارز خود فاکتور'),
              ] else ...<Widget>[
                _ccyDrop('ارز ماندهٔ صراف که تسویه می‌شود', _ccy, (String v) => setState(() => _ccy = v)),
                _ccyDrop('ارز پولی که جابه‌جا شد', _payCcy, (String v) {
                  setState(() {
                    _payCcy = v;
                    _rate.clear();
                    _acct = null;
                  });
                  _prefillRate();
                }),
                _numField(_pay, 'مبلغ پرداخت ${_payCcy == 'IRR' ? '(ریال)' : '($_payCcy)'}'),
                if (!same) _numField(_amount, 'چه مقدار از ماندهٔ $_ccy صراف تسویه شد؟', helper: 'به $_ccy'),
                if (_payCcy != 'IRR') _numField(_rate, 'نرخ ریالی $_payCcy در این روز', helper: 'ریال برای هر واحد $_payCcy'),
                InternalAccountPicker(
                  value: _acct,
                  ccy: _payCcy,
                  label: _kind == 'xch_paid_us' ? 'به کدام حساب ما واریز شد؟ (اختیاری)' : 'از کدام حساب ما پرداخت شد؟ (اختیاری)',
                  onChanged: (String? u, InternalAccount? a) => setState(() {
                    _acct = u;
                    _acctKind = a?.kind;
                  }),
                ),
              ],
              _lotsPicker(), // v92
              textField(_note, 'توضیح'),
              _preview(),
              const SizedBox(height: 8),
              FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'در حال ذخیره…' : 'ذخیره')),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }
}
