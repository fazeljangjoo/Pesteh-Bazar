import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_service.dart';
import 'proforma_model.dart';

/// v96 — خروجی پیش‌فاکتور صادراتی: PDF (چاپ/اشتراک) و Word (.docx) با همان چیدمان و رنگ‌های قالب.
class PfExport {
  PfExport._();

  static String fileBase(PfData d) {
    final String n = d.number.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return 'Proforma_Invoice_${n.isEmpty ? DateTime.now().millisecondsSinceEpoch : n}';
  }

  // ============================== PDF ==============================

  static Future<File> pdf(PfData d) async {
    await PdfService.ensureFonts();
    final Uint8List bytes = await pdfBytes(d, theme: PdfService.theme());
    final Directory dir = await getTemporaryDirectory();
    final File f = File(p.join(dir.path, '${fileBase(d)}.pdf'));
    await f.writeAsBytes(bytes);
    return f;
  }

  static Future<Uint8List> pdfBytes(PfData d, {pw.ThemeData? theme}) async {
    final PdfColor primary = PdfColor.fromHex(d.cPrimary), accent = PdfColor.fromHex(d.cAccent);
    final PdfColor light = PdfColor.fromHex(d.cLight), tag = PdfColor.fromHex(d.cTagline);
    const PdfColor ink = PdfColor.fromInt(0xFF222222);
    final PdfColor footerInk = PdfColor.fromHex('4F6228');
    final Uint8List? logo = d.logoBytes;
    final pw.Document doc = pw.Document(theme: theme);
    final pw.TableBorder border = pw.TableBorder.all(color: PdfColor.fromHex('BFBFBF'), width: 0.5);

    pw.Widget heading(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
        child: pw.Text(t, style: pw.TextStyle(color: primary, fontSize: 11, fontWeight: pw.FontWeight.bold)));
    pw.Widget cell(String t, {PdfColor? bg, PdfColor? color, bool bold = false, double size = 9, pw.TextAlign align = pw.TextAlign.left}) => pw.Container(
        color: bg,
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: pw.Text(t, textAlign: align, style: pw.TextStyle(color: color ?? ink, fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)));
    pw.Widget head(String t) => cell(t, bg: primary, color: PdfColors.white, bold: true, size: 9.5, align: pw.TextAlign.center);
    pw.Widget label(String t) => cell(t, bg: light, color: primary, bold: true);
    pw.Widget bullets(List<String> l) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
          for (final String s in l.where((String s) => s.trim().isNotEmpty))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
                pw.Container(width: 4, height: 4, margin: const pw.EdgeInsets.only(top: 4, right: 7), decoration: pw.BoxDecoration(color: primary, shape: pw.BoxShape.circle)),
                pw.Expanded(child: pw.Text(s, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))),
              ]),
            ),
        ]);

    final List<PfItem> items = d.items.where((PfItem i) => i.type.trim().isNotEmpty || i.qty > 0 || i.price > 0).toList();
    final List<PfPair> pay = d.payment.where((PfPair e) => e.label.trim().isNotEmpty || e.value.trim().isNotEmpty).toList();
    final List<PfPair> info = d.info.where((PfPair e) => e.label.trim().isNotEmpty || e.value.trim().isNotEmpty).toList();
    final List<PfPair> bank = d.bank.where((PfPair e) => e.label.trim().isNotEmpty || e.value.trim().isNotEmpty).toList();
    final List<PfPair> qual = d.quality.where((PfPair e) => e.label.trim().isNotEmpty || e.value.trim().isNotEmpty).toList();
    final String c = d.ccy.toUpperCase();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 24),
      footer: (pw.Context ctx) => d.footer.trim().isEmpty
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Container(alignment: pw.Alignment.center, child: pw.Text(d.footer, textAlign: pw.TextAlign.center, style: pw.TextStyle(color: footerInk, fontSize: 8.5)))),
      build: (pw.Context ctx) => <pw.Widget>[
        // ---- سربرگ ----
        pw.Table(defaultVerticalAlignment: pw.TableCellVerticalAlignment.full, columnWidths: const <int, pw.TableColumnWidth>{0: pw.FlexColumnWidth(1.6), 1: pw.FlexColumnWidth(1)}, children: <pw.TableRow>[
          pw.TableRow(children: <pw.Widget>[
            pw.Container(
              color: primary,
              padding: const pw.EdgeInsets.all(10),
              child: pw.Row(children: <pw.Widget>[
                if (logo != null)
                  pw.Container(
                      width: 52, height: 52, margin: const pw.EdgeInsets.only(right: 10), color: PdfColors.white, padding: const pw.EdgeInsets.all(3),
                      child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain)),
                pw.Expanded(
                    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: <pw.Widget>[
                  pw.Text(d.company, style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  if (d.tagline.trim().isNotEmpty) pw.Text(d.tagline, style: pw.TextStyle(color: tag, fontSize: 9)),
                ])),
              ]),
            ),
            pw.Container(
              color: accent,
              padding: const pw.EdgeInsets.all(10),
              alignment: pw.Alignment.centerRight,
              child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, crossAxisAlignment: pw.CrossAxisAlignment.end, children: <pw.Widget>[
                pw.Text(d.title, style: pw.TextStyle(color: PdfColors.white, fontSize: 15, fontWeight: pw.FontWeight.bold)),
                if (d.number.trim().isNotEmpty) pw.Text('No. ${d.number}', style: const pw.TextStyle(color: PdfColors.white, fontSize: 12)),
              ]),
            ),
          ]),
        ]),
        pw.SizedBox(height: 10),
        // ---- تاریخ / فروشنده / خریدار ----
        pw.Table(defaultVerticalAlignment: pw.TableCellVerticalAlignment.full, border: border, columnWidths: const <int, pw.TableColumnWidth>{0: pw.FixedColumnWidth(80), 1: pw.FlexColumnWidth()}, children: <pw.TableRow>[
          if (d.date.isNotEmpty) pw.TableRow(children: <pw.Widget>[label('Date'), cell(pfDate(d.date))]),
          if (d.seller.trim().isNotEmpty) pw.TableRow(children: <pw.Widget>[label('Seller'), cell(d.seller)]),
          if (d.buyer.trim().isNotEmpty) pw.TableRow(children: <pw.Widget>[label('Buyer'), cell(d.buyer)]),
        ]),
        // ---- اقلام ----
        if (items.isNotEmpty) ...<pw.Widget>[
          heading('PISTACHIO DESCRIPTION'),
          pw.Table(defaultVerticalAlignment: pw.TableCellVerticalAlignment.full, border: border, children: <pw.TableRow>[
            pw.TableRow(children: <pw.Widget>[head('Pistachio Type'), head('Grade'), head('Ounce'), head('Weight'), head('Price per kg ($c)'), head('Total ($c)')]),
            for (final PfItem i in items)
              pw.TableRow(children: <pw.Widget>[
                cell(i.type, bold: true, align: pw.TextAlign.center),
                cell(i.grade, align: pw.TextAlign.center),
                cell(i.ounce, align: pw.TextAlign.center),
                cell('${pfQty(i.qty)} ${i.unit}', align: pw.TextAlign.center),
                cell(pfUnitPrice(i.price, c), align: pw.TextAlign.center),
                cell(pfMoney(i.total, c), bold: true, align: pw.TextAlign.center),
              ]),
            if (items.length > 1)
              pw.TableRow(children: <pw.Widget>[
                label('TOTAL'), cell(''), cell(''),
                cell('${pfQty(items.fold<double>(0, (double s, PfItem i) => s + i.kg) / 1000)} MT', bold: true, align: pw.TextAlign.center),
                cell(''),
                cell(pfMoney(d.total, c), bold: true, align: pw.TextAlign.center),
              ]),
          ]),
        ],
        // ---- شرایط پرداخت ----
        if (pay.isNotEmpty) ...<pw.Widget>[
          heading('PAYMENT TERMS'),
          for (int s = 0; s < pay.length; s += 4) // حداکثر ۴ ستون در هر ردیف جدول
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Table(defaultVerticalAlignment: pw.TableCellVerticalAlignment.full, border: border, children: <pw.TableRow>[
                pw.TableRow(children: <pw.Widget>[for (final PfPair e in pay.skip(s).take(4)) head(e.label)]),
                pw.TableRow(children: <pw.Widget>[for (final PfPair e in pay.skip(s).take(4)) cell(pfPayValue(e.value, c), align: pw.TextAlign.center)]),
              ]),
            ),
        ],
        if (info.isNotEmpty) ...<pw.Widget>[
          pw.SizedBox(height: 10),
          pw.Table(defaultVerticalAlignment: pw.TableCellVerticalAlignment.full, border: border, columnWidths: const <int, pw.TableColumnWidth>{0: pw.FixedColumnWidth(110), 1: pw.FlexColumnWidth()}, children: <pw.TableRow>[
            for (final PfPair e in info) pw.TableRow(children: <pw.Widget>[label(e.label), cell(e.value)]),
          ]),
        ],
        // ---- بانک ----
        if (bank.isNotEmpty) ...<pw.Widget>[
          heading('BANK INFORMATION'),
          pw.Table(defaultVerticalAlignment: pw.TableCellVerticalAlignment.full, border: border, columnWidths: const <int, pw.TableColumnWidth>{0: pw.FixedColumnWidth(110), 1: pw.FlexColumnWidth()}, children: <pw.TableRow>[
            for (final PfPair e in bank) pw.TableRow(children: <pw.Widget>[label(e.label), cell(e.value)]),
          ]),
        ],
        // ---- مشخصات کیفی (دو جفت در هر ردیف) ----
        if (qual.isNotEmpty) ...<pw.Widget>[
          heading('QUALITY SPECIFICATIONS'),
          pw.Table(defaultVerticalAlignment: pw.TableCellVerticalAlignment.full, border: border, columnWidths: const <int, pw.TableColumnWidth>{
            0: pw.FlexColumnWidth(1.3), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1.3), 3: pw.FlexColumnWidth(1),
          }, children: <pw.TableRow>[
            pw.TableRow(children: <pw.Widget>[head('Parameter'), head('Limit'), head('Parameter'), head('Limit')]),
            for (int r = 0; r < qual.length; r += 2)
              pw.TableRow(children: <pw.Widget>[
                label(qual[r].label),
                cell(qual[r].value),
                if (r + 1 < qual.length) label(qual[r + 1].label) else cell(''),
                if (r + 1 < qual.length) cell(qual[r + 1].value) else cell(''),
              ]),
          ]),
        ],
        if (d.conditions.any((String s) => s.trim().isNotEmpty)) ...<pw.Widget>[heading('IMPORTANT CONDITIONS'), bullets(d.conditions)],
        if (d.documents.any((String s) => s.trim().isNotEmpty)) ...<pw.Widget>[heading('DOCUMENTS'), bullets(d.documents)],
        // ---- امضا ----
        pw.SizedBox(height: 40),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: <pw.Widget>[
          for (final String s in <String>[d.signLeft, d.signRight])
            pw.Column(children: <pw.Widget>[
              pw.Text(s, style: pw.TextStyle(color: primary, fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 36),
              pw.Container(width: 150, height: 0.6, color: PdfColor.fromHex('999999')),
            ]),
        ]),
      ],
    ));
    return doc.save();
  }

  // ============================== Word (.docx) ==============================

  static Future<File> docx(PfData d) async {
    final Directory dir = await getTemporaryDirectory();
    final File f = File(p.join(dir.path, '${fileBase(d)}.docx'));
    await f.writeAsBytes(docxBytes(d));
    return f;
  }

  static String _x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  /// یک run؛ خط جدید ⇒ <w:br/>
  static String _r(String t, {bool b = false, String? color, int sz = 19}) {
    final String pr = '<w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>${b ? '<w:b/>' : ''}'
        '${color != null ? '<w:color w:val="$color"/>' : ''}<w:sz w:val="$sz"/><w:szCs w:val="$sz"/></w:rPr>';
    final List<String> lines = t.split('\n');
    final StringBuffer o = StringBuffer('<w:r>$pr');
    for (int i = 0; i < lines.length; i++) {
      if (i > 0) o.write('<w:br/>');
      o.write('<w:t xml:space="preserve">${_x(lines[i])}</w:t>');
    }
    o.write('</w:r>');
    return o.toString();
  }

  static String _p(String runs, {String align = 'left', int before = 0, int after = 0}) =>
      '<w:p><w:pPr><w:spacing w:before="$before" w:after="$after"/><w:jc w:val="$align"/></w:pPr>$runs</w:p>';

  static String _tc(String content, int w, {String? fill}) => '<w:tc><w:tcPr><w:tcW w:w="$w" w:type="dxa"/>'
      '${fill != null ? '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>' : ''}'
      '<w:tcMar><w:top w:w="60" w:type="dxa"/><w:bottom w:w="60" w:type="dxa"/></w:tcMar></w:tcPr>$content</w:tc>';

  static String _tbl(List<int> widths, List<String> rows, {bool borders = true}) {
    final String b = borders ? 'single" w:sz="4" w:space="0" w:color="BFBFBF' : 'nil';
    return '<w:tbl><w:tblPr><w:tblW w:w="${widths.fold<int>(0, (int s, int w) => s + w)}" w:type="dxa"/><w:tblLayout w:type="fixed"/>'
        '<w:tblBorders><w:top w:val="$b"/><w:left w:val="$b"/><w:bottom w:val="$b"/><w:right w:val="$b"/><w:insideH w:val="$b"/><w:insideV w:val="$b"/></w:tblBorders>'
        '<w:tblCellMar><w:left w:w="90" w:type="dxa"/><w:right w:w="90" w:type="dxa"/></w:tblCellMar></w:tblPr>'
        '<w:tblGrid>${widths.map((int w) => '<w:gridCol w:w="$w"/>').join()}</w:tblGrid>${rows.join()}</w:tbl>';
  }

  static String _tr(List<String> cells) => '<w:tr><w:trPr><w:cantSplit/></w:trPr>${cells.join()}</w:tr>';

  /// (عرض، ارتفاع) تصویر PNG یا JPEG؛ null = نامشخص
  static (int, int)? _imgSize(Uint8List b) {
    if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50) {
      final ByteData bd = ByteData.sublistView(b);
      return (bd.getUint32(16), bd.getUint32(20));
    }
    if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
      int i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) return null;
        final int m = b[i + 1];
        final int len = (b[i + 2] << 8) + b[i + 3];
        if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) return ((b[i + 7] << 8) + b[i + 8], (b[i + 5] << 8) + b[i + 6]);
        i += 2 + len;
      }
    }
    return null;
  }

  static Uint8List docxBytes(PfData d) {
    const int full = 10466; // A4 منهای حاشیه‌ها (twips)
    final String c = d.ccy.toUpperCase();
    final String pri = d.cPrimary, acc = d.cAccent, lig = d.cLight, tag = d.cTagline;
    const String ink = '222222';
    final Uint8List? logo = d.logoBytes;
    final bool png = logo != null && logo.length > 1 && logo[0] == 0x89;
    String head(String t, int w) => _tc(_p(_r(t, b: true, color: 'FFFFFF', sz: 19), align: 'center'), w, fill: pri);
    String label(String t, int w) => _tc(_p(_r(t, b: true, color: pri)), w, fill: lig);
    String val(String t, int w, {bool b = false, String align = 'left'}) => _tc(_p(_r(t, b: b, color: ink), align: align), w);
    String heading(String t) => _p(_r(t, b: true, color: pri, sz: 22), before: 220, after: 80);
    String bullets(List<String> l) => l
        .where((String s) => s.trim().isNotEmpty)
        .map((String s) => '<w:p><w:pPr><w:spacing w:after="60"/><w:ind w:left="360" w:hanging="240"/></w:pPr>${_r('•  ', b: true, color: pri, sz: 20)}${_r(s, b: true, sz: 20)}</w:p>')
        .join();
    bool has(PfPair e) => e.label.trim().isNotEmpty || e.value.trim().isNotEmpty;

    // لوگو (درون سلول سبز سربرگ)
    String logoXml = '';
    if (logo != null) {
      final (int, int) sz = _imgSize(logo) ?? (1, 1);
      const int h = 640080; // ۰٫۷ اینچ
      final int w = (h * sz.$1 / (sz.$2 == 0 ? 1 : sz.$2)).round().clamp(200000, 1600000);
      logoXml = '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="$w" cy="$h"/><wp:docPr id="1" name="Logo"/>'
          '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
          '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="1" name="logo"/><pic:cNvPicPr/></pic:nvPicPr>'
          '<pic:blipFill><a:blip r:embed="rIdLogo"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
          '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$w" cy="$h"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
          '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';
    }

    final StringBuffer body = StringBuffer();
    // سربرگ
    body.write(_tbl(<int>[6466, 4000], <String>[
      _tr(<String>[
        _tc(
            '${logoXml.isEmpty ? '' : _p(logoXml)}${_p(_r(d.company, b: true, color: 'FFFFFF', sz: 36))}'
            '${d.tagline.trim().isEmpty ? '' : _p(_r(d.tagline, color: tag, sz: 18))}',
            6466,
            fill: pri),
        _tc('${_p(_r(d.title, b: true, color: 'FFFFFF', sz: 30), align: 'right')}${d.number.trim().isEmpty ? '' : _p(_r('No. ${d.number}', color: 'FFFFFF', sz: 24), align: 'right')}', 4000,
            fill: acc),
      ]),
    ], borders: false));
    body.write(_p('', after: 120));
    body.write(_tbl(<int>[1700, full - 1700], <String>[
      if (d.date.isNotEmpty) _tr(<String>[label('Date', 1700), val(pfDate(d.date), full - 1700)]),
      if (d.seller.trim().isNotEmpty) _tr(<String>[label('Seller', 1700), val(d.seller, full - 1700)]),
      if (d.buyer.trim().isNotEmpty) _tr(<String>[label('Buyer', 1700), val(d.buyer, full - 1700)]),
    ]));

    final List<PfItem> items = d.items.where((PfItem i) => i.type.trim().isNotEmpty || i.qty > 0 || i.price > 0).toList();
    if (items.isNotEmpty) {
      const List<int> w = <int>[1900, 1300, 1300, 1500, 2066, 2400];
      body.write(heading('PISTACHIO DESCRIPTION'));
      body.write(_tbl(w, <String>[
        _tr(<String>[head('Pistachio Type', w[0]), head('Grade', w[1]), head('Ounce', w[2]), head('Weight', w[3]), head('Price per kg ($c)', w[4]), head('Total ($c)', w[5])]),
        for (final PfItem i in items)
          _tr(<String>[
            val(i.type, w[0], b: true, align: 'center'),
            val(i.grade, w[1], align: 'center'),
            val(i.ounce, w[2], align: 'center'),
            val('${pfQty(i.qty)} ${i.unit}', w[3], align: 'center'),
            val(pfUnitPrice(i.price, c), w[4], align: 'center'),
            val(pfMoney(i.total, c), w[5], b: true, align: 'center'),
          ]),
        if (items.length > 1)
          _tr(<String>[
            label('TOTAL', w[0]), val('', w[1]), val('', w[2]),
            val('${pfQty(items.fold<double>(0, (double s, PfItem i) => s + i.kg) / 1000)} MT', w[3], b: true, align: 'center'),
            val('', w[4]), val(pfMoney(d.total, c), w[5], b: true, align: 'center'),
          ]),
      ]));
    }
    final List<PfPair> pay = d.payment.where(has).toList();
    if (pay.isNotEmpty) {
      body.write(heading('PAYMENT TERMS'));
      for (int s = 0; s < pay.length; s += 4) {
        final List<PfPair> chunk = pay.skip(s).take(4).toList();
        final int cw = full ~/ chunk.length;
        final List<int> w = List<int>.filled(chunk.length, cw);
        body.write(_tbl(w, <String>[
          _tr(<String>[for (final PfPair e in chunk) head(e.label, cw)]),
          _tr(<String>[for (final PfPair e in chunk) val(pfPayValue(e.value, c), cw, align: 'center')]),
        ]));
      }
    }
    final List<PfPair> info = d.info.where(has).toList();
    if (info.isNotEmpty) {
      body.write(_p('', after: 120));
      body.write(_tbl(<int>[2300, full - 2300], <String>[for (final PfPair e in info) _tr(<String>[label(e.label, 2300), val(e.value, full - 2300)])]));
    }
    final List<PfPair> bank = d.bank.where(has).toList();
    if (bank.isNotEmpty) {
      body.write(heading('BANK INFORMATION'));
      body.write(_tbl(<int>[2300, full - 2300], <String>[for (final PfPair e in bank) _tr(<String>[label(e.label, 2300), val(e.value, full - 2300)])]));
    }
    final List<PfPair> q = d.quality.where(has).toList();
    if (q.isNotEmpty) {
      const List<int> w = <int>[3033, 2200, 3033, 2200];
      body.write(heading('QUALITY SPECIFICATIONS'));
      body.write(_tbl(w, <String>[
        _tr(<String>[head('Parameter', w[0]), head('Limit', w[1]), head('Parameter', w[2]), head('Limit', w[3])]),
        for (int r = 0; r < q.length; r += 2)
          _tr(<String>[
            label(q[r].label, w[0]),
            val(q[r].value, w[1]),
            if (r + 1 < q.length) label(q[r + 1].label, w[2]) else val('', w[2]),
            if (r + 1 < q.length) val(q[r + 1].value, w[3]) else val('', w[3]),
          ]),
      ]));
    }
    if (d.conditions.any((String s) => s.trim().isNotEmpty)) body.write('${heading('IMPORTANT CONDITIONS')}${bullets(d.conditions)}');
    if (d.documents.any((String s) => s.trim().isNotEmpty)) body.write('${heading('DOCUMENTS')}${bullets(d.documents)}');
    body.write(_p('', after: 600));
    body.write(_tbl(<int>[4233, 2000, 4233], <String>[
      _tr(<String>[
        _tc('${_p(_r(d.signLeft, b: true, color: pri, sz: 22), align: 'center')}${_p('', after: 600)}${_p(_r('______________________', color: '999999'), align: 'center')}', 4233),
        _tc(_p(''), 2000),
        _tc('${_p(_r(d.signRight, b: true, color: pri, sz: 22), align: 'center')}${_p('', after: 600)}${_p(_r('______________________', color: '999999'), align: 'center')}', 4233),
      ]),
    ], borders: false));

    const String ns = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"';
    final bool hasFooter = d.footer.trim().isNotEmpty;
    final String document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document $ns><w:body>$body'
        '<w:sectPr>${hasFooter ? '<w:footerReference w:type="default" r:id="rIdFooter"/>' : ''}'
        '<w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" w:header="360" w:footer="360" w:gutter="0"/></w:sectPr>'
        '</w:body></w:document>';
    final String footer = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:ftr $ns>${_p(_r(d.footer, color: '4F6228', sz: 17), align: 'center')}</w:ftr>';
    final String rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '${hasFooter ? '<Relationship Id="rIdFooter" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>' : ''}'
        '${logo != null ? '<Relationship Id="rIdLogo" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/logo.${png ? 'png' : 'jpeg'}"/>' : ''}'
        '</Relationships>';
    const String styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri" w:eastAsia="Calibri"/><w:sz w:val="20"/><w:szCs w:val="20"/>'
        '<w:lang w:val="en-US"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="252" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>';
    final String types = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="png" ContentType="image/png"/><Default Extension="jpeg" ContentType="image/jpeg"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '${hasFooter ? '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>' : ''}'
        '</Types>';
    const String rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>';

    final Archive a = Archive();
    void add(String path, List<int> bytes) => a.addFile(ArchiveFile(path, bytes.length, bytes));
    add('[Content_Types].xml', utf8.encode(types));
    add('_rels/.rels', utf8.encode(rootRels));
    add('word/document.xml', utf8.encode(document));
    add('word/styles.xml', utf8.encode(styles));
    add('word/_rels/document.xml.rels', utf8.encode(rels));
    if (hasFooter) add('word/footer1.xml', utf8.encode(footer));
    if (logo != null) add('word/media/logo.${png ? 'png' : 'jpeg'}', logo);
    final List<int>? out = ZipEncoder().encode(a);
    return Uint8List.fromList(out ?? <int>[]);
  }
}
