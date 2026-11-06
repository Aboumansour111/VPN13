$ErrorActionPreference = "Stop"

$version = "26.10.31"
$url = "https://github.com/2dust/AndroidLibXrayLite/releases/download/v$version/libv2ray.aar"
$expectedSha256 = "2efdf731b1ed624eb1cb0d5a4d0aa95c0672e89f9702226d1ba2dc90308630b6"

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetDir = Join-Path $repoRoot "client/android/app/libs"
$targetFile = Join-Path $targetDir "libv2ray.aar"

New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
Write-Host "Downloading AndroidLibXrayLite v$version..."
Invoke-WebRequest -Uri $url -OutFile $targetFile

$actualSha256 = (Get-FileHash -Path $targetFile -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha256 -ne $expectedSha256) {
    Remove-Item $targetFile -Force
    throw "SHA-256 mismatch. Expected $expectedSha256; got $actualSha256"
}

Write-Host "Verified: $targetFile"
Write-Host "SHA-256: $actualSha256"
