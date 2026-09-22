import 'package:flutter/material.dart';

import 'db.dart';
import 'notify_service.dart';
import 'utils.dart';
import 'widgets.dart';

class PaymentScreen extends StatefulWidget {
  final int purchaseId;
  final String purchaseLabel;
  const PaymentScreen({super.key, required this.purchaseId, required this.purchaseLabel});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _loading = true;
  int? _paymentId;
  String? _payType; // lump | staged
  String? _stagedType; // credit | cheque

  List<Map<String, dynamic>> _lump = [];
  List<Map<String, dynamic>> _credit = [];
  List<Map<String, dynamic>> _cheque = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pay = await AppDb.I.paymentOf(widget.purchaseId);
    _paymentId = pay?['id'] as int?;
    _payType = pay?['pay_type'] as String?;
    _stagedType = pay?['staged_type'] as String?;
    if (_paymentId != null) {
      _lump = await AppDb.I.lumpTxList(_paymentId!);
      _credit = await AppDb.I.creditInstList(_paymentId!);
      _cheque = await AppDb.I.chequeInstList(_paymentId!);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setType(String payType, String? stagedType) async {
    _paymentId = await AppDb.I.setPaymentType(widget.purchaseId, payType, stagedType);
    setState(() {
      _payType = payType;
      _stagedType = stagedType;
    });
    await _load();
  }

  Future<void> _addLump() async {
    if (_lump.length >= kMaxLumpTx) {
      snack(context, 'حداکثر ${faNum(kMaxLumpTx)} تراکنش مجاز است');
      return;
    }
    final row = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _LumpForm(),
    );
    if (row == null) return;
    await AppDb.I.addLumpTx(_paymentId!, row);
    await _load();
  }

  Future<void> _editLump(Map<String, dynamic> existing) async {
    final row = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LumpForm(existing: existing),
    );
    if (row == null) return;
    await AppDb.I.updateLumpTx(existing['id'] as int, row);
    await _load();
  }

  Future<void> _addCredit() async {
    if (_credit.length >= kMaxStagedTx) {
      snack(context, 'حداکثر ${faNum(kMaxStagedTx)} قسط مجاز است');
      return;
    }
    final row = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreditForm(),
    );
    if (row == null) return;
    final id = await AppDb.I.addCreditInst(_paymentId!, row);
    if (id != null) {
      await NotifyService.I.scheduleCreditRow({...row, 'id': id});
    }
    await _load();
  }

  Future<void> _editCredit(Map<String, dynamic> existing) async {
    final row = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreditForm(existing: existing),
    );
    if (row == null) return;
    await AppDb.I.updateCreditInst(existing['id'] as int, row);
    if (row['paid'] == 1) {
      await NotifyService.I.cancelCreditRow(existing['id'] as int);
    } else {
      await NotifyService.I.scheduleCreditRow({...row, 'id': existing['id']});
    }
    await _load();
  }

  Future<void> _toggleCreditPaid(Map<String, dynamic> row, bool paid) async {
    final updated = Map<String, dynamic>.from(row)..remove('id')..remove('payment_id');
    updated['paid'] = paid ? 1 : 0;
    await AppDb.I.updateCreditInst(row['id'] as int, updated);
    if (paid) {
      await NotifyService.I.cancelCreditRow(row['id'] as int);
    } else {
      await NotifyService.I.scheduleCreditRow({...updated, 'id': row['id']});
    }
    await _load();
  }

  Future<void> _addCheque() async {
    if (_cheque.length >= kMaxStagedTx) {
      snack(context, 'حداکثر ${faNum(kMaxStagedTx)} چک مجاز است');
      return;
    }
    final row = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ChequeForm(),
    );
    if (row == null) return;
    final id = await AppDb.I.addChequeInst(_paymentId!, row);
    if (id != null) {
      await NotifyService.I.scheduleChequeRow({...row, 'id': id});
    }
    await _load();
  }

  Future<void> _editCheque(Map<String, dynamic> existing) async {
    final row = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChequeForm(existing: existing),
    );
    if (row == null) return;
    await AppDb.I.updateChequeInst(existing['id'] as int, row);
    if (row['paid'] == 1) {
      await NotifyService.I.cancelChequeRow(existing['id'] as int);
    } else {
      await NotifyService.I.scheduleChequeRow({...row, 'id': existing['id']});
    }
    await _load();
  }

  Future<void> _toggleChequePaid(Map<String, dynamic> row, bool paid) async {
    final updated = Map<String, dynamic>.from(row)..remove('id')..remove('payment_id');
    updated['paid'] = paid ? 1 : 0;
    await AppDb.I.updateChequeInst(row['id'] as int, updated);
    if (paid) {
      await NotifyService.I.cancelChequeRow(row['id'] as int);
    } else {
      await NotifyService.I.scheduleChequeRow({...updated, 'id': row['id']});
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('پرداخت — ${widget.purchaseLabel}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                sectionTitle(context, 'نوع پرداخت'),
                Card(
                  child: Column(children: [
                    RadioListTile<String>(
                      value: 'lump',
                      groupValue: _payType,
                      title: const Text('پرداخت یکجا'),
                      onChanged: (v) => _setType('lump', null),
                    ),
                    RadioListTile<String>(
                      value: 'staged',
                      groupValue: _payType,
                      title: const Text('پرداخت مرحله‌ای'),
                      onChanged: (v) => _setType('staged', _stagedType ?? 'credit'),
                    ),
                  ]),
                ),
                if (_payType == 'staged') ...[
                  const SizedBox(height: 8),
                  Card(
                    child: Column(children: [
                      RadioListTile<String>(
                        value: 'credit',
                        groupValue: _stagedType,
                        title: const Text('تسویه اعتباری (قسطی)'),
                        onChanged: (v) => _setType('staged', 'credit'),
                      ),
                      RadioListTile<String>(
                        value: 'cheque',
                        groupValue: _stagedType,
                        title: const Text('چک'),
                        onChanged: (v) => _setType('staged', 'cheque'),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),
                if (_payType == 'lump') _lumpSection(),
                if (_payType == 'staged' && _stagedType == 'credit') _creditSection(),
                if (_payType == 'staged' && _stagedType == 'cheque') _chequeSection(),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _lumpSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: sectionTitle(context, 'تراکنش‌های پرداخت یکجا (${faNum(_lump.length)}/${faNum(kMaxLumpTx)})')),
        IconButton(onPressed: _addLump, icon: const Icon(Icons.add_circle_outline)),
      ]),
      if (_lump.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('هنوز تراکنشی ثبت نشده')),
      for (final r in _lump)
        Card(
          child: ListTile(
            onTap: () => _editLump(r),
            title: Text('${faNum(r['amount'] as num, dec: 0)} تومان — ${jalaliDate(r['date'] as String)}'),
            subtitle: Text('از ${r['from_account'] ?? '-'} (${r['payer_name'] ?? '-'})\nبه ${r['to_account'] ?? '-'} (${r['seller_name'] ?? '-'})'),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'این تراکنش حذف شود؟')) {
                  await AppDb.I.deleteLumpTx(r['id'] as int);
                  await _load();
                }
              },
            ),
          ),
        ),
    ]);
  }

  Widget _creditSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: sectionTitle(context, 'اقساط اعتباری (${faNum(_credit.length)}/${faNum(kMaxStagedTx)})')),
        IconButton(onPressed: _addCredit, icon: const Icon(Icons.add_circle_outline)),
      ]),
      if (_credit.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('هنوز قسطی ثبت نشده')),
      for (final r in _credit)
        Card(
          child: ListTile(
            onTap: () => _editCredit(r),
            leading: Checkbox(
              value: (r['paid'] as int) == 1,
              onChanged: (v) => _toggleCreditPaid(r, v ?? false),
            ),
            title: Text('${faNum(r['amount'] as num, dec: 0)} تومان — سررسید ${jalaliDate(r['due_date'] as String)}'),
            subtitle: Text('از ${r['from_account'] ?? '-'} (${r['payer_name'] ?? '-'})\nبه ${r['to_account'] ?? '-'} (${r['seller_name'] ?? '-'})'
                '${(r['paid'] as int) == 1 ? '\nپرداخت شده' : ''}'),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'این قسط حذف شود؟')) {
                  await NotifyService.I.cancelCreditRow(r['id'] as int);
                  await AppDb.I.deleteCreditInst(r['id'] as int);
                  await _load();
                }
              },
            ),
          ),
        ),
    ]);
  }

  Widget _chequeSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: sectionTitle(context, 'چک‌ها (${faNum(_cheque.length)}/${faNum(kMaxStagedTx)})')),
        IconButton(onPressed: _addCheque, icon: const Icon(Icons.add_circle_outline)),
      ]),
      if (_cheque.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('هنوز چکی ثبت نشده')),
      for (final r in _cheque)
        Card(
          child: ListTile(
            onTap: () => _editCheque(r),
            leading: Checkbox(
              value: (r['paid'] as int) == 1,
              onChanged: (v) => _toggleChequePaid(r, v ?? false),
            ),
            title: Text('${faNum(r['amount'] as num, dec: 0)} تومان — سررسید ${jalaliDate(r['due_date'] as String)}'),
            subtitle: Text('چک ${r['cheque_no'] ?? '-'} — بانک ${r['bank_name'] ?? '-'}\n'
                'از ${r['from_account'] ?? '-'} (${r['payer_name'] ?? '-'}) به ${r['to_account'] ?? '-'} (${r['seller_name'] ?? '-'})'
                '${(r['paid'] as int) == 1 ? '\nپرداخت شده' : ''}'),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'این چک حذف شود؟')) {
                  await NotifyService.I.cancelChequeRow(r['id'] as int);
                  await AppDb.I.deleteChequeInst(r['id'] as int);
                  await _load();
                }
              },
            ),
          ),
        ),
    ]);
  }
}

// ------------------- فرم تراکنش یکجا -------------------
class _LumpForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _LumpForm({this.existing});
  @override
  State<_LumpForm> createState() => _LumpFormState();
}

class _LumpFormState extends State<_LumpForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _fromAccount;
  late final TextEditingController _payerName;
  late final TextEditingController _toAccount;
  late final TextEditingController _sellerName;
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(text: e == null ? '' : plain(e['amount'] as num));
    _fromAccount = TextEditingController(text: e?['from_account'] as String? ?? '');
    _payerName = TextEditingController(text: e?['payer_name'] as String? ?? '');
    _toAccount = TextEditingController(text: e?['to_account'] as String? ?? '');
    _sellerName = TextEditingController(text: e?['seller_name'] as String? ?? '');
    _date = e == null ? DateTime.now() : DateTime.parse(e['date'] as String);
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, {
      'amount': parseNum(_amount.text) ?? 0,
      'date': (_date ?? DateTime.now()).toIso8601String(),
      'from_account': _fromAccount.text.trim(),
      'payer_name': _payerName.text.trim(),
      'to_account': _toAccount.text.trim(),
      'seller_name': _sellerName.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.existing == null ? 'تراکنش جدید' : 'ویرایش تراکنش',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              numField(_amount, 'مبلغ (تومان)', required: true, thousands: true),
              dateField(context, 'تاریخ واریز', _date, (d) => setState(() => _date = d)),
              textField(_fromAccount, 'از کدام حساب'),
              textField(_payerName, 'به نام چه کسی (واریزکننده)'),
              textField(_toAccount, 'به کدام حساب فروشنده'),
              textField(_sellerName, 'به نام چه کسی (فروشنده)'),
              const SizedBox(height: 8),
              FilledButton(onPressed: _save, child: const Text('ذخیره')),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------- فرم قسط اعتباری -------------------
class _CreditForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _CreditForm({this.existing});
  @override
  State<_CreditForm> createState() => _CreditFormState();
}

class _CreditFormState extends State<_CreditForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _fromAccount;
  late final TextEditingController _payerName;
  late final TextEditingController _toAccount;
  late final TextEditingController _sellerName;
  DateTime? _due;
  bool _paid = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(text: e == null ? '' : plain(e['amount'] as num));
    _fromAccount = TextEditingController(text: e?['from_account'] as String? ?? '');
    _payerName = TextEditingController(text: e?['payer_name'] as String? ?? '');
    _toAccount = TextEditingController(text: e?['to_account'] as String? ?? '');
    _sellerName = TextEditingController(text: e?['seller_name'] as String? ?? '');
    _due = e == null ? DateTime.now() : DateTime.parse(e['due_date'] as String);
    _paid = e != null && (e['paid'] as int) == 1;
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    if (_due == null) {
      snack(context, 'سررسید را انتخاب کنید');
      return;
    }
    Navigator.pop(context, {
      'amount': parseNum(_amount.text) ?? 0,
      'due_date': _due!.toIso8601String(),
      'from_account': _fromAccount.text.trim(),
      'payer_name': _payerName.text.trim(),
      'to_account': _toAccount.text.trim(),
      'seller_name': _sellerName.text.trim(),
      'paid': _paid ? 1 : 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.existing == null ? 'قسط جدید' : 'ویرایش قسط', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              numField(_amount, 'مبلغ قسط (تومان)', required: true, thousands: true),
              dateField(context, 'تاریخ سررسید', _due, (d) => setState(() => _due = d)),
              textField(_fromAccount, 'از کدام حساب'),
              textField(_payerName, 'به نام چه کسی (واریزکننده)'),
              textField(_toAccount, 'به کدام حساب فروشنده'),
              textField(_sellerName, 'به نام چه کسی (فروشنده)'),
              SwitchListTile(
                value: _paid,
                onChanged: (v) => setState(() => _paid = v),
                title: const Text('پرداخت شده'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _save, child: const Text('ذخیره')),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------- فرم چک -------------------
class _ChequeForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _ChequeForm({this.existing});
  @override
  State<_ChequeForm> createState() => _ChequeFormState();
}

class _ChequeFormState extends State<_ChequeForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _chequeNo;
  late final TextEditingController _bankName;
  late final TextEditingController _fromAccount;
  late final TextEditingController _payerName;
  late final TextEditingController _toAccount;
  late final TextEditingController _sellerName;
  DateTime? _due;
  bool _paid = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _amount = TextEditingController(text: e == null ? '' : plain(e['amount'] as num));
    _chequeNo = TextEditingController(text: e?['cheque_no'] as String? ?? '');
    _bankName = TextEditingController(text: e?['bank_name'] as String? ?? '');
    _fromAccount = TextEditingController(text: e?['from_account'] as String? ?? '');
    _payerName = TextEditingController(text: e?['payer_name'] as String? ?? '');
    _toAccount = TextEditingController(text: e?['to_account'] as String? ?? '');
    _sellerName = TextEditingController(text: e?['seller_name'] as String? ?? '');
    _due = e == null ? DateTime.now() : DateTime.parse(e['due_date'] as String);
    _paid = e != null && (e['paid'] as int) == 1;
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    if (_due == null) {
      snack(context, 'سررسید را انتخاب کنید');
      return;
    }
    Navigator.pop(context, {
      'amount': parseNum(_amount.text) ?? 0,
      'due_date': _due!.toIso8601String(),
      'cheque_no': _chequeNo.text.trim(),
      'bank_name': _bankName.text.trim(),
      'from_account': _fromAccount.text.trim(),
      'payer_name': _payerName.text.trim(),
      'to_account': _toAccount.text.trim(),
      'seller_name': _sellerName.text.trim(),
      'paid': _paid ? 1 : 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.existing == null ? 'چک جدید' : 'ویرایش چک', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              numField(_amount, 'مبلغ چک (تومان)', required: true, thousands: true),
              dateField(context, 'تاریخ سررسید چک', _due, (d) => setState(() => _due = d)),
              textField(_chequeNo, 'شماره چک'),
              textField(_bankName, 'نام بانک'),
              textField(_fromAccount, 'از کدام حساب'),
              textField(_payerName, 'به نام چه کسی (واریزکننده)'),
              textField(_toAccount, 'به کدام حساب فروشنده'),
              textField(_sellerName, 'به نام چه کسی (فروشنده)'),
              SwitchListTile(
                value: _paid,
                onChanged: (v) => setState(() => _paid = v),
                title: const Text('پرداخت شده'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _save, child: const Text('ذخیره')),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }
}
