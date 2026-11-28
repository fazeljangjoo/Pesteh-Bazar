import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/import_engine.dart';
import 'package:pesteh_bazar/xlsx_reader.dart';

/// v96: فایل اکسلی که چند رشتهٔ مشترک خالی/تکراری دارد (مثل ستون «مسئول» خالی) — پکیج excel با Null check می‌شکست.
Uint8List _xlsx() {
  final Archive a = Archive();
  void add(String p, String s) {
    final List<int> b = utf8.encode(s);
    a.addFile(ArchiveFile(p, b.length, b));
  }

  add('[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
          '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
          '</Types>');
  add('_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>');
  add('xl/workbook.xml',
      '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>');
  add('xl/_rels/workbook.xml.rels',
      '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
          '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/></Relationships>');
  // 0 نام | 1 مسئول | 2 '' | 3 Lead A | 4 '' (تکراری) | 5 Lead B | 6 امارات
  add('xl/sharedStrings.xml',
      '<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="7" uniqueCount="7">'
          '<si><t>نام</t></si><si><t>مسئول</t></si><si><t></t></si><si><t>Lead A</t></si><si><t></t></si><si><r><t>Lead</t></r><r><t> B</t></r></si><si><t>کشور</t></si></sst>');
  add('xl/worksheets/sheet1.xml',
      '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
          '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>6</v></c></row>'
          '<row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2" t="s"><v>2</v></c><c r="C2" t="inlineStr"><is><t>AE</t></is></c></row>'
          '<row r="4"><c r="A4" t="s"><v>5</v></c><c r="B4" t="s"><v>4</v></c><c r="C4"><v>12</v></c></row>'
          '</sheetData></worksheet>');
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

void main() {
  test('reader keeps every shared string in order (duplicate empties do not shift indices)', () {
    final List<List<String>> r = XlsxReader.firstSheet(_xlsx());
    expect(r[0], <String>['نام', 'مسئول', 'کشور']);
    expect(r[1], <String>['Lead A', '', 'AE']);
    expect(r[2], isEmpty); // ردیف ۳ در فایل نیست
    expect(r[3], <String>['Lead B', '', '12']);
  });

  test('ImportEngine.parse reads the file and an empty owner column gives no error', () {
    final ImpSheet s = ImportEngine.parse('leads.xlsx', _xlsx());
    final Map<String, int> map = ImportEngine.autoMap(kMkLeadImportKind, s.headers);
    final List<ImpRow> rows = ImportEngine.validate(kMkLeadImportKind, s, map);
    expect(rows.map((ImpRow e) => e.values['name']), <String>['Lead A', 'Lead B']);
    expect(rows.every((ImpRow e) => e.values['owner'] == null), isTrue);
    expect(rows.first.ok, isTrue);
  });
}
