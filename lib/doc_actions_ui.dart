// v91 p3 — جزئیات خرید/فروش در «همان فرم ثبت» به حالت قفل (فقط‌خواندنی) + همهٔ کارهای سند در پایین فرم.
// قبلاً این کارها روی برگهٔ جزئیات (خرید)، کارت (فروش) و منوی سه‌نقطه بود؛ حالا یک‌جا در PurchaseDocActions / SaleDocActions.
// فایل مشترک اندروید و ویندوز. مجوزها: StaffPerms.can (سرور هر اکشن را دوباره بررسی می‌کند).
import 'package:flutter/material.dart';

import 'barcode_utils.dart';
import 'broker_ui.dart';
import 'grade_lines_ui.dart' show GradeCostRows;
import 'vouchers_links.dart';
import 'correction_ui.dart' show showCorrectionDialog;
import 'db.dart';
import 'fmt.dart' show Fmt;
import 'invoice_service.dart';
import 'license_service.dart';
import 'notify_service.dart';
import 'payment_screen.dart';
import 'pdf_output.dart';
import 'pdf_service.dart';
import 'perms.dart';
import 'receipt_screen.dart';
import 'settle_ui.dart' show openDocPayment; // v92 · v94
import 'returns_ui.dart';
import 'sale_export_ui.dart';
import 'utils.dart';
import 'weigh_docs_pdf.dart';
import 'weigh_print_menu.dart' show weighPrintMenu;
import 'widgets.dart';

/// کلید کارهای قابل نمایش برای یک خرید (خالص؛ آزمون: test/doc_actions_test.dart). ترتیب = ترتیب دکمه‌ها.
/// [can] = StaffPerms.I.can (در آزمون جایگزین می‌شود). [isMix] = کوت/خروجی (دلال و برگشت ندارد).
List<String> purchaseActionKeys({required bool isMix, required bool Function(String) can, bool isFx = false}) => <String>[
      if (can('payments.save') || can('purchases.create')) 'payment',
      'cartex',
      'weigh_slip',
      'waybill',
      'invoice',
      if (!isMix && can('purchases.create')) 'broker',
      if (!isMix && can('purchases.return')) 'return',
      if (can('purchases.create')) 'correction',
      if (can('purchases.delete')) 'delete',
    ];

/// کلید کارهای قابل نمایش برای یک فروش.
List<String> saleActionKeys({required bool Function(String) can, bool isFx = false}) => <String>[
      if (can('receipts.save') || can('sales.create') || can('sales.update')) 'receipt',
      'invoice',
      'weigh_slip',
      'waybill',
      if (can('sales.create')) 'broker',
      if (isFx && can('sales.view')) 'export',
      if (can('sales.return')) 'return',
      if (can('sales.update')) 'correction',
      if (can('sales.delete')) 'delete',
    ];

/// آیا کاربر می‌تواند فرم قفل را با «ویرایش» باز کند؟ (خرید: purchases.create؛ فروش: sales.update)
bool canUnlockPurchase(bool Function(String) can) => can('purchases.create');
bool canUnlockSale(bool Function(String) can) => can('sales.update');

bool _isMixDoc(Map<String, dynamic> p) => p['is_mix'] == true || '${p['is_mix']}' == '1'; // کوت (مثل برگهٔ قبلی)

/// نوار بالای فرم در حالت قفل: «فقط‌خواندنی» + دکمهٔ «ویرایش» (اگر مجوز دارد).
class LockedFormBanner extends StatelessWidget {
  const LockedFormBanner({super.key, required this.canEdit, required this.onEdit});
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(children: <Widget>[
          Icon(Icons.lock_outline, color: cs.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(child: Text(canEdit ? 'نمایش سند (قفل). برای تغییر «ویرایش» را بزنید.' : 'نمایش سند (فقط‌خواندنی)', style: TextStyle(color: cs.onSecondaryContainer))),
          if (canEdit) FilledButton.icon(key: const ValueKey<String>('unlock_edit'), onPressed: onEdit, icon: const Icon(Icons.edit_outlined), label: const Text('ویرایش')),
        ]),
      ),
    );
  }
}

/// محتوای فرم در حالت قفل: هیچ لمسی به فیلدها نمی‌رسد (FieldGate و قفل‌های دسترسی داخل آن همچنان کار می‌کنند).
class LockedFields extends StatelessWidget {
  const LockedFields({super.key, required this.locked, required this.child});
  final bool locked;
  final Widget child;
  @override
  Widget build(BuildContext context) => AbsorbPointer(absorbing: locked, child: child);
}


Widget _btn(String key, IconData icon, String label, VoidCallback onTap, {bool filled = false}) => filled
    ? FilledButton.icon(key: ValueKey<String>('act_$key'), onPressed: onTap, icon: Icon(icon), label: Text(label))
    : OutlinedButton.icon(key: ValueKey<String>('act_$key'), onPressed: onTap, icon: Icon(icon), label: Text(label));

/// کارهای یک خرید (پایین فرم خرید در حالت قفل). [onDeleted]: بعد از حذف موفق (فرم را می‌بندد).
class PurchaseDocActions extends StatelessWidget {
  const PurchaseDocActions({super.key, required this.doc, this.onDeleted});
  final Map<String, dynamic> doc;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> p = doc;
    final List<String> keys = purchaseActionKeys(isMix: _isMixDoc(p), can: StaffPerms.I.can, isFx: LicenseService.I.isFx.value);
    final List<Widget> out = <Widget>[];
    for (final String k in keys) {
      switch (k) {
        case 'payment':
          // v94: یک دکمه ⇒ شناسنامه‌های این خرید + «پرداخت» تازه (روش قدیمی انتخاب نوع پرداخت حذف شد)
          out.add(_btn(k, Icons.payments_outlined, 'پرداخت', filled: true, () => openDocPayment(context, isPurchase: true, docId: p['id'] as int,
              legacy: () => PaymentScreen(purchaseId: p['id'] as int, purchaseLabel: '${p['category_name'] ?? ''} - ${p['type_name'] ?? ''}'))));
        case 'cartex':
          out.add(_btn(k, Icons.picture_as_pdf_outlined, 'دریافت کارتکس A6', () async {
            final file = await PdfService.buildStockCard(
              code: p['code'] as String? ?? '-',
              totalWeight: ((p['total_weight'] as num?) ?? 0).toDouble(),
              netWeight: ((p['net_weight'] as num?) ?? 0).toDouble(),
              smallSacks: ((p['small_sack_count'] as num?) ?? 0).toDouble(),
              largeSacks: ((p['large_sack_count'] as num?) ?? 0).toDouble(),
            );
            if (context.mounted) await PdfOutput.show(context, file);
          }));
        case 'weigh_slip':
          out.add(weighPrintMenu(context, 'رسید باسکول', (WeighPaper w) async {
            final f = await WeighDocs.buildSlip(p, paper: w);
            if (context.mounted) await PdfOutput.show(context, f);
          }));
        case 'waybill':
          out.add(weighPrintMenu(context, 'بارنامه', (WeighPaper w) async {
            final f = await WeighDocs.buildWaybill(p, paper: w, items: <Map<String, dynamic>>[
              <String, dynamic>{'type_name': p['type_name'], 'code': p['code'], 'weight': p['net_weight'], 'sacks': '${p['small_sack_count'] ?? 0} / ${p['large_sack_count'] ?? 0}'},
            ]);
            if (context.mounted) await PdfOutput.show(context, f);
          }));
        case 'invoice':
          out.add(_btn(k, Icons.receipt_long_outlined, 'فاکتور خرید', () => InvoiceService.forPurchase(context, p)));
        case 'broker':
          out.add(_btn(k, Icons.handshake_outlined, 'دلال / کمیسیون', () => openBrokerDialog(context, isSale: false, doc: p)));
        case 'return':
          out.add(_btn(k, Icons.assignment_return_outlined, 'برگشت از خرید', () => openPurchaseReturn(context, p)));
        case 'correction':
          out.add(_btn(k, Icons.rule_outlined, 'سند اصلاحی (فی/وزن)', () => showCorrectionDialog(context, docType: 'purchase', id: p['id'] as int, price: (p['price'] as num?) ?? 0, netWeight: (p['net_weight'] as num?) ?? 0)));
        case 'delete':
          out.add(_btn(k, Icons.delete_outline, 'حذف', () async {
            if (await deletePurchaseFlow(context, p)) onDeleted?.call();
          }));
      }
    }
    final String code = p['code'] as String? ?? '-';
    final List<String> inMix = ((p['in_mix_codes'] as List?) ?? const <dynamic>[]).cast<String>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      // اطلاعاتی که فقط نمایشی است (برگهٔ جزئیات قبلی): کد و بارکد، مانده، گونی مانده، داخل کوت، بهای درجه‌ها، اسناد حسابداری
      sectionTitle(context, 'وضعیت سند'),
      infoRow('کد پسته', code),
      BarcodeBox(code),
      infoRow('مانده در انبار (خالص)', '${faNum(((p['remaining'] as num?) ?? 0))} کیلو'),
      infoRow('گونی کوچک مانده', faNum((p['small_sacks_remaining'] as num?) ?? 0)),
      infoRow('گونی بزرگ مانده', faNum((p['large_sacks_remaining'] as num?) ?? 0)),
      if (inMix.isNotEmpty) infoRow('داخل مخلوط/جداسازی (هنوز فروش نرفته)', inMix.join('، ')),
      GradeCostRows(docType: 'purchase', docId: p['id'] as int), // S35.T35.3c
      LocalDocVoucherLinks(mapKind: 'pur', localId: p['id'] as int, sourceType: 'purchase'),
      _ActionsCard(children: out),
    ]);
  }
}

/// کارهای یک فروش (پایین فرم فروش در حالت قفل). [doc] همان ردیف فهرست فروش (با items).
class SaleDocActions extends StatelessWidget {
  const SaleDocActions({super.key, required this.doc, this.onDeleted});
  final Map<String, dynamic> doc;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> sale = doc;
    final int id = sale['id'] as int;
    final List<String> keys = saleActionKeys(can: StaffPerms.I.can, isFx: LicenseService.I.isFx.value);
    final List<Widget> out = <Widget>[];
    for (final String k in keys) {
      switch (k) {
        case 'receipt':
          // v94: یک دکمه ⇒ شناسنامه‌های این فروش + «وصول» تازه (روش قدیمی انتخاب نوع دریافت حذف شد)
          out.add(_btn(k, Icons.request_quote_outlined, 'وصول', filled: true, () => openDocPayment(context, isPurchase: false, docId: id,
              legacy: () => ReceiptScreen(saleId: id, saleLabel: sale['buyer'] != null ? '${sale['buyer']}' : jalaliDate(sale['date'] as String)))));
        case 'invoice':
          out.add(_btn(k, Icons.receipt_long_outlined, 'فاکتور فروش', () => InvoiceService.forSale(context, sale)));
        case 'weigh_slip':
          out.add(weighPrintMenu(context, 'رسید باسکول', (WeighPaper w) async {
            final f = await WeighDocs.buildSlip(sale, paper: w);
            if (context.mounted) await PdfOutput.show(context, f);
          }));
        case 'waybill':
          out.add(weighPrintMenu(context, 'بارنامه', (WeighPaper w) async {
            final f = await WeighDocs.buildWaybill(sale, paper: w, items: <Map<String, dynamic>>[
              <String, dynamic>{'type_name': sale['type_name'], 'code': sale['code'], 'weight': sale['net_weight'] ?? sale['weight'], 'sacks': '${sale['small_sack_count'] ?? 0} / ${sale['large_sack_count'] ?? 0}'},
            ]);
            if (context.mounted) await PdfOutput.show(context, f);
          }));
        case 'broker':
          out.add(_btn(k, Icons.handshake_outlined, 'دلال / کمیسیون', () => openBrokerDialog(context, isSale: true, doc: sale)));
        case 'export':
          out.add(_btn(k, Icons.local_shipping_outlined, 'اطلاعات صادراتی', () async {
            final int? sid = await AppDb.I.serverIdOf('sale', id);
            if (!context.mounted) return;
            if (sid == null) {
              snack(context, 'ابتدا همگام‌سازی شود');
              return;
            }
            Navigator.push(context, MaterialPageRoute<void>(builder: (_) => SaleExportScreen(saleId: sid)));
          }));
        case 'return':
          out.add(_btn(k, Icons.assignment_return_outlined, 'برگشت از فروش', () => openSaleReturn(context, sale)));
        case 'correction':
          out.add(_btn(k, Icons.rule_outlined, 'سند اصلاحی (فی/وزن)', () => showCorrectionDialog(context, docType: 'sale', id: id, price: (sale['price'] as num?) ?? 0, netWeight: (sale['net_weight'] as num?) ?? 0)));
        case 'delete':
          out.add(_btn(k, Icons.delete_outline, 'حذف', () async {
            if (await deleteSaleFlow(context, id)) onDeleted?.call();
          }));
      }
    }
    final List<dynamic> items = (sale['items'] as List?) ?? const <dynamic>[];
    final String code = items.isEmpty ? '-' : ((items.first as Map)['code'] as String?) ?? '-';
    final double net = ((sale['net_weight'] as num?) ?? 0).toDouble(), price = ((sale['price'] as num?) ?? 0).toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      sectionTitle(context, 'وضعیت سند'),
      infoRow('کد پسته', code),
      for (final String c in printableCodesIn(code)) BarcodeBox(c, height: 44),
      if (StaffPerms.I.canPriceIn('sales') && StaffPerms.I.fieldShown('sale.price')) infoRow('مبلغ فروش', Fmt.money(net * price)),
      LocalDocVoucherLinks(mapKind: 'sale', localId: id, sourceType: 'sale'),
      _ActionsCard(children: out),
    ]);
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        sectionTitle(context, 'کارهای این سند'),
        Wrap(spacing: 8, runSpacing: 8, children: children),
      ]),
    );
  }
}

/// حذف خرید (با دلیل) + لغو یادآورهای اقساط/چک. true = حذف شد.
Future<bool> deletePurchaseFlow(BuildContext context, Map<String, dynamic> p) async {
  final String? reason = await askDeleteReason(context, 'این خرید حذف شود؟'); // S35.T35.9a
  if (reason == null) return false;
  final pay = await AppDb.I.paymentOf(p['id'] as int);
  var creditIds = <int>[], chequeIds = <int>[];
  if (pay != null) {
    final payId = pay['id'] as int;
    creditIds = (await AppDb.I.creditInstList(payId)).map((r) => r['id'] as int).toList();
    chequeIds = (await AppDb.I.chequeInstList(payId)).map((r) => r['id'] as int).toList();
  }
  final ok = await AppDb.I.deletePurchase(p['id'] as int, reason: reason);
  if (ok) {
    for (final id in creditIds) {
      await NotifyService.I.cancelCreditRow(id);
    }
    for (final id in chequeIds) {
      await NotifyService.I.cancelChequeRow(id);
    }
  } else if (context.mounted) {
    snack(context, 'از این خرید فروش، کوت یا برگشت ثبت شده؛ ابتدا آن سندها را حذف کنید');
  }
  return ok;
}

/// حذف فروش (با دلیل) + لغو یادآورهای اقساط/چک دریافتی. true = حذف شد.
Future<bool> deleteSaleFlow(BuildContext context, int id) async {
  final String? reason = await askDeleteReason(context, 'این فروش حذف شود؟ وزن و گونی‌ها به انبار برمی‌گردند.'); // S35.T35.9a
  if (reason == null) return false;
  final rec = await AppDb.I.receiptOf(id);
  var creditIds = <int>[], chequeIds = <int>[];
  if (rec != null) {
    final recId = rec['id'] as int;
    creditIds = (await AppDb.I.receiptCreditInstList(recId)).map((r) => r['id'] as int).toList();
    chequeIds = (await AppDb.I.receiptChequeInstList(recId)).map((r) => r['id'] as int).toList();
  }
  await AppDb.I.deleteSale(id, reason: reason);
  for (final cid in creditIds) {
    await NotifyService.I.cancelReceiptCreditRow(cid);
  }
  for (final cid in chequeIds) {
    await NotifyService.I.cancelReceiptChequeRow(cid);
  }
  return true;
}
