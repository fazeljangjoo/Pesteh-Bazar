import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/proforma_export.dart';
import 'package:pesteh_bazar/proforma_model.dart';
import 'package:xml/xml.dart';

/// v96: پیش‌فاکتور صادراتی — مدل، جمع، قالب‌بندی، و خروجی Word/PDF.
PfData _doc() => PfData.sample()
  ..company = 'MAJD PISTACHIOS'
  ..number = '3126'
  ..date = '2026-11-02'
  ..buyer = 'T.M. S.R.L.\nBergamo, Italy'
  ..items = <PfItem>[PfItem(type: 'Akbari', grade: 'AA', ounce: '22-24', qty: 10, unit: 'MT', price: 17), PfItem(type: 'Fandoghi', qty: 500, unit: 'kg', price: 12.5)]
  ..payment = <PfPair>[PfPair('Deposit', '30000'), PfPair('Upon Preparation', '146250')];

void main() {
  test('totals, MT/kg and formatting', () {
    final PfData d = _doc();
    expect(d.items[0].total, 170000);
    expect(d.items[1].total, 6250);
    expect(d.total, 176250);
    expect(pfMoney(170000, 'USD'), r'$170,000.00');
    expect(pfUnitPrice(17, 'USD'), r'$17');
    expect(pfUnitPrice(12.5, 'EUR'), '€12.50');
    expect(pfDate('2026-11-02'), '02/11/2026');
    expect(pfPayValue('30000', 'USD'), r'$30,000.00');
    expect(pfPayValue('On delivery', 'USD'), 'On delivery');
  });

  test('json round trip keeps every section and caps rows at 20', () {
    final PfData d = _doc()..documents = List<String>.generate(25, (int i) => 'Doc $i');
    final PfData r = PfData.fromJson(jsonDecode(jsonEncode(d.toJson())));
    expect(r.items.length, 2);
    expect(r.items[1].unit, 'kg');
    expect(r.quality.length, d.quality.length);
    expect(r.documents.length, kPfMaxRows);
    expect(r.number, '3126');
    expect(PfData.fromJson(d.toJson(withLogo: false)).logo, isEmpty);
  });

  test('docx is a valid package with the invoice text', () {
    final Uint8List b = PfExport.docxBytes(_doc());
    final Archive a = ZipDecoder().decodeBytes(b);
    final String xml = utf8.decode(a.findFile('word/document.xml')!.content as List<int>);
    XmlDocument.parse(xml); // well-formed
    XmlDocument.parse(utf8.decode(a.findFile('word/footer1.xml')!.content as List<int>));
    XmlDocument.parse(utf8.decode(a.findFile('[Content_Types].xml')!.content as List<int>));
    for (final String t in <String>['MAJD PISTACHIOS', 'PROFORMA INVOICE', 'No. 3126', '02/11/2026', 'PISTACHIO DESCRIPTION', r'$170,000.00',
      'PAYMENT TERMS', 'BANK INFORMATION', 'QUALITY SPECIFICATIONS', 'IMPORTANT CONDITIONS', 'DOCUMENTS', 'Certificate of Origin', '2F4A2B', 'B08D3C']) {
      expect(xml.contains(t), isTrue, reason: t);
    }
    expect(xml.contains('TOTAL'), isTrue); // بیش از یک ردیف ⇒ ردیف جمع
  });

  test('pdf is produced', () async {
    final Uint8List b = await PfExport.pdfBytes(_doc());
    expect(String.fromCharCodes(b.take(4)), '%PDF');
  });
}
