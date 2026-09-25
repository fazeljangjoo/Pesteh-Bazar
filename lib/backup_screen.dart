import 'package:flutter/material.dart';

import 'backup_service.dart';
import 'utils.dart';
import 'widgets.dart';

String _fmtTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${jalaliDateFromDt(t)}  ${toFaDigits('${two(t.hour)}:${two(t.minute)}')}';
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '${faNum(bytes)} بایت';
  if (bytes < 1024 * 1024) return '${faNum(bytes / 1024, dec: 1)} کیلوبایت';
  return '${faNum(bytes / (1024 * 1024), dec: 1)} مگابایت';
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<RemoteBackup> _remote = [];
  String? _remoteError;
  bool _loadingList = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadList();
  }

  Future<void> _loadList() async {
    setState(() {
      _loadingList = true;
      _remoteError = null;
    });
    try {
      final l = await BackupService.I.listRemote();
      if (!mounted) return;
      setState(() {
        _remote = l;
        _loadingList = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _remoteError = '$e';
        _loadingList = false;
      });
    }
  }

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    await BackupService.I.backupNow();
    if (!mounted) return;
    setState(() => _busy = false);
    final err = BackupService.I.info.value.error;
    snack(context, err == null ? 'پشتیبان‌گیری انجام شد' : err);
    _loadList();
  }

  Future<void> _restore(RemoteBackup b) async {
    final ok = await confirm(
      context,
      'اطلاعات فعلی این گوشی با نسخهٔ ${_fmtTime(b.time)} جایگزین می‌شود.\n'
      '(از وضعیت فعلی هم یک کپی روی گوشی نگه داشته می‌شود.)\n\nادامه می‌دهید؟',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    String msg;
    try {
      await BackupService.I.restoreFromServer(b);
      msg = 'بازیابی انجام شد';
    } catch (e) {
      msg = '$e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    snack(context, msg);
    _loadList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('پشتیبان‌گیری و بازیابی'),
        actions: [
          IconButton(onPressed: _busy ? null : _loadList, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ValueListenableBuilder<BackupInfo>(
        valueListenable: BackupService.I.info,
        builder: (context, info, _) {
          final String status;
          Color? statusColor;
          if (info.running) {
            status = 'در حال ارسال به سرور…';
          } else if (info.error != null) {
            status = 'ارسال نشد';
            statusColor = scheme.error;
          } else if (info.pending) {
            status = 'در صف ارسال';
          } else {
            status = 'همه‌چیز ذخیره شده';
            statusColor = Colors.green.shade800;
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: scheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    infoRow('آخرین پشتیبان روی سرور',
                        info.lastOk == null ? 'هنوز گرفته نشده' : _fmtTime(info.lastOk!)),
                    if (info.frequency != BackupFrequency.instant && info.nextDue != null)
                      infoRow('ارسال بعدی به سرور', _fmtTime(info.nextDue!)),
                    infoRow('وضعیت', status, valueColor: statusColor),
                    if (info.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(info.error!, style: TextStyle(color: scheme.error)),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'نسخهٔ محلی روی خود گوشی همیشه بعد از هر ثبت، ویرایش یا حذف گرفته می‌شود. '
                'زمان ارسال آن به سرور را در «زمان‌بندی ارسال» زیر تعیین کنید. '
                'اگر اینترنت نباشد، بعداً خودکار ارسال می‌شود. عکس‌های نمونه در پشتیبان نیستند.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy || info.running ? null : _backupNow,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('پشتیبان‌گیری همین حالا'),
              ),
              const SizedBox(height: 16),
              sectionTitle(context, 'زمان‌بندی ارسال به سرور'),
              Card(
                child: Column(
                  children: [
                    for (final f in BackupFrequency.values)
                      RadioListTile<BackupFrequency>(
                        title: Text(f.label),
                        value: f,
                        groupValue: info.frequency,
                        onChanged: (v) {
                          if (v != null) BackupService.I.setFrequency(v);
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              sectionTitle(context, 'نسخه‌های ذخیره‌شده روی سرور'),
              if (_loadingList)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_remoteError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_remoteError!, style: TextStyle(color: scheme.error)),
                )
              else if (_remote.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('هنوز نسخه‌ای روی سرور نیست'),
                )
              else
                for (final b in _remote)
                  Card(
                    child: ListTile(
                      title: Text(_fmtTime(b.time)),
                      subtitle: Text(_fmtSize(b.size)),
                      trailing: TextButton(
                        onPressed: _busy ? null : () => _restore(b),
                        child: const Text('بازیابی'),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
