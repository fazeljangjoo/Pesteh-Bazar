// v90 — بازاریابی بین‌المللی: لایهٔ داده روی EntityStore (آفلاین، صف ارسال، همگام‌سازی لحظه‌ای) + گزارش سرور.
import 'entity_store.dart';
import 'marketing_calc.dart';
import 'perms.dart';
import 'utils.dart' show gregorianToJalali, jalaliToGregorian, daysInJalaliMonth;
import 'warehouse_ui.dart' show StockApi;

class MkStore {
  MkStore._();
  static final MkStore I = MkStore._();

  static const String leadsE = 'mk_leads';
  static const String actsE = 'mk_activities';
  static const String salesE = 'mk_sales';
  static const String targetsE = 'mk_targets';
  static const String settingsE = 'mk_settings';

  // ---------- دسترسی ----------
  int get myId => ((StaffPerms.I.current.value?['id'] as num?) ?? 0).toInt();
  String get myName => StaffPerms.I.isStaff ? '${StaffPerms.I.current.value?['name'] ?? ''}' : 'مالک';
  bool get isManager => StaffPerms.I.can('marketing.manage'); // مالک ⇒ همیشه true
  bool get canEntry => StaffPerms.I.can('marketing.entry') || isManager;
  bool get canTeamReports => isManager || StaffPerms.I.can('marketing.reports');
  bool get hasAny => canEntry || canTeamReports;

  // ---------- خواندن ----------
  /// لیدهایی که این کاربر باید ببیند (مدیر/مالک ⇒ همه؛ بازاریاب ⇒ فقط مسئولیت خودش؛ لید سپرده‌شده به دیگری پنهان).
  Future<List<Map<String, dynamic>>> leads({String q = ''}) async {
    final List<Map<String, dynamic>> all = await EntityStore.I.list(leadsE, q: q);
    if (isManager) return all;
    return all.where((Map<String, dynamic> l) => _int(l['owner_staff_id']) == myId || (l['owner_staff_id'] == null && _int(l['creator_staff_id']) == myId)).toList();
  }

  Future<Map<String, dynamic>?> lead(String uid) => EntityStore.I.get(leadsE, uid);

  /// مشتری‌هایی که این کاربر می‌بیند (برای پنهان‌کردن تاریخچه/فروش مشتری سپرده‌شده به دیگری)
  Future<Set<String>> _visibleLeadUids() async => <String>{for (final Map<String, dynamic> l in await leads()) '${l['uid']}'};

  Future<List<Map<String, dynamic>>> activities(String leadUid) async {
    if (!isManager && !(await _visibleLeadUids()).contains(leadUid)) return <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> l = (await EntityStore.I.list(actsE)).where((Map<String, dynamic> a) => a['lead_uid'] == leadUid).toList();
    l.sort((Map<String, dynamic> a, Map<String, dynamic> b) => '${b['at'] ?? ''}'.compareTo('${a['at'] ?? ''}'));
    return l;
  }

  Future<List<Map<String, dynamic>>> sales({String? leadUid, String? status}) async {
    final Set<String>? vis = isManager ? null : await _visibleLeadUids();
    final List<Map<String, dynamic>> l = (await EntityStore.I.list(salesE))
        .where((Map<String, dynamic> s) =>
            (leadUid == null || s['lead_uid'] == leadUid) && (status == null || s['status'] == status) && (vis == null || vis.contains('${s['lead_uid']}')))
        .toList();
    l.sort((Map<String, dynamic> a, Map<String, dynamic> b) => '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}'));
    return l;
  }

  Future<List<Map<String, dynamic>>> targets() => EntityStore.I.list(targetsE);

  Future<Map<String, dynamic>> settings() async {
    final List<Map<String, dynamic>> l = await EntityStore.I.list(settingsE);
    return l.isEmpty ? <String, dynamic>{} : l.first;
  }

  Future<MkWeights> weights() async => MkWeights.fromSettings(await settings());

  // ---------- نوشتن ----------
  String _now() => DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ');

  /// ذخیرهٔ کارت مشتری. تغییر مرحله ⇒ یک خط «تغییر مرحله» در تاریخچه (پایهٔ قیف و مدت ماندن در هر مرحله).
  Future<String> saveLead(Map<String, dynamic> data, {String? uid}) async {
    final Map<String, dynamic>? old = uid == null ? null : await lead(uid);
    final String oldStage = '${old?['stage'] ?? ''}';
    final String newStage = '${data['stage'] ?? (old?['stage'] ?? 'lead')}';
    final Map<String, dynamic> d = Map<String, dynamic>.from(data);
    if (uid == null) {
      d['creator_staff_id'] = myId;
      d.putIfAbsent('owner_staff_id', () => myId);
      d.putIfAbsent('owner_name', () => myName);
      d['stage_at'] = _now();
    } else if (oldStage != newStage) {
      d['stage_at'] = _now();
    }
    if (newStage != 'lost') d['lost_reason'] = null;
    final String id = await EntityStore.I.save(leadsE, d, uid: uid);
    if (uid != null && oldStage.isNotEmpty && oldStage != newStage) {
      await EntityStore.I.save(actsE, <String, dynamic>{
        'lead_uid': id, 'staff_id': myId, 'staff_name': myName, 'at': _now(), 'kind': 'stage', 'from_stage': oldStage, 'to_stage': newStage,
      });
    } else if (uid == null && newStage != 'lead') {
      await EntityStore.I.save(actsE, <String, dynamic>{
        'lead_uid': id, 'staff_id': myId, 'staff_name': myName, 'at': _now(), 'kind': 'stage', 'from_stage': 'lead', 'to_stage': newStage,
      });
    }
    return id;
  }

  Future<void> changeStage(String leadUid, String stage, {String? lostReason}) async {
    await saveLead(<String, dynamic>{'stage': stage, if (lostReason != null) 'lost_reason': lostReason}, uid: leadUid);
  }

  /// پیگیری تازه: خط تاریخچه + موعد پیگیری بعدی روی کارت. اولین تماسِ لید جدید ⇒ مرحله «ارتباط گرفته».
  Future<void> addActivity(String leadUid, {required String kind, String? result, DateTime? at, DateTime? next, bool clearNext = false}) async {
    await EntityStore.I.save(actsE, <String, dynamic>{
      'lead_uid': leadUid, 'staff_id': myId, 'staff_name': myName, 'kind': kind, 'result': result,
      'at': (at ?? DateTime.now()).toIso8601String().substring(0, 19).replaceFirst('T', ' '),
    });
    final Map<String, dynamic>? l = await lead(leadUid);
    final Map<String, dynamic> upd = <String, dynamic>{};
    if (next != null) upd['next_followup_at'] = next.toIso8601String().substring(0, 19).replaceFirst('T', ' ');
    if (clearNext && next == null) upd['next_followup_at'] = null;
    if (l != null && '${l['stage']}' == 'lead' && kind != 'note') upd['stage'] = 'contacted';
    if (kind == 'proforma' && l != null && kMkOpenStages.indexOf('${l['stage']}') < kMkOpenStages.indexOf('proforma')) upd['stage'] = 'proforma';
    if (upd.isNotEmpty) await saveLead(upd, uid: leadUid);
  }

  /// فروش تازه/ویرایش. بازاریاب ⇒ همیشه «منتظر تأیید»؛ اولین فروش، مرحلهٔ کارت را «فروش» می‌کند.
  Future<String> saveSale(String leadUid, Map<String, dynamic> data, {String? uid}) async {
    final Map<String, dynamic> d = <String, dynamic>{...data, 'lead_uid': leadUid};
    // v90: فرم یک uid از پیش می‌سازد تا «ذخیره»ی دوباره (پس از خطا) همان فروش را ویرایش کند، نه فروش دوم بسازد
    if (uid == null || await EntityStore.I.get(salesE, uid) == null) {
      d['staff_id'] = myId;
      d['staff_name'] = myName;
    }
    if (!isManager) d['status'] = 'pending';
    if (d['collected'] != true) d['collected_at'] = null;
    final String id = await EntityStore.I.save(salesE, d, uid: uid);
    final Map<String, dynamic>? l = await lead(leadUid);
    if (l != null && '${l['stage']}' != 'won') await changeStage(leadUid, 'won');
    return id;
  }

  /// تأیید یا رد فروش (فقط مدیر؛ سرور هم بررسی می‌کند).
  Future<void> setSaleStatus(String saleUid, String status) async {
    await EntityStore.I.save(salesE, <String, dynamic>{'status': status, 'confirmed_by': status == 'pending' ? null : myName, 'confirmed_at': status == 'pending' ? null : _now()},
        uid: saleUid, patch: true); // فقط وضعیت ⇒ تغییر تازه‌تر بازاریاب (مثلاً تناژ) بازنویسی نمی‌شود
  }

  /// سپردن مشتری به بازاریاب دیگر (فقط مدیر).
  Future<void> assign(String leadUid, int staffId, String staffName) async {
    final Map<String, dynamic>? l = await lead(leadUid);
    await EntityStore.I.save(leadsE, <String, dynamic>{'owner_staff_id': staffId, 'owner_name': staffName, 'prev_owner_staff_id': _int(l?['owner_staff_id'])}, uid: leadUid, patch: true);
  }

  Future<void> saveTarget(int staffId, String month, Map<String, dynamic> values) async {
    final List<Map<String, dynamic>> all = await targets();
    final Map<String, dynamic>? ex = all.cast<Map<String, dynamic>?>().firstWhere((Map<String, dynamic>? t) => _int(t!['staff_id']) == staffId && t['month'] == month, orElse: () => null);
    await EntityStore.I.save(targetsE, <String, dynamic>{'staff_id': staffId, 'month': month, ...values}, uid: ex?['uid'] as String?);
  }

  Future<void> saveSettings(Map<String, dynamic> values) async {
    final Map<String, dynamic> s = await settings();
    await EntityStore.I.save(settingsE, values, uid: s['uid'] as String?);
  }

  // ---------- گزارش ----------
  /// گزارش سرور (from/to میلادی Y-m-d). staffId = -1 ⇒ کل تیم.
  Future<Map<String, dynamic>> report(DateTime from, DateTime to, {int staffId = -1, String? country, String? source}) =>
      StockApi.call('marketing.report', <String, dynamic>{
        'from': ymd(from), 'to': ymd(to),
        if (staffId >= 0) 'staff_id': staffId,
        if ((country ?? '').isNotEmpty) 'country': country,
        if ((source ?? '').isNotEmpty) 'source': source,
      });

  /// شمارش‌های ماه شمسی جاری خودِ کاربر از دادهٔ محلی (برای «امروز من» حتی بدون اینترنت).
  Future<({MkCounts counts, MkScore score, int overdue, int today, int open})> myMonth() async {
    final DateTime now = DateTime.now();
    final List<int> j = gregorianToJalali(now.year, now.month, now.day);
    final String from = ymd(jalaliToGregorian(j[0], j[1], 1));
    final String to = ymd(jalaliToGregorian(j[0], j[1], daysInJalaliMonth(j[0], j[1])));
    bool inR(Object? v) {
      final String d = '${v ?? ''}';
      if (d.length < 10) return false;
      final String x = d.substring(0, 10);
      return x.compareTo(from) >= 0 && x.compareTo(to) <= 0;
    }

    final int me = myId;
    final List<Map<String, dynamic>> ls = await leads();
    final List<Map<String, dynamic>> acts = (await EntityStore.I.list(actsE)).where((Map<String, dynamic> a) => _int(a['staff_id']) == me).toList();
    final List<Map<String, dynamic>> ss = (await EntityStore.I.list(salesE)).where((Map<String, dynamic> s) => _int(s['staff_id']) == me && s['status'] == 'confirmed').toList();
    double fu = 0, neg = 0, pf = 0;
    final Set<String> seen = <String>{};
    for (final Map<String, dynamic> a in acts) {
      if (!inR(a['at'])) continue;
      if (a['kind'] != 'stage') {
        fu++;
      } else if ((a['to_stage'] == 'negotiation' || a['to_stage'] == 'proforma') && seen.add('${a['to_stage']}|${a['lead_uid']}')) {
        if (a['to_stage'] == 'negotiation') {
          neg++;
        } else {
          pf++;
        }
      }
    }
    final double nl = ls.where((Map<String, dynamic> l) => _int(l['creator_staff_id']) == me && inR(l['created_at'])).length.toDouble();
    double sales = 0, tons = 0, col = 0;
    for (final Map<String, dynamic> s in ss) {
      if (inR(s['date'])) {
        sales++;
        tons += ((s['tons'] as num?) ?? 0).toDouble();
      }
      if (s['collected'] == true && inR(s['collected_at'])) col++;
    }
    final MkCounts c = MkCounts(followUps: fu, newLeads: nl, negotiations: neg, proformas: pf, sales: sales, tons: tons, collections: col);
    final String today = ymd(now);
    int overdue = 0, td = 0, open = 0;
    for (final Map<String, dynamic> l in ls) {
      if (!kMkOpenStages.contains(l['stage'])) continue;
      open++;
      final String nf = '${l['next_followup_at'] ?? ''}';
      if (nf.length < 10) continue;
      final String d = nf.substring(0, 10);
      if (d.compareTo(today) < 0) {
        overdue++;
      } else if (d == today) {
        td++;
      }
    }
    return (counts: c, score: mkScore(c, await weights()), overdue: overdue, today: td, open: open);
  }

  static String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static int _int(Object? v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? -1);
}
