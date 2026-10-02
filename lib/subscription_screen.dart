import 'package:flutter/material.dart';

import 'sync_screen.dart';
import 'license_gate_screen.dart' show ContactButtons;
import 'license_service.dart';
import 'utils.dart';
import 'widgets.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _loading = true;
  LicenseResult? _result;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final r = await LicenseService.I.check();
    if (!mounted) return;
    setState(() {
      _result = r;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final valid = r?.state == LicenseState.valid;
    return Scaffold(
      appBar: AppBar(title: const Text('اشتراک من')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: valid
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (r?.name != null) infoRow('نام', r!.name!),
                      infoRow('شماره حساب', r?.phone != null ? toFaDigits(r!.phone!) : '-'),
                      if (r?.expiry != null) infoRow('تاریخ انقضا', jalaliDateFromDt(r!.expiry!)),
                      infoRow(
                        'وضعیت',
                        valid ? 'فعال — ${faNum(r!.remainingDays)} روز باقی‌مانده' : 'غیرفعال / منقضی',
                        valueColor: valid ? Colors.green.shade800 : Colors.red.shade800,
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('برای تمدید یا تغییر اشتراک با پشتیبانی تماس بگیرید:',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ContactButtons(phoneForMessage: r?.phone),
                const SizedBox(height: 24),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const SyncScreen())),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('همگام‌سازی و بازیابی اطلاعات'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('بررسی مجدد وضعیت')),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    if (await confirm(context, 'از حساب خارج شوید؟')) {
                      await LicenseService.I.signOut();
                      if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('خروج از حساب'),
                ),
              ],
            ),
    );
  }
}
