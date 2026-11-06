# انتشار مستقیم کانفیگ‌های VPN13 با Cloudflare Worker

این Worker کانفیگ‌های جدید را از مبدل GitHub Pages دریافت می‌کند و به `config/servers.json` اضافه می‌کند. سرورهای قبلی حفظ می‌شوند و کانفیگ تکراری بر اساس مقدار `config` دوباره ثبت نمی‌شود.

## 1) ساخت GitHub Token

1. در GitHub وارد Settings → Developer settings → Personal access tokens → Fine-grained tokens شو.
2. یک توکن بساز که فقط به مخزن `Aboumansour111/VPN13` دسترسی داشته باشد.
3. در Repository permissions فقط **Contents: Read and write** را فعال کن.
4. توکن را کپی کن؛ فقط در Cloudflare به‌عنوان Secret ذخیره می‌شود، نه در سایت یا این مخزن.

## 2) ساخت Worker در Cloudflare

1. وارد داشبورد Cloudflare شو: Workers & Pages → Create → Worker.
2. نامی مانند `vpn13-config-publisher` انتخاب کن و Worker را بساز.
3. کد فایل `worker.js` همین پوشه را در ویرایشگر Worker جایگزین کد پیش‌فرض کن و Deploy بزن.
4. در Worker → Settings → Variables and Secrets دو مقدار از نوع **Secret** اضافه کن:
   - `GITHUB_TOKEN`: توکن مرحله قبل
   - `ADMIN_KEY`: یک رمز طولانی و تصادفی که فقط خودت می‌دانی
5. پس از افزودن Secretها، Worker را دوباره Deploy کن.

## 3) اتصال مبدل

1. آدرس Worker را کپی کن؛ معمولاً شبیه `https://vpn13-config-publisher.<account>.workers.dev` است.
2. مبدل را باز کن و آدرس Worker را در فیلد مربوط وارد کن.
3. همان رمز `ADMIN_KEY` را در فیلد کد مدیریت وارد کن.
4. کانفیگ‌ها را تبدیل کن و روی «ارسال مستقیم به GitHub» بزن.

مبدل فقط کانفیگ‌های تازه تبدیل‌شده را ارسال می‌کند؛ Worker آخرین نسخه فایل GitHub را می‌خواند، موارد تکراری را حذف می‌کند و موارد جدید را به انتهای فهرست می‌افزاید. برای هر بار استفاده، آدرس Worker و کد مدیریت باید در مبدل وارد شده باشند.

## نکات امنیتی

- هرگز `GITHUB_TOKEN` را در فایل HTML، مخزن GitHub یا چت قرار نده.
- اگر توکن یا کد مدیریت افشا شد، آن را در سرویس مربوطه لغو و جایگزین کن.
- Worker فقط درخواست‌هایی را می‌پذیرد که Origin آن‌ها دقیقاً `https://aboumansour111.github.io` باشد.
- این ابزار برای افزودن کانفیگ است؛ حذف همه سرورها همچنان باید با خروجی گرفتن و جایگزینی فایل انجام شود.
