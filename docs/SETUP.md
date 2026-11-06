# راه‌اندازی VPN13

## پیش‌نیاز
- Flutter 3.44 یا جدیدتر و Dart 3.12+
- Android SDK
- Python 3.11 یا جدیدتر برای Backend
- PostgreSQL یا SQLite برای Backend

## موتورهای VPN اندروید

VPN13 دو موتور دارد و بر اساس نوع کانفیگ، موتور را خودکار انتخاب می‌کند:

- **sing-box:** برای پروتکل‌های معمولی که در هسته فعلی پشتیبانی می‌شوند.
- **Xray:** برای کانفیگ‌های دارای انتقال XHTTP، از جمله VLESS + XHTTP.

در هر لحظه فقط یک موتور VPN فعال است. هنگام تغییر نوع سرور، ابتدا موتور قبلی متوقف و سپس موتور موردنیاز اجرا می‌شود. XHTTP به HTTPUpgrade تبدیل نمی‌شود.

## نصب وابستگی‌ها و بررسی برنامه (Windows PowerShell)

از ریشه مخزن:
```powershell
cd client
flutter clean
flutter pub get
flutter analyze
flutter test
```

## ساخت APK

از ریشه مخزن:
```powershell
./scripts/build-apks.ps1
```

برای ساخت دستی:
```powershell
cd client
flutter build apk --release --split-per-abi
```

## افزودن سرور

فهرست سرورها در `config/servers.json` نگهداری می‌شود. هر `config` یک outbound از sing-box به‌صورت JSON رشته‌ای یا لینک اشتراک پشتیبانی‌شده است.

برای XHTTP، مقدار انتقال باید دقیقاً `xhttp` باشد. نمونه ساختار outbound:
```json
{
  "type": "vless",
  "tag": "vpn13-xhttp",
  "server": "example.com",
  "server_port": 443,
  "uuid": "00000000-0000-4000-8000-000000000000",
  "tls": {
    "enabled": true,
    "server_name": "example.com"
  },
  "transport": {
    "type": "xhttp",
    "path": "/your-path",
    "mode": "auto"
  }
}
```

مقادیر نمونه را با اطلاعات واقعی سرور جایگزین کن. UUID، کلیدها و رمزهای واقعی را در مخزن عمومی قرار نده.

برای مشاهده خطاهای اتصال، جزئیات خطا در صفحه اصلی VPN13 نمایش داده می‌شود. پس از ساخت، هر دو نوع سرور را روی گوشی واقعی آزمایش کن؛ موفقیت در شروع سرویس به‌تنهایی اثبات عبور ترافیک نیست.
