import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'utils.dart';

/// برچسب‌های جهت تراکنش که در جدول PDF نشان داده می‌شود
typedef DirectionLabels = ({String from, String fromName, String to, String toName});

/// مسیر فونت فارسی داخل assets پروژه — این دو فایل باید توسط خودتان اضافه شوند
/// (به README یا توضیحات پایین فایل مراجعه کنید). با این روش نیازی به اینترنت
/// در زمان اجرا نیست؛ فونت همراه خود اپ نصب می‌شود.
const String _kFontRegularAsset = 'assets/fonts/Vazirmatn-Regular.ttf';
const String _kFontBoldAsset = 'assets/fonts/Vazirmatn-Bold.ttf';

class PdfService {
  static pw.Font? _regular;
  static pw.Font? _bold;

  /// فونت فارسی را از assets داخل خود اپ بارگیری می‌کند (آفلاین، بدون اینترنت)
  static Future<void> _ensureFonts() async {
    if (_regular != null && _bold != null) return;
    try {
      final regularData = await rootBundle.load(_kFontRegularAsset);
      final boldData = await rootBundle.load(_kFontBoldAsset);
      _regular = pw.Font.ttf(regularData);
      _bold = pw.Font.ttf(boldData);
    } catch (e) {
      throw Exception(
          'فونت فارسی پیدا نشد. فایل‌های $_kFontRegularAsset و $_kFontBoldAsset را '
          'در پروژه قرار دهید و در pubspec.yaml به‌عنوان asset معرفی کنید.');
    }
  }

  static pw.ThemeData _theme() => pw.ThemeData.withFont(base: _regular, bold: _bold);

  static Future<File> _saveDoc(pw.Document doc, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static Future<void> share(File file) async {
    await Printing.sharePdf(bytes: await file.readAsBytes(), filename: p.basename(file.path));
  }

  static pw.Widget _kv(String k, String v, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(k, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(v, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  /// رسید تراکنش‌های پرداخت (خرید) یا دریافت (فروش) برای یک رکورد مشخص
  static Future<File> buildPaymentLedger({
    required String title,
    required String totalLabel,
    required double total,
    required double settled,
    required double remaining,
    required String? payType,
    required String? stagedType,
    required List<Map<String, dynamic>> lump,
    required List<Map<String, dynamic>> credit,
    required List<Map<String, dynamic>> cheque,
    required DirectionLabels directionLabels,
  }) async {
    await _ensureFonts();
    final doc = pw.Document(theme: _theme());
    final now = DateTime.now();

    List<List<String>> rows = [];
    if (payType == 'lump') {
      rows = [
        ['وضعیت', 'تاریخ', directionLabels.toName, directionLabels.fromName, 'مبلغ (تومان)'],
        for (final r in lump)
          [
            (r['paid'] as int? ?? 1) == 1 ? 'تسویه شده' : 'ثبت‌شده',
            jalaliDate(r['date'] as String),
            '${r['seller_name'] ?? '-'}',
            '${r['payer_name'] ?? '-'}',
            faNum(r['amount'] as num, dec: 0),
          ],
      ];
    } else if (payType == 'staged' && stagedType == 'credit') {
      rows = [
        ['وضعیت', 'سررسید', directionLabels.toName, directionLabels.fromName, 'مبلغ (تومان)'],
        for (final r in credit)
          [
            (r['paid'] as int) == 1 ? 'تسویه شده' : 'باقیمانده',
            jalaliDate(r['due_date'] as String),
            '${r['seller_name'] ?? '-'}',
            '${r['payer_name'] ?? '-'}',
            faNum(r['amount'] as num, dec: 0),
          ],
      ];
    } else if (payType == 'staged' && stagedType == 'cheque') {
      rows = [
        ['وضعیت', 'بانک', 'شماره چک', 'سررسید', 'مبلغ (تومان)'],
        for (final r in cheque)
          [
            (r['paid'] as int) == 1 ? 'تسویه شده' : 'باقیمانده',
            '${r['bank_name'] ?? '-'}',
            '${r['cheque_no'] ?? '-'}',
            jalaliDate(r['due_date'] as String),
            faNum(r['amount'] as num, dec: 0),
          ],
      ];
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text('تاریخ تهیه گزارش: ${jalaliDateFromDt(now)}', style: const pw.TextStyle(fontSize: 9)),
          pw.Divider(),
        ]),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(children: [
              _kv(totalLabel, '${faNum(total, dec: 0)} تومان', bold: true),
              _kv('تسویه شده', '${faNum(settled, dec: 0)} تومان'),
              _kv(remaining >= 0 ? 'باقیمانده' : 'اضافه‌پرداخت', '${faNum(remaining.abs(), dec: 0)} تومان'),
            ]),
          ),
          pw.SizedBox(height: 16),
          if (rows.length > 1)
            pw.Table.fromTextArray(
              headers: rows.first,
              data: rows.skip(1).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerRight,
              headerAlignment: pw.Alignment.centerRight,
              border: pw.TableBorder.all(width: 0.4),
            )
          else
            pw.Text('تراکنشی ثبت نشده است'),
        ],
      ),
    );

    final fname = 'ledger_${now.millisecondsSinceEpoch}.pdf';
    return _saveDoc(doc, fname);
  }

  /// گزارش کلی همه‌ی تراکنش‌های پرداخت یا دریافت در یک بازه‌ی زمانی
  static Future<File> buildGlobalReport({
    required String title,
    required String periodLabel,
    required double grandTotal,
    required List<List<String>> tableRows, // ردیف اول = عنوان ستون‌ها
  }) async {
    await _ensureFonts();
    final doc = pw.Document(theme: _theme());
    final now = DateTime.now();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(periodLabel, style: const pw.TextStyle(fontSize: 10)),
          pw.Text('تاریخ تهیه گزارش: ${jalaliDateFromDt(now)}', style: const pw.TextStyle(fontSize: 9)),
          pw.Divider(),
        ]),
        build: (ctx) => [
          _kv('جمع کل', '${faNum(grandTotal, dec: 0)} تومان', bold: true),
          pw.SizedBox(height: 12),
          if (tableRows.length > 1)
            pw.Table.fromTextArray(
              headers: tableRows.first,
              data: tableRows.skip(1).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerRight,
              headerAlignment: pw.Alignment.centerRight,
              border: pw.TableBorder.all(width: 0.4),
            )
          else
            pw.Text('در این بازه تراکنشی یافت نشد'),
        ],
      ),
    );

    final fname = 'report_${now.millisecondsSinceEpoch}.pdf';
    return _saveDoc(doc, fname);
  }
}
