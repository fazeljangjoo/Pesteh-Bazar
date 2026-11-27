// v92 — «شناسنامهٔ پرداخت/وصول»: فهرست، فرم ثبت (تخصیص FIFO/دستی + مراحل مستقیم/صرافی به هر ارز)، شناسنامه (خط زمانی مراحل) و چاپ.
// داده: موجودیت `settlements` (EntityStore ⇒ ذخیرهٔ محلی + صف همگام‌سازی). محاسبه: settle_calc.dart (همان الگوریتم سرور).
import 'package:flutter/material.dart';

import 'db.dart';
import 'entity_store.dart';
import 'fmt.dart' show Fmt;
import 'fx_local.dart';
import 'ledger.dart';
import 'settle_calc.dart';
import 'settle_data.dart';
import 'settle_pdf.dart';
import 'treasury_link.dart';
import 'utils.dart';
import 'widgets.dart';
import 'xch_calc.dart';
import 'xch_ui.dart' show showXchMoveSheet; // v94

/// مبلغ به ارز خودش (IRR = ریال)
String stlAmount(String ccy, num v) => ccy == 'IRR' ? Fmt.money(v.abs(), from: 'rial') : faCcy(ccy, v.abs(), dec: 2);
String stlRial(num v) => Fmt.money(v.abs(), from: 'rial');
String stlGain(int r) => r == 0 ? 'بدون سود/زیان' : '${r > 0 ? 'سود' : 'زیان'} ${stlRial(r)}';
Color stlGainColor(int r) => r > 0 ? Colors.green.shade800 : (r < 0 ? Colors.red.shade800 : Colors.black54);

/// پنجرهٔ پهن ویندوز: فرم و شناسنامه حداکثر ۹۲۰ پیکسل پهنا (روی گوشی بی‌اثر)
Widget stlWide(Widget child) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 920), child: child));

String stlKindFa(String k) => k == 'xch' ? 'از طریق صراف' : (k == 'cheque' ? 'چک' : 'مستقیم');

/// آیا سرور این بخش را دارد؟ (سرور قدیمی ⇒ پنهان)
Future<bool> settlementsAvailable() async {
  try {
    return await EntityStore.I.isVisible('settlements');
  } catch (_) {
    return false;
  }
}

Future<(bool, StlState)> _availAndState() async => (await settlementsAvailable(), await loadStlState());

Future<void> openSettlementForm(BuildContext context, {String? party, String dir = 'recv', String? ccy, Settlement? existing, StlDoc? doc}) async {
  if (!await settlementsAvailable()) {
    if (context.mounted) snack(context, 'شناسنامهٔ پرداخت/وصول هنوز روی سرور فعال نشده است؛ پس از به‌روزرسانی سرور و همگام‌سازی در دسترس است.');
    return;
  }
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SettlementFormScreen(party: party, dir: dir, ccy: ccy, existing: existing, doc: doc)));
}

// ============================================================================
// فهرست شناسنامه‌ها (تب «پرداخت و وصول»)
// ============================================================================
class SettlementsTab extends StatefulWidget {
  final String? party; // فقط شناسنامه‌های یک طرف‌حساب / صراف
  final bool embedded;
  const SettlementsTab({super.key, this.party, this.embedded = true});
  @override
  State<SettlementsTab> createState() => _SettlementsTabState();
}

class _SettlementsTabState extends State<SettlementsTab> {
  String _dir = 'all';
  String _status = 'all';
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppDb.I.version,
      builder: (BuildContext _, int __, Widget? ___) => FutureBuilder<(bool, StlState)>(
        future: _availAndState(),
        builder: (BuildContext context, AsyncSnapshot<(bool, StlState)> snap) {
          if (snap.hasError) return Center(child: Text('خطا: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (bool avail, StlState st) = snap.data!;
          if (!avail) {
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('شناسنامهٔ پرداخت/وصول هنوز روی سرور فعال نشده است.\nپس از به‌روزرسانی سرور و همگام‌سازی، این بخش باز می‌شود.', textAlign: TextAlign.center),
            ));
          }
          final String? only = widget.party == null ? null : xchPartyKey(widget.party);
          final List<Trail> all = <Trail>[
            for (final Settlement s in st.stls.reversed)
              if (only == null || s.party == only || s.legs.any((StlLeg l) => l.exchanger == only)) stlTrail(st, s.uid)!,
          ]..sort((Trail a, Trail b) => b.s.date.compareTo(a.s.date));
          final String q = xchPartyKey(_q);
          final List<Trail> list = all.where((Trail t) {
            if (_dir != 'all' && t.s.dir != _dir) return false;
            if (_status == 'open' && t.complete) return false;
            if (_status == 'complete' && !t.complete) return false;
            if (q.isNotEmpty && !('${t.s.party} ${t.s.refNo} ${t.s.legs.map((StlLeg l) => l.exchanger ?? '').join(' ')}').contains(q)) return false;
            return true;
          }).toList();
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: <Widget>[
            if (widget.party == null) ...<Widget>[
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                      'هر پرداخت یا وصول یک «شناسنامه» دارد: روی کدام فاکتورها نشست (خودکار از قدیمی‌ترین یا دستی)، و از چه مسیری آمد یا رفت (مستقیم، یا از طریق یک یا چند صراف، به هر ارزی). '
                      'تا صراف با ما تسویه نکند، شناسنامه «باز» است.',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
              TextField(
                decoration: const InputDecoration(labelText: 'جستجو (طرف‌حساب، صراف، شماره)', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                onChanged: (String v) => setState(() => _q = v),
              ),
              const SizedBox(height: 6),
            ],
            Wrap(spacing: 6, runSpacing: 4, children: <Widget>[
              for (final MapEntry<String, String> e in const <String, String>{'all': 'همه', 'recv': 'وصول', 'pay': 'پرداخت'}.entries)
                ChoiceChip(label: Text(e.value), selected: _dir == e.key, onSelected: (_) => setState(() => _dir = e.key)),
              const SizedBox(width: 8),
              for (final MapEntry<String, String> e in const <String, String>{'all': 'همهٔ وضعیت‌ها', 'open': 'باز', 'complete': 'کامل‌شده'}.entries)
                ChoiceChip(label: Text(e.value), selected: _status == e.key, onSelected: (_) => setState(() => _status = e.key)),
            ]),
            const SizedBox(height: 6),
            if (list.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('شناسنامه‌ای پیدا نشد'))),
            for (final Trail t in list) TrailTile(trail: t),
          ]);
        },
      ),
    );
  }
}

class TrailTile extends StatelessWidget {
  final Trail trail;
  const TrailTile({super.key, required this.trail});
  @override
  Widget build(BuildContext context) {
    final Trail t = trail;
    final List<String> ex = <String>{for (final StlLeg l in t.s.legs) if (l.isXch) l.exchanger ?? ''}.toList();
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: t.s.isRecv ? Colors.green.shade100 : Colors.red.shade100,
          child: Icon(t.s.isRecv ? Icons.south_west : Icons.north_east, color: t.s.isRecv ? Colors.green.shade800 : Colors.red.shade800),
        ),
        title: Text('${t.s.isRecv ? 'وصول از' : 'پرداخت به'} ${t.s.party} — ${stlAmount(t.s.ccy, t.s.amt4 / kQ)}'),
        subtitle: Text('${t.s.refNo.isEmpty ? 'در انتظار همگام‌سازی' : t.s.refNo} • ${jalaliDate(t.s.date)} • ${t.stages.length} مرحله'
            '${ex.isEmpty ? '' : ' • صراف: ${ex.join('، ')}'}'
            '${t.advOpen4 > 0 ? '\nعلی‌الحساب باز: ${stlAmount(t.s.ccy, t.advOpen4 / kQ)}' : ''}'),
        isThreeLine: t.advOpen4 > 0,
        trailing: Chip(
          label: Text(t.complete ? 'کامل' : 'باز', style: const TextStyle(fontSize: 11)),
          backgroundColor: t.complete ? Colors.green.shade50 : Colors.orange.shade50,
          visualDensity: VisualDensity.compact,
        ),
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SettlementTrailScreen(uid: t.s.uid))),
      ),
    );
  }
}

/// کارت شناسنامه‌های یک طرف‌حساب (در جزئیات طرف‌حساب) + دکمه‌های وصول/پرداخت
class PartySettlementsCard extends StatelessWidget {
  final PartyAccount account;
  const PartySettlementsCard({super.key, required this.account});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(bool, StlState)>(
      future: _availAndState(),
      builder: (BuildContext context, AsyncSnapshot<(bool, StlState)> snap) {
        if (!snap.hasData || !snap.data!.$1) return const SizedBox.shrink();
        final StlState st = snap.data!.$2;
        final String me = account.key;
        final List<Trail> trails = <Trail>[
          for (final Settlement s in st.stls)
            if (s.party == me || s.legs.any((StlLeg l) => l.exchanger == me)) stlTrail(st, s.uid)!,
        ]..sort((Trail a, Trail b) => b.s.date.compareTo(a.s.date));
        final List<StlAdvLot> adv = <StlAdvLot>[for (final StlAdvLot l in st.match.adv) if (l.party == me && l.q4 > 0) l];
        final List<StlDoc> open = <StlDoc>[
          for (final StlDoc d in st.docs.values)
            if (d.party == me && (st.match.docs[d.key]?.open4 ?? 0) > 0) d,
        ];
        final Map<String, int> recv = <String, int>{}, pay = <String, int>{};
        for (final StlDoc d in open) {
          final Map<String, int> m = d.t == 'sale' ? recv : pay;
          m[d.ccy] = (m[d.ccy] ?? 0) + st.match.docs[d.key]!.open4;
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Row(children: <Widget>[
                Icon(Icons.fact_check_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('پرداخت و وصول (شناسنامه‌ها)', style: Theme.of(context).textTheme.titleMedium)),
              ]),
              const SizedBox(height: 6),
              for (final MapEntry<String, int> e in recv.entries)
                infoRow('فاکتورهای فروش باز (${e.key})', stlAmount(e.key, e.value / kQ), valueColor: Colors.green.shade800),
              for (final MapEntry<String, int> e in pay.entries)
                infoRow('فاکتورهای خرید باز (${e.key})', stlAmount(e.key, e.value / kQ), valueColor: Colors.red.shade800),
              for (final StlAdvLot l in adv)
                infoRow(l.dir == 'recv' ? 'علی‌الحساب دریافتی (${l.ccy})' : 'علی‌الحساب پرداختی (${l.ccy})', stlAmount(l.ccy, l.q4 / kQ)),
              const SizedBox(height: 6),
              Row(children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => openSettlementForm(context, party: me, dir: 'recv', ccy: recv.keys.isEmpty ? null : recv.keys.first),
                    icon: const Icon(Icons.south_west),
                    label: const Text('وصول از این طرف'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => openSettlementForm(context, party: me, dir: 'pay', ccy: pay.keys.isEmpty ? null : pay.keys.first),
                    icon: const Icon(Icons.north_east),
                    label: const Text('پرداخت به این طرف'),
                  ),
                ),
              ]),
              for (final Trail t in trails.take(20)) TrailTile(trail: t),
              if (trails.length > 20)
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
                      builder: (_) => Scaffold(appBar: AppBar(title: Text('شناسنامه‌های $me')), body: SettlementsTab(party: me)))),
                  child: Text('همهٔ ${faNum(trails.length, dec: 0)} شناسنامه'),
                ),
            ]),
          ),
        );
      },
    );
  }
}

/// شناسنامه‌هایی که روی یک فاکتور نشسته‌اند
Future<void> showDocTrails(BuildContext context, {required bool isPurchase, required int docId}) async {
  final StlState st = await loadStlState();
  final String k = stlDocKey(isPurchase ? 'purchase' : 'sale', docId);
  final Set<String> uids = <String>{
    for (final StlBy b in st.match.docs[k]?.by ?? const <StlBy>[]) b.uid,
    for (final StlCons c in st.match.docs[k]?.cons ?? const <StlCons>[]) c.uid,
  };
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(12), children: <Widget>[
        Text('شناسنامه‌های ${isPurchase ? 'خرید' : 'فروش'} #$docId', style: Theme.of(ctx).textTheme.titleMedium),
        if (st.docs[k] != null)
          infoRow('ماندهٔ باز این فاکتور', stlAmount(st.docs[k]!.ccy, (st.match.docs[k]?.open4 ?? 0) / kQ)),
        const Text('پرداخت/دریافت‌های تک‌فاکتوری قبلی در «مدیریت پرداخت/دریافت» همین فاکتور هستند.', style: TextStyle(fontSize: 12)),
        if (uids.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('هنوز شناسنامه‌ای روی این فاکتور ننشسته است.')),
        for (final String u in uids)
          if (stlTrail(st, u) != null) TrailTile(trail: stlTrail(st, u)!),
        const SizedBox(height: 8),
        if (st.docs[k] != null && docId > 0)
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              openSettlementForm(context, party: st.docs[k]!.party, dir: isPurchase ? 'pay' : 'recv', ccy: st.docs[k]!.ccy, doc: st.docs[k]);
            },
            icon: const Icon(Icons.add),
            label: Text(isPurchase ? 'پرداخت چندمرحله‌ای / از طریق صراف' : 'وصول چندمرحله‌ای / از طریق صراف'),
          ),
      ]),
    ),
  );
}

// ============================================================================
// فرم ثبت/ویرایش شناسنامه
// ============================================================================
class _LegCtl {
  final String lid;
  String k;
  String ccy;
  String? account;
  final TextEditingController exchanger;
  final TextEditingController settle;
  final TextEditingController amount;
  final TextEditingController rate;
  final TextEditingController ref;
  final TextEditingController note;
  DateTime? date;
  // v92 فاز د: چک
  final TextEditingController chqNo = TextEditingController();
  final TextEditingController chqBank = TextEditingController();
  final TextEditingController chqSayad = TextEditingController();
  DateTime? chqDue;
  String shareMode = 'rate'; // v93: مرحلهٔ ارز دیگر ⇒ سهم از بدهی «طبق نرخ روز» یا «مبلغ توافقی»
  _LegCtl({required this.lid, this.k = 'direct', required this.ccy, this.account, String exchanger = '', String settle = '', String amount = '', String rate = '', String ref = '', String note = '', this.date})
      : exchanger = TextEditingController(text: exchanger),
        settle = TextEditingController(text: settle),
        amount = TextEditingController(text: amount),
        rate = TextEditingController(text: rate),
        ref = TextEditingController(text: ref),
        note = TextEditingController(text: note);
}

String _num(double v, {int dec = 4}) {
  final String s = v.toStringAsFixed(dec);
  return s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
}

class SettlementFormScreen extends StatefulWidget {
  final String? party;
  final String dir;
  final String? ccy;
  final Settlement? existing;
  final StlDoc? doc; // از صفحهٔ فاکتور: تخصیص دستی همین فاکتور
  const SettlementFormScreen({super.key, this.party, this.dir = 'recv', this.ccy, this.existing, this.doc});
  @override
  State<SettlementFormScreen> createState() => _SettlementFormScreenState();
}

class _SettlementFormScreenState extends State<SettlementFormScreen> with EditGuard {
  late String _dir;
  late final TextEditingController _party;
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String _ccy = 'IRR';
  DateTime _date = DateTime.now();
  String _mode = 'fifo';
  final Map<String, TextEditingController> _manual = <String, TextEditingController>{};
  final List<_LegCtl> _legs = <_LegCtl>[];
  List<String> _ccys = <String>['IRR'];
  List<String> _names = <String>[];
  List<String> _exchangers = <String>[];
  StlState? _base;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final Settlement? e = widget.existing;
    _dir = e?.dir ?? widget.dir;
    _party = TextEditingController(text: e?.party ?? widget.party ?? '');
    _ccy = e?.ccy ?? widget.ccy ?? widget.doc?.ccy ?? 'IRR';
    if (e != null) {
      _date = DateTime.tryParse(e.date) ?? DateTime.now();
      _amount.text = stlFmt4(e.amt4);
      _mode = e.allocMode;
      _note.text = e.note ?? '';
      for (final (String k, int q) in e.alloc) {
        _manual[k] = TextEditingController(text: stlFmt4(q));
      }
      for (final StlLeg l in e.legs) {
        _legs.add(_LegCtl(
          lid: l.lid,
          k: l.k,
          ccy: l.ccy,
          account: l.accountUid,
          exchanger: l.exchanger ?? '',
          settle: stlFmt4(l.settle4),
          amount: _num(l.amount),
          rate: l.ccy == 'IRR' ? '' : _num(l.rate, dec: 6),
          ref: l.ref ?? '',
          note: l.note ?? '',
          date: l.date == null ? null : DateTime.tryParse(l.date!),
        ));
        if (l.ccy != (e.ccy)) _legs.last.shareMode = 'agreed'; // v93: سهم ذخیره‌شده دست نمی‌خورد
        if (l.cheque != null) { // v92 فاز د
          _legs.last.chqNo.text = l.cheque!['no'] ?? '';
          _legs.last.chqBank.text = l.cheque!['bank'] ?? '';
          _legs.last.chqSayad.text = l.cheque!['sayad'] ?? '';
          _legs.last.chqDue = DateTime.tryParse(l.cheque!['due'] ?? '');
        }
      }
    } else {
      if (widget.doc != null) _mode = 'manual';
      _legs.add(_LegCtl(lid: EntityStore.newUid(), ccy: _ccy));
    }
    _init();
  }

  Future<void> _init() async {
    final List<Map<String, dynamic>> cur = await FxLocal.loadCurrencies().catchError((Object _) => <Map<String, dynamic>>[]);
    final List<PartyAccount> parties = await loadParties();
    final StlState base = await loadStlState(excludeUid: widget.existing?.uid ?? '');
    if (!mounted) return;
    setState(() {
      _ccys = <String>['IRR', for (final Map<String, dynamic> c in cur) if (c['is_base'] != true && c['active'] == true && '${c['code']}'.isNotEmpty) '${c['code']}'];
      for (final String c in <String>[_ccy, for (final _LegCtl l in _legs) l.ccy]) {
        if (!_ccys.contains(c)) _ccys.add(c);
      }
      _names = <String>[for (final PartyAccount a in parties) if (a.key.isNotEmpty) a.key];
      _exchangers = <String>[for (final PartyAccount a in parties) if (a.isExchanger && a.key.isNotEmpty) a.key];
      _base = base;
      final StlDoc? d = widget.doc;
      if (d != null && widget.existing == null) {
        final int open = base.match.docs[d.key]?.open4 ?? 0;
        _manual[d.key] = TextEditingController(text: stlFmt4(open));
        _amount.text = stlFmt4(open);
        _legs.first.settle.text = stlFmt4(open);
        if (_legs.first.ccy == _ccy) _legs.first.amount.text = stlFmt4(open);
      }
    });
    for (final _LegCtl l in _legs) {
      await _prefillRate(l);
    }
  }

  // v93: نرخ روزِ ارز بدهی برای تبدیل خودکار مرحله‌های ارز دیگر
  final Map<String, double> _debtRates = <String, double>{};
  final Set<String> _debtRateAsked = <String>{};

  double? _debtRate(String date) {
    if (_ccy == 'IRR') return 1;
    final String k = '$_ccy|$date';
    if (!_debtRates.containsKey(k) && _debtRateAsked.add(k)) {
      FxLocal.rateAt(_ccy, date).then((({double rate, String date})? r) {
        if (!mounted) return;
        setState(() => _debtRates[k] = r?.rate ?? 0);
      });
    }
    final double? v = _debtRates[k];
    return v == null || v <= 0 ? null : v;
  }

  /// سهم از بدهی = مبلغ × نرخ ارز مرحله ÷ نرخ روز ارز بدهی (فقط در حالت «نرخ روز»)
  void _autoShares() {
    for (final _LegCtl l in _legs) {
      if (l.ccy == _ccy || l.shareMode != 'rate') continue;
      final double amt = parseNum(l.amount.text) ?? 0;
      final double lr = l.ccy == 'IRR' ? 1 : (parseNum(l.rate.text) ?? 0);
      final double? dr = _debtRate(fxIsoDate(l.date ?? _date));
      if (amt <= 0 || lr <= 0 || dr == null) continue;
      final String v = stlFmt4(stlQ4(amt * lr / dr));
      if (l.settle.text != v) l.settle.text = v;
    }
  }

  Future<void> _prefillRate(_LegCtl l) async {
    if (l.ccy == 'IRR' || l.rate.text.trim().isNotEmpty) return;
    final ({double rate, String date})? r = await FxLocal.rateAt(l.ccy, fxIsoDate(l.date ?? _date));
    if (r != null && mounted) setState(() => l.rate.text = _num(r.rate, dec: 6));
  }

  String get _partyKey => xchPartyKey(_party.text);
  int get _amt4 => stlQ4(parseNum(_amount.text) ?? 0);
  String get _side => _dir == 'recv' ? 'sale' : 'purchase';

  /// فاکتورهای همگام‌شدهٔ همین طرف/ارز/جهت (برای تخصیص)
  Map<String, StlDoc> get _docs => <String, StlDoc>{
        for (final StlDoc d in _base?.docs.values ?? const <StlDoc>[])
          if (d.id > 0) d.key: d,
      };

  List<StlDoc> get _myDocs => <StlDoc>[
        for (final StlDoc d in _docs.values)
          if ((d.isLoan ? d.dir == _dir : d.t == _side) && d.party == _partyKey && d.ccy == _ccy) d, // v92 فاز ج: + قرض‌های همین جهت
      ]..sort((StlDoc a, StlDoc b) {
          final int c = a.date.compareTo(b.date);
          return c != 0 ? c : a.id.compareTo(b.id);
        });

  int _open4(StlDoc d) => _base?.match.docs[d.key]?.open4 ?? 0;

  /// باز «ذخیره‌شده» (بدون مصرف علی‌الحساب) — سقف تخصیص دستی، مثل سرور
  int _openStored(StlDoc d) {
    int o = d.total4 - (d.pre4 < d.total4 ? d.pre4 : d.total4);
    for (final StlBy b in _base?.match.docs[d.key]?.by ?? const <StlBy>[]) {
      o -= b.q4;
    }
    return o < 0 ? 0 : o;
  }

  List<(String, int)> _alloc() {
    if (_base == null || _partyKey.isEmpty) return const <(String, int)>[];
    if (_mode == 'fifo') return stlFifo(_docs, _base!.match, _partyKey, _ccy, _dir, fxIsoDate(_date), _amt4);
    return <(String, int)>[
      for (final StlDoc d in _myDocs)
        if (stlQ4(parseNum(_manual[d.key]?.text) ?? 0) > 0) (d.key, stlQ4(parseNum(_manual[d.key]!.text)!)),
    ];
  }

  List<StlLeg> _legModels() => <StlLeg>[
        for (final _LegCtl l in _legs)
          StlLeg(
            lid: l.lid,
            k: l.k,
            settle4: stlQ4(parseNum(l.settle.text) ?? 0),
            ccy: l.ccy,
            amount: l.ccy == _ccy ? (parseNum(l.settle.text) ?? 0) : (parseNum(l.amount.text) ?? 0),
            rate: l.ccy == 'IRR' ? 1 : (parseNum(l.rate.text) ?? 0),
            exchanger: l.k == 'xch' ? xchPartyKey(l.exchanger.text) : null,
            accountUid: l.k == 'direct' ? l.account : null,
            date: l.date == null ? null : fxIsoDate(l.date!),
            ref: l.ref.text.trim().isEmpty ? null : l.ref.text.trim(),
            note: l.note.text.trim().isEmpty ? null : l.note.text.trim(),
            cheque: l.k == 'cheque'
                ? <String, String>{'no': l.chqNo.text.trim(), 'bank': l.chqBank.text.trim(), 'sayad': l.chqSayad.text.trim(), 'due': l.chqDue == null ? '' : fxIsoDate(l.chqDue!)}
                : null,
          ),
      ];

  Settlement _candidate() => Settlement(
        uid: widget.existing?.uid ?? 'preview',
        order: widget.existing?.order ?? 1 << 40,
        date: fxIsoDate(_date),
        dir: _dir,
        party: _partyKey,
        ccy: _ccy,
        amt4: _amt4,
        allocMode: _mode,
        alloc: _alloc(),
        legs: _legModels(),
        refNo: widget.existing?.refNo ?? '',
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );

  int get _legsSum => _legModels().fold(0, (int s, StlLeg l) => s + l.settle4);

  String? _problem() {
    if (_partyKey.isEmpty) return 'طرف‌حساب را انتخاب کنید';
    if (_amt4 <= 0) return 'مبلغ را وارد کنید';
    if (_legs.isEmpty) return 'حداقل یک مرحله لازم است';
    final List<StlLeg> ls = _legModels();
    for (int i = 0; i < ls.length; i++) {
      final StlLeg l = ls[i];
      final String n = 'مرحلهٔ ${faNum(i + 1, dec: 0)}';
      if (l.settle4 <= 0) return '$n: سهم از بدهی را وارد کنید';
      if (l.amount <= 0) return '$n: مبلغ را وارد کنید';
      if (l.ccy != 'IRR' && l.rate <= 0) return '$n: نرخ ریالی ${l.ccy} را وارد کنید';
      if (l.isXch && (l.exchanger ?? '').isEmpty) return '$n: صراف را انتخاب کنید';
      if (l.isXch && l.exchanger == _partyKey) return '$n: صراف و طرف‌حساب نمی‌توانند یکی باشند';
      if (l.isCheque && (l.cheque?['no'] ?? '').isEmpty) return '$n: شمارهٔ چک را وارد کنید';
      if (l.isCheque && (l.cheque?['due'] ?? '').isEmpty) return '$n: تاریخ سررسید چک را وارد کنید';
    }
    if (_legsSum != _amt4) return 'جمع سهم مراحل (${stlFmt4(_legsSum)}) با مبلغ (${stlFmt4(_amt4)} $_ccy) برابر نیست';
    if (_mode == 'manual') {
      int tot = 0;
      for (final (String k, int q) in _alloc()) {
        final StlDoc d = _docs[k]!;
        if (q > _openStored(d) + (_ccy == 'IRR' ? 100000 : 50)) return 'تخصیص به ${d.label} بیشتر از ماندهٔ آن است';
        tot += q;
      }
      if (tot > _amt4) return 'جمع تخصیص از مبلغ بیشتر است';
    }
    return null;
  }

  Future<void> _save() async {
    final String? p = _problem();
    if (p != null) {
      snack(context, p);
      return;
    }
    final Settlement c = _candidate();
    final Map<String, dynamic> data = <String, dynamic>{
      'date': c.date,
      'dir': c.dir,
      'party': c.party,
      'ccy': c.ccy,
      'amount_ccy': double.parse(stlFmt4(c.amt4)),
      'alloc_mode': c.allocMode,
      'alloc': <Map<String, dynamic>>[
        for (final (String k, int q) in c.alloc)
          _docs[k]!.isLoan
              ? <String, dynamic>{'t': 'loan', 'uid': _docs[k]!.uid, 'amt': double.parse(stlFmt4(q))} // v92 فاز ج
              : <String, dynamic>{'t': _docs[k]!.t, 'id': _docs[k]!.id, 'amt': double.parse(stlFmt4(q))},
      ],
      'legs': <Map<String, dynamic>>[for (final StlLeg l in c.legs) l.toJson()],
      'note': c.note,
    };
    setState(() => _saving = true);
    String savedUid = widget.existing?.uid ?? '';
    final bool ok = await saveConfirmed(context, () async => savedUid = await saveSettlement(data, uid: widget.existing?.uid),
        successMsg: _dir == 'recv' ? 'وصول ثبت شد' : 'پرداخت ثبت شد');
    if (mounted) setState(() => _saving = false);
    if (ok && mounted && widget.existing == null && savedUid.isNotEmpty) await _askXchSettled(c, savedUid); // v94
    if (ok && mounted) Navigator.pop(context);
  }

  /// v94: مرحلهٔ «از طریق صراف» ⇒ بپرس پول صراف همین حالا رد و بدل شده؟ بله ⇒ فرم تسویه با صراف پیش‌پر (پیوند به همین مرحله).
  /// بدون این، پرداخت از طریق صراف یعنی «صراف از طرف ما داد و ما به او بدهکاریم» تا تسویه ثبت شود.
  Future<void> _askXchSettled(Settlement c, String uid) async {
    for (final StlLeg l in c.legs) {
      if (l.k != 'xch' || (l.exchanger ?? '').isEmpty || !mounted) continue;
      final bool pay = c.dir == 'pay';
      final String amt = stlAmount(l.ccy, l.amount);
      final bool yes = await confirm(
          context,
          pay
              ? 'صراف «${l.exchanger}» مبلغ $amt را به «${c.party}» داد.\nپول این مبلغ را همین حالا به صراف داده‌اید؟\n(اگر نه، این مبلغ بدهی شما به صراف می‌ماند تا بعداً «پرداخت به صراف» را ثبت کنید.)'
              : '«${c.party}» مبلغ $amt را به صراف «${l.exchanger}» داد.\nصراف همین حالا این پول را به شما داده است؟\n(اگر نه، این مبلغ طلب شما از صراف می‌ماند تا بعداً «دریافت از صراف» را ثبت کنید.)');
      if (!yes || !mounted) continue;
      await showXchMoveSheet(context,
          exchanger: l.exchanger, prefill: (kind: pay ? 'we_paid_xch' : 'xch_paid_us', ccy: l.ccy, amount: l.amount, link: 's:$uid:${l.lid}'));
    }
  }

  // ---------------- UI ----------------

  Widget _ccyDrop(String label, String value, ValueChanged<String> on, {bool enabled = true}) => DropdownButtonFormField<String>(
        value: _ccys.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        items: <DropdownMenuItem<String>>[for (final String c in _ccys) DropdownMenuItem<String>(value: c, child: Text(c == 'IRR' ? 'ریال (IRR)' : c))],
        onChanged: enabled
            ? (String? v) {
                if (v != null) on(v);
              }
            : null,
      );

  Widget _numBox(TextEditingController c, String label, {String? helper, String? suffix, bool readOnly = false}) => TextField(
        controller: c,
        readOnly: readOnly,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, helperText: helper, suffixText: suffix, border: const OutlineInputBorder(), isDense: true),
        onChanged: (_) => setState(() {}),
      );

  Widget _nameField(TextEditingController ctl, String label, List<String> options) => Autocomplete<String>(
        initialValue: TextEditingValue(text: ctl.text),
        optionsBuilder: (TextEditingValue v) {
          final String q = xchPartyKey(v.text);
          if (q.isEmpty) return options.take(8);
          return options.where((String n) => n.contains(q)).take(8);
        },
        onSelected: (String v) => setState(() => ctl.text = v),
        fieldViewBuilder: (BuildContext c, TextEditingController t, FocusNode f, VoidCallback _) => TextField(
          controller: t,
          focusNode: f,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
          onChanged: (String v) => setState(() => ctl.text = v),
        ),
      );

  Widget _allocSection() {
    final List<StlDoc> docs = _myDocs.where((StlDoc d) => (_mode == 'manual' || !d.isLoan) && (_open4(d) > 0 || (_manual[d.key] != null && widget.existing != null))).toList();
    final List<(String, int)> alloc = _alloc();
    final Map<String, int> am = <String, int>{for (final (String k, int q) in alloc) k: q};
    final int allocated = alloc.fold(0, (int s, (String, int) e) => s + e.$2);
    final int adv = _amt4 - allocated;
    final int unsynced = (_base?.docs.values ?? const <StlDoc>[]).where((StlDoc d) => d.id <= 0 && d.party == _partyKey && d.t == _side).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            const Expanded(child: Text('روی کدام فاکتورها بنشیند؟', style: TextStyle(fontWeight: FontWeight.bold))),
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'fifo', label: Text('خودکار')),
                ButtonSegment<String>(value: 'manual', label: Text('دستی')),
              ],
              selected: <String>{_mode},
              onSelectionChanged: (Set<String> s) => setState(() {
                _mode = s.first;
                if (_mode == 'manual') {
                  // شروع دستی از همان پیشنهاد خودکار
                  final Map<String, int> f = <String, int>{for (final (String k, int q) in stlFifo(_docs, _base!.match, _partyKey, _ccy, _dir, fxIsoDate(_date), _amt4)) k: q};
                  for (final StlDoc d in _myDocs) {
                    (_manual[d.key] ??= TextEditingController()).text = f[d.key] == null ? '' : stlFmt4(f[d.key]!);
                  }
                }
              }),
            ),
          ]),
          Text(
              _mode == 'fifo'
                  ? 'از قدیمی‌ترین فاکتور باز (تا تاریخ همین شناسنامه) شروع می‌شود. اگر مبلغ بیشتر باشد، باقی «علی‌الحساب» می‌ماند و فاکتورهای بعدی خودکار از آن کم می‌کنند. برای بازپرداخت قرض «دستی» را بزنید.'
                  : 'سهم هر فاکتور یا قرض را خودتان بنویسید؛ هرچه تخصیص داده نشود علی‌الحساب می‌ماند.',
              style: const TextStyle(fontSize: 12)),
          if (unsynced > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${faNum(unsynced, dec: 0)} فاکتور این طرف هنوز همگام نشده و تا همگام‌سازی قابل تخصیص نیست.', style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
            ),
          const SizedBox(height: 6),
          if (docs.isEmpty) const Text('فاکتور بازی با این ارز نیست؛ کل مبلغ علی‌الحساب ثبت می‌شود.', style: TextStyle(fontSize: 12)),
          for (final StlDoc d in docs)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: <Widget>[
                Expanded(
                  child: Text('${d.label} • ${jalaliDate(d.date)}\nمانده: ${stlAmount(d.ccy, _open4(d) / kQ)}${d.ccy == 'IRR' ? '' : ' • نرخ ${faNum(d.rate, dec: 0)}'}',
                      style: const TextStyle(fontSize: 12)),
                ),
                SizedBox(
                  width: 130,
                  child: _mode == 'manual'
                      ? _numBox(_manual[d.key] ??= TextEditingController(), 'سهم', suffix: d.ccy == 'IRR' ? null : d.ccy)
                      : Text(am[d.key] == null ? '—' : stlAmount(d.ccy, am[d.key]! / kQ), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          const Divider(),
          infoRow('روی فاکتورها', stlAmount(_ccy, allocated / kQ)),
          if (adv != 0) infoRow(adv > 0 ? 'علی‌الحساب' : 'بیش از مبلغ!', stlAmount(_ccy, adv / kQ), valueColor: adv < 0 ? Colors.red.shade800 : null),
        ]),
      ),
    );
  }

  Widget _legCard(int i, _LegCtl l, StlLegRes? res, XchResult? xres) {
    final bool cross = l.ccy != _ccy;
    final int remaining = _amt4 - _legsSum;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            CircleAvatar(radius: 13, child: Text(faNum(i + 1, dec: 0), style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 8),
            Expanded(
              child: SegmentedButton<String>(
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'direct', label: Text(_dir == 'recv' ? 'مستقیم به ما' : 'مستقیم از ما'), icon: const Icon(Icons.account_balance_wallet_outlined)),
                  const ButtonSegment<String>(value: 'xch', label: Text('از طریق صراف'), icon: Icon(Icons.currency_exchange)),
                  const ButtonSegment<String>(value: 'cheque', label: Text('چک'), icon: Icon(Icons.receipt_outlined)), // v92 فاز د
                ],
                selected: <String>{l.k},
                onSelectionChanged: (Set<String> s) => setState(() => l.k = s.first),
              ),
            ),
            if (_legs.length > 1)
              IconButton(tooltip: 'حذف مرحله', icon: const Icon(Icons.close), onPressed: () => setState(() => _legs.removeAt(i))),
          ]),
          const SizedBox(height: 8),
          if (l.k == 'xch') ...<Widget>[
            _nameField(l.exchanger, _dir == 'recv' ? 'نام صراف (طرف‌حساب پول را به او داد)' : 'نام صراف (به طرف‌حساب پرداخت کرد)', _exchangers.isEmpty ? _names : _exchangers),
            const SizedBox(height: 8),
          ],
          Row(children: <Widget>[
            Expanded(
                child: _numBox(l.settle, 'سهم از بدهی', suffix: _ccy == 'IRR' ? 'ریال' : _ccy, readOnly: cross && l.shareMode == 'rate',
                    helper: !cross
                        ? null
                        : l.shareMode == 'rate'
                            ? (_debtRate(fxIsoDate(l.date ?? _date)) == null ? 'نرخ روز $_ccy ثبت نشده؛ «مبلغ توافقی» را بزنید' : 'طبق نرخ روز: مبلغ × نرخ ${l.ccy} ÷ نرخ $_ccy')
                            : 'مبلغ توافقی با طرف‌حساب')),
            if (remaining > 0 && !(cross && l.shareMode == 'rate'))
              TextButton(
                onPressed: () => setState(() {
                  final int cur = stlQ4(parseNum(l.settle.text) ?? 0);
                  l.settle.text = stlFmt4(cur + remaining);
                }),
                child: const Text('باقی‌مانده'),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: <Widget>[
            Expanded(
              child: _ccyDrop(l.k == 'xch' ? 'ارز واریز/پرداخت صراف' : 'ارز پول', l.ccy, (String v) {
                setState(() {
                  l.ccy = v;
                  l.rate.clear();
                  l.account = null;
                });
                _prefillRate(l);
              }),
            ),
            if (cross) ...<Widget>[const SizedBox(width: 8), Expanded(child: _numBox(l.amount, 'مبلغ', suffix: l.ccy == 'IRR' ? 'ریال' : l.ccy))],
          ]),
          if (l.ccy != 'IRR') ...<Widget>[
            const SizedBox(height: 8),
            _numBox(l.rate, 'نرخ ریالی ${l.ccy} در روز این مرحله', helper: 'ریال برای هر واحد؛ پیش‌فرض نرخ روز'),
          ],
          if (cross) ...<Widget>[ // v93: تبدیل به ارز بدهی
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'rate', label: Text('تبدیل به $_ccy طبق نرخ روز')),
                const ButtonSegment<String>(value: 'agreed', label: Text('مبلغ توافقی')),
              ],
              selected: <String>{l.shareMode},
              onSelectionChanged: (Set<String> s) => setState(() => l.shareMode = s.first),
            ),
          ],
          if (l.k == 'cheque') ...<Widget>[ // v92 فاز د: چک دریافتی/پرداختی؛ وصول، پاس و برگشت از «مدیریت چک»
            const SizedBox(height: 8),
            Row(children: <Widget>[
              Expanded(child: TextField(controller: l.chqNo, decoration: const InputDecoration(labelText: 'شمارهٔ چک', border: OutlineInputBorder(), isDense: true), onChanged: (_) => setState(() {}))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: l.chqBank, decoration: const InputDecoration(labelText: 'بانک', border: OutlineInputBorder(), isDense: true))),
            ]),
            const SizedBox(height: 8),
            TextField(controller: l.chqSayad, decoration: const InputDecoration(labelText: 'شناسهٔ صیاد (اختیاری)', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 8),
            dateField(context, 'سررسید چک', l.chqDue, (DateTime d) => setState(() => l.chqDue = d)),
            Text(_dir == 'recv' ? 'چک در «مدیریت چک» به‌عنوان «نزد ما» ثبت می‌شود؛ تا پاس نشود شناسنامه باز است و اگر برگشت بخورد، طرف دوباره بدهکار می‌شود.'
                : 'چک در «مدیریت چک» به‌عنوان «صادرشده» ثبت می‌شود؛ تا پاس نشود شناسنامه باز است.', style: const TextStyle(fontSize: 12)),
          ],
          if (l.k == 'direct') ...<Widget>[
            const SizedBox(height: 8),
            InternalAccountPicker(
              value: l.account,
              ccy: l.ccy,
              label: _dir == 'recv' ? 'به کدام حساب ما واریز شد؟ (اختیاری)' : 'از کدام حساب ما پرداخت شد؟ (اختیاری)',
              onChanged: (String? u, InternalAccount? _) => setState(() => l.account = u),
            ),
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('جزئیات (تاریخ مرحله، شمارهٔ حواله، توضیح)', style: TextStyle(fontSize: 13)),
            children: <Widget>[
              dateField(context, 'تاریخ این مرحله (اگر با تاریخ شناسنامه فرق دارد)', l.date ?? _date, (DateTime d) => setState(() => l.date = d)),
              TextField(controller: l.ref, decoration: const InputDecoration(labelText: 'شمارهٔ حواله/پیگیری', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: l.note, decoration: const InputDecoration(labelText: 'توضیح', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 8),
            ],
          ),
          if (res != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                Text('ارزش این مرحله: ${stlRial(res.v)}${cross && l.ccy != 'IRR' && _ccy != 'IRR' && (parseNum(l.settle.text) ?? 0) > 0 ? ' • نرخ ضمنی: هر ۱ $_ccy = ${faNum((parseNum(l.amount.text) ?? 0) / (parseNum(l.settle.text) ?? 1), dec: 4)} ${l.ccy}' : ''}',
                    style: const TextStyle(fontSize: 12)),
                if (res.carry != 0) Text('ارزش دفتری فاکتورهای تسویه‌شده: ${stlRial(res.carry)}', style: const TextStyle(fontSize: 12)),
                if (res.adv4 != 0) Text('علی‌الحساب از این مرحله: ${stlAmount(_ccy, res.adv4 / kQ)}', style: const TextStyle(fontSize: 12)),
                Text(stlGain(res.realized + (xres?.realized ?? 0)), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: stlGainColor(res.realized + (xres?.realized ?? 0)))),
              ]),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool ready = _base != null;
    _autoShares(); // v93
    StlState? preview;
    Trail? trail;
    if (ready && _partyKey.isNotEmpty && _amt4 > 0) {
      try {
        final Settlement c = _candidate();
        preview = StlState.build(_base!.docs, <Settlement>[..._base!.stls, c], _base!.xmoves);
        trail = stlTrail(preview, c.uid);
      } catch (_) {/* ورودی ناقص */}
    }
    final String? problem = ready ? _problem() : null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing != null ? 'ویرایش شناسنامهٔ ${widget.existing!.refNo}' : (_dir == 'recv' ? 'وصول (شناسنامهٔ تازه)' : 'پرداخت (شناسنامهٔ تازه)'))),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : stlWide(ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: <Widget>[
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'recv', label: Text('وصول از طرف‌حساب'), icon: Icon(Icons.south_west)),
                  ButtonSegment<String>(value: 'pay', label: Text('پرداخت به طرف‌حساب'), icon: Icon(Icons.north_east)),
                ],
                selected: <String>{_dir},
                onSelectionChanged: widget.existing != null ? null : (Set<String> s) => setState(() => _dir = s.first),
              ),
              const SizedBox(height: 10),
              _nameField(_party, 'طرف‌حساب', _names),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                Expanded(
                    child: _ccyDrop('ارز بدهی', _ccy, (String v) {
                  setState(() {
                    for (final _LegCtl l in _legs) {
                      if (l.ccy == _ccy) l.ccy = v; // مرحله‌های هم‌ارز با ارز بدهی همراهش عوض می‌شوند
                    }
                    _ccy = v;
                  });
                  for (final _LegCtl l in _legs) {
                    _prefillRate(l);
                  }
                })),
                const SizedBox(width: 8),
                Expanded(child: _numBox(_amount, 'مبلغ', suffix: _ccy == 'IRR' ? 'ریال' : _ccy)),
              ]),
              const SizedBox(height: 10),
              dateField(context, 'تاریخ', _date, (DateTime d) => setState(() => _date = d)),
              _allocSection(),
              sectionTitle(context, _dir == 'recv' ? 'پول از چه مسیری آمد؟' : 'پول از چه مسیری رفت؟'),
              for (int i = 0; i < _legs.length; i++)
                _legCard(i, _legs[i], trail?.res.legs[_legs[i].lid], preview?.legRes(trail?.s.uid ?? '', _legs[i].lid)),
              OutlinedButton.icon(
                onPressed: () {
                  final int rem = _amt4 - _legsSum;
                  final _LegCtl l = _LegCtl(lid: EntityStore.newUid(), k: 'xch', ccy: _ccy, settle: rem > 0 ? stlFmt4(rem) : '');
                  setState(() => _legs.add(l));
                  _prefillRate(l);
                },
                icon: const Icon(Icons.add),
                label: const Text('افزودن مرحله (بخشی از طرف، بقیه از صراف…)'),
              ),
              const SizedBox(height: 8),
              textField(_note, 'توضیح'),
              if (trail != null)
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                      const Text('خلاصه', style: TextStyle(fontWeight: FontWeight.bold)),
                      infoRow('جمع سهم مراحل', '${stlAmount(_ccy, _legsSum / kQ)} از ${stlAmount(_ccy, _amt4 / kQ)}',
                          valueColor: _legsSum == _amt4 ? null : Colors.red.shade800),
                      infoRow('ارزش دفتری تسویه‌شده', stlRial(trail.res.carry)),
                      if (trail.res.adv4 > 0) infoRow('علی‌الحساب', stlAmount(_ccy, trail.res.adv4 / kQ)),
                      infoRow('سود/زیان تفاوت نرخ همین ثبت', stlGain(trail.stages.fold(0, (int s, TrailStage t) => s + t.realized)),
                          valueColor: stlGainColor(trail.stages.fold(0, (int s, TrailStage t) => s + t.realized))),
                    ]),
                  ),
                ),
              if (problem != null) Padding(padding: const EdgeInsets.all(6), child: Text(problem, style: TextStyle(color: Colors.red.shade800))),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _saving || problem != null ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(_saving ? 'در حال ذخیره…' : 'ثبت'),
              ),
            ])),
    );
  }
}

// ============================================================================
// شناسنامه (خط زمانی مراحل)
// ============================================================================
class SettlementTrailScreen extends StatelessWidget {
  final String uid;
  const SettlementTrailScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppDb.I.version,
      builder: (BuildContext _, int __, Widget? ___) => FutureBuilder<(StlState, Map<String, String>)>(
        future: () async {
          final StlState st = await loadStlState();
          final Map<String, String> acc = <String, String>{for (final InternalAccount a in await loadInternalAccounts()) a.uid: a.label};
          return (st, acc);
        }(),
        builder: (BuildContext context, AsyncSnapshot<(StlState, Map<String, String>)> snap) {
          if (snap.hasError) return Scaffold(appBar: AppBar(), body: Center(child: Text('خطا: ${snap.error}')));
          if (!snap.hasData) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
          final (StlState st, Map<String, String> accounts) = snap.data!;
          final Trail? t = stlTrail(st, uid);
          if (t == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('این شناسنامه پیدا نشد (شاید حذف شده باشد).')));
          return Scaffold(
            appBar: AppBar(
              title: Text('شناسنامهٔ ${t.s.refNo.isEmpty ? '(تازه)' : t.s.refNo}'),
              actions: <Widget>[
                IconButton(tooltip: 'چاپ کل شناسنامه', icon: const Icon(Icons.print_outlined), onPressed: () => printTrail(context, t, accounts)),
                PopupMenuButton<String>(
                  onSelected: (String v) async {
                    if (v == 'edit') {
                      await openSettlementForm(context, existing: t.s);
                    } else if (v == 'delete') {
                      final bool ok = await confirm(context, 'این شناسنامه حذف شود؟ ماندهٔ طرف‌حساب و صرافان و سود/زیان دوباره حساب می‌شود.');
                      if (ok && context.mounted) {
                        final bool done = await saveConfirmed(context, () => deleteSettlement(t.s.uid), successMsg: 'حذف شد');
                        if (done && context.mounted) Navigator.pop(context);
                      }
                    }
                  },
                  itemBuilder: (_) => const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(value: 'edit', child: Text('ویرایش')),
                    PopupMenuItem<String>(value: 'delete', child: Text('حذف')),
                  ],
                ),
              ],
            ),
            body: stlWide(ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: <Widget>[
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                    Row(children: <Widget>[
                      Expanded(
                        child: Text('${t.s.isRecv ? 'وصول از' : 'پرداخت به'} «${t.s.party}»', style: Theme.of(context).textTheme.titleMedium),
                      ),
                      Chip(label: Text(t.complete ? 'کامل‌شده' : 'باز'), backgroundColor: t.complete ? Colors.green.shade50 : Colors.orange.shade50),
                    ]),
                    infoRow('مبلغ', stlAmount(t.s.ccy, t.s.amt4 / kQ)),
                    infoRow('تاریخ', jalaliDate(t.s.date)),
                    infoRow('ارزش دفتری تسویه‌شده', stlRial(t.res.carry)),
                    if (t.res.adv4 > 0) infoRow('علی‌الحساب', '${stlAmount(t.s.ccy, t.res.adv4 / kQ)}${t.advOpen4 > 0 ? ' (هنوز باز: ${stlAmount(t.s.ccy, t.advOpen4 / kQ)})' : ''}'),
                    infoRow('سود/زیان تفاوت نرخ (همهٔ مراحل)', stlGain(t.realized), valueColor: stlGainColor(t.realized)),
                    if ((t.s.note ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(t.s.note!)),
                  ]),
                ),
              ),
              if (t.alloc.isNotEmpty) ...<Widget>[
                sectionTitle(context, 'روی این فاکتورها نشست'),
                Card(
                  child: Column(children: <Widget>[
                    for (final TrailAlloc a in t.alloc)
                      ListTile(
                        dense: true,
                        title: Text('${a.doc.label} • ${jalaliDate(a.doc.date)}'),
                        subtitle: Text('مبلغ فاکتور ${stlAmount(a.doc.ccy, a.doc.total4 / kQ)} • ماندهٔ فعلی ${stlAmount(a.doc.ccy, a.openAfter4 / kQ)}'),
                        trailing: Text(stlAmount(a.doc.ccy, a.q4 / kQ), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ]),
                ),
              ],
              sectionTitle(context, 'مراحل'),
              for (final TrailStage s in t.stages) _StageCard(trail: t, stage: s, accounts: accounts),
              if (t.advUse.isNotEmpty) ...<Widget>[
                sectionTitle(context, 'مصرف علی‌الحساب'),
                Card(
                  child: Column(children: <Widget>[
                    for (final StlAdvUse u in t.advUse)
                      ListTile(
                        dense: true,
                        title: Text('${st.docLabel(u.k)} • ${jalaliDate(u.date)}'),
                        subtitle: Text(stlGain(u.realized), style: TextStyle(color: stlGainColor(u.realized))),
                        trailing: Text(stlAmount(t.s.ccy, u.q4 / kQ)),
                      ),
                  ]),
                ),
              ],
            ])),
          );
        },
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  final Trail trail;
  final TrailStage stage;
  final Map<String, String> accounts;
  const _StageCard({required this.trail, required this.stage, required this.accounts});

  @override
  Widget build(BuildContext context) {
    final TrailStage s = stage;
    final StlLeg l = s.leg;
    final Color line = Theme.of(context).colorScheme.outlineVariant;
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        ListTile(
          leading: CircleAvatar(child: Text(faNum(int.parse(s.no), dec: 0))),
          title: Text('${s.from} ← ${s.to}'),
          subtitle: Text('${stlKindFa(l.k)} • ${jalaliDate(s.date)}\n${stlAmount(l.ccy, l.amount)}'
              '${l.ccy == trail.s.ccy ? '' : ' بابت ${stlAmount(trail.s.ccy, s.res.settle4 / kQ)}'} • ${stlGain(s.realized)}'),
          isThreeLine: true,
          trailing: l.isXch
              ? Chip(label: Text(s.open ? 'نزد صراف' : 'تسویه'), visualDensity: VisualDensity.compact, backgroundColor: s.open ? Colors.orange.shade50 : Colors.green.shade50)
              : l.isCheque
                  ? Chip(label: Text(kChequeStatusFa[s.chequeStatus] ?? 'چک: وضعیت در «مدیریت چک»'), visualDensity: VisualDensity.compact,
                      backgroundColor: s.chequeStatus == 'cleared' ? Colors.green.shade50 : (s.chequeStatus == 'bounced' ? Colors.red.shade50 : Colors.orange.shade50))
                  : const Icon(Icons.chevron_left),
          onTap: () => showStageSheet(context, trail, s, null, accounts),
        ),
        for (final TrailNext n in s.next)
          Container(
            margin: const EdgeInsetsDirectional.only(start: 34),
            decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: line, width: 2))),
            child: ListTile(
              dense: true,
              leading: Text(toFaDigits(n.no)),
              title: Text(n.kind == 'xch_paid_us'
                  ? '${n.exchanger} ← ما'
                  : n.kind == 'we_paid_xch'
                      ? 'ما ← ${n.exchanger}'
                      : '${n.exchanger} (${n.kind == 'leg_in' ? 'واریز طرف دیگر' : 'پرداخت به طرف دیگر'})'),
              subtitle: Text('${jalaliDate(n.date)} • ${n.payAmount == null ? stlAmount(n.closedCcy, n.closed) : stlAmount(n.payCcy ?? 'IRR', n.payAmount!)}'
                  '${n.payCcy != null && n.payCcy != n.closedCcy ? ' بابت ${stlAmount(n.closedCcy, n.closed)}' : ''} • ${stlGain(n.realized)}'),
              onTap: () => showStageSheet(context, trail, s, n, accounts),
            ),
          ),
        if (l.isXch && s.open)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 50, bottom: 8),
            child: Text('هنوز نزد صراف: ${stlAmount(l.ccy, s.openAtExchanger)}', style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
          ),
      ]),
    );
  }
}

/// برگهٔ جزئیات یک مرحله (یا مرحلهٔ بعدی آن) + چاپ
Future<void> showStageSheet(BuildContext context, Trail t, TrailStage s, TrailNext? n, Map<String, String> accounts) {
  final List<(String, String)> rows = stageRows(t, s, n, accounts);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: <Widget>[
        Text(n == null ? 'مرحلهٔ ${toFaDigits(s.no)}' : 'مرحلهٔ ${toFaDigits(n.no)}', style: Theme.of(ctx).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final (String k, String v) in rows) infoRow(k, v),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => printStage(ctx, t, s, n, accounts),
          icon: const Icon(Icons.print_outlined),
          label: const Text('چاپ این مرحله'),
        ),
      ]),
    ),
  );
}

/// ردیف‌های جزئیات یک مرحله (مشترک بین برگهٔ جزئیات و چاپ)
List<(String, String)> stageRows(Trail t, TrailStage s, TrailNext? n, Map<String, String> accounts) {
  final StlLeg l = s.leg;
  if (n != null) {
    final String what = switch (n.kind) {
      'xch_paid_us' => 'صراف «${n.exchanger}» به ما پرداخت کرد',
      'we_paid_xch' => 'ما به صراف «${n.exchanger}» پرداخت کردیم',
      _ => 'با مرحلهٔ شناسنامهٔ دیگری نزد «${n.exchanger}» بسته شد',
    };
    return <(String, String)>[
      ('شناسنامه', '${t.s.refNo.isEmpty ? '(تازه)' : t.s.refNo} — ${t.s.isRecv ? 'وصول از' : 'پرداخت به'} ${t.s.party}'),
      ('شرح', what),
      ('تاریخ', jalaliDate(n.date)),
      ('بسته‌شده از واریز مرحلهٔ ${toFaDigits(s.no)}', stlAmount(n.closedCcy, n.closed)),
      if (n.payAmount != null) ('پول جابه‌جاشده', stlAmount(n.payCcy ?? 'IRR', n.payAmount!)),
      if (n.payRate != null && (n.payCcy ?? 'IRR') != 'IRR') ('نرخ ریالی ${n.payCcy}', faNum(n.payRate!, dec: 0)),
      ('ارزش ریالی', stlRial(n.value)),
      ('ارزش دفتری واریز', stlRial(n.carry)),
      ('سود/زیان تفاوت نرخ', stlGain(n.realized)),
      if ((n.cashBox ?? n.bankAccount) != null) ('حساب ما', accounts[n.cashBox ?? n.bankAccount] ?? '—'),
      if ((n.refNo ?? '').isNotEmpty) ('شمارهٔ شناسنامهٔ دیگر', n.refNo!),
      if ((n.note ?? '').isNotEmpty) ('توضیح', n.note!),
    ];
  }
  return <(String, String)>[
    ('شناسنامه', '${t.s.refNo.isEmpty ? '(تازه)' : t.s.refNo} — ${t.s.isRecv ? 'وصول از' : 'پرداخت به'} ${t.s.party}'),
    ('مسیر', '${s.from} ← ${s.to} (${stlKindFa(l.k)})'),
    ('تاریخ', jalaliDate(s.date)),
    ('مبلغ', stlAmount(l.ccy, l.amount)),
    ('سهم از بدهی', stlAmount(t.s.ccy, s.res.settle4 / kQ)),
    if (l.ccy != 'IRR') ('نرخ ریالی ${l.ccy}', faNum(l.rate, dec: 0)),
    ('ارزش ریالی', stlRial(s.res.v)),
    if (s.res.carry != 0) ('ارزش دفتری فاکتورهای تسویه‌شده', stlRial(s.res.carry)),
    for (final StlPiece p in s.res.pieces)
      (p.k == 'adv' ? 'علی‌الحساب' : 'روی ${t.alloc.where((TrailAlloc a) => a.doc.key == p.k).map((TrailAlloc a) => a.doc.label).firstOrNull ?? p.k}', stlAmount(t.s.ccy, p.q4 / kQ)),
    ('سود/زیان تفاوت نرخ', stlGain(s.realized)),
    if (l.isXch) ('وضعیت نزد صراف', s.open ? 'باز: ${stlAmount(l.ccy, s.openAtExchanger)}' : 'تسویه شد'),
    if (l.isCheque) ('چک', '${l.cheque?['no'] ?? ''}${(l.cheque?['bank'] ?? '').isEmpty ? '' : ' — ${l.cheque!['bank']}'}'),
    if (l.isCheque) ('سررسید چک', jalaliDate(l.cheque?['due'] ?? '')),
    if (l.isCheque && (l.cheque?['sayad'] ?? '').isNotEmpty) ('شناسهٔ صیاد', l.cheque!['sayad']!),
    if (l.isCheque) ('وضعیت چک', kChequeStatusFa[s.chequeStatus] ?? 'در «مدیریت چک» ببینید'),
    if (l.accountUid != null) ('حساب ما', accounts[l.accountUid] ?? '—'),
    if ((l.ref ?? '').isNotEmpty) ('شمارهٔ حواله/پیگیری', l.ref!),
    if ((l.note ?? '').isNotEmpty) ('توضیح', l.note!),
  ];
}
