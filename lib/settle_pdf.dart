// v92 — چاپ «شناسنامهٔ پرداخت/وصول»: رسید یک مرحله (A5) و کل شناسنامه (A4). همان فونت/خروجی بقیهٔ PDFها (PdfService + PdfOutput).
import 'dart:io';

import 'package:flutter/material.dart' show BuildContext;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'company_profile.dart';
import 'excel_io.dart';
import 'pdf_output.dart';
import 'pdf_service.dart';
import 'settle_calc.dart';
import 'settle_data.dart';
import 'settle_ui.dart';
import 'utils.dart';
import 'widgets.dart';

pw.Widget _kv(String k, String v, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
        pw.SizedBox(width: 150, child: pw.Text(pdfText(k), style: const pw.TextStyle(fontSize: 9.5))),
        pw.Expanded(child: pw.Text(pdfText(v), style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
      ]),
    );

pw.Widget _table(List<List<String>> rows) => pw.Table.fromTextArray(
      headers: rows.first.map(pdfText).toList(),
      data: rows.skip(1).map((List<String> r) => r.map(pdfText).toList()).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignment: pw.Alignment.centerRight,
      headerAlignment: pw.Alignment.centerRight,
      border: pw.TableBorder.all(width: 0.4),
    );

Future<pw.Widget> _header(String title, String subtitle) async {
  CompanyProfile? cp;
  try {
    cp = await CompanyProfile.load();
  } catch (_) {}
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
    if ((cp?.name ?? '').isNotEmpty) pw.Text(pdfText(cp!.name), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
    pw.Text(pdfText(title), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
    if (subtitle.isNotEmpty) pw.Text(pdfText(subtitle), style: const pw.TextStyle(fontSize: 9)),
    pw.Text(pdfText('تاریخ چاپ: ${jalaliDateFromDt(DateTime.now())}'), style: const pw.TextStyle(fontSize: 8)),
    pw.Divider(),
  ]);
}

pw.Widget _signatures(String a, String b) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 24),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: <pw.Widget>[
        for (final String s in <String>[a, b])
          pw.Column(children: <pw.Widget>[
            pw.Text(pdfText('امضای $s'), style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 28),
            pw.Container(width: 120, height: 0.5, color: PdfColors.grey700),
          ]),
      ]),
    );

/// رسید یک مرحله (یا مرحلهٔ بعدیِ یک مرحله) — A5
Future<File> buildStagePdf(Trail t, TrailStage s, TrailNext? n, Map<String, String> accounts) async {
  await PdfService.ensureFonts();
  final pw.Document doc = pw.Document(theme: PdfService.theme());
  final List<(String, String)> rows = stageRows(t, s, n, accounts);
  final String no = n?.no ?? s.no;
  final pw.Widget head = await _header('رسید مرحلهٔ ${toFaDigits(no)} از شناسنامهٔ ${t.s.refNo.isEmpty ? '(تازه)' : t.s.refNo}',
      '${t.s.isRecv ? 'وصول از' : 'پرداخت به'} ${t.s.party} — ${stlAmount(t.s.ccy, t.s.amt4 / kQ)}');
  final String a = n == null ? s.from : (n.kind == 'we_paid_xch' ? 'ما' : n.exchanger);
  final String b = n == null ? s.to : (n.kind == 'we_paid_xch' ? n.exchanger : 'ما');
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    textDirection: pw.TextDirection.rtl,
    build: (pw.Context ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: <pw.Widget>[
      head,
      for (final (String k, String v) in rows) _kv(k, v),
      _signatures('پرداخت‌کننده ($a)', 'دریافت‌کننده ($b)'),
      pw.Spacer(),
      PdfService.brandFooter(),
    ]),
  ));
  final File f = await PdfService.saveDocument(doc, 'settle_stage_${DateTime.now().millisecondsSinceEpoch}.pdf');
  ExcelIo.register(f.path, 'مرحلهٔ $no', <List<String>>[for (final (String k, String v) in rows) <String>[k, v]]);
  return f;
}

/// کل شناسنامه — A4: خلاصه، تخصیص به فاکتورها، مراحل و مراحل بعدی، مصرف علی‌الحساب
Future<File> buildTrailPdf(Trail t, Map<String, String> accounts, String Function(String k) docLabel) async {
  await PdfService.ensureFonts();
  final pw.Document doc = pw.Document(theme: PdfService.theme());
  final String title = 'شناسنامهٔ ${t.s.isRecv ? 'وصول' : 'پرداخت'} ${t.s.refNo.isEmpty ? '(تازه)' : t.s.refNo}';
  final pw.Widget head = await _header(title, '${t.s.isRecv ? 'وصول از' : 'پرداخت به'} ${t.s.party}');
  final List<(String, String)> summary = <(String, String)>[
    ('مبلغ', stlAmount(t.s.ccy, t.s.amt4 / kQ)),
    ('تاریخ', jalaliDate(t.s.date)),
    ('وضعیت', t.complete ? 'کامل‌شده' : 'باز (بخشی هنوز نزد صراف یا علی‌الحساب است)'),
    ('ارزش دفتری تسویه‌شده', stlRial(t.res.carry)),
    if (t.res.adv4 > 0) ('علی‌الحساب', stlAmount(t.s.ccy, t.res.adv4 / kQ)),
    ('سود/زیان تفاوت نرخ (همهٔ مراحل)', stlGain(t.realized)),
    if ((t.s.note ?? '').isNotEmpty) ('توضیح', t.s.note!),
  ];
  final List<List<String>> alloc = <List<String>>[
    <String>['فاکتور', 'تاریخ', 'مبلغ فاکتور', 'سهم این شناسنامه', 'ماندهٔ فعلی'],
    for (final TrailAlloc a in t.alloc)
      <String>[a.doc.label, jalaliDate(a.doc.date), stlAmount(a.doc.ccy, a.doc.total4 / kQ), stlAmount(a.doc.ccy, a.q4 / kQ), stlAmount(a.doc.ccy, a.openAfter4 / kQ)],
  ];
  final List<List<String>> stages = <List<String>>[
    <String>['مرحله', 'تاریخ', 'مسیر', 'مبلغ', 'سهم از بدهی', 'نرخ', 'ارزش ریالی', 'سود/زیان', 'حساب/حواله'],
  ];
  for (final TrailStage s in t.stages) {
    final String acc = <String>[if (s.leg.accountUid != null) accounts[s.leg.accountUid] ?? '', if ((s.leg.ref ?? '').isNotEmpty) s.leg.ref!, if (s.leg.isCheque) 'چک ${s.leg.cheque?['no'] ?? ''} (${kChequeStatusFa[s.chequeStatus] ?? 'وضعیت نامعلوم'})'].join(' / '); // v92 فاز د
    stages.add(<String>[
      toFaDigits(s.no), jalaliDate(s.date), '${s.from} ← ${s.to}', stlAmount(s.leg.ccy, s.leg.amount), stlAmount(t.s.ccy, s.res.settle4 / kQ),
      s.leg.ccy == 'IRR' ? '' : faNum(s.leg.rate, dec: 0), stlRial(s.res.v), stlGain(s.realized), acc,
    ]);
    for (final TrailNext n in s.next) {
      stages.add(<String>[
        toFaDigits(n.no), jalaliDate(n.date),
        n.kind == 'xch_paid_us' ? '${n.exchanger} ← ما' : (n.kind == 'we_paid_xch' ? 'ما ← ${n.exchanger}' : n.exchanger),
        n.payAmount == null ? stlAmount(n.closedCcy, n.closed) : stlAmount(n.payCcy ?? 'IRR', n.payAmount!),
        stlAmount(n.closedCcy, n.closed), (n.payRate ?? 0) > 0 && (n.payCcy ?? 'IRR') != 'IRR' ? faNum(n.payRate!, dec: 0) : '',
        stlRial(n.value), stlGain(n.realized), (n.cashBox ?? n.bankAccount) == null ? '' : accounts[n.cashBox ?? n.bankAccount] ?? '',
      ]);
    }
    if (s.leg.isXch && s.open) stages.add(<String>['', '', 'هنوز نزد ${s.leg.exchanger}', stlAmount(s.leg.ccy, s.openAtExchanger), '', '', '', '', '']);
  }
  final List<List<String>> adv = <List<String>>[
    <String>['فاکتور', 'تاریخ', 'مبلغ', 'سود/زیان'],
    for (final StlAdvUse u in t.advUse) <String>[docLabel(u.k), jalaliDate(u.date), stlAmount(t.s.ccy, u.q4 / kQ), stlGain(u.realized)],
  ];
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    textDirection: pw.TextDirection.rtl,
    header: (pw.Context ctx) => ctx.pageNumber == 1 ? head : pw.SizedBox(),
    footer: (pw.Context ctx) => PdfService.brandFooter(),
    build: (pw.Context ctx) => <pw.Widget>[
      for (final (String k, String v) in summary) _kv(k, v, bold: true),
      if (alloc.length > 1) ...<pw.Widget>[pw.SizedBox(height: 10), pw.Text(pdfText('تخصیص به فاکتورها'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 4), _table(alloc)],
      pw.SizedBox(height: 10),
      pw.Text(pdfText('مراحل'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      _table(stages),
      if (adv.length > 1) ...<pw.Widget>[pw.SizedBox(height: 10), pw.Text(pdfText('مصرف علی‌الحساب'), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 4), _table(adv)],
      _signatures('تنظیم‌کننده', 'تأییدکننده'),
    ],
  ));
  final File f = await PdfService.saveDocument(doc, 'settle_trail_${DateTime.now().millisecondsSinceEpoch}.pdf');
  ExcelIo.register(f.path, title, <List<String>>[for (final (String k, String v) in summary) <String>[k, v], <String>[], ...alloc, <String>[], ...stages, <String>[], ...adv]);
  return f;
}

Future<void> printStage(BuildContext context, Trail t, TrailStage s, TrailNext? n, Map<String, String> accounts) async {
  try {
    final File f = await buildStagePdf(t, s, n, accounts);
    if (context.mounted) await PdfOutput.show(context, f);
  } catch (e) {
    if (context.mounted) snack(context, 'خطا در ساخت PDF: $e');
  }
}

Future<void> printTrail(BuildContext context, Trail t, Map<String, String> accounts) async {
  try {
    final StlState st = await loadStlState();
    final File f = await buildTrailPdf(t, accounts, st.docLabel);
    if (context.mounted) await PdfOutput.show(context, f);
  } catch (e) {
    if (context.mounted) snack(context, 'خطا در ساخت PDF: $e');
  }
}
