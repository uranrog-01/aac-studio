# install_ipa_windows.ps1 — install a SIGNED ipa on a USB-connected iPhone
# using open-source pymobiledevice3 (no iTunes UI, no Apple tooling).
#
# Usage:
#   tools\install_ipa_windows.ps1                # uses dist\AACStudio-unsigned.ipa
#   tools\install_ipa_windows.ps1 C:\path\to\any.ipa
#
# The IPA must already be signed (e.g. once via Sideloadly with a free
# Apple ID). Unsigned IPAs are rejected by iOS with a provisioning error —
# see docs\IOS_SIGNING.md.

param(
    [string]$IpaPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$venvDir = Join-Path $PSScriptRoot ".venv-md3"

# --- resolve the IPA -------------------------------------------------------
if (-not $IpaPath) {
    $candidates = @(
        (Join-Path $repoRoot "dist\AACStudio-unsigned.ipa"),
        (Join-Path $repoRoot "build\ios\iphoneos\AACStudio-unsigned.ipa")
    )
    $IpaPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $IpaPath) {
        Write-Host "No IPA found. Expected one of:" -ForegroundColor Yellow
        $candidates | ForEach-Object { Write-Host "  $_" }
        Write-Host "Or pass a path: tools\install_ipa_windows.ps1 C:\path\app.ipa"
        exit 1
    }
}
if (-not (Test-Path $IpaPath)) {
    Write-Host "IPA not found: $IpaPath" -ForegroundColor Red
    exit 1
}
Write-Host "IPA: $IpaPath"

# --- one-time venv setup ---------------------------------------------------
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { Write-Host "python not on PATH - install Python 3.10+" -ForegroundColor Red; exit 1 }
if (-not (Test-Path (Join-Path $venvDir "Scripts\python.exe"))) {
    Write-Host "Setting up tools venv (one time)..."
    & $py -m venv $venvDir
    & (Join-Path $venvDir "Scripts\pip.exe") install --quiet --disable-pip-version-check pymobiledevice3
}
$md3 = Join-Path $venvDir "Scripts\pymobiledevice3.exe"

# --- device check ----------------------------------------------------------
Write-Host "Looking for USB devices..."
$devices = & $md3 usbmux list 2>$null
if (-not $devices) {
    Write-Host "No device detected. Checks:" -ForegroundColor Yellow
    Write-Host "  - iPhone unlocked, USB cable in, tap Trust This Computer"
    Write-Host "  - Install iTunes (Apple version) once if drivers are missing"
    Write-Host "  - iOS 16+: Settings > Privacy & Security > Developer Mode ON"
    exit 1
}

# --- install ---------------------------------------------------------------
Write-Host "Installing..."
& $md3 apps install $IpaPath
if ($LASTEXITCODE -eq 0) {
    Write-Host "Installed. First launch: Settings > General > VPN & Device" -ForegroundColor Green
    Write-Host "Management > trust the developer profile, then open AAC Studio." -ForegroundColor Green
} else {
    Write-Host "Install failed. If the error mentions provisioning/signing," -ForegroundColor Yellow
    Write-Host "the IPA is unsigned or expired - re-sign with Sideloadly first" -ForegroundColor Yellow
    Write-Host "(docs\IOS_SIGNING.md), then re-run this script." -ForegroundColor Yellow
    exit 1
}
