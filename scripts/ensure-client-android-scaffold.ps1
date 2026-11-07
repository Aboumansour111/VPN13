$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ClientRoot = Join-Path $RepoRoot "client"
$AndroidRoot = Join-Path $ClientRoot "android"

$RequiredFiles = @(
    "gradlew.bat",
    "settings.gradle.kts",
    "gradle/wrapper/gradle-wrapper.jar",
    "gradle/wrapper/gradle-wrapper.properties"
)
$Missing = $RequiredFiles | Where-Object { !(Test-Path (Join-Path $AndroidRoot $_)) }
if (!$Missing) {
    Write-Host "Android Gradle scaffold is complete."
    exit 0
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vpn13_android_scaffold_" + [guid]::NewGuid().ToString("N"))
$GeneratedRoot = Join-Path $TempRoot "generated"
$ExistingRoot = Join-Path $TempRoot "existing"

New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
if (Test-Path $AndroidRoot) {
    Copy-Item -Path $AndroidRoot -Destination $ExistingRoot -Recurse -Force
}

Write-Host "Generating missing Flutter Android Gradle scaffold..."
flutter create --platforms=android --project-name vpn13_client --org com.vpn13 $GeneratedRoot
if ($LASTEXITCODE -ne 0) {
    throw "flutter create failed with exit code $LASTEXITCODE"
}

if (Test-Path $AndroidRoot) {
    Remove-Item -Path $AndroidRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $AndroidRoot | Out-Null
Copy-Item -Path (Join-Path $GeneratedRoot "android\*") -Destination $AndroidRoot -Recurse -Force

if (Test-Path $ExistingRoot) {
    Copy-Item -Path (Join-Path $ExistingRoot "*") -Destination $AndroidRoot -Recurse -Force
}

Remove-Item -Path $TempRoot -Recurse -Force
Write-Host "Flutter Android scaffold is ready; existing VPN13 native files were preserved."
