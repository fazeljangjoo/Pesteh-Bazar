// v90 — باگ «نام شرکت/مشتری الزامی است» هنگام ثبت فروش: ذخیرهٔ چندفیلدی روی ردیف موجود (تغییر مرحله، تأیید فروش، سپردن، پیگیری بعدی)
// باید فیلدهای الزامیِ دست‌نخورده را از ردیف ذخیره‌شده بگیرد، مثل سرور. روی EntityStore و MkStore واقعی با SQLite در حافظه.
import 'package:flutter_test/flutter_test.dart';
import 'package:pesteh_bazar/db.dart';
import 'package:pesteh_bazar/entity_store.dart';
import 'package:pesteh_bazar/marketing_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database d;

  setUp(() async {
    d = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDb.I.debugCreate(d);
    AppDb.I.debugUseDb(d);
  });
  tearDown(() async => d.close());

  test('recording a sale moves the card to «فروش» (was: «نام شرکت/مشتری» الزامی است)', () async {
    final String lead = await MkStore.I.saveLead(<String, dynamic>{'name': 'Al Noor Trading', 'country': 'AE', 'stage': 'negotiation'});
    final String sale = await MkStore.I.saveSale(lead, <String, dynamic>{'date': '2026-11-21', 'tons': 50, 'deal_value': 740000, 'ccy': 'USD', 'product': 'خندان', 'collected': true, 'collected_at': '2026-11-22'});
    expect((await MkStore.I.lead(lead))!['stage'], 'won');
    expect((await MkStore.I.lead(lead))!['name'], 'Al Noor Trading');
    expect((await MkStore.I.sales(leadUid: lead)).single['uid'], sale);
  });

  test('saving the same sale again (retry with the same uid) updates it instead of adding a second sale', () async {
    final String lead = await MkStore.I.saveLead(<String, dynamic>{'name': 'Muze'});
    final String uid = EntityStore.newUid();
    await MkStore.I.saveSale(lead, <String, dynamic>{'date': '2026-11-21', 'tons': 10}, uid: uid);
    await MkStore.I.saveSale(lead, <String, dynamic>{'date': '2026-11-21', 'tons': 12}, uid: uid);
    final List<Map<String, dynamic>> s = await MkStore.I.sales(leadUid: lead);
    expect(s.length, 1);
    expect(s.single['tons'], 12);
    expect(s.single['staff_name'], isNotNull); // first save stamped as new
  });

  test('stage change, follow-up date, assign and sale approval all work on stored rows', () async {
    final String lead = await MkStore.I.saveLead(<String, dynamic>{'name': 'Kevin Foods'});
    await MkStore.I.changeStage(lead, 'lost', lostReason: 'price');
    expect((await MkStore.I.lead(lead))!['stage'], 'lost');
    await MkStore.I.changeStage(lead, 'contacted');
    await MkStore.I.addActivity(lead, kind: 'proforma', result: 'sent', next: DateTime(2026, 12, 1));
    final Map<String, dynamic> l = (await MkStore.I.lead(lead))!;
    expect(l['stage'], 'proforma');
    expect('${l['next_followup_at']}', startsWith('2026-12-01'));
    await MkStore.I.assign(lead, 5, 'سارا');
    expect((await MkStore.I.lead(lead))!['owner_name'], 'سارا');
    final String sale = await MkStore.I.saveSale(lead, <String, dynamic>{'date': '2026-11-21', 'tons': 3});
    await MkStore.I.setSaleStatus(sale, 'confirmed');
    expect((await MkStore.I.sales(leadUid: lead)).single['status'], 'confirmed');
  });

  test('a new card still needs a name, and clearing a required field is still an error', () async {
    expect(() => MkStore.I.saveLead(<String, dynamic>{'country': 'TR'}), throwsArgumentError);
    final String lead = await MkStore.I.saveLead(<String, dynamic>{'name': 'X Co'});
    expect(() => EntityStore.I.save('mk_leads', <String, dynamic>{'name': '  '}, uid: lead), throwsArgumentError);
    expect((await MkStore.I.lead(lead))!['name'], 'X Co'); // rolled back
  });
}
