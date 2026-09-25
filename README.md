# بازار پسته

راه‌اندازی:
1. Flutter را نصب کنید (https://docs.flutter.dev/get-started/install)
2. flutter create pesteh_bazar
3. فایل pubspec.yaml و پوشه lib این پروژه را جایگزین فایل‌های پروژه جدید کنید
4. cd pesteh_bazar && flutter pub get
5. flutter run           (اجرا روی گوشی)
6. flutter build apk     (ساخت فایل نصب: build/app/outputs/flutter-apk/app-release.apk)

⚠️ **نکتهٔ مهم برای بیلد release:** بعد از مرحلهٔ ۲ (`flutter create`)، فایل
`android/app/src/main/AndroidManifest.xml` را باز کنید و این خط را همان
بالای `<application` اضافه کنید — بدون این، نسخهٔ release اصلاً به اینترنت
دسترسی ندارد (حتی اگر گوشی کاملاً آنلاین باشد):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```
(اگر از GitHub Actions پروژه استفاده می‌کنید، این کار خودکار انجام می‌شود
و نیازی به این مرحلهٔ دستی نیست.)

## اشتراک/لایسنس
برنامه برای ورود کاربر و کنترل اشتراک به یک سرور کوچک PHP+MySQL خودتان نیاز
دارد (به‌جای Firebase — چون Firebase در ایران فیلتر/تحریم است و پایدار نیست).

قبل از اولین بیلد:
1. بک‌اند را طبق راهنمای پوشهٔ `backend/` (کنار همین پروژه) روی یک هاست
   اشتراکی ارزان نصب کنید.
2. مقدار `ApiConfig.baseUrl` در `lib/license_service.dart` از قبل روی
   `https://pesteh-bazar.ir/backend/api` تنظیم شده — نیازی به تغییر نیست،
   مگر دامنه یا مسیر آپلود بک‌اند عوض شود.
3. در همان فایل، کلاس `SupportContact` را با شماره تماس/واتس‌اپ واقعی خودتان
   پر کنید.
4. مشتری‌های خودتان را از پنل مدیریت (`backend/admin/`) اضافه و فعال کنید —
   نیازی به دانستن SQL یا کار با phpMyAdmin نیست.
