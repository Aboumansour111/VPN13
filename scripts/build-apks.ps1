$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ApiUrl = if ($env:API_BASE_URL) { $env:API_BASE_URL } else { "http://10.0.2.2:8000" }
foreach ($App in @("client","admin")) {
    $AppPath = Join-Path $Root $App
    Set-Location $AppPath
    if ($App -eq "client") {
        & (Join-Path $Root "scripts/ensure-client-android-scaffold.ps1")
        & (Join-Path $Root "scripts/setup-xray-core.ps1")
        py -3 (Join-Path $Root "scripts/set-android-min-sdk.py") $AppPath
    } elseif (!(Test-Path "android")) {
        flutter create . --platforms=android
    }
    if ($App -eq "client") { flutter clean }
    flutter pub get
    flutter analyze
    flutter test
    if ($App -eq "client") {
        flutter build apk --release --target-platform android-arm64 --dart-define="API_BASE_URL=$ApiUrl"
    } else {
        flutter build apk --release --dart-define="API_BASE_URL=$ApiUrl"
    }
}
Write-Host "Client APK: client/build/app/outputs/flutter-apk/app-release.apk"
Write-Host "Admin APK: admin/build/app/outputs/flutter-apk/app-release.apk"
