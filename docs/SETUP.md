# Setup and local build

## Prerequisites
- Flutter stable (Dart version compatible with pubspec)
- Android Studio / Android SDK + accepted licenses
- Python 3.11+
- PostgreSQL (recommended) or SQLite for local development

## Backend
```bash
cd backend
python -m venv .venv
# Windows: .venv\\Scripts\\activate
# Linux/macOS: source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Set a strong ADMIN_PASSWORD and SECRET_KEY in .env
uvicorn app.main:app --host 0.0.0.0 --port 8000
```
API docs during development: /docs. Do not expose development docs publicly.

## Flutter apps
```bash
cd client
flutter pub get
flutter run
```
Repeat in `admin`. Set API base URL in each app's `lib/config.dart` before release.
Android emulator uses 10.0.2.2 to reach host localhost; physical phone requires reachable LAN/server address and firewall rules.

## Build APKs
From repository root:
- Windows PowerShell: `scripts/build-apks.ps1`
- macOS/Linux: `bash scripts/build-apks.sh`

Artifacts: `client/build/app/outputs/flutter-apk/app-release.apk` and corresponding admin path.
A release APK needs your own signing configuration. The default Flutter release build may use local debug signing only if explicitly configured; do not publish debug-signed APKs as production.

## VPN
The client uses the sing-box Flutter integration. Android asks the user for VPN consent on first connection. A valid supported configuration and reachable VPN node are required. Validate full-device routing, DNS, IPv6 behavior, reconnects, and kill-switch expectations on a physical device before production use.
