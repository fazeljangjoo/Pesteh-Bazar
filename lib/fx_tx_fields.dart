// S28.T28.2b — foreign-currency fields for receipt / payment / cheque lines (fx plan only).
// The main «amount» controller of the form keeps holding the RIAL EQUIVALENT in the stored unit (toman until S29),
// so overpay checks, totals and reports are unchanged. When a currency is chosen: amount = ccy_amount * rate / 10
// (auto-filled, still editable = the rial actually moved). The line sends ccy, ccy_amount, fx_rate + amount.
// Rial plan / no cached currencies: the widget renders nothing and fields() is empty.
import 'package:flutter/material.dart';

import 'fx_doc_field.dart';
import 'fmt.dart' show MoneyField;
import 'fx_local.dart';
import 'utils.dart';
import 'widgets.dart';

class FxTxController {
  final TextEditingController amount;
  final TextEditingController ccyAmount = TextEditingController();
  final TextEditingController rate = TextEditingController();
  String? ccy;
  List<Map<String, dynamic>> currencies = <Map<String, dynamic>>[];

  // ---- v93: ردیفی که به ارز دیگری غیر از ارز فاکتور پرداخت/دریافت می‌شود ⇒ «سهم به ارز فاکتور» ----
  /// ارز فاکتوری که صفحهٔ پرداخت/دریافت باز است (null یا IRR = فاکتور ریالی). صفحه هنگام بارگذاری می‌گذارد و هنگام بستن پاک می‌کند.
  static String? docCcy;
  final TextEditingController share = TextEditingController();
  String shareMode = 'rate'; // rate = نرخ روز، agreed = مبلغ توافقی
  double docRate = 0;
  String docRateDate = '';

  FxTxController(this.amount) {
    amount.addListener(() {
      if (!active) recomputeShare(); // ردیف ریالی: سهم از مبلغ ریالی
    });
  }

  bool get active => ccy != null;
  bool get available => currencies.isNotEmpty;

  /// فاکتور ارزی است و ارز این ردیف چیز دیگری است (از جمله ریال)
  bool get needsShare {
    final String? d = docCcy;
    return d != null && d.isNotEmpty && d != 'IRR' && d != 'IRT' && (ccy ?? 'IRR') != d;
  }

  /// نرخ روزِ ارز فاکتور برای تاریخ ردیف (یک بار برای هر تاریخ)
  Future<void> resolveDocRate(String dateIso) async {
    final String? d = docCcy;
    if (!needsShare || d == null || docRateDate == dateIso) return;
    docRateDate = dateIso;
    final ({double rate, String date})? r = await FxLocal.rateAt(d, dateIso);
    docRate = r?.rate ?? 0;
    recomputeShare();
  }

  /// نرخ روز: سهم = ارزش ریالی ردیف ÷ نرخ روزِ ارز فاکتور (۴ رقم اعشار)
  void recomputeShare() {
    if (!needsShare || shareMode != 'rate' || docRate <= 0) return;
    final double rial = active
        ? (parseNum(ccyAmount.text) ?? 0) * (parseNum(rate.text) ?? 0)
        : (MoneyField.stored(amount) ?? 0) * kFxRialPerStoredUnit;
    if (rial <= 0) return;
    String v = ((rial / docRate * 10000).roundToDouble() / 10000).toStringAsFixed(4); // ۴ رقم اعشار، مثل سرور
    if (v.contains('.')) v = v.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    if (share.text != v) share.text = v;
  }

  Future<void> load(Map<String, dynamic>? existing) async {
    try {
      final List<Map<String, dynamic>> all = await FxLocal.loadCurrencies();
      currencies = all.where((Map<String, dynamic> c) => c['active'] == true && c['is_base'] != true).toList();
    } catch (_) {
      currencies = <Map<String, dynamic>>[];
    }
    if (existing != null) {
      final num? dca = existing['doc_ccy_amount'] as num?; // v93
      if (dca != null && dca > 0) share.text = dca.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
      if (existing['doc_ccy_mode'] == 'agreed') shareMode = 'agreed';
      final String? c = existing['ccy'] as String?;
      if (c != null && c.isNotEmpty) {
        ccy = c;
        final num? ca = existing['ccy_amount'] as num?;
        final num? fr = existing['fx_rate'] as num?;
        if (ca != null) ccyAmount.text = plain(ca);
        if (fr != null) rate.text = plain(fr);
      }
    }
  }

  Future<void> resolveRate(String dateIso) async {
    final String? c = ccy;
    if (c == null) return;
    final ({double rate, String date})? r = await FxLocal.rateAt(c, dateIso);
    rate.text = r == null ? '' : plain(r.rate);
    recompute();
  }

  /// amount (stored unit) = ccy_amount * rate / kFxRialPerStoredUnit.
  void recompute() {
    final double? ca = parseNum(ccyAmount.text);
    final double? r = parseNum(rate.text);
    if (!active || ca == null || r == null || ca <= 0 || r <= 0) return;
    final double v = (ca * r / kFxRialPerStoredUnit * 100).roundToDouble() / 100;
    MoneyField.setStored(amount, v);
    recomputeShare(); // v93
  }

  String? validate() {
    if (needsShare && (parseNum(share.text) ?? 0) <= 0) return 'سهم این ردیف به ارز فاکتور ($docCcy) را وارد کنید'; // v93
    if (!active) return null;
    final double? ca = parseNum(ccyAmount.text);
    final double? r = parseNum(rate.text);
    if (ca == null || ca <= 0) return 'مبلغ ارزی را وارد کنید';
    if (r == null || r <= 0) return 'نرخ ارز را وارد کنید (یا ابتدا نرخ را در «نرخ ارز» ثبت و همگام کنید)';
    return null;
  }

  Map<String, dynamic> fields() {
    // v93: سهم به ارز فاکتور (یا پاک شدنش وقتی دیگر لازم نیست)
    final Map<String, dynamic> sh = docCcy == null
        ? <String, dynamic>{}
        : <String, dynamic>{'doc_ccy_amount': needsShare ? parseNum(share.text) : null, 'doc_ccy_mode': needsShare ? shareMode : null};
    if (!active) return sh;
    return <String, dynamic>{
      'ccy': ccy,
      'ccy_amount': parseNum(ccyAmount.text),
      'fx_rate': parseNum(rate.text),
      ...sh,
    };
  }

  void dispose() {
    ccyAmount.dispose();
    rate.dispose();
    share.dispose();
  }
}

/// Currency picker + foreign amount + editable rate. Put it just above the rial amount field.
class FxTxFields extends StatelessWidget {
  final FxTxController c;
  final String dateIso;
  final VoidCallback onChanged;
  const FxTxFields({super.key, required this.c, required this.dateIso, required this.onChanged});

  /// v93: سهم این ردیف به ارز فاکتور — «نرخ روز» (خودکار) یا «مبلغ توافقی» (دستی)
  Widget _share(BuildContext context) {
    if (c.docRateDate != dateIso) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await c.resolveDocRate(dateIso);
        onChanged();
      });
    }
    final String d = FxTxController.docCcy ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text('فاکتور به $d است؛ این پرداخت چقدر از $d کم کند؟', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const <ButtonSegment<String>>[
            ButtonSegment<String>(value: 'rate', label: Text('طبق نرخ روز')),
            ButtonSegment<String>(value: 'agreed', label: Text('مبلغ توافقی')),
          ],
          selected: <String>{c.shareMode},
          onSelectionChanged: (Set<String> s) {
            c.shareMode = s.first;
            c.recomputeShare();
            onChanged();
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: c.share,
          readOnly: c.shareMode == 'rate',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'سهم به ارز فاکتور ($d)',
            border: const OutlineInputBorder(),
            helperText: c.shareMode == 'rate'
                ? (c.docRate > 0 ? 'ارزش ریالی این ردیف ÷ نرخ روز $d (${faNum(c.docRate, dec: 0)})' : 'نرخ روز $d برای این تاریخ ثبت نشده؛ «مبلغ توافقی» را بزنید یا نرخ را ثبت کنید')
                : 'مقداری که با طرف‌حساب توافق کرده‌اید',
          ),
          onChanged: (_) => onChanged(),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!c.available) return c.needsShare ? _share(context) : const SizedBox.shrink();
    final List<Widget> w = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String?>(
          value: c.ccy,
          decoration: const InputDecoration(labelText: 'ارز', border: OutlineInputBorder()),
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(value: null, child: Text('ریال')),
            for (final Map<String, dynamic> cur in c.currencies)
              DropdownMenuItem<String?>(value: cur['code'] as String, child: Text('${cur['name'] ?? ''} (${cur['code']})')),
          ],
          onChanged: (String? v) async {
            c.ccy = v;
            if (v == null) {
              c.ccyAmount.clear();
              c.rate.clear();
            } else {
              await c.resolveRate(dateIso);
            }
            onChanged();
          },
        ),
      ),
    ];
    if (c.active) {
      w.add(numField(c.ccyAmount, 'مبلغ ارزی', required: true, thousands: true, onChanged: () {
        c.recompute();
        onChanged();
      }));
      w.add(numField(c.rate, 'نرخ (ریال به ازای هر واحد)', required: true, thousands: true, onChanged: () {
        c.recompute();
        onChanged();
      }));
      w.add(const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('مبلغ زیر معادل ریالی (ریال) است و از مبلغ ارزی × نرخ پر می‌شود؛ در صورت نیاز می‌توانید ریال واقعاً دریافتی/پرداختی را اصلاح کنید.',
            style: TextStyle(color: Colors.black54, fontSize: 12)),
      ));
    }
    if (c.needsShare) w.add(_share(context)); // v93
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: w);
  }
}
