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

/// نتیجهٔ درخواست ارسال کد پیامکی
class OtpSendResult {
  /// کد ارسال شد
  final bool ok;

  /// پیام خطای قابل‌نمایش (اگر ok نباشد)
  final String? error;

  /// ثانیه‌های باقی‌مانده تا امکان ارسال دوبارهٔ کد
  final int resendIn;
  const OtpSendResult({required this.ok, this.error, this.resendIn = 0});

  /// اگر کد قبلاً فرستاده شده و فقط مهلت ارسال دوباره باقی است، کاربر باید به مرحلهٔ وارد کردن کد برود
  bool get canEnterCode => ok || resendIn > 0;
}

/// نتیجهٔ تأیید کد پیامکی
class OtpVerifyResult {
  final String? error;

  /// کاربر جدید است و باید نامش را وارد کند (کد هنوز مصرف نشده)
  final bool needName;

  /// حساب همین الان ساخته شد (اشتراک آزمایشی فعال شد)
  final bool isNew;
  final int daysLeft;
  const OtpVerifyResult({this.error, this.needName = false, this.isNew = false, this.daysLeft = 0});

  bool get ok => error == null && !needName;
}

class _ApiResp {
  final int status;
  final Map<String, dynamic> data;
  final String? netError;
  _ApiResp(this.status, this.data, [this.netError]);
}

class LicenseResult {
  final LicenseState state;
  final String? phone;
  final String? name;
  final DateTime? expiry;
  LicenseResult(this.state, {this.phone, this.name, this.expiry});

  int get remainingDays {
    if (expiry == null) return 0;
    final now = DateTime.now();
    final end = DateTime(expiry!.year, expiry!.month, expiry!.day, 23, 59, 59);
    final diff = end.difference(now).inHours / 24;
    return diff < 0 ? 0 : diff.ceil();
  }
}

/// مدیریت ورود (شماره موبایل + کد پیامکی) و بررسی اعتبار اشتراک،
/// از طریق سرور PHP خودتان (به‌جای Firebase) — دقیقاً مثل نسخهٔ وب.
///
/// جریان ورود: ۱) otp_send.php کد را می‌فرستد ۲) otp_verify.php کد را تأیید می‌کند.
/// اگر شماره جدید باشد، سرور {need_name: true} برمی‌گرداند (کد مصرف نمی‌شود)؛
/// برنامه نام را می‌پرسد و همان کد را همراه نام دوباره می‌فرستد؛ حساب جدید با
/// اشتراک آزمایشی ساخته می‌شود.
///
/// بعد از ورود موفق، سرور یک «توکن» طولانی‌مدت می‌سازد که روی گوشی ذخیره می‌شود؛
/// دفعات بعد همان توکن برای بررسی اعتبار اشتراک استفاده می‌شود.
class LicenseService {
  LicenseService._();
  static final LicenseService I = LicenseService._();

  static const _kPhoneKey = 'license_phone';
  static const _kTokenKey = 'license_token';
  static const _kActiveKey = 'license_active';
  static const _kExpiryKey = 'license_expiry';
  static const _kNameKey = 'license_name';

  /// پیام خوش‌آمدگویی کاربر جدید؛ یک‌بار توسط LicenseGate نمایش داده می‌شود
  String? _pendingWelcome;
  String? takeWelcome() {
    final w = _pendingWelcome;
    _pendingWelcome = null;
    return w;
  }

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

  Future<String?> savedName() async {
    final sp = await SharedPreferences.getInstance();
    final n = sp.getString(_kNameKey);
    return (n == null || n.trim().isEmpty) ? null : n;
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

  /// یک درخواست POST به API؛ خطاهای شبکه را به پیام فارسی تبدیل می‌کند.
  Future<_ApiResp> _post(String path, Map<String, dynamic> body, {int timeoutSec = 20}) async {
    try {
      final resp = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: timeoutSec));
      Map<String, dynamic> data;
      try {
        data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      } on FormatException {
        // سرور جواب JSON نداده (مثلاً صفحهٔ خطا/ریدایرکت/فایروال هاست)
        return _ApiResp(resp.statusCode, {}, 'پاسخ نامعتبر از سرور (کد ${resp.statusCode}).');
      }
      return _ApiResp(resp.statusCode, data);
    } on TimeoutException {
      return _ApiResp(0, {}, 'سرور در زمان مناسب پاسخ نداد. اینترنت/VPN را بررسی کنید و دوباره تلاش کنید.');
    } on SocketException catch (e) {
      return _ApiResp(0, {}, 'اتصال به سرور برقرار نشد.\n${e.message}');
    } on HandshakeException catch (e) {
      return _ApiResp(0, {}, 'خطای SSL/گواهی امنیتی.\n${e.message}');
    } on http.ClientException catch (e) {
      return _ApiResp(0, {}, 'اتصال به سرور برقرار نشد.\n${e.message}');
    } catch (e) {
      return _ApiResp(0, {}, 'خطای غیرمنتظره:\n$e');
    }
  }

  /// مرحلهٔ ۱ ورود: ارسال کد پیامکی به شماره.
  /// سقف‌ها (۴ کد در ساعت و ۱۰ کد در روز برای هر شماره/دستگاه) سمت سرور اعمال می‌شود
  /// و پیام فارسی خطا (کد 429) همان‌طور که هست نمایش داده می‌شود.
  Future<OtpSendResult> sendOtp(String phone) async {
    if (!isValidPhone(phone)) return const OtpSendResult(ok: false, error: 'شماره موبایل را درست وارد کنید');
    final r = await _post('otp_send.php', {'phone': normalizePhone(phone)});
    if (r.netError != null) return OtpSendResult(ok: false, error: r.netError);
    final resendIn = (r.data['resend_in'] is num) ? (r.data['resend_in'] as num).toInt() : 0;
    if (r.status == 200 && r.data['ok'] == true) {
      return OtpSendResult(ok: true, resendIn: resendIn > 0 ? resendIn : 60);
    }
    return OtpSendResult(
      ok: false,
      error: (r.data['error'] as String?) ?? 'ارسال کد ناموفق بود؛ دوباره تلاش کنید.',
      resendIn: resendIn,
    );
  }

  /// مرحلهٔ ۲ ورود: تأیید کد. برای کاربر جدید ابتدا بدون [name] صدا زده می‌شود؛
  /// اگر needName برگشت، نام گرفته می‌شود و دوباره با همان کد و نام صدا زده می‌شود.
  Future<OtpVerifyResult> verifyOtp(String phone, String code, {String? name}) async {
    if (!isValidPhone(phone)) return const OtpVerifyResult(error: 'شماره موبایل را درست وارد کنید');
    final cleanCode = toEnDigits(code.trim()).replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanCode.isEmpty) return const OtpVerifyResult(error: 'کد پیامکی را وارد کنید');
    final n = normalizePhone(phone);
    final cleanName = name?.trim().replaceAll(RegExp(r'\s+'), ' ');

    final body = <String, dynamic>{'phone': n, 'code': cleanCode};
    if (cleanName != null && cleanName.isNotEmpty) body['name'] = cleanName;
    final r = await _post('otp_verify.php', body);
    if (r.netError != null) return OtpVerifyResult(error: r.netError);
    if (r.status != 200) {
      return OtpVerifyResult(error: (r.data['error'] as String?) ?? 'ورود ناموفق بود؛ دوباره تلاش کنید.');
    }
    if (r.data['need_name'] == true) return const OtpVerifyResult(needName: true);

    final token = r.data['token'];
    if (token is! String || token.isEmpty) return const OtpVerifyResult(error: 'پاسخ نامعتبر از سرور.');

    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPhoneKey, n);
    await sp.setString(_kTokenKey, token);
    final srvName = r.data['name'];
    if (srvName is String && srvName.trim().isNotEmpty) {
      await sp.setString(_kNameKey, srvName.trim());
    } else {
      await sp.remove(_kNameKey);
    }
    await _saveCache(r.data['active'] == true, _parseDate(r.data['expiry_date']));
    _signedInCache = true;

    final isNew = r.data['is_new'] == true;
    final daysLeft = (r.data['days_left'] is num) ? (r.data['days_left'] as num).toInt() : 0;
    if (isNew) {
      _pendingWelcome =
          'خوش آمدید! ${faNum(daysLeft > 0 ? daysLeft : 20, dec: 0)} روز اشتراک آزمایشی رایگان برای شما فعال شد';
    }
    return OtpVerifyResult(isNew: isNew, daysLeft: daysLeft);
  }

  Future<void> signOut() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kPhoneKey);
    await sp.remove(_kTokenKey);
    await sp.remove(_kActiveKey);
    await sp.remove(_kExpiryKey);
    await sp.remove(_kNameKey);
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
        // توکن دیگر معتبر نیست؛ کاربر باید دوباره با کد پیامکی وارد شود.
        await signOut();
        return LicenseResult(LicenseState.loggedOut);
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final active = data['active'] == true;
      final expiry = _parseDate(data['expiry_date']);

      await _saveCache(active, expiry);
      // نام کاربر (برای نمایش در صفحهٔ اشتراک) هر بار از سرور تازه می‌شود
      final srvName = data['name'];
      final sp = await SharedPreferences.getInstance();
      if (srvName is String && srvName.trim().isNotEmpty) {
        await sp.setString(_kNameKey, srvName.trim());
      } else if (data.containsKey('name')) {
        await sp.remove(_kNameKey);
      }
      final name = await savedName();
      final valid = active &&
          expiry != null &&
          DateTime.now()
              .isBefore(DateTime(expiry.year, expiry.month, expiry.day, 23, 59, 59));
      return LicenseResult(valid ? LicenseState.valid : LicenseState.blocked,
          phone: phone, name: name, expiry: expiry);
    } catch (_) {
      final (active, expiry) = await _loadCache();
      final name = await savedName();
      if (expiry == null) {
        return LicenseResult(LicenseState.needsInternet, phone: phone, name: name);
      }
      final valid = active &&
          DateTime.now()
              .isBefore(DateTime(expiry.year, expiry.month, expiry.day, 23, 59, 59));
      return LicenseResult(valid ? LicenseState.valid : LicenseState.blocked,
          phone: phone, name: name, expiry: expiry);
    }
  }
}
