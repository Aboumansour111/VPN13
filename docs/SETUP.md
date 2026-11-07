# راه‌اندازی VPN13

## پیش‌نیاز
- Flutter 3.44 یا جدیدتر و Dart 3.12+
- Android SDK و JDK 17
- Python 3.11 یا جدیدتر برای Backend
- PostgreSQL یا SQLite برای Backend

## موتور VPN اندروید

VPN13 فقط از **Xray-core** استفاده می‌کند. سرویس بومی `XrayVpnService` مالک تونل VPN، مجوز اندروید، رابط TUN و چرخه عمر هسته است. هیچ مسیر اجرایی برای sing-box وجود ندارد.

کدهای ورودی سرور می‌توانند لینک اشتراک، Xray JSON یا outboundهای سازگار با قالب sing-box باشند؛ همه آن‌ها پیش از اتصال به پیکربندی Xray تبدیل می‌شوند. وابستگی `flutter_vless` فعلاً فقط برای تجزیه و تبدیل پروفایل نگه داشته شده و کنترلر اتصال آن اجرا نمی‌شود.

## نصب وابستگی‌ها و بررسی برنامه (Windows PowerShell)

از ریشه مخزن:

```powershell
cd client
flutter clean
flutter pub get
flutter analyze
flutter test
```

## دریافت کتابخانه بومی Xray

از ریشه مخزن:

```powershell
.\\scripts\\setup-xray-core.ps1
```

این اسکریپت AndroidLibXrayLite نسخه 26.10.31 را دریافت و SHA-256 آن را بررسی می‌کند.

## ساخت APK

از ریشه مخزن:

```powershell
.\\scripts\\build-apks.ps1
```

برای ساخت دستی ARM64 از مسیر `client/`:

```powershell
flutter build apk --release --target-platform android-arm64
```

## افزودن سرور

فهرست سرورها در `config/servers.json` نگهداری می‌شود. هر مقدار `config` باید یک لینک یا پروفایل پشتیبانی‌شده باشد. قالب sing-box فقط قالب ورودی داده است و به معنی اجرای sing-box نیست.

برای XHTTP، مقدار انتقال باید دقیقاً `xhttp` باشد. پارامترهای path، mode، host و extra باید بدون تبدیل به transport دیگری حفظ شوند.

مقادیر نمونه را با اطلاعات واقعی سرور جایگزین کن. UUID، کلیدها و رمزهای واقعی را در مخزن عمومی قرار نده.

پس از ساخت، Shadowsocks 2022 و VLESS + XHTTP + REALITY را روی گوشی واقعی آزمایش کن؛ موفقیت در شروع سرویس به‌تنهایی اثبات عبور ترافیک نیست.
