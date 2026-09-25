import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'license_service.dart';

/// هر چند وقت یک‌بار نسخه روی سرور آپلود شود (نسخهٔ محلی همیشه بعد از هر تغییر
/// گرفته می‌شود؛ این تنظیم فقط زمان‌بندی ارسال به سرور را کم/زیاد می‌کند)
enum BackupFrequency { instant, daily, every3days, weekly, biweekly, monthly }

extension BackupFrequencyX on BackupFrequency {
  String get label => switch (this) {
        BackupFrequency.instant => 'بعد از هر تغییر (پیشنهادی)',
        BackupFrequency.daily => 'روزانه',
        BackupFrequency.every3days => 'هر ۳ روز',
        BackupFrequency.weekly => 'هفتگی',
        BackupFrequency.biweekly => 'هر دو هفته',
        BackupFrequency.monthly => 'ماهانه',
      };

  Duration? get interval => switch (this) {
        BackupFrequency.instant => null,
        BackupFrequency.daily => const Duration(days: 1),
        BackupFrequency.every3days => const Duration(days: 3),
        BackupFrequency.weekly => const Duration(days: 7),
        BackupFrequency.biweekly => const Duration(days: 14),
        BackupFrequency.monthly => const Duration(days: 30),
      };
}

class BackupException implements Exception {
  final String message;
  BackupException(this.message);
  @override
  String toString() => message;
}

/// یک نسخهٔ پشتیبان روی سرور
class RemoteBackup {
  final String name;
  final int size;
  final DateTime time;
  RemoteBackup(this.name, this.size, this.time);
}

/// وضعیت پشتیبان‌گیری برای نمایش در صفحه
class BackupInfo {
  final DateTime? lastOk;
  final bool pending;
  final bool running;
  final String? error;
  final BackupFrequency frequency;
  final DateTime? nextDue;
  const BackupInfo(
      {this.lastOk,
      this.pending = false,
      this.running = false,
      this.error,
      this.frequency = BackupFrequency.instant,
      this.nextDue});
}

/// پشتیبان‌گیری خودکار: بعد از هر تغییر داده (هر ثبت/ویرایش/حذف)، چند ثانیه صبر می‌کند
/// (تا چند ثبت پشت‌سرهم یک پشتیبان شوند)، از دیتابیس یک نسخهٔ سالم می‌گیرد،
/// چند نسخهٔ آخر را روی خود گوشی نگه می‌دارد و نسخه را روی سرور آپلود می‌کند.
/// اگر اینترنت نبود، در صف می‌ماند و خودکار دوباره تلاش می‌شود.
class BackupService {
  BackupService._();
  static final BackupService I = BackupService._();

  static const _kLastOk = 'backup_last_ok_ms';
  static const _kPending = 'backup_pending';
  static const _kFrequency = 'backup_frequency';
  static const int _keepLocal = 5;

  final ValueNotifier<BackupInfo> info = ValueNotifier<BackupInfo>(const BackupInfo());

  bool _started = false;
  bool _running = false;
  bool _again = false;
  bool _pending = false;
  DateTime? _lastOk;
  String? _error;
  BackupFrequency _frequency = BackupFrequency.instant;
  Timer? _debounce;
  Timer? _retry;

  String get _base => '${ApiConfig.baseUrl}/backup.php';

  void _emit() {
    info.value = BackupInfo(
      lastOk: _lastOk,
      pending: _pending,
      running: _running,
      error: _error,
      frequency: _frequency,
      nextDue: _nextDue(),
    );
  }

  DateTime? _nextDue() {
    final iv = _frequency.interval;
    if (iv == null || _lastOk == null) return null;
    return _lastOk!.add(iv);
  }

  /// آیا الان وقت ارسال به سرور رسیده؟ (نسخهٔ محلی همیشه گرفته می‌شود)
  bool _dueNow() {
    final iv = _frequency.interval;
    if (iv == null || _lastOk == null) return true;
    return !DateTime.now().isBefore(_lastOk!.add(iv));
  }

  Future<void> _setPending(bool v) async {
    _pending = v;
    _emit();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPending, v);
  }

  /// یک‌بار در main صدا زده می‌شود
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final sp = await SharedPreferences.getInstance();
    final ms = sp.getInt(_kLastOk);
    _lastOk = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    _pending = sp.getBool(_kPending) ?? false;
    final fIdx = sp.getInt(_kFrequency);
    if (fIdx != null && fIdx >= 0 && fIdx < BackupFrequency.values.length) {
      _frequency = BackupFrequency.values[fIdx];
    }
    _emit();

    AppDb.I.version.addListener(_onDataChanged);
    _retry = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_pending && !_running) _schedule(const Duration(seconds: 1));
    });
    // اولین بار (یا اگر پشتیبان ارسال‌نشده مانده) کمی بعد از باز شدن اپ
    if (_lastOk == null || _pending) _schedule(const Duration(seconds: 15));
  }

  void _onDataChanged() {
    _setPending(true);
    _schedule(const Duration(seconds: 4));
  }

  void _schedule(Duration d) {
    _debounce?.cancel();
    _debounce = Timer(d, _run);
  }

  Future<void> setFrequency(BackupFrequency f) async {
    _frequency = f;
    _emit();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kFrequency, f.index);
    // اگر الان وقتش رسیده، همین حالا ارسال کن؛ وگرنه فقط زمان‌بندی عوض می‌شود
    if (_dueNow() && _pending) _schedule(const Duration(seconds: 2));
  }

  /// دکمهٔ «پشتیبان‌گیری همین حالا» — زمان‌بندی را نادیده می‌گیرد
  Future<void> backupNow() async {
    _debounce?.cancel();
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _emit();
    try {
      await _backupOnce(force: true);
    } finally {
      _running = false;
      _emit();
    }
  }

  Future<void> _run() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _emit();
    try {
      do {
        _again = false;
        await _backupOnce();
      } while (_again);
    } finally {
      _running = false;
      _emit();
    }
  }

  Future<void> _backupOnce({bool force = false}) async {
    try {
      // نسخهٔ محلی همیشه گرفته می‌شود، صرف‌نظر از تنظیم زمان‌بندی سرور
      final local = await _makeLocalSnapshot();
      if (!force && !_dueNow()) {
        // نسخهٔ محلی تازه است؛ طبق تنظیم کاربر هنوز وقت ارسال به سرور نرسیده
        await _setPending(false);
        return;
      }
      await _setPending(false);
      final cred = await LicenseService.I.credentials();
      if (cred == null) {
        await _setPending(true);
        _error = 'برای ذخیرهٔ پشتیبان روی سرور باید وارد حساب شوید';
        return;
      }
      await _upload(local, cred.$1, cred.$2);
      _lastOk = DateTime.now();
      _error = null;
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_kLastOk, _lastOk!.millisecondsSinceEpoch);
    } catch (e) {
      await _setPending(true);
      _error = _friendly(e);
    } finally {
      _emit();
    }
  }

  // ---------------------- نسخهٔ محلی ----------------------
  Future<File> _makeLocalSnapshot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
    final path = p.join(dir.path, 'backup_$stamp.db');
    await AppDb.I.snapshotTo(path);

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('backup_'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    while (files.length > _keepLocal) {
      try {
        files.removeAt(0).deleteSync();
      } catch (_) {}
    }
    return File(path);
  }

  // ---------------------- سرور ----------------------
  Future<void> _upload(File f, String phone, String token) async {
    final req = http.MultipartRequest('POST', Uri.parse(_base))
      ..fields['phone'] = phone
      ..fields['token'] = token
      ..fields['action'] = 'upload'
      ..files.add(await http.MultipartFile.fromPath('file', f.path, filename: 'backup.db'));
    final streamed = await req.send().timeout(const Duration(seconds: 90));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) throw BackupException(_serverError(resp));
  }

  Future<List<RemoteBackup>> listRemote() async {
    final cred = await LicenseService.I.credentials();
    if (cred == null) throw BackupException('ابتدا وارد حساب شوید');
    final resp = await http
        .post(Uri.parse(_base),
            body: {'phone': cred.$1, 'token': cred.$2, 'action': 'list'})
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) throw BackupException(_serverError(resp));
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return (data['backups'] as List)
        .map((e) => RemoteBackup(
              e['name'] as String,
              (e['size'] as num).toInt(),
              DateTime.fromMillisecondsSinceEpoch((e['time'] as num).toInt() * 1000),
            ))
        .toList();
  }

  /// بازیابی یک نسخه از سرور؛ در صورت هر مشکل BackupException می‌اندازد
  /// و اطلاعات فعلی دست‌نخورده می‌ماند.
  Future<void> restoreFromServer(RemoteBackup b) async {
    final cred = await LicenseService.I.credentials();
    if (cred == null) throw BackupException('ابتدا وارد حساب شوید');
    final resp = await _postSafe({
      'phone': cred.$1,
      'token': cred.$2,
      'action': 'download',
      'name': b.name,
    }, 90);
    if (resp.statusCode != 200) throw BackupException(_serverError(resp));

    final tmpDir = await getTemporaryDirectory();
    final tmp = File(p.join(tmpDir.path, 'restore_tmp.db'));
    await tmp.writeAsBytes(resp.bodyBytes, flush: true);
    try {
      await _validate(tmp);
      await AppDb.I.replaceWith(tmp.path);
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  Future<http.Response> _postSafe(Map<String, String> body, int timeoutSec) async {
    try {
      return await http
          .post(Uri.parse(_base), body: body)
          .timeout(Duration(seconds: timeoutSec));
    } catch (e) {
      throw BackupException(_friendly(e));
    }
  }

  Future<void> _validate(File f) async {
    if (await f.length() < 512) throw BackupException('فایل پشتیبان ناقص است');
    final head = await f.openRead(0, 16).first;
    if (head.length != 16 || String.fromCharCodes(head) != 'SQLite format 3\u0000') {
      throw BackupException('این فایل، پشتیبان معتبر اپ نیست');
    }
    final t = await openDatabase(f.path, readOnly: true);
    try {
      final ic = await t.rawQuery('PRAGMA integrity_check');
      if (ic.isEmpty || ic.first.values.first != 'ok') {
        throw BackupException('فایل پشتیبان آسیب دیده است');
      }
      final uv = Sqflite.firstIntValue(await t.rawQuery('PRAGMA user_version')) ?? 0;
      if (uv > AppDb.schemaVersion) {
        throw BackupException('این پشتیبان با نسخهٔ جدیدتری از اپ ساخته شده؛ اول اپ را به‌روز کنید');
      }
      final tables = await t.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('purchases','sales','categories')");
      if (tables.length != 3) throw BackupException('این فایل، پشتیبان معتبر اپ نیست');
    } finally {
      await t.close();
    }
  }

  // ---------------------- خطاها ----------------------
  String _serverError(http.Response resp) {
    String code = '';
    try {
      final m = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      code = (m['error'] ?? '').toString();
    } catch (_) {}
    if (code == 'invalid_token') return 'نشست ورود منقضی شده؛ از حساب خارج و دوباره وارد شوید';
    if (code == 'bad_size' || code == 'upload_error_1' || code == 'upload_error_2') {
      return 'حجم فایل از حد مجاز سرور بیشتر است';
    }
    if (code == 'not_found') return 'این نسخه دیگر روی سرور نیست';
    return 'خطای سرور (کد ${resp.statusCode}${code.isEmpty ? '' : ' - $code'})';
  }

  String _friendly(Object e) {
    if (e is BackupException) return e.message;
    if (e is TimeoutException) return 'سرور دیر جواب داد؛ بعداً خودکار دوباره تلاش می‌شود';
    if (e is SocketException || e is http.ClientException) {
      return 'اینترنت وصل نیست؛ بعد از اتصال خودکار دوباره تلاش می‌شود';
    }
    return 'خطا: $e';
  }
}
