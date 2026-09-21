import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'utils.dart';
import 'widgets.dart';

class PurchaseForm extends StatefulWidget {
  const PurchaseForm({super.key});
  @override
  State<PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends State<PurchaseForm> {
  final _form = GlobalKey<FormState>();
  String _cat = 'dombest';
  int? _typeId;
  List<Map<String, dynamic>> _types = [];
  String? _photo;

  final _ounce = TextEditingController();
  final _price = TextEditingController();
  final _total = TextEditingController();
  final _sackCount = TextEditingController(text: '1');
  final _sackWeight = TextEditingController(text: '0');
  final _gram = TextEditingController();
  final _pctKhandan = TextEditingController(); // درصد خندان در دنبست
  final _pctDombest = TextEditingController(); // درصد دنبست در خندان
  final _pctTuchin = TextEditingController();
  final _pctCrooked = TextEditingController();
  final _seller = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  List<Map<String, dynamic>> _typesOf(String c) =>
      _types.where((t) => t['category'] == c).toList();

  Future<void> _loadTypes({int? select}) async {
    final t = await AppDb.I.types();
    if (!mounted) return;
    setState(() {
      _types = t;
      final list = _typesOf(_cat);
      _typeId = select ?? (list.isNotEmpty ? list.first['id'] as int : null);
    });
  }

  double get _tare =>
      (parseNum(_sackCount.text) ?? 0) * (parseNum(_sackWeight.text) ?? 0);
  double get _net => (parseNum(_total.text) ?? 0) - _tare;

  Future<void> _addType() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('افزودن نوع جدید به «${kCategories[_cat]}»'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'نام نوع'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('افزودن')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final id = await AppDb.I.addType(_cat, name);
    await _loadTypes(select: id);
  }

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1280, imageQuality: 80);
    if (x == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dest = p.join(dir.path, 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(x.path).copy(dest);
    if (mounted) setState(() => _photo = dest);
  }

  void _photoSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('گرفتن عکس'),
            onTap: () {
              Navigator.pop(ctx);
              _pick(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('انتخاب از گالری'),
            onTap: () {
              Navigator.pop(ctx);
              _pick(ImageSource.gallery);
            },
          ),
          if (_photo != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('حذف عکس'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _photo = null);
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_typeId == null) {
      snack(context, 'نوع پسته را انتخاب کنید');
      return;
    }
    if (_net <= 0) {
      snack(context, 'وزن خالص باید بیشتر از صفر باشد');
      return;
    }
    final isDom = _cat == 'dombest';
    final isKha = _cat == 'khandan';
    await AppDb.I.insertPurchase({
      'type_id': _typeId,
      'date': DateTime.now().toIso8601String(),
      'photo': _photo,
      'ounce': parseNum(_ounce.text),
      'price': parseNum(_price.text),
      'total_weight': parseNum(_total.text),
      'sack_count': parseNum(_sackCount.text) ?? 0,
      'sack_weight': parseNum(_sackWeight.text) ?? 0,
      'net_weight': _net,
      'gram': isDom ? parseNum(_gram.text) : null,
      'pct_khandan': isDom ? parseNum(_pctKhandan.text) : null,
      'pct_dombest': isKha ? parseNum(_pctDombest.text) : null,
      'pct_tuchin': isKha ? parseNum(_pctTuchin.text) : null,
      'pct_crooked': (isDom || isKha) ? parseNum(_pctCrooked.text) : null,
      'seller': _seller.text.trim().isEmpty ? null : _seller.text.trim(),
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final list = _typesOf(_cat);
    return Scaffold(
      appBar: AppBar(title: const Text('خرید جدید')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            sectionTitle(context, 'نوع پسته'),
            DropdownButtonFormField<String>(
              value: _cat,
              decoration: const InputDecoration(labelText: 'دسته', border: OutlineInputBorder()),
              items: kCategories.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _cat = v;
                  final l = _typesOf(v);
                  _typeId = l.isNotEmpty ? l.first['id'] as int : null;
                });
              },
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('$_cat-$_typeId'),
                  value: _typeId,
                  decoration:
                      const InputDecoration(labelText: 'نوع', border: OutlineInputBorder()),
                  items: list
                      .map((t) =>
                          DropdownMenuItem(value: t['id'] as int, child: Text(t['name'] as String)))
                      .toList(),
                  onChanged: (v) => setState(() => _typeId = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _addType,
                icon: const Icon(Icons.add),
                tooltip: 'افزودن نوع جدید',
              ),
            ]),
            const SizedBox(height: 16),
            sectionTitle(context, 'عکس نمونه (اختیاری)'),
            InkWell(
              onTap: _photoSheet,
              child: Container(
                height: 140,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: _photo == null
                    ? const Center(child: Icon(Icons.add_a_photo_outlined, size: 36))
                    : Image.file(File(_photo!), fit: BoxFit.cover, width: double.infinity),
              ),
            ),
            const SizedBox(height: 16),
            sectionTitle(context, 'قیمت و وزن'),
            numField(_ounce, 'انس پسته'),
            numField(_price, 'فی خرید (تومان به ازای هر کیلو)', required: true),
            numField(_total, 'وزن کل (کیلو)',
                required: true, onChanged: () => setState(() {})),
            Row(children: [
              Expanded(
                  child: numField(_sackCount, 'تعداد گونی', onChanged: () => setState(() {}))),
              const SizedBox(width: 8),
              Expanded(
                  child: numField(_sackWeight, 'وزن هر گونی (کیلو)',
                      onChanged: () => setState(() {}))),
            ]),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  infoRow('وزن گونی‌ها', '${faNum(_tare)} کیلو'),
                  infoRow('وزن خالص', '${faNum(_net)} کیلو'),
                  infoRow('ارزش کل', '${faNum(_net * (parseNum(_price.text) ?? 0), dec: 0)} تومان'),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            if (_cat == 'dombest') ...[
              sectionTitle(context, 'مشخصات پسته دنبست'),
              numField(_gram, 'گرم'),
              numField(_pctKhandan, 'درصد پسته خندان در دنبست', suffix: '٪', max: 100),
              numField(_pctCrooked, 'درصد پسته کج / ناخالص', suffix: '٪', max: 100),
            ],
            if (_cat == 'khandan') ...[
              sectionTitle(context, 'مشخصات پسته خندان'),
              numField(_pctDombest, 'درصد دنبست در پسته خندان', suffix: '٪', max: 100),
              numField(_pctTuchin, 'درصد توچین', suffix: '٪', max: 100),
              numField(_pctCrooked, 'درصد پسته کج / ناخالص', suffix: '٪', max: 100),
            ],
            sectionTitle(context, 'سایر'),
            textField(_seller, 'فروشنده (اختیاری)'),
            textField(_note, 'توضیحات (اختیاری)', lines: 2),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('ثبت خرید'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
