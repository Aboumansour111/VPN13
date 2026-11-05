#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for app in client admin; do
 cd "$ROOT/$app"
 if [ ! -d android ]; then flutter create . --platforms=android; fi
 flutter pub get
 flutter analyze
 flutter test
 flutter build apk --release --dart-define=API_BASE_URL="${API_BASE_URL:-https://YOUR_API_HOST}"
done
echo "Client: $ROOT/client/build/app/outputs/flutter-apk/app-release.apk"
echo "Admin:  $ROOT/admin/build/app/outputs/flutter-apk/app-release.apk"
