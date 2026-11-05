$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
 $ApiUrl = if ($env:API_BASE_URL) { $env:API_BASE_URL } else { "http://10.0.2.2:8000" }
foreach ($App in @("client","admin")) {
 Set-Location (Join-Path $Root $App)
 if (!(Test-Path "android")) { flutter create . --platforms=android }
 flutter pub get
 flutter analyze
 flutter test
 flutter build apk --release --dart-define="API_BASE_URL=$ApiUrl"
}
Write-Host "Client APK: client/build/app/outputs/flutter-apk/app-release.apk"
Write-Host "Admin APK: admin/build/app/outputs/flutter-apk/app-release.apk"
