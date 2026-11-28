import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// v96: خوانندهٔ سادهٔ xlsx (فقط مقدار خانه‌ها) برای وقتی که پکیج excel روی فایل می‌شکند.
/// excel 4.0.6 رشته‌های مشترک تکراری (مثلاً چند خانهٔ خالی "") را یکی می‌کند ⇒ اندیس‌ها جابه‌جا و
/// «Null check operator used on a null value». این‌جا هر <si> به ترتیب خودش خوانده می‌شود.
class XlsxReader {
  XlsxReader._();

  /// First worksheet as rows of trimmed strings (missing cells = '').
  static List<List<String>> firstSheet(Uint8List bytes) {
    final Archive zip = ZipDecoder().decodeBytes(bytes);
    String? read(String path) {
      final ArchiveFile? f = zip.findFile(path);
      if (f == null) return null;
      return utf8.decode(f.content as List<int>, allowMalformed: true);
    }

    final List<String> shared = <String>[];
    final String? ss = read('xl/sharedStrings.xml');
    if (ss != null) {
      for (final XmlElement si in XmlDocument.parse(ss).findAllElements('si')) {
        // متن‌های <r><t> (rich text) کنار هم؛ <rPh> (آوانویسی) نه
        shared.add(si.descendantElements.where((XmlElement e) => e.name.local == 't' && e.parentElement?.name.local != 'rPh').map((XmlElement e) => e.innerText).join());
      }
    }

    final String sheetPath = _firstSheetPath(read) ?? 'xl/worksheets/sheet1.xml';
    final String? sheet = read(sheetPath);
    if (sheet == null) throw Exception('برگهٔ اول فایل اکسل پیدا نشد');

    final List<List<String>> out = <List<String>>[];
    for (final XmlElement row in XmlDocument.parse(sheet).findAllElements('row')) {
      final int rIdx = (int.tryParse(row.getAttribute('r') ?? '') ?? (out.length + 1)) - 1;
      while (out.length < rIdx) {
        out.add(<String>[]);
      }
      final List<String> cells = <String>[];
      for (final XmlElement c in row.findElements('c')) {
        final int col = _col(c.getAttribute('r')) ?? cells.length;
        while (cells.length < col) {
          cells.add('');
        }
        final String t = c.getAttribute('t') ?? 'n';
        final String v = c.getElement('v')?.innerText ?? '';
        String val;
        switch (t) {
          case 's':
            final int? i = int.tryParse(v.trim());
            val = (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
          case 'inlineStr':
            val = c.findAllElements('t').map((XmlElement e) => e.innerText).join();
          case 'b':
            val = v.trim() == '1' ? 'TRUE' : 'FALSE';
          default:
            val = v;
        }
        if (cells.length == col) {
          cells.add(val.trim());
        } else {
          cells[col] = val.trim();
        }
      }
      if (out.length == rIdx) {
        out.add(cells);
      } else if (rIdx >= 0 && rIdx < out.length) {
        out[rIdx] = cells;
      }
    }
    return out;
  }

  static String? _firstSheetPath(String? Function(String) read) {
    final String? wb = read('xl/workbook.xml');
    final String? rels = read('xl/_rels/workbook.xml.rels');
    if (wb == null || rels == null) return null;
    final XmlElement? first = XmlDocument.parse(wb).findAllElements('sheet').firstOrNull;
    final String? rid = first?.attributes.where((XmlAttribute a) => a.name.local == 'id').map((XmlAttribute a) => a.value).firstOrNull;
    if (rid == null) return null;
    for (final XmlElement r in XmlDocument.parse(rels).findAllElements('Relationship')) {
      if (r.getAttribute('Id') == rid) {
        final String target = r.getAttribute('Target') ?? '';
        if (target.startsWith('/')) return target.substring(1);
        return 'xl/$target';
      }
    }
    return null;
  }

  /// "C12" ⇒ 2 (0-based column).
  static int? _col(String? ref) {
    if (ref == null) return null;
    int n = 0;
    bool any = false;
    for (final int u in ref.toUpperCase().codeUnits) {
      if (u < 65 || u > 90) break;
      n = n * 26 + (u - 64);
      any = true;
    }
    return any ? n - 1 : null;
  }
}
