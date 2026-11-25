import 'package:flutter/material.dart';
import 'fmt.dart' show Fmt;

import 'db.dart';
import 'doc_drafts.dart' show DraftsScreen;
import 'list_filter.dart';
import 'live_query.dart';
import 'license_service.dart';
import 'purchase_form.dart';
import 'code_kind.dart' show groupColor; // v86: رنگ گروه کوت
import 'utils.dart';

class PurchasesScreen extends StatefulWidget {
  /// اگر از اسکن آمده باشیم، جزئیات همین کد یک‌بار باز می‌شود
  const PurchasesScreen({super.key, this.openCode});

  final String? openCode;
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  String _query = '';
  bool _openedCode = false;
  // پیش‌فرض: سال پسته‌ای جاری (۱ مهر تا ۳۱ شهریور سال بعد)، جدیدترین اول
  DocListFilter _filter = DocListFilter.defaults();
  // v86: فیلتر فروخته‌شده در هر دو تب (همه / بدون فروخته‌شده / فقط فروخته‌شده) + «کوت‌های هم‌گروه زیر هم» در تب کوت و فراوری
  String _soldMode = 'hide';
  bool _groupMix = false;
  // v87: نام‌های ساده: موجود / فروخته‌شده / همه

  /// v86: خریدها + کیلوی فروش/کوت/برگشت + گروه کوت ⇒ «کوت‌ریزی یا فراوری‌شده» = بخشی از وزن به کوت رفته یا (خالص − مانده − فروش − کوت − برگشت) به فراوری.
  Future<List<Map<String, dynamic>>> _load() async {
    final List<Map<String, dynamic>> rows = await AppDb.I.purchases();
    final d = await AppDb.I.db;
    Future<Map<int, double>> sum(String sql) async {
      try {
        return <int, double>{
          for (final Map<String, Object?> r in await d.rawQuery(sql))
            if (r['id'] is num) (r['id'] as num).toInt(): ((r['kg'] as num?) ?? 0).toDouble(),
        };
      } catch (_) {
        return <int, double>{};
      }
    }

    final Map<int, double> sold = await sum('SELECT purchase_id AS id, SUM(weight) AS kg FROM sale_items GROUP BY purchase_id');
    final Map<int, double> kout = await sum('SELECT source_purchase_id AS id, SUM(weight) AS kg FROM mix_sources GROUP BY source_purchase_id');
    final Map<int, double> ret = await sum('SELECT lot_id AS id, SUM(kg) AS kg FROM purchase_return_items GROUP BY lot_id');
    final Map<int, int?> groups = await AppDb.I.mixGroupKeyMap();
    return <Map<String, dynamic>>[
      for (final Map<String, dynamic> r in rows)
        () {
          final int id = (r['id'] as num).toInt();
          final double net = ((r['net_weight'] as num?) ?? 0).toDouble(), rem = ((r['remaining'] as num?) ?? 0).toDouble();
          final bool held = ((r['stock_hold'] as num?) ?? 0).toInt() == 1; // v89: بی‌فی ⇒ هنوز در موجودی نیست (مصرفی هم ندارد)
          final double k = kout[id] ?? 0, proc = held ? 0.0 : net - rem - (sold[id] ?? 0) - k - (ret[id] ?? 0);
          return <String, dynamic>{...r, 'sold_kg': sold[id] ?? 0.0, 'kout_kg': k, 'proc_kg': proc > 1e-3 ? proc : 0.0, 'used': k > 1e-6 || proc > 1e-3, 'mix_group': k > 1e-6 ? groups[id] : null};
        }(),
    ];
  }

  bool _soldOk(Map<String, dynamic> p) => _soldMode == 'all' || (_soldMode == 'only' ? _isSold(p) : !_isSold(p));

  /// v86: «کوت‌های هم‌گروه زیر هم»: ترتیب فیلتر حفظ می‌شود؛ هر گروه کوت در جای اولین عضوش کنار هم می‌آید.
  static List<Map<String, dynamic>> _grouped(List<Map<String, dynamic>> list) {
    final Map<int, List<Map<String, dynamic>>> byG = <int, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> p in list) {
      final int? g = (p['mix_group'] as num?)?.toInt();
      if (g != null) byG.putIfAbsent(g, () => <Map<String, dynamic>>[]).add(p);
    }
    final Set<int> done = <int>{};
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> p in list) {
      final int? g = (p['mix_group'] as num?)?.toInt();
      if (g == null) {
        out.add(p);
      } else if (done.add(g)) {
        out.addAll(byG[g]!);
      }
    }
    return out;
  }

  /// v91 p3: جزئیات = همان فرم ثبت خرید به حالت قفل (فقط‌خواندنی)؛ «ویرایش» همه را باز می‌کند و همهٔ کارهای سند
  /// (پرداخت، کارتکس، باسکول، بارنامه، فاکتور، دلال، برگشت، سند اصلاحی، حذف) پایین همان فرم است.
  void _details(BuildContext context, Map<String, dynamic> p) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PurchaseForm(existing: p, locked: true)));
  }

  /// یکسان‌سازی «ي/ك» عربی و «ی/ک» فارسی برای جستجو
  static String _norm(String s) => toEnDigits(s.replaceAll('ي', 'ی').replaceAll('ك', 'ک')).trim().toLowerCase();

  /// مثل وب: «فروخته‌شده» فقط وقتی است که وزنی از خودش نمانده باشد و مقداری از آن هم
  /// داخل مخلوطِ فروش‌نرفته نباشد.
  // v87: «فروخته‌شده» فقط وقتی واقعاً فروش ثبت شده (sale_items) و چیزی از آن نمانده؛ لاتِ تمام‌شده در فراوری/کوت «فروخته‌شده» نیست.
  static double _soldKg(Map<String, dynamic> p) => ((p['sold_kg'] as num?) ?? 0).toDouble();
  static bool _isSold(Map<String, dynamic> p) => _soldKg(p) > 1e-6 && !AppDb.isAvailable(p);

  /// وضعیت کارت: مانده / فروخته‌شده / تمام‌شده در فراوری یا کوت.
  static String _statusText(Map<String, dynamic> p) {
    if (((p['stock_hold'] as num?) ?? 0).toInt() == 1) return '⏳ منتظر فی — هنوز وارد موجودی نشده'; // v89
    if (AppDb.isAvailable(p)) return 'مانده ${faNum(p['remaining'] as num)} کیلو (خالص)';
    if (_isSold(p)) return 'فروخته‌شده';
    final double kout = ((p['kout_kg'] as num?) ?? 0).toDouble(), proc = ((p['proc_kg'] as num?) ?? 0).toDouble();
    if (kout > 1e-6 && proc > 1e-3) return 'تمام‌شده (فراوری و کوت‌ریزی)';
    if (kout > 1e-6) return 'تمام‌شده (کوت‌ریزی)';
    if (proc > 1e-3) return 'تمام‌شده (فراوری)';
    return 'تمام‌شده';
  }

  static String _inMixLine(Map<String, dynamic> p) {
    final codes = ((p['in_mix_codes'] as List?) ?? const []).cast<String>();
    if (codes.isEmpty) return '';
    final rem = (p['remaining'] as num).toDouble();
    return '\n🔀 ${rem <= 1e-6 ? 'کل موجودی آن' : 'بخشی از آن'} داخل مخلوط/جداسازی ${codes.join('، ')} است (هنوز کامل فروش نرفته)';
  }

  Widget _card(BuildContext context, Map<String, dynamic> p) {
    final hasPhoto = ((p['has_photo'] as num?) ?? 0) == 1;
    final int? g = (p['mix_group'] as num?)?.toInt(); // v86: خریدهایی که با هم کوت شده‌اند هم‌رنگ‌اند
    final double koutKg = ((p['kout_kg'] as num?) ?? 0).toDouble(), procKg = ((p['proc_kg'] as num?) ?? 0).toDouble();
    return Card(
      color: g == null ? null : groupColor(g).withAlpha(28),
      shape: g == null ? null : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: groupColor(g).withAlpha(170), width: 1.5)),
      child: ListTile(
        onTap: () => _details(context, p),
        leading: CircleAvatar(child: Icon(hasPhoto ? Icons.photo_camera_outlined : Icons.grass)),
        title: Text('${p['category_name']} - ${p['type_name']}'),
        subtitle: Text(
            'کد ${p['code'] ?? '-'}  •  ${jalaliDate(p['date'] as String)}  •  ${faNum(p['net_weight'] as num)} کیلو (خالص)\n'
            '${_statusText(p)}  •  فی ${Fmt.money(p['price'] as num)}'
            '${LicenseService.I.isFx.value && p['price_usd'] != null ? ' (${faUsd(p['price_usd'] as num, dec: 3)})' : ''}'
            '${_inMixLine(p)}'
            '${koutKg > 1e-6 || procKg > 1e-3 || _soldKg(p) > 1e-6 ? '\n${<String>[if (_soldKg(p) > 1e-6) 'فروش ${faNum(_soldKg(p))} کیلو', if (koutKg > 1e-6) 'کوت ${faNum(koutKg)} کیلو${g == null ? '' : ' (گروه کوت #${faNum(g, dec: 0)})'}', if (procKg > 1e-3) 'فراوری ${faNum(procKg)} کیلو'].join('  •  ')}' : ''}'),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_left), // v91 p3: کارها در پایین فرم جزئیات
      ),
    );
  }

  Widget _tabList(BuildContext context, List<Map<String, dynamic>> list, String emptyText, {bool narrowed = false}) {
    if (list.isEmpty) return Center(child: Text(_query.trim().isEmpty && !narrowed ? emptyText : 'نتیجه‌ای پیدا نشد'));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
      itemCount: list.length,
      itemBuilder: (context, i) => _card(context, list[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('خرید'),
          actions: <Widget>[
            FutureBuilder<bool>(
              future: Future<bool>.value(true), // v87: پیش‌نویس همیشه در دسترس (قبلاً FormSettingsLocal 'draft')
              builder: (BuildContext c, AsyncSnapshot<bool> s) => s.data == true
                  ? IconButton(
                      tooltip: 'پیش‌نویس‌ها',
                      icon: const Icon(Icons.edit_note),
                      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const DraftsScreen(docType: 'purchase'))),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'خریدها'),
            Tab(text: 'کوت و فراوری'), // v86: خریدهای کوت‌ریزی یا فراوری‌شده
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseForm())),
          icon: const Icon(Icons.add),
          label: const Text('خرید جدید'),
        ),
        body: LiveQuery<List<Map<String, dynamic>>>(
          tab: 1,
          load: _load, // v86
          builder: (context, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              final all = s.data!;
              // اسکن موفق: جزئیات همان پسته یک‌بار باز شود
              if (widget.openCode != null && !_openedCode) {
                _openedCode = true;
                final hit = all.where((p) => p['code'] == widget.openCode).toList();
                if (hit.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _details(context, hit.first);
                  });
                }
              }
              final q = _norm(_query);
              final byText = q.isEmpty
                  ? all
                  : all
                      .where((p) => _norm('${p['code']} ${p['category_name']} ${p['type_name']}').contains(q))
                      .toList();
              final filtered = _filter.apply(byText); // بازهٔ تاریخ + ترتیب
              final narrowed = !_filter.isAll && all.isNotEmpty;
              final plain = filtered.where((p) => p['used'] != true && _soldOk(p)).toList();
              final used0 = filtered.where((p) => p['used'] == true && _soldOk(p)).toList();
              final used = _groupMix ? _grouped(used0) : used0;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'جستجو با کد، دسته یا نوع',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: DocListFilterBar(
                    value: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                    shown: filtered.length,
                    total: all.length,
                    // v87: وضعیت فروش و ترتیب کوت‌ها داخل «فیلتر و ترتیب» (نه بالای صفحه)
                    extras: [
                      DocFilterExtra(key: 'sold', title: 'نمایش', options: const {'hide': 'فروش‌نرفته', 'only': 'فروخته‌شده', 'all': 'همه'}, value: _soldMode),
                      DocFilterExtra(key: 'group', title: 'ترتیب کوت‌ها (تب کوت و فراوری)', options: const {'date': 'طبق تاریخ', 'together': 'هم‌گروه‌ها کنار هم'}, value: _groupMix ? 'together' : 'date'),
                    ],
                    onExtras: (m) => setState(() {
                      _soldMode = m['sold'] ?? _soldMode;
                      _groupMix = m['group'] == 'together';
                    }),
                  ),
                ),
                Expanded(
                  child: TabBarView(children: [
                    _tabList(context, plain, _soldMode == 'only' ? 'خرید فروخته‌شده‌ای نیست' : 'خریدی نیست', narrowed: narrowed || _soldMode != 'all'),
                    _tabList(context, used, 'هنوز خریدی کوت‌ریزی یا فراوری نشده', narrowed: narrowed || _soldMode != 'all'),
                  ]),
                ),
              ]);
            },
        ),
      ),
    );
  }
}

