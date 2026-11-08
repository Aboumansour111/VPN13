$ErrorActionPreference = "Stop"

$version = "26.10.31"
$expectedSha256 = "2efdf731b1ed624eb1cb0d5a4d0aa95c0672e89f9702226d1ba2dc90308630b6"
$urls = @(
    "https://github.com/2dust/AndroidLibXrayLite/releases/download/v$version/libv2ray.aar",
    "https://sourceforge.net/projects/androidlibxraylite.mirror/files/v$version/libv2ray.aar/download"
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetDir = Join-Path $repoRoot "client/android/app/libs"
$targetFile = Join-Path $targetDir "libv2ray.aar"

New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Reuse an existing archive only when its checksum is verified.
if (Test-Path $targetFile) {
    $existingSha256 = (Get-FileHash -Path $targetFile -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($existingSha256 -eq $expectedSha256) {
        Write-Host "Using verified existing AndroidLibXrayLite v$version archive."
        Write-Host "SHA-256: $existingSha256"
        return
    }

    Write-Warning "Existing libv2ray.aar failed SHA-256 verification; removing it."
    Remove-Item $targetFile -Force
}

$downloaded = $false
foreach ($url in $urls) {
    try {
        Write-Host "Downloading AndroidLibXrayLite v$version from $url"
        Invoke-WebRequest -Uri $url -OutFile $targetFile -TimeoutSec 300

        $actualSha256 = (Get-FileHash -Path $targetFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualSha256 -ne $expectedSha256) {
            throw "SHA-256 mismatch. Expected $expectedSha256; got $actualSha256"
        }

        $downloaded = $true
        Write-Host "Verified: $targetFile"
        Write-Host "SHA-256: $actualSha256"
        break
    }
    catch {
        Write-Warning "Download or verification failed: $($_.Exception.Message)"
        if (Test-Path $targetFile) {
            Remove-Item $targetFile -Force
        }
    }
}

if (-not $downloaded) {
    throw "Could not download a verified libv2ray.aar from the official release or mirror. Check your connection and run the build script again."
}
