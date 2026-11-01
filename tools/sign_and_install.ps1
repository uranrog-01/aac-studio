# sign_and_install.ps1 - sign an IPA with a local certificate and install it
# over USB. Fully local + open source: the ONLY credential ever used is the
# passphrase of YOUR OWN certificate file (.p12) - no Apple ID, no account
# password, no third-party service. Signing happens with zsign (compiled from
# source in WSL); installation with pymobiledevice3.
#
# One-time setup (see docs\IOS_SIGNING.md):
#   1. Mint a certificate once (any client; your Apple ID is used exactly
#      once, by you) and copy the two files here:
#        tools\certs\cert.p12
#        tools\certs\cert.mobileprovision
#   2. Build zsign: open a terminal and run
#        wsl -e bash -c "git clone --depth 1 https://github.com/kenfoo/zsign.git ~/zsign && cd ~/zsign && make"
#
# Usage:
#   tools\sign_and_install.ps1                          # defaults below
#   tools\sign_and_install.ps1 -IpaPath C:\path\app.ipa
#   tools\sign_and_install.ps1 -Pass "p12-passphrase"   # else prompted

param(
    [string]$IpaPath = "",
    [string]$Cert = "",
    [string]$Profile = "",
    [string]$Pass = "",
    [string]$OutPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if (-not $IpaPath) {
    $default = Join-Path $repoRoot "dist\AACStudio-unsigned.ipa"
    if (Test-Path $default) { $IpaPath = $default }
}
if (-not $IpaPath -or -not (Test-Path $IpaPath)) {
    Write-Host "IPA not found: $IpaPath" -ForegroundColor Red; exit 1
}

if (-not $Cert)    { $Cert    = Join-Path $PSScriptRoot "certs\cert.p12" }
if (-not $Profile) { $Profile = Join-Path $PSScriptRoot "certs\cert.mobileprovision" }
if (-not (Test-Path $Cert))    { Write-Host "Missing $Cert - see docs\IOS_SIGNING.md (one-time mint)." -ForegroundColor Red; exit 1 }
if (-not (Test-Path $Profile)) { Write-Host "Missing $Profile - see docs\IOS_SIGNING.md (one-time mint)." -ForegroundColor Red; exit 1 }

if (-not $Pass) {
    $sec = Read-Host "Passphrase for cert.p12 (masked)" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    $Pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
}
if (-not $Pass) { Write-Host "Empty passphrase." -ForegroundColor Red; exit 1 }

if (-not $OutPath) { $OutPath = Join-Path $repoRoot "dist\AACStudio-signed.ipa" }

# C:\foo\bar  ->  /mnt/c/foo/bar  (for WSL)
function To-WslPath([string]$p) {
    $p = [IO.Path]::GetFullPath($p)
    return "/mnt/" + $p.Substring(0,1).ToLower() + $p.Substring(2).Replace("\","/")
}

$wslZsign = wsl -e bash -c "ls -t ~/zsign/*/bin/zsign ~/zsign/bin/zsign ~/zsign/zsign 2>/dev/null | head -1"
if (-not $wslZsign) {
    Write-Host "zsign not found in WSL. Build it once:" -ForegroundColor Red
    Write-Host '  wsl -e bash -c "git clone --depth 1 https://github.com/zhlynn/zsign.git ~/zsign/src"' -ForegroundColor Yellow
    Write-Host '  wsl -e bash -c "sudo apt-get install -y g++ make pkg-config libssl-dev && cd ~/zsign/src/build/linux && make"' -ForegroundColor Yellow
    exit 1
}
Write-Host "Signing with zsign (WSL)..."
$cmd = "$wslZsign -f -k '$(To-WslPath $Cert)' -p '$Pass' -m '$(To-WslPath $Profile)' -o '$(To-WslPath $OutPath)' '$(To-WslPath $IpaPath)'"
$zout = wsl -e bash -c $cmd 2>&1
$zout | Select-Object -Last 6 | Write-Host
if (-not (Test-Path $OutPath)) {
    Write-Host "Signing failed - zsign output above. Wrong passphrase?" -ForegroundColor Red; exit 1
}
Write-Host "Signed IPA: $OutPath" -ForegroundColor Green

# install over USB with the existing pymobiledevice3 helper
& (Join-Path $PSScriptRoot "install_ipa_windows.ps1") -IpaPath $OutPath
