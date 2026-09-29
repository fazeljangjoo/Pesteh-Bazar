import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'db.dart';
import 'notify_service.dart';
import 'sync_service.dart';
import 'license_service.dart';
import 'utils.dart';
import 'widgets.dart';

/// این ویجت را دور کل برنامه می‌پیچیم: تا وقتی کاربر وارد نشده یا اشتراکش
/// معتبر نیست، به‌جای برنامه، صفحهٔ ورود/پیام مناسب نشان داده می‌شود.
class LicenseGate extends StatefulWidget {
  final Widget child;
  const LicenseGate({super.key, required this.child});
  @override
  State<LicenseGate> createState() => LicenseGateState();
}

class LicenseGateState extends State<LicenseGate> with WidgetsBindingObserver {
  bool _loading = true;
  LicenseResult? _result;
  String? _dataError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  /// دیتابیس حساب را باز می‌کند؛ اگر این دستگاه هنوز داده‌های حساب را نگرفته (ورود اول /
  /// نصب مجدد)، همه را از سرور می‌آورد. بعد از آن برنامه بدون اینترنت هم کار می‌کند.
  Future<String?> _prepareData(String phone) async {
    try {
      await AppDb.I.useAccount(phone);
      if (await AppDb.I.metaGet('initial_done') == null) {
        final err = await SyncService.I.initialSync();
        if (err != null) return err;
      }
      // ignore: unawaited_futures
      NotifyService.I.rescheduleAll();
      // ignore: unawaited_futures
      SyncService.I.syncNow();
    } catch (e) {
      return 'خطا در باز کردن اطلاعات حساب: $e';
    }
    return null;
  }

  Future<void> refresh() async {
    // در بازگشت به برنامه، اگر قبلاً وارد شده بود، صفحهٔ فعلی با اسپینر عوض نشود
    if (_result == null || _result!.state != LicenseState.valid) setState(() => _loading = true);
    final r = await LicenseService.I.check();
    String? dataErr;
    if (r.state == LicenseState.valid && r.phone != null) {
      dataErr = await _prepareData(r.phone!);
    }
    if (!mounted) return;
    setState(() {
      _result = r;
      _dataError = dataErr;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final r = _result!;
    switch (r.state) {
      case LicenseState.loggedOut:
        return LoginScreen(onSuccess: refresh);
      case LicenseState.needsInternet:
        return MessageScreen(
          icon: Icons.wifi_off_outlined,
          title: 'نیاز به اتصال اینترنت',
          message: 'برای اولین بررسیِ اشتراک، یک‌بار باید اینترنت داشته باشید.',
          onRetry: refresh,
        );
      case LicenseState.blocked:
        return BlockedScreen(phone: r.phone, onRetry: refresh);
      case LicenseState.valid:
        if (_dataError != null) {
          return MessageScreen(
            icon: Icons.cloud_download_outlined,
            title: 'دریافت اطلاعات حساب',
            message: _dataError!,
            onRetry: refresh,
          );
        }
        return widget.child;
    }
  }
}

/// دکمه‌های تماس/واتس‌اپ با پشتیبانی — در چند صفحه استفاده می‌شود
class ContactButtons extends StatelessWidget {
  final String? phoneForMessage;
  const ContactButtons({super.key, this.phoneForMessage});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () => launchUrl(Uri.parse('tel:${SupportContact.callNumber}')),
          icon: const Icon(Icons.call_outlined),
          label: Text('تماس: ${SupportContact.displayPhone}'),
        ),
        OutlinedButton.icon(
          onPressed: () {
            final base = 'سلام، برای فعال‌سازی/تمدید اشتراک بازار پسته تماس می‌گیرم.';
            final withPhone = (phoneForMessage != null && phoneForMessage!.trim().isNotEmpty)
                ? '$base شماره من: ${phoneForMessage!}'
                : base;
            final msg = Uri.encodeComponent(withPhone);
            launchUrl(Uri.parse('https://wa.me/${SupportContact.whatsappNumber}?text=$msg'));
          },
          icon: const Icon(Icons.chat_outlined),
          label: const Text('واتس‌اپ'),
        ),
      ],
    );
  }
}

class LoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  const LoginScreen({super.key, required this.onSuccess});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await LicenseService.I.signIn(_phone.text, _password.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.storefront_outlined, size: 64),
                const SizedBox(height: 12),
                Text('بازار پسته', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                const Text('برای استفاده از برنامه وارد حساب کاربری‌تان شوید',
                    style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: 'شماره موبایل',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'شماره موبایل را وارد کنید' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'رمز عبور',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? 'رمز عبور را وارد کنید' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('ورود'),
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                const Text('حساب کاربری ندارید یا شماره/رمزتان کار نمی‌کند؟',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 10),
                ContactButtons(phoneForMessage: _phone.text),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class MessageScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;
  const MessageScreen(
      {super.key, required this.icon, required this.title, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 56, color: Colors.black45),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 20),
              FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('بررسی مجدد')),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  await LicenseService.I.signOut();
                  onRetry();
                },
                child: const Text('خروج از حساب'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class BlockedScreen extends StatelessWidget {
  final String? phone;
  final VoidCallback onRetry;
  const BlockedScreen({super.key, this.phone, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_clock_outlined, size: 56, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text('اشتراک شما فعال نیست', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'اشتراک این حساب هنوز فعال نشده یا منقضی شده است. برای فعال‌سازی یا تمدید با پشتیبانی تماس بگیرید.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              if (phone != null) ...[
                const SizedBox(height: 8),
                Text('شماره حساب شما: ${toFaDigits(phone!)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 20),
              ContactButtons(phoneForMessage: phone),
              const SizedBox(height: 20),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('بررسی مجدد')),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  await LicenseService.I.signOut();
                  onRetry();
                },
                child: const Text('خروج از حساب'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
