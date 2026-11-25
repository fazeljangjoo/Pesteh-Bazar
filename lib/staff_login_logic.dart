// v91 p2: منطق مشترک ورود کارمند و قاعدهٔ نام کاربری (بدون وابستگی به UI تا آزمون واحد داشته باشد).

/// قاعدهٔ نام کاربریِ تازه/تغییرکرده (هم‌تراز pb_sa_username_valid سرور): ۳ تا ۳۰ حرف انگلیسی یا عدد.
final RegExp kStaffUsernameRule = RegExp(r'^[A-Za-z0-9]{3,30}$');

/// پیام خطای قاعدهٔ نام کاربری (هم‌متن سرور)
const String kStaffUsernameRuleMsg = 'نام کاربری باید ۳ تا ۳۰ نویسه و فقط حروف انگلیسی و عدد باشد (بدون فاصله و نماد).';

/// کد سرور وقتی نام کاربری قدیمی در چند مجموعه تکراری است و شمارهٔ مالک لازم است.
const String kNeedOwnerPhoneCode = 'need_owner_phone';

/// اعتبارسنجی زندهٔ نام کاربری در فرم کارمند. null = درست.
/// [original] = نام فعلی کارمند (ویرایش)؛ اگر بدون تغییر بماند، حتی اگر با قاعدهٔ تازه جور نباشد پذیرفته می‌شود (حق قدیمی).
String? validateStaffUsername(String raw, {String? original}) {
  final u = raw.trim();
  if (u.isEmpty) return 'نام کاربری را وارد کنید';
  if (original != null && original.isNotEmpty && u == original) return null;
  if (!kStaffUsernameRule.hasMatch(u)) return kStaffUsernameRuleMsg;
  return null;
}

/// نتیجهٔ ورود کارمند. error == null یعنی موفق. needOwnerPhone = سرور شمارهٔ مالک را خواسته است.
class StaffSignInResult {
  final String? error;
  final bool needOwnerPhone;
  const StaffSignInResult({this.error, this.needOwnerPhone = false});
  bool get ok => error == null && !needOwnerPhone;
}

/// آیا پاسخ سرور (staff_login / staff_reset) شمارهٔ مالک را خواسته است؟
bool responseNeedsOwnerPhone(int status, Map<String, dynamic> data) =>
    status == 409 && data['code'] == kNeedOwnerPhoneCode;

/// شمارهٔ مالک برای ذخیرهٔ ورود کارمند: همیشه از پاسخ سرور (phone)؛ اگر نبود/نامعتبر بود، شماره‌ای که خودمان فرستادیم.
/// کلاینت با همین شماره pesteh_<phone>.db، credentials()، همگام‌سازی و مجوز امضاشدهٔ ویندوز را می‌سازد.
/// '' = پاسخ نامعتبر.
String resolveStaffOwnerPhone(Object? serverPhone, String sentPhone,
    {required String Function(String) normalize, required bool Function(String) isValid}) {
  if (serverPhone is String && isValid(serverPhone)) return normalize(serverPhone);
  return sentPhone;
}
