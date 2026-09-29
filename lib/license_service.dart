import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';
import 'sync_service.dart';
import 'utils.dart';

/// اطلاعات تماس شما برای فعال‌سازی/تمدید اشتراک — حتماً این‌ها را با اطلاعات
/// واقعی خودتان جایگزین کنید.
class SupportContact {
  /// شماره‌ای که به کاربر نمایش داده می‌شود
  static const String displayPhone = '۰۹۱۳۴۹۷۰۴۸۳';

  /// همان شماره با کد کشور و بدون صفر، برای دکمه «تماس» (tel:)
  static const String callNumber = '+989134970483';

  /// همان شماره با کد کشور، بدون + و بدون صفر ابتدایی، برای دکمه واتس‌اپ
  static const String whatsappNumber = '989134970483';
}

/// آدرس سرور خودتان (همان بک‌اند PHP که روی هاست آپلود کردید).
/// حتماً «https://» و بدون اسلش انتهایی وارد کنید.
/// مثال: 'https://example.com/backend' یا 'https://api.example.com'
class ApiConfig {
  static const String baseUrl = 'https://pesteh-bazar.ir/backend/api';
}

enum LicenseState {
  /// هنوز وارد حساب نشده (نیاز به شماره و رمز عبور)
  loggedOut,

  /// وارد شده اما نه اینترنت داریم و نه سابقهٔ تاییدشدهٔ قبلی از اشتراک
  needsInternet,

  /// اشتراک فعال نیست / هنوز فعال نشده / منقضی شده
  blocked,

  /// اشتراک معتبر است
  valid,
}

class LicenseResult {
  final LicenseState state;
  final String? phone;
  final DateTime? expiry;
  LicenseResult(this.state, {this.phone, this.expiry});

  int get remainingDays {
    if (expiry == null) return 0;
    final now = DateTime.now();
    final end = DateTime(expiry!.year, expiry!.month, expiry!.day, 23, 59, 59);
    final diff = end.difference(now).inHours / 24;
    return diff < 0 ? 0 : diff.ceil();
  }
}

/// مدیریت ورود (شماره موبایل + رمز عبور) و بررسی اعتبار اشتراک،
/// از طریق سرور PHP خودتان (به‌جای Firebase).
///
/// نکتهٔ معماری: بعد از اولین ورود موفق، سرور یک «توکن» طولانی‌مدت می‌سازد
/// که روی گوشی ذخیره می‌شود؛ دفعات بعد، بدون نیاز به فرستادن دوبارهٔ رمز
/// عبور، همان توکن برای بررسی اعتبار اشتراک استفاده می‌شود.
///
/// هر مشتری را باید از طریق پنل مدیریت (admin/ در پوشهٔ بک‌اند) بسازید —
/// یعنی کنترل کامل دارید کی اصلاً می‌تواند وارد شود و اشتراکش تا کی معتبر است.
class LicenseService {
  LicenseService._();
  static final LicenseService I = LicenseService._();

  static const _kPhoneKey = 'license_phone';
  static const _kTokenKey = 'license_token';
  static const _kActiveKey = 'license_active';
  static const _kExpiryKey = 'license_expiry';

  String normalizePhone(String raw) {
    var s = toEnDigits(raw.trim()).replaceAll(RegExp(r'[^0-9]'), '');
    if (s.startsWith('0')) s = '98${s.substring(1)}';
    if (!s.startsWith('98')) s = '98$s';
    return s;
  }

  bool isValidPhone(String raw) => normalizePhone(raw).length == 12;

  Future<String?> savedPhone() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kPhoneKey);
  }

  Future<String?> _savedToken() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kTokenKey);
  }

  /// برای پشتیبان‌گیری: شماره و توکن ذخیره‌شده (اگر کاربر وارد شده باشد)
  Future<(String, String)?> credentials() async {
    final phone = await savedPhone();
    final token = await _savedToken();
    if (phone == null || token == null || phone.isEmpty || token.isEmpty) return null;
    return (phone, token);
  }

  bool get isSignedIn => _signedInCache;
  bool _signedInCache = false;

  Future<void> _restoreSignedInFlag() async {
    final phone = await savedPhone();
    final token = await _savedToken();
    _signedInCache = phone != null && token != null;
  }

  /// ورود با شماره موبایل و رمزی که در پنل مدیریت برای مشتری ساخته‌اید.
  /// در موفقیت null برمی‌گرداند؛ در خطا یک پیام فارسیِ قابل‌نمایش.
  Future<String?> signIn(String phone, String password) async {
    if (!isValidPhone(phone)) return 'شماره موبایل را درست وارد کنید';
    if (password.trim().isEmpty) return 'رمز عبور را وارد کنید';
    final n = normalizePhone(phone);

    try {
      final resp = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/login.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': n, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic> data;
      try {
        data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      } on FormatException {
        // سرور جواب JSON نداده (مثلاً صفحهٔ خطا/ریدایرکت/فایروال هاست)
        return 'پاسخ نامعتبر از سرور (کد ${resp.statusCode}).';
      }

      if (resp.statusCode != 200) {
        return (data['error'] as String?) ?? 'شماره یا رمز عبور اشتباه است';
      }

      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kPhoneKey, n);
      await sp.setString(_kTokenKey, data['token'] as String);
      await _saveCache(data['active'] == true, _parseDate(data['expiry_date']));
      _signedInCache = true;
      return null;
    } on TimeoutException {
      return 'سرور در زمان مناسب پاسخ نداد. اینترنت/VPN را بررسی کنید و دوباره تلاش کنید.';
    } on SocketException catch (e) {
      return 'اتصال به سرور برقرار نشد.\n${e.message}';
    } on HandshakeException catch (e) {
      return 'خطای SSL/گواهی امنیتی.\n${e.message}';
    } on http.ClientException catch (e) {
      return 'اتصال به سرور برقرار نشد.\n${e.message}';
    } catch (e) {
      return 'خطای غیرمنتظره:\n$e';
    }
  }

  Future<void> signOut() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kPhoneKey);
    await sp.remove(_kTokenKey);
    await sp.remove(_kActiveKey);
    await sp.remove(_kExpiryKey);
    _signedInCache = false;
    // دیتابیس هر حساب جداست و روی گوشی می‌ماند؛ فقط بسته می‌شود. اگر عملیات ارسال‌نشده
    // داشته باشد، با ورود دوباره به همان حساب ارسال می‌شود.
    SyncService.I.stop();
    await AppDb.I.closeAccount();
  }

  Future<void> _saveCache(bool active, DateTime? expiry) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kActiveKey, active);
    if (expiry != null) {
      await sp.setString(_kExpiryKey, expiry.toIso8601String());
    } else {
      await sp.remove(_kExpiryKey);
    }
  }

  Future<(bool, DateTime?)> _loadCache() async {
    final sp = await SharedPreferences.getInstance();
    final active = sp.getBool(_kActiveKey) ?? false;
    final expStr = sp.getString(_kExpiryKey);
    final expiry = expStr == null ? null : DateTime.tryParse(expStr);
    return (active, expiry);
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  /// وضعیت اشتراک را برمی‌گرداند. اول تلاش می‌کند از سرور (آنلاین) بخواند؛
  /// اگر اینترنت نبود، بر اساس آخرین وضعیتِ تاییدشده‌ای که روی گوشی ذخیره شده
  /// تصمیم می‌گیرد (چون تاریخ انقضا ثابت است، با آفلاین‌ماندن قابل دور زدن نیست).
  Future<LicenseResult> check() async {
    await _restoreSignedInFlag();
    if (!isSignedIn) return LicenseResult(LicenseState.loggedOut);
    final phone = await savedPhone();
    final token = await _savedToken();
    if (phone == null || token == null) return LicenseResult(LicenseState.loggedOut);

    try {
      final resp = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/check.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'token': token}),
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 401) {
        // توکن دیگر معتبر نیست (مثلاً رمز عبور از پنل مدیریت عوض شده)؛
        // کاربر باید دوباره وارد شود.
        await signOut();
        return LicenseResult(LicenseState.loggedOut);
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final active = data['active'] == true;
      final expiry = _parseDate(data['expiry_date']);

      await _saveCache(active, expiry);
      final valid = active &&
          expiry != null &&
          DateTime.now()
              .isBefore(DateTime(expiry.year, expiry.month, expiry.day, 23, 59, 59));
      return LicenseResult(valid ? LicenseState.valid : LicenseState.blocked,
          phone: phone, expiry: expiry);
    } catch (_) {
      final (active, expiry) = await _loadCache();
      if (expiry == null) {
        return LicenseResult(LicenseState.needsInternet, phone: phone);
      }
      final valid = active &&
          DateTime.now()
              .isBefore(DateTime(expiry.year, expiry.month, expiry.day, 23, 59, 59));
      return LicenseResult(valid ? LicenseState.valid : LicenseState.blocked,
          phone: phone, expiry: expiry);
    }
  }
}
