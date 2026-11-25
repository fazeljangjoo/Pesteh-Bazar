import 'package:flutter/material.dart';

import 'license_service.dart';

/// v89: بازیابی رمز کارمند با پیامک به شمارهٔ ثبت‌شدهٔ خودش (staff_reset.php).
/// v91 p2: فقط با نام کاربری؛ شمارهٔ مالک فقط وقتی سرور بخواهد (نام قدیمی تکراری در چند مجموعه) نشان داده می‌شود.
class StaffResetScreen extends StatefulWidget {
  const StaffResetScreen({super.key, this.ownerPhone = '', this.username = ''});
  final String ownerPhone;
  final String username;

  @override
  State<StaffResetScreen> createState() => _StaffResetScreenState();
}

class _StaffResetScreenState extends State<StaffResetScreen> {
  late final TextEditingController _owner = TextEditingController(text: widget.ownerPhone);
  late final TextEditingController _user = TextEditingController(text: widget.username);
  final TextEditingController _code = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  final TextEditingController _pass2 = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _masked;
  String? _error;
  late bool _needOwner = widget.ownerPhone.trim().isNotEmpty;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_owner, _user, _code, _pass, _pass2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await LicenseService.I.staffResetSend(_needOwner ? _owner.text : '', _user.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.masked != null) _masked = r.masked;
      if (r.error == null) _sent = true;
      if (r.needOwnerPhone) _needOwner = true;
      _error = r.error;
    });
  }

  Future<void> _confirm() async {
    if (_pass.text != _pass2.text) return setState(() => _error = 'رمز تازه و تکرارش یکی نیستند');
    setState(() {
      _busy = true;
      _error = null;
    });
    final String? e = await LicenseService.I.staffResetConfirm(_needOwner ? _owner.text : '', _user.text, _code.text, _pass.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (e != null) return setState(() => _error = e);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رمز عوض شد؛ با رمز تازه وارد شوید')));
    Navigator.of(context).pop(true);
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(labelText: label, border: const OutlineInputBorder(), prefixIcon: Icon(icon), counterText: '');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بازیابی رمز کارمند')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(padding: const EdgeInsets.all(20), children: <Widget>[
            const Text('کد به شمارهٔ موبایلی پیامک می‌شود که مالک در فرم شما ثبت کرده است.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            TextField(
                key: const ValueKey<String>('staff-reset-user'),
                controller: _user,
                enabled: !_sent,
                textDirection: TextDirection.ltr,
                maxLength: 60,
                autocorrect: false,
                decoration: _dec('نام کاربری', Icons.badge_outlined)),
            const SizedBox(height: 12),
            if (_needOwner) ...<Widget>[
              TextField(
                  key: const ValueKey<String>('staff-reset-owner'),
                  controller: _owner,
                  enabled: !_sent,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  maxLength: 14,
                  decoration: _dec('شمارهٔ موبایل مالک مجموعه', Icons.phone_outlined)),
              const SizedBox(height: 12),
            ],
            if (!_sent)
              FilledButton.icon(onPressed: _busy ? null : _send, icon: const Icon(Icons.sms_outlined), label: Text(_busy ? 'در حال ارسال…' : 'ارسال کد پیامکی')),
            if (_sent) ...<Widget>[
              Text('کد به ${_masked ?? 'شمارهٔ شما'} ارسال شد', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                  maxLength: 8,
                  autofillHints: const <String>[AutofillHints.oneTimeCode],
                  decoration: _dec('کد پیامکی', Icons.pin_outlined)),
              const SizedBox(height: 12),
              TextField(controller: _pass, obscureText: true, maxLength: 200, decoration: _dec('رمز تازه (حداقل ۶ نویسه)', Icons.lock_outline)),
              const SizedBox(height: 12),
              TextField(controller: _pass2, obscureText: true, maxLength: 200, decoration: _dec('تکرار رمز تازه', Icons.lock_outline)),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _busy ? null : _confirm, icon: const Icon(Icons.check), label: Text(_busy ? 'در حال ثبت…' : 'ثبت رمز تازه')),
              TextButton(onPressed: _busy ? null : _send, child: const Text('ارسال دوبارهٔ کد')),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
      ),
    );
  }
}
