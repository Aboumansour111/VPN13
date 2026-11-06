# راه‌اندازی VPN13

## پیش‌نیاز
- Flutter 3.44 یا جدیدتر (Dart 3.12+) و Android SDK
- Python 3.11 یا جدیدتر
- PostgreSQL یا SQLite برای Backend
- آدرس HTTPS عمومی برای استفاده واقعی از Backend

## موتور VPN اندروید
برنامه Client از موتور Xray از طریق بستهٔ `flutter_vless` استفاده می‌کند. حداقل نسخه Android SDK برابر 23 است؛ اسکریپت ساخت پروژه این مقدار را پس از تولید Android scaffold تنظیم می‌کند.

## Backend (Windows PowerShell)
```powershell
cd backend
py -3 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
```
در فایل `.env` مقدارهای SECRET_KEY، ADMIN_PASSWORD و CLIENT_ACCESS_CODE را تنظیم کنید. سپس:
```powershell
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

برای Linux:
```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

## ساخت APK
در ریشه مخزن:
- Windows PowerShell: `./scripts/build-apks.ps1`
- Linux/macOS: `bash scripts/build-apks.sh`

برای تنظیم آدرس API:
```powershell
$env:API_BASE_URL="https://api.example.com"
./scripts/build-apks.ps1
```

## افزودن سرور به VPN13
فهرست عمومی سرورها در `config/servers.json` نگهداری می‌شود. مقدار `config` برای هر سرور باید یک رشتهٔ JSON کامل و معتبر Xray باشد و حداقل شامل `inbounds` و `outbounds` باشد. کانفیگ‌های sing-box مستقیماً قابل استفاده نیستند و دیگر مبدل آنلاین VPN13 وجود ندارد.

نمونهٔ ورودی SOCKS محلی مورد استفاده برای تونل:
```json
{
  "listen": "127.0.0.1",
  "port": 10808,
  "protocol": "socks",
  "settings": { "auth": "noauth", "udp": true }
}
```

برای افزودن سرور، یک شیء جدید با شناسه یکتا، نام و کانفیگ کامل Xray به آرایهٔ `servers` اضافه و تغییر را در شاخهٔ `main` منتشر کنید. برنامه فهرست را مستقیماً از GitHub دریافت می‌کند.

## شبکه و آزمون
- Emulator اندروید: `http://10.0.2.2:8000`
- گوشی واقعی: IP شبکه یا دامنه Backend؛ در انتشار عمومی HTTPS استفاده شود.
- آزمون Backend:
```bash
cd backend
pip install -r requirements-dev.txt
pytest -q
```
اتصال VPN، DNS، ترافیک و قطع اتصال باید روی گوشی واقعی و با سرور فعال بررسی شود.
