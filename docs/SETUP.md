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
فهرست سرورها در فایل `config/servers.json` روی GitHub نگهداری می‌شود. برای هر سرور، لینک خام اشتراک را در فیلد `config` قرار دهید؛ مانند `vless://` یا `ss://`. نیازی به ساخت JSON کامل Xray یا تبدیل sing-box نیست؛ برنامه لینک را با موتور Xray پردازش می‌کند.

نمونه:
```json
{
  "version": 3,
  "engine": "xray",
  "format": "share-links",
  "servers": [
    {
      "id": 1,
      "name": "My VLESS",
      "description": "VLESS Reality",
      "config": "vless://UUID@host:port?type=tcp&security=reality#MyServer"
    }
  ]
}
```

برای افزودن سرور، یک مورد جدید با شناسه یکتا، نام و لینک خام در آرایه `servers` اضافه و تغییر را در شاخه `main` منتشر کنید. برنامه فهرست را از GitHub دریافت می‌کند؛ کاربران نیازی به افزودن دستی کانفیگ ندارند.
