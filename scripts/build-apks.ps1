$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ClientPath = Join-Path $Root "client"

Push-Location $ClientPath
try {
    & (Join-Path $Root "scripts/ensure-client-android-scaffold.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Android scaffold setup failed (exit code $LASTEXITCODE)." }

    & (Join-Path $Root "scripts/setup-xray-core.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Xray core setup failed (exit code $LASTEXITCODE)." }

    py -3 (Join-Path $Root "scripts/set-android-min-sdk.py") $ClientPath
    if ($LASTEXITCODE -ne 0) { throw "Setting Android minSdk failed (exit code $LASTEXITCODE)." }

    flutter clean
    if ($LASTEXITCODE -ne 0) { throw "Flutter clean failed (exit code $LASTEXITCODE)." }

    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "Flutter dependency resolution failed (exit code $LASTEXITCODE)." }

    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw "Flutter analysis failed (exit code $LASTEXITCODE)." }

    flutter test
    if ($LASTEXITCODE -ne 0) { throw "Flutter tests failed (exit code $LASTEXITCODE)." }

    flutter build apk --release --target-platform android-arm64
    if ($LASTEXITCODE -ne 0) { throw "Client APK build failed (exit code $LASTEXITCODE)." }

    $ApkPath = Join-Path $ClientPath "build/app/outputs/flutter-apk/app-release.apk"
    if (!(Test-Path $ApkPath)) { throw "Build command completed but APK was not found at $ApkPath." }

    Write-Host "Client APK: $ApkPath"
}
finally {
    Pop-Location
}
