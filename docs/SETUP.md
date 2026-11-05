# راه‌اندازی MahdiVPN روی لپ‌تاپ

## پیش‌نیاز
- Flutter 3.44 یا جدیدتر (Dart 3.12+) + Android Studio/SDK و Android licenses
- Python 3.11 یا جدیدتر
- PostgreSQL (پیشنهاد برای سرور) یا SQLite برای آزمایش
- آدرس HTTPS عمومی برای Backend در استفاده واقعی

## Backend (Windows PowerShell)
```powershell
cd backend
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
```
در فایل `.env` حتماً SECRET_KEY تصادفی، ADMIN_PASSWORD قوی و CLIENT_ACCESS_CODE دلخواه (حداقل ۶ نویسه؛ عددی، حروفی یا ترکیبی) قرار دهید. همین یک کد را به تمام کاربران می‌دهید؛ هیچ ثبت‌نام یا حساب جداگانه‌ای وجود ندارد. برای تغییر کد، مقدار CLIENT_ACCESS_CODE را عوض و Backend را راه‌اندازی مجدد کنید. سپس:
```powershell
uvicorn app.main:app --host 0.0.0.0 --port 8000
```
برای Linux:
```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env # سپس secrets را تغییر دهید
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## Build دو APK
در ریشه repo:
- PowerShell: `./scripts/build-apks.ps1`
- Linux/macOS: `bash scripts/build-apks.sh`

برای تنظیم آدرس API:
```powershell
$env:API_BASE_URL="https://api.example.com"
./scripts/build-apks.ps1
```
APKها در `client/build/app/outputs/flutter-apk/app-release.apk` و `admin/build/app/outputs/flutter-apk/app-release.apk` قرار می‌گیرند. Build نخست Android scaffold را با `flutter create . --platforms=android` تولید می‌کند.

## ورود و افزودن سرور
1. Admin APK را باز کنید؛ نام مدیر و ADMIN_PASSWORD تنظیم‌شده در .env را وارد کنید.
2. «+» سرور جدید، نام و کانفیگ را وارد کنید. لینک‌هایی مانند VLESS/VMess/Trojan/SS/Hysteria2/TUIC/WireGuard و JSON sing-box با موتور سازگار قابل پردازش‌اند.
3. کد مشترک CLIENT_ACCESS_CODE را در اختیار کاربران بگذارید؛ هر کاربر همان کد را در Client APK وارد می‌کند. حساب مستقل و ثبت‌نام جداگانه وجود ندارد.
4. سرور فعال را انتخاب و اتصال را بزنید. نخستین اتصال مجوز VPN اندروید را می‌خواهد.

## شبکه
- Emulator اندروید: `http://10.0.2.2:8000`
- گوشی واقعی: IP/LAN یا دامنه سرور Backend؛ فایروال و HTTPS لازم است.
- `API_BASE_URL` در زمان Build با `--dart-define` تنظیم می‌شود.
- از HTTP ساده فقط در تست LAN استفاده کنید. انتشار production باید HTTPS باشد.

## آزمون
```bash
cd backend
pip install -r requirements-dev.txt
pytest -q
```
CI GitHub نیز Flutter analyze/test و Backend tests را اجرا می‌کند.
