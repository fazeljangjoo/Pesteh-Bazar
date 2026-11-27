import 'package:flutter/material.dart';
import 'access_catalog.dart' show FieldGate; // v87: قسمت‌های قفل/پنهان فرم
import 'perms.dart'; // v89
import 'sale_lot_picker.dart' show SaleLotPicker; // v87
import 'fin_block_view.dart'; // S35.T35.6f
import 'package:flutter/services.dart';

import 'db.dart';
import 'fx_doc_field.dart';
import 'doc_drafts.dart' show DocDraftsLocal, DraftRestoreBanner; // v94: + کادر ادامهٔ پیش‌نویس
import 'form_settings.dart' show FormSettingsLocal;
import 'grade_lines_ui.dart';
import 'fx_local.dart';
import 'license_service.dart';
import 'party_field.dart';
import 'tax_choice.dart';
import 'price_table_ui.dart' show PriceSuggestionHint;
import 'buy_mode_ui.dart' show BuyMode; // v95
import 'purchase_pct_ui.dart' show PurchasePctCtl, PurchasePctSection; // v95: درصدها و قیمت جدای هر درصد مثل فرم خرید
import 'fmt.dart' show Fmt, MoneyField;
import 'utils.dart';
import 'voucher_preview_ui.dart' show confirmVoucherPreview;
import 'doc_summary_ui.dart' show confirmDocSummary; // S35.T35.13
import 'warehouse_ui.dart';
import 'widgets.dart';
import 'doc_actions_ui.dart' show LockedFormBanner, LockedFields, SaleDocActions, canUnlockSale; // v91 p3
import 'legacy_sale_edit.dart' show LegacySaleForm; // v91 p3

/// وزن هر گونی (کیلو) — همان مقادیر فرم خرید
const double _kSmallSackKg = 0.1;
const double _kLargeSackKg = 0.2;

/// گرد کردن به ۳ رقم اعشار (جلوگیری از خطای اعشاری مثل 999.3000000000001)
double _r3(double v) => (v * 1000).round() / 1000;


/// عددی که کاربر تایپ می‌کند از سقف داده‌شده (گونی باقی‌مانده) بیشتر نمی‌شود:
/// اگر بیشتر شد، خودکار روی همان سقف می‌ایستد.
class _CapFormatter extends TextInputFormatter {
  final double Function() max;
  _CapFormatter(this.max);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final n = parseNum(newValue.text);
    if (n == null) return newValue;
    final m = max();
    if (n > m + 1e-9) {
      final t = plain(m);
      return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    }
    return newValue;
  }
}

/// فرم فروش — هر فروش فقط از «یک قلم انبار» (یک purchase_id) ثبت می‌شود.
/// اگر خریدار چند جنس می‌خرد، برای هر جنس یک فروش جدا ثبت کنید.
///
/// * کاربر همیشه وزن واقعی (کل، با گونی — طبق ترازو) را وارد می‌کند.
/// * گونی کوچک/بزرگِ خالی‌شده اختیاری است و سقفش دقیقاً گونی باقی‌ماندهٔ همان خرید است.
class SaleForm extends StatefulWidget {
  final int? editSaleId;
  /// v91 p3: نمایش جزئیات فروش در همین فرم به حالت قفل؛ «ویرایش» همهٔ فیلدها را باز می‌کند. [doc] = ردیف فهرست فروش (برای کارهای سند).
  final bool locked;
  final Map<String, dynamic>? doc;
  /// v94: [draft] / [draftId] = ادامهٔ پیش‌نویس فروش (مثل فرم خرید).
  final Map<String, dynamic>? draft;
  final int? draftId;
  const SaleForm({super.key, this.editSaleId, this.locked = false, this.doc, this.draft, this.draftId});
  @override
  State<SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<SaleForm> with EditGuard<SaleForm> {
  final _form = GlobalKey<FormState>();
  // S35.T35.2b: weighing block (only when the «توزین» switch is on)
  bool _weighOn = false;
  bool _gradesOn = false; // S35.T35.3b
  bool _priceTableOn = false; // S35.T35.4
  final GradeLinesController _gc = GradeLinesController();
  double _sackSmallKg = _kSmallSackKg;
  double _sackLargeKg = _kLargeSackKg;
  bool _deductPct = false;
  final _tareManual = TextEditingController();
  final _deduct = TextEditingController();
  final _ticket = TextEditingController();
  final _plate = TextEditingController();
  final _driver = TextEditingController();
  // S35.T35.6d: بلوک مالی (فقط وقتی form.fin_block روشن است). وضعیت مالیاتی از TaxChoiceField می‌آید.
  bool _finOn = false;
  bool _draftOn = false; // S35.T35.9b form.draft
  bool _hintOn = false; // S35.T35.8 form.profit_hint
  Map<String, String> _whNames = <String, String>{};
  final _finDisc = TextEditingController();
  final _finWb = TextEditingController();
  String _finPayer = 'us';
  List<Map<String, dynamic>> _lots = [];
  int? _selId;
  bool _loading = true;
  bool _saving = false;
  DateTime _date = DateTime.now(); // v91: تاریخ فروش (پیش‌فرض امروز؛ در ویرایش تاریخ ذخیره‌شده)

  /// تاریخ انتخابی + ساعت فعلی (ترتیب ثبت‌های یک روز حفظ شود)
  String get _dateIso {
    final DateTime n = DateTime.now();
    return DateTime(_date.year, _date.month, _date.day, n.hour, n.minute, n.second).toIso8601String();
  }
  bool _legacyMulti = false; // فروش قدیمیِ چندقلمی (قابل ویرایش نیست)

  final _gross = TextEditingController();
  final _small = TextEditingController();
  final _large = TextEditingController();
  final _price = TextEditingController();
  // v95: روش فروش (یک فی / پایه ۵۰ گرم / گرمی) و فروش جدای هر درصد — همان کنترلر فرم خرید، برای ریالی و ارزی.
  // درصدها و گرم از لات انتخاب‌شدهٔ انبار پر می‌شوند و قابل ویرایش‌اند (فقط برای قیمت‌گذاری؛ روی فروش ذخیره نمی‌شوند).
  final PurchasePctCtl _pp = PurchasePctCtl(sale: true);
  final TextEditingController _gramCtl = TextEditingController();
  int? _ppLot;

  void _ppSync(Map<String, dynamic>? lot) {
    final int? id = lot == null ? null : (lot['id'] as num?)?.toInt();
    if (id == _ppLot) return;
    _ppLot = id;
    for (final r in _pp.rows) {
      r.dispose();
    }
    _pp.rows.clear();
    if (lot == null) return;
    _pp.loadFrom(lot);
    final num? g = lot['gram'] as num?;
    _gramCtl.text = g == null || g <= 0 ? '' : plain(g);
  }

  /// فی فروش = میانگین هر کیلوی قیمت‌گذاری درصدها (روش فروش / قیمت جدای درصدها)؛ وگرنه همان فی پایه.
  double get _pctPrice {
    final double base = (MoneyField.stored(_price) ?? 0).toDouble();
    if (!_pp.pricing) return base;
    final r = _pp.blend(base, _net);
    return (r != null && r.ok) ? r.avgPerKg.toDouble() : base;
  }

  /// فروش ارزی: همان موتور روی فی ارزی واردشده.
  double? get _fxPerKg {
    final double? base = _fxc.priceCcyNum;
    if (base == null) return null;
    if (!_pp.pricing) return base;
    final r = _pp.blend(base, _net);
    return (r != null && r.ok) ? r.avgPerKg.toDouble() : base;
  }

  void _onFxChanged() {
    final bool cleared = _pp.syncFx(_fxc.active ? _fxc.ccy : null, _fxc.decimals);
    _changed();
    if (cleared && mounted) snack(context, 'ارز فروش عوض شد؛ قیمت‌های جدای درصدها را به ارز تازه دوباره وارد کنید');
  }

  String get _fxPriceLabel => _pp.pricing || _pp.baseMode != BuyMode.fixed ? '${_pp.priceLabel(pricedRows: _pp.pricing)} — ارزی' : 'فی فروش ارزی (هر کیلو)';
  final FxDocController _fxc = FxDocController(); // S27c: ارز سند (نرخ دستی دلار حذف شد)
  final bool _fxEditBlocked = false; // v91 p3: دیگر true نمی‌شود (سند ارزی ویرایش می‌شود؛ ارز و نرخ ثابت)
  late bool _viewOnly = widget.locked && widget.editSaleId != null; // v91 p3
  String? _fxCcy; // v91 p3: ارز فروش ارزیِ ثبت‌شده (برای پیام)

  /// v91 p3: حالت قفل ⇒ بنر «ویرایش»، فیلدها بدون لمس، کارهای سند پایین فرم.
  List<Widget> _vo(List<Widget> children) {
    if (!_viewOnly && _fxCcy == null) return children;
    return <Widget>[
      if (_viewOnly) LockedFormBanner(canEdit: canUnlockSale(StaffPerms.I.can), onEdit: () => setState(() => _viewOnly = false)),
      if (_fxCcy != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('فروش ارزی ($_fxCcy): ارز و نرخ ثبت‌شده ثابت می‌ماند؛ فی را به واحد پول برنامه ویرایش کنید. برای تغییر نرخ «سند تعدیل نرخ» ثبت کنید.'))),
      for (final Widget w in children) LockedFields(locked: _viewOnly, child: w),
      if (_viewOnly && widget.doc != null) SaleDocActions(doc: widget.doc!, onDeleted: () { if (mounted) Navigator.pop(context); }),
    ];
  }
  final _buyer = TextEditingController();
  final _note = TextEditingController();
  final _laborCost = TextEditingController(); // هزینه کارگر (اختیاری؛ از سود این فروش کم می‌شود)
  String? _taxStatus; // S17.T17.1b (طلایی): null = طبق سال مالی
  final _taxRate = TextEditingController();
  final _transportCost = TextEditingController(); // هزینه حمل‌ونقل / باسکول (اختیاری)
  String? _saleWh; // S01: انبار برداشت (فقط وقتی قلم در چند انبار است)

  bool get _isEdit => widget.editSaleId != null;

  // ---- v94: پیش‌نویس فروش مثل خرید: دستی (بدون اعتبارسنجی) + ذخیرهٔ خودکار هنگام ترک فرم؛ ادامه از کادر بالای فرم یا فهرست پیش‌نویس‌ها ----
  late int? _draftId = widget.draftId;
  bool _done = false; // ثبت یا پیش‌نویس انجام شد ⇒ ذخیرهٔ خودکار لازم نیست

  bool get _hasInput =>
      _selId != null || _gross.text.trim().isNotEmpty || (MoneyField.stored(_price) ?? 0) > 0 || _buyer.text.trim().isNotEmpty || _note.text.trim().isNotEmpty;

  String get _draftTitle {
    final Map<String, dynamic>? lot = _selLot;
    final String b = _buyer.text.trim();
    final double net = lot == null ? 0 : _net;
    return '${b.isEmpty ? '' : '$b — '}${lot == null ? 'فروش' : '${lot['type_name'] ?? 'فروش'}'}${net > 0 ? ' — ${faNum(net)} کیلو' : ''}';
  }

  /// دادهٔ خام فرم (هر قدر پر شده). 'form' = قالب v94؛ قالب قدیمی {'sale','items'} هم خوانده می‌شود.
  Map<String, dynamic> _draftData() => <String, dynamic>{
        'form': <String, dynamic>{
          'date': _dateIso,
          'lot': _selId,
          'gross': _gross.text.trim(),
          'small': _small.text.trim(),
          'large': _large.text.trim(),
          'price': MoneyField.stored(_price),
          'buyer': _buyer.text.trim(),
          'note': _note.text.trim(),
          'labor': MoneyField.stored(_laborCost),
          'transport': MoneyField.stored(_transportCost),
        },
      };

  /// پیش‌نویس ⇒ فیلدها؛ شناسهٔ لات انتخاب‌شده را برمی‌گرداند.
  int? _applyDraft(Map<String, dynamic> d) {
    String t(Object? v) => v == null ? '' : (v is num ? plain(v) : '$v');
    Map<String, dynamic> f;
    if (d['form'] is Map) {
      f = Map<String, dynamic>.from(d['form'] as Map<dynamic, dynamic>);
    } else if (d['sale'] is Map) { // پیش‌نویس کامل قدیمی
      final Map<dynamic, dynamic> s = d['sale'] as Map<dynamic, dynamic>;
      final List<dynamic> it = (d['items'] as List<dynamic>?) ?? const <dynamic>[];
      final Map<dynamic, dynamic> i0 = it.isNotEmpty && it.first is Map ? it.first as Map<dynamic, dynamic> : const <dynamic, dynamic>{};
      f = <String, dynamic>{
        'date': s['date'], 'lot': i0['purchase_id'], 'gross': s['total_weight'], 'small': i0['small_sacks'], 'large': i0['large_sacks'],
        'price': s['price'], 'buyer': s['buyer'], 'note': s['note'], 'labor': s['labor_cost'], 'transport': s['transport_cost'],
      };
    } else {
      return null;
    }
    _date = DateTime.tryParse(t(f['date'])) ?? _date;
    _fxc.dateIso = fxIsoDate(_date);
    _gross.text = t(f['gross']);
    _small.text = (f['small'] is num && f['small'] == 0) ? '' : t(f['small']);
    _large.text = (f['large'] is num && f['large'] == 0) ? '' : t(f['large']);
    if (f['price'] is num) MoneyField.setStored(_price, f['price'] as num);
    _buyer.text = t(f['buyer']);
    _note.text = t(f['note']);
    if (f['labor'] is num) MoneyField.setStored(_laborCost, f['labor'] as num);
    if (f['transport'] is num) MoneyField.setStored(_transportCost, f['transport'] as num);
    final Object? lot = f['lot'];
    return lot is num ? lot.toInt() : int.tryParse('${lot ?? ''}');
  }

  Future<void> _saveDraft() async {
    if (!_hasInput) {
      snack(context, 'فرم خالی است');
      return;
    }
    _draftId = await DocDraftsLocal.saveOrReplace('sale', _draftTitle, _draftData(), replaceId: _draftId);
    _done = true;
    if (!mounted) return;
    snack(context, 'پیش‌نویس ذخیره شد (بدون اثر روی انبار و حساب‌ها)');
    Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadWeighSettings(); // S35.T35.2b
    if (LicenseService.I.isFx.value) _initFx();
    _fxc.effectivePriceCcy = () => _fxPerKg; // v95: روش فروش ارزی
    _pp.gramSource = () => parseNum(_gramCtl.text);
    _pp.init().then((_) {
      if (!mounted) return;
      _ppLot = null;
      _ppSync(_selLot);
      setState(() {});
    });
  }

  /// ارزهای فعال از کش دستگاه؛ سپس تازه‌سازی بی‌صدای کش (آنلاین) و دوباره‌خوانی نرخ.
  Future<void> _initFx() async {
    await _fxc.load();
    if (mounted) setState(() {});
    if (await FxLocal.refresh()) {
      await _fxc.load();
      await _fxc.resolveRate();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    // v94: ترک فرم وسط کار (بدون ثبت) ⇒ ذخیرهٔ خودکار پیش‌نویس تا اطلاعات وارد‌شده نپرد
    if (!_isEdit && !_done && _hasInput) DocDraftsLocal.autosave('sale', _draftTitle, _draftData());
    _gross.dispose();
    _gc.dispose();
    _tareManual.dispose();
    _deduct.dispose();
    _ticket.dispose();
    _plate.dispose();
    _driver.dispose();
    _finDisc.dispose();
    _finWb.dispose();
    _small.dispose();
    _large.dispose();
    _price.dispose();
    _pp.dispose();
    _gramCtl.dispose();
    _fxc.dispose();
    _buyer.dispose();
    _note.dispose();
    _laborCost.dispose();
    _taxRate.dispose();
    _transportCost.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<Map<String, dynamic>> l;
    int? preSel;
    var legacy = false;
    if (_isEdit) {
      final items = await AppDb.I.saleItemsOf(widget.editSaleId!);
      if (items.length != 1) {
        legacy = true;
      } else {
        preSel = (items.first['purchase_id'] as num).toInt();
      }
      l = await AppDb.I.lotsForSaleEdit(widget.editSaleId!);
      final sale = await AppDb.I.saleById(widget.editSaleId!);
      if (sale != null && !legacy) {
        MoneyField.setStored(_price, sale['price'] as num);
        if (sale['ccy'] != null && (sale['ccy'] as String).isNotEmpty && sale['ccy'] != 'IRT') _fxCcy = sale['ccy'] as String;
        _gross.text = plain(sale['total_weight'] as num);
        if (sale['gross_kg'] != null) { // S35.T35.2b
          _tareManual.text = sale['tare_kg'] == null ? '' : plain(sale['tare_kg'] as num);
          _deduct.text = (sale['quality_deduct_kg'] == null || (sale['quality_deduct_kg'] as num) == 0) ? '' : plain(sale['quality_deduct_kg'] as num);
          _ticket.text = (sale['weigh_ticket_no'] as String?) ?? '';
          _plate.text = (sale['vehicle_plate'] as String?) ?? '';
          _driver.text = (sale['driver_name'] as String?) ?? '';
        }
        // گونی از خودِ قلم فروش خوانده می‌شود (همان مقداری که واقعاً از انبار کم شده بود)
        final small = ((items.first['small_sacks'] as num?) ?? 0).toDouble();
        final large = ((items.first['large_sacks'] as num?) ?? 0).toDouble();
        _small.text = small == 0 ? '' : plain(small);
        _large.text = large == 0 ? '' : plain(large);
        _buyer.text = (sale['buyer'] as String?) ?? '';
        _date = DateTime.tryParse('${sale['date'] ?? ''}') ?? _date; // v91
        _fxc.dateIso = fxIsoDate(_date);
        _note.text = (sale['note'] as String?) ?? '';
    MoneyField.setStored(_laborCost, sale['labor_cost'] as num?);
    _taxStatus = sale['tax_status'] as String?;
    _taxRate.text = taxRateTextFromMilli(sale['tax_rate_milli']);
    MoneyField.setStored(_transportCost, sale['transport_cost'] as num?);
    final Object? fd = sale['discount_amount'] ?? sale['discount']; // S35.T35.6d: prefill
    final Object? fw = sale['weighbridge_cost'];
    if (fd is num && fd > 0) MoneyField.setStored(_finDisc, fd);
    if (fw is num && fw > 0) MoneyField.setStored(_finWb, fw);
    _finPayer = sale['side_cost_payer'] == 'party' ? 'party' : 'us';
      }
    } else {
      l = await AppDb.I.lots();
      if (widget.draft != null) preSel = _applyDraft(widget.draft!); // v94
    }
    if (!mounted) return;
    setState(() {
      _lots = l;
      _legacyMulti = legacy;
      if (preSel != null && l.any((e) => e['id'] == preSel)) _selId = preSel; _ppSync(_selLot); // v95
      _loading = false;
    });
  }

  // ------------------------- محاسبات -------------------------
  Map<String, dynamic>? get _selLot {
    if (_selId == null) return null;
    for (final e in _lots) {
      if (e['id'] == _selId) return e;
    }
    return null;
  }

  double get _rem => ((_selLot?['remaining'] as num?) ?? 0).toDouble();
  double get _smallCap => ((_selLot?['small_left'] as num?) ?? 0).toDouble();
  double get _largeCap => ((_selLot?['large_left'] as num?) ?? 0).toDouble();

  double get _grossKg => parseNum(_gross.text) ?? 0;
  double get _smallN => parseNum(_small.text) ?? 0;
  double get _largeN => parseNum(_large.text) ?? 0;
  double get _sackTare => _smallN * (_weighOn ? _sackSmallKg : _kSmallSackKg) + _largeN * (_weighOn ? _sackLargeKg : _kLargeSackKg);
  double get _tare => (_weighOn && _tareManual.text.trim().isNotEmpty) ? (parseNum(_tareManual.text) ?? 0) : _sackTare;
  double get _deductKg {
    if (!_weighOn) return 0;
    final double v = parseNum(_deduct.text) ?? 0;
    if (!_deductPct) return v;
    final double base = _grossKg - _tare;
    return base <= 0 ? 0 : _r3(base * v / 100);
  }
  double get _net => _r3(_grossKg - _tare - _deductKg);

  Future<void> _loadWeighSettings() async {
    final bool on = await FormSettingsLocal.isOn('weigh');
    final bool gOn = await FormSettingsLocal.isOn('grades');
    final bool ptOn = await FormSettingsLocal.isOn('price_table'); // S35.T35.4
    final bool fin = await FormSettingsLocal.isOn('fin_block'); // S35.T35.6d
    final bool draftOn = await FormSettingsLocal.isOn('draft'); // S35.T35.9b
    final bool hintOn = await FormSettingsLocal.isOn('profit_hint'); // S35.T35.8
    final Map<String, String> whNames = hintOn ? await StockLookup.warehouseNames() : <String, String>{};
    List<Map<String, dynamic>> gl = <Map<String, dynamic>>[];
    if (gOn && widget.editSaleId != null) gl = await GradeLinesLocal.load('sale', widget.editSaleId!);
    final List<double> k = await FormSettingsLocal.sackKg();
    if (!mounted) return;
    setState(() {
      _gradesOn = gOn;
      _priceTableOn = ptOn;
      _hintOn = hintOn;
      _whNames = whNames;
      if (gl.isNotEmpty) _gc.loadFrom(gl);
      _weighOn = on;
      _sackSmallKg = k[0];
      _sackLargeKg = k[1];
      _finOn = fin;
      _draftOn = draftOn || true; // v94: پیش‌نویس همیشه در دسترس است (مثل خرید)
    });
  }
  /// فی فروش (واحد ذخیره، تومان تا S29): در سند ارزی = فی ارزی × نرخ ÷ ۱۰
  bool get _useGrades => _gradesOn && _gc.hasRows && !_fxc.active; // S35.T35.3b: price = weighted average of the grade lines
  // v89: فی فروش فقط برای کسی که قیمت فروش را می‌بیند و قسمت «فی فروش» برایش پنهان نیست
  bool get _priceShown => StaffPerms.I.canPriceIn('sales') && StaffPerms.I.fieldShown('sale.price');
  bool get _priceEditable => _priceShown && StaffPerms.I.fieldEditable('sale.price');

  double get _priceVal => _fxc.active ? (_fxc.priceStored ?? 0) : (_useGrades ? _gc.weightedPrice : _pctPrice); // v95: روش فروش / درصدها
  double get _revenue => _net * _priceVal;

  bool get _fx => LicenseService.I.isFx.value;

  /// فی دلاریِ خریدِ پستهٔ انتخاب‌شده (null = ثبت نشده، مثلاً خرید قبل از ارتقای پلن)
  double? get _costPerKgUsd => (_selLot?['price_usd'] as num?)?.toDouble();

  void _changed() {
    if (mounted) setState(() {});
  }

  void _select(int id) {
    setState(() {
      if (_selId != id) {
        _selId = id;
        _ppSync(_selLot); // v95: درصدها و گرم از لات
        // سقف گونی هر خرید فرق دارد؛ مقدارهای قبلی پاک می‌شوند
        _small.clear();
        _large.clear();
      }
    });
  }

  void _fillAll() {
    final lot = _selLot;
    if (lot == null) return;
    final small = _smallCap;
    final large = _largeCap;
    _small.text = small == 0 ? '' : plain(small);
    _large.text = large == 0 ? '' : plain(large);
    _gross.text = plain(_rem + small * (_weighOn ? _sackSmallKg : _kSmallSackKg) + large * (_weighOn ? _sackLargeKg : _kLargeSackKg));
    _changed();
  }

  // ------------------------- ذخیره -------------------------
  Future<void> _save({bool draft = false}) async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    final lot = _selLot;
    if (lot == null) {
      snack(context, 'یک پسته از انبار انتخاب کنید');
      return;
    }
    final fxErr = _fxc.validate();
    if (fxErr != null) {
      snack(context, fxErr);
      return;
    }
    if (_priceShown) {
      final String? pe = _pp.validate(); // v95
      if (pe != null) {
        snack(context, pe);
        return;
      }
    }
    final price = _priceVal;
    final bool keepPrice = _isEdit && !_priceEditable; // v89: ویرایش بدون دسترسی فی ⇒ سرور فی ذخیره‌شده را نگه می‌دارد
    if (price <= 0 && !keepPrice) {
      snack(context, _priceShown ? 'فی فروش را وارد کنید' : 'ثبت فروش تازه به فی نیاز دارد؛ کاربری که دسترسی قیمت فروش دارد باید آن را ثبت کند');
      return;
    }
    final net = _net;
    if (net <= 0) {
      snack(context, 'وزن (خالص) باید بیشتر از صفر باشد (وزن گونی‌ها از وزن کل (ناخالص) بیشتر است؟)');
      return;
    }
    if (net > _rem + 1e-6) {
      snack(context, 'وزن (خالص) «${lot['type_name']}» از موجودی آن (${faNum(_rem)} کیلو) بیشتر است');
      return;
    }
    if (_gradesOn) {
      final String? ge = _gc.validate(net); // S35.T35.3b
      if (ge != null) {
        snack(context, ge);
        return;
      }
    }
    final smallN = _smallN;
    final largeN = _largeN;
    if (smallN > _smallCap + 1e-6) {
      snack(context, 'گونی کوچک از گونی کوچک باقی‌ماندهٔ این خرید (${faNum(_smallCap)}) بیشتر است');
      return;
    }
    if (largeN > _largeCap + 1e-6) {
      snack(context, 'گونی بزرگ از گونی بزرگ باقی‌ماندهٔ این خرید (${faNum(_largeCap)}) بیشتر است');
      return;
    }

    final sacksEntered = (smallN + largeN) > 0;
    // اگر این خرید اصلاً گونی‌ای ندارد، هشدار معنی ندارد
    final lotHasSacks = (_smallCap + _largeCap) > 0;
    if (!sacksEntered && lotHasSacks) {
      final ok = await confirm(context,
          'شما تعداد گونی خالی‌شده را وارد نکردید؛ گونیِ انبار برای این خرید کم نخواهد شد. مطمئنید؟');
      if (!ok || !mounted) return;
    }

    final id = lot['id'] as int;
    final items = <Map<String, dynamic>>[
      {
        'purchase_id': id,
        'weight': net,
        'item_price': price,
        'small_sacks': sacksEntered ? smallN : null,
        'large_sacks': sacksEntered ? largeN : null,
      }
    ];
    final saleData = <String, dynamic>{
      ..._fxc.fields(),
      'price': price,
      'total_weight': _grossKg,
      'small_sack_count': smallN,
      'large_sack_count': largeN,
      'net_weight': net,
      if (_gradesOn) 'grade_lines': _gc.toPayload(), // S35.T35.3b (empty list = single-price document)
      // S35.T35.2b: weighing block (null when the switch is off)
      'gross_kg': _weighOn ? _grossKg : null,
      'tare_kg': _weighOn ? _tare : null,
      'quality_deduct_kg': _weighOn ? _deductKg : null,
      'weigh_ticket_no': _weighOn && _ticket.text.trim().isNotEmpty ? _ticket.text.trim() : null,
      'vehicle_plate': _weighOn && _plate.text.trim().isNotEmpty ? _plate.text.trim() : null,
      'driver_name': _weighOn && _driver.text.trim().isNotEmpty ? _driver.text.trim() : null,
      'buyer': _buyer.text.trim().isEmpty ? null : _buyer.text.trim(),
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      'labor_cost': MoneyField.stored(_laborCost),
      'transport_cost': MoneyField.stored(_transportCost),
      if (_finOn) ...<String, dynamic>{ // S35.T35.6d: server applies only when form.fin_block is on
        'discount_amount': MoneyField.stored(_finDisc) ?? 0,
        'weighbridge_cost': MoneyField.stored(_finWb) ?? 0,
        'side_cost_payer': _finPayer,
      },
      if (taxChoiceAvailable()) 'tax_status': _taxStatus,
      if (taxChoiceAvailable()) 'tax_rate_milli': _taxStatus == 'taxable' ? taxRateMilliFromText(_taxRate.text) : null,
      if (_saleWh != null) 'warehouse_uid': _saleWh,
    };

    if (draft) {
      // S35.T35.9b: پیش‌نویس فقط محلی؛ موجودی انبار رزرو یا کم نمی‌شود
      saleData['date'] = _dateIso;
      await DocDraftsLocal.save('sale', '${lot['type_name']} — ${faNum(net)} کیلو', <String, dynamic>{'sale': saleData, 'items': items});
      if (!mounted) return;
      snack(context, 'پیش‌نویس ذخیره شد (بدون اثر روی انبار و حساب‌ها)');
      Navigator.pop(context);
      return;
    }
    if (!_isEdit) {
      // S35.T35.9d: gold dry-run preview of the voucher (display-only; never blocks when offline)
      final bool go = await confirmVoucherPreview(context, docType: 'sale', doc: <String, dynamic>{...saleData, 'date': _dateIso}, items: items);
      if (!go || !mounted) return;
    }
    if (await FormSettingsLocal.isOn('confirm_summary')) { // S35.T35.13
      if (!mounted) return;
      final double sumKg = items.fold<double>(0, (double a, Map<String, dynamic> i) => a + ((i['weight'] as num?) ?? 0).toDouble());
      final bool okSum = await confirmDocSummary(context, title: 'تأیید فروش', rows: <MapEntry<String, String>>[
        MapEntry<String, String>('خریدار', '${saleData['buyer'] ?? '—'}'),
        MapEntry<String, String>('وزن خالص', Fmt.kg(sumKg)),
        MapEntry<String, String>('فی فروش', Fmt.money((items.isEmpty ? 0 : (items.first['item_price'] as num?) ?? 0))),
        if (saleData['discount_amount'] != null) MapEntry<String, String>('تخفیف', Fmt.money(saleData['discount_amount'] as num)),
        if (saleData['weighbridge_cost'] != null) MapEntry<String, String>('هزینه باسکول', Fmt.money(saleData['weighbridge_cost'] as num)),
        if (saleData['labor_cost'] != null) MapEntry<String, String>('هزینه کارگر', Fmt.money(saleData['labor_cost'] as num)),
        if (saleData['transport_cost'] != null) MapEntry<String, String>('حمل‌ونقل', Fmt.money(saleData['transport_cost'] as num)),
        MapEntry<String, String>('وضعیت مالیاتی', '${saleData['tax_status'] ?? 'بدون مالیات'}'),
      ]);
      if (!okSum || !mounted) return;
    }
    setState(() => _saving = true);
    saleData['date'] = _dateIso; // v91: ثبت و ویرایش
    final ok = await saveConfirmed(
      context,
      () async {
        if (_isEdit) {
          await AppDb.I.updateSale(widget.editSaleId!, saleData, items, keepPrice: keepPrice);
        } else {
          await AppDb.I.insertSale(saleData, items);
        }
      },
      successMsg: _isEdit ? 'ویرایش فروش با موفقیت ثبت شد' : 'فروش با موفقیت ثبت شد',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _done = true; // v94
      if (_draftId != null) await DocDraftsLocal.delete(_draftId!);
      if (mounted) Navigator.pop(context);
    }
  }

  // ------------------------- رابط کاربری -------------------------
  @override
  Widget build(BuildContext context) {
    if (!_loading && _legacyMulti) return LegacySaleForm(saleId: widget.editSaleId!, locked: _viewOnly, doc: widget.doc); // v91 p3: چندقلمی قدیمی هم ویرایش می‌شود
    return Scaffold(
      appBar: AppBar(title: Text(_viewOnly ? 'جزئیات فروش' : (_isEdit ? 'ویرایش فروش' : 'فروش جدید'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _legacyMulti
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'این فروش قدیمی و چندقلمی است و دیگر قابل ویرایش نیست.\n'
                      'هر فروش فقط از یک قلم انبار ثبت می‌شود؛ می‌توانید آن را حذف کنید '
                      'و برای هر جنس یک فروش جدا ثبت کنید.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _fxEditBlocked
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'این فروش به ارز ثبت شده و نرخ آن ثابت است؛ ویرایش مستقیم ممکن نیست.\n'
                          'برای اصلاح نرخ از «سند تعدیل نرخ» استفاده کنید، یا فروش را حذف و دوباره ثبت کنید.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
              : _lots.isEmpty
                  ? const Center(child: Text('انبار خالی است؛ ابتدا خرید ثبت کنید'))
                  : Form(
                      key: _form,
                      // v91: فرم فشرده‌تر (کادرهای کوتاه‌تر، فاصلهٔ کمتر) تا فرم فروش بلند نشود
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          visualDensity: VisualDensity.compact,
                          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                        ),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          children: _vo(<Widget>[
                            if (!_isEdit && widget.draft == null && !_viewOnly) DraftRestoreBanner(docType: 'sale', onRestore: (int id, Map<String, dynamic> data) => Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => SaleForm(draft: data, draftId: id)))), // v94
                            ..._children(context),
                          ]),
                        ),
                      ),
                    ),
    );
  }


  List<Widget> _children(BuildContext context) {
    final w = <Widget>[];
    final lot = _selLot;

    // v96: تاریخ و خریدار در یک ردیف (فشرده مثل فرم خرید)
    w.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Expanded(child: KeyedSubtree(key: const ValueKey('saleDate'), child: DocDateField(label: 'تاریخ فروش', value: _date, onChanged: (DateTime d) { setState(() => _date = d); _fxc.setDate(d).then((_) => _changed()); }))), // v91
      const SizedBox(width: 8),
      Expanded(child: KeyedSubtree(key: const ValueKey('buyer'), child: FieldGate(field: 'sale.buyer', child: PartyField(controller: _buyer, label: 'خریدار (اختیاری)')))),
    ]));
    w.add(sectionTitle(context, 'پسته (از انبار؛ هر فروش یک قلم)'));
    w.add(SaleLotPicker(lots: _lots, selectedId: _selId, onSelect: _select, whNames: _whNames, showUsd: _fx)); // v87: انتخاب لات مثل فرم شکست (به‌جای فهرست همهٔ لات‌ها)

    if (lot == null) {
      w.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('بعد از انتخاب پسته، وزن فروش را وارد کنید.', style: TextStyle(color: Colors.black54)),
      ));
    } else {
      w.add(sectionTitle(context, 'وزن (طبق ترازو)'));
      w.add(KeyedSubtree(key: ValueKey('weigh${lot['id']}'), child: _weighFields(lot)));
      w.add(KeyedSubtree(
          key: ValueKey('swh${lot['id']}'),
          child: SaleWarehouseField(lotId: lot['id'] as int, onChanged: (String? v) => _saleWh = v)));
      w.add(_summaryCard(context));
      if (_priceShown) w.add(sectionTitle(context, 'قیمت'));
      if (_fx && _priceShown) w.add(FxDocFields(c: _fxc, priceLabel: _fxPriceLabel, onChanged: _onFxChanged)); // v95: روش فروش ارزی
      if (_priceShown && !_useGrades && _selLot != null) { // v95: روش فروش + درصدها (از انبار، قابل ویرایش) + قیمت جدای هر درصد
        w.add(FieldGate(field: 'sale.price', child: PurchasePctSection(
            key: ValueKey('salePct${_selLot!['id']}'),
            ctl: _pp,
            basePrice: _fxc.active ? _fxc.priceCcyNum : MoneyField.stored(_price),
            netKg: _net,
            onChanged: _changed,
            readOnly: !_priceEditable,
            priceField: _fxc.active ? null : MoneyField(controller: _price, label: _pp.priceLabel(pricedRows: _pp.pricing), required: true, onChanged: _changed))));
        if (_pp.baseGram || _pp.rows.isNotEmpty) w.add(numField(_gramCtl, 'گرم پسته (از انبار؛ قابل ویرایش)', onChanged: _changed));
      }
      if (_priceEditable && _priceTableOn && !_fxc.active && !_useGrades && _selLot != null) {
        w.add(PriceSuggestionHint(
            typeName: '${_selLot!['type_name']}', ounceUid: _selLot!['ounce_uid'] as String?, onAccept: (num v) { MoneyField.setStored(_price, v); _changed(); })); // S35.T35.4
      }
      if (_priceShown && _hintOn && _selLot != null) w.add(_profitHint(_selLot!)); // S35.T35.8
      if (_priceShown && _gradesOn && !_fxc.active) w.add(FieldGate(field: 'sale.price', child: GradeLinesEditor(c: _gc, netKg: _net, onChanged: _changed))); // S35.T35.3b

    }

    w.add(sectionTitle(context, 'سایر')); // v94: فشرده مثل فرم خرید · v96: خریدار بالای فرم
    w.add(KeyedSubtree(key: const ValueKey('note'), child: FieldGate(field: 'sale.note', child: textField(_note, 'توضیحات (اختیاری)'))));
    w.add(FieldGate(
        field: 'sale.costs',
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Expanded(child: KeyedSubtree(key: const ValueKey('laborCost'), child: MoneyField(controller: _laborCost, label: 'هزینه کارگر'))),
          const SizedBox(width: 8),
          Expanded(child: KeyedSubtree(key: const ValueKey('transportCost'), child: MoneyField(controller: _transportCost, label: 'حمل / باسکول'))),
        ])));
    if (_finOn)
      w.addAll(<Widget>[
        sectionTitle(context, 'بلوک مالی'),
        FieldGate(
            field: 'sale.fin',
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Expanded(child: MoneyField(controller: _finDisc, label: 'تخفیف')),
              const SizedBox(width: 8),
              Expanded(child: MoneyField(controller: _finWb, label: 'هزینهٔ باسکول')),
            ])),
        FieldGate(field: 'sale.fin', child: DropdownButtonFormField<String>(
          value: _finPayer,
          decoration: const InputDecoration(labelText: 'هزینه‌های جانبی بر عهدهٔ'),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem<String>(value: 'us', child: Text('ما')),
            DropdownMenuItem<String>(value: 'party', child: Text('طرف حساب')),
          ],
          onChanged: (String? v) => setState(() => _finPayer = v ?? 'us'),
        )),
      ]);
    if (_finOn && widget.editSaleId != null) w.add(FinBlockCard(docType: 'sale', docId: widget.editSaleId));
    if (_priceShown) {
      w.add(KeyedSubtree(
          key: const ValueKey('taxChoice'),
          child: FieldGate(field: 'sale.price', child: TaxChoiceField(status: _taxStatus, rate: _taxRate, onChanged: (String? v) => setState(() => _taxStatus = v)))));
    }
    if (!_viewOnly) w.add(FilledButton.icon(
      onPressed: _saving ? null : _save,
      icon: _saving
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.check),
      label: Text(_isEdit ? 'ذخیره تغییرات' : 'ثبت فروش'),
    ));
    if (_draftOn && !_isEdit) {
      w.add(const SizedBox(height: 8));
      w.add(OutlinedButton.icon(
        onPressed: _saving ? null : _saveDraft, // v94: بدون اعتبارسنجی، قابل ادامه
        icon: const Icon(Icons.edit_note),
        label: const Text('ذخیره به‌عنوان پیش‌نویس'),
      ));
    }
    w.add(const SizedBox(height: 24));
    return w;
  }

  /// S35.T35.8: cost per kg of a lot = (price x net + labor + transport) / net (same basis as margin.php pb_pl_lot).
  /// null for mixed/processed lots (cost lives in stock_moves on the server). Read-only hint, never blocks.
  double? _lotCostPerKg(Map<String, dynamic> lot) {
    if ((lot['is_mix'] as num?)?.toInt() != 0) return null;
    final double net = (lot['net_weight'] as num?)?.toDouble() ?? 0;
    if (net <= 0) return null;
    final double price = (lot['price'] as num?)?.toDouble() ?? 0;
    final double labor = (lot['labor_cost'] as num?)?.toDouble() ?? 0;
    final double transport = (lot['transport_cost'] as num?)?.toDouble() ?? 0;
    return (price * net + labor + transport) / net;
  }

  Widget _profitHint(Map<String, dynamic> lot) {
    final double? cost = _lotCostPerKg(lot);
    if (cost == null) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text('بهای تمام‌شده این پسته در اینجا قابل نمایش نیست.', style: TextStyle(color: Colors.black54)),
      );
    }
    final double price = _priceVal;
    final bool hasPrice = price > 0;
    final double margin = price - cost;
    final bool loss = hasPrice && margin < 0;
    final Color c = loss ? Colors.red.shade800 : Colors.black87;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: loss ? Colors.red.shade50 : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('بهای تمام‌شده هر کیلو: ${Fmt.money(cost)}', style: TextStyle(color: c)),
          if (hasPrice)
            Text('سود تقریبی هر کیلو: ${Fmt.money(margin)}  •  حاشیه ${faNum(margin * 100 / price, dec: 1)}٪', style: TextStyle(color: c)),
          if (loss)
            Text('هشدار: فی فروش کمتر از بهای تمام‌شده است.', style: TextStyle(color: c, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }



  Widget _sackField(TextEditingController c, String label, double cap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [_CapFormatter(() => cap)],
        decoration: InputDecoration(
          labelText: label,
          hintText: '0',
          helperText: 'حداکثر ${faNum(cap)}',
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => _changed(),
        validator: (v) {
          if ((v ?? '').trim().isEmpty) return null;
          final n = parseNum(v);
          if (n == null || n < 0) return 'عدد معتبر وارد کنید';
          if (n > cap + 1e-6) return 'حداکثر ${faNum(cap)}';
          return null;
        },
      ),
    );
  }

  /// وزن واقعی (کل، با گونی) + گونی‌های خالی‌شده (اختیاری)
  Widget _weighFields(Map<String, dynamic> lot) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // v91: وزن کل و «همه موجودی» در یک ردیف؛ راهنمای گونی کوتاه
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: numField(_gross, 'وزن کل (ناخالص، با گونی)', required: true, onChanged: _changed)),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: TextButton.icon(onPressed: _fillAll, icon: const Icon(Icons.all_inclusive, size: 18), label: const Text('همه موجودی')),
        ),
      ]),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _sackField(_small, 'گونی کوچک (${faNum(_kSmallSackKg * 1000, dec: 0)} گرم)', _smallCap)),
        const SizedBox(width: 8),
        Expanded(child: _sackField(_large, 'گونی بزرگ (${faNum(_kLargeSackKg * 1000, dec: 0)} گرم)', _largeCap)),
      ]),
      const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Text('گونی اختیاری است؛ خالی ⇒ فقط وزن از انبار کم می‌شود.', style: TextStyle(color: Colors.black54, fontSize: 11.5)),
      ),
      if (_weighOn) ...[
        sectionTitle(context, 'توزین'),
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text('تارا یعنی وزن گونی یا ظرف خالی که از وزن کل کم می‌شود', style: TextStyle(fontSize: 12, color: Colors.black54)),
        ),
        numField(_tareManual, 'تارا (کیلو) — خالی = از تعداد گونی', hint: faNum(_sackTare), onChanged: _changed),
        Row(children: [
          Expanded(child: numField(_deduct, _deductPct ? 'کسر کیفیت (درصد)' : 'کسر کیفیت (کیلو)', onChanged: _changed)),
          const SizedBox(width: 8),
          DropdownButton<bool>(
            value: _deductPct,
            items: const <DropdownMenuItem<bool>>[
              DropdownMenuItem<bool>(value: false, child: Text('کیلو')),
              DropdownMenuItem<bool>(value: true, child: Text('درصد')),
            ],
            onChanged: (bool? v) {
              setState(() => _deductPct = v ?? false);
              _changed();
            },
          ),
        ]),
        textField(_ticket, 'شمارهٔ قبض باسکول'),
        Row(children: [
          Expanded(child: textField(_plate, 'پلاک')),
          const SizedBox(width: 8),
          Expanded(child: textField(_driver, 'راننده')),
        ]),
      ],
    ]);
  }

  Widget _summaryCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = _net > _rem + 1e-6;
    final tooHeavy = _grossKg > 0 && _net <= 0;
    // v91: خلاصهٔ فشرده (کنار هم به‌جای یک ردیف برای هر عدد)
    Widget kv(String k, String v, {Color? color, bool strong = false}) => Text.rich(
          TextSpan(children: <InlineSpan>[
            TextSpan(text: '$k: ', style: const TextStyle(color: Colors.black54)),
            TextSpan(text: v, style: TextStyle(fontWeight: strong ? FontWeight.bold : FontWeight.w600, color: color)),
          ]),
          style: const TextStyle(fontSize: 13),
        );
    return Card(
      color: scheme.primaryContainer,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 14, runSpacing: 4, children: <Widget>[
            kv('ناخالص', '${faNum(_grossKg)} کیلو'),
            kv(_weighOn ? 'تارا' : 'وزن گونی‌ها', '${faNum(_tare)} کیلو'),
            if (_weighOn && _deductKg > 0) kv('کسر کیفیت', '${faNum(_deductKg)} کیلو'),
            kv('خالص', '${faNum(_net)} کیلو', color: over ? scheme.error : null, strong: true),
            kv('مبلغ تقریبی', Fmt.money(_revenue), strong: true),
            if (_fxc.active && _fxc.priceCcyNum != null) ...[
              kv('فی ارزی', faCcy(_fxc.ccy!, _fxc.priceCcyNum!, dec: _fxc.decimals)),
              kv('مبلغ ارزی', faCcy(_fxc.ccy!, _net * _fxc.priceCcyNum!, dec: _fxc.decimals)),
            ],
          ]),
          if (tooHeavy)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('وزن گونی‌ها از وزن کل (ناخالص) بیشتر یا مساوی آن است', style: TextStyle(color: scheme.error)),
            ),
          if (over)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('وزن (خالص) «${_selLot?['type_name']}» از موجودی آن (${faNum(_rem)} کیلو) بیشتر است',
                  style: TextStyle(color: scheme.error)),
            ),
        ]),
      ),
    );
  }
}
