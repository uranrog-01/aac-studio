<#
Re-signs a release APK so it updates BOTH install lines in place:
  - v1.0-v1.1 GitHub releases, signed with this PC's debug key (~/.android/debug.keystore)
  - 1.2+ builds, signed with android/app/local-update.keystore (key.properties)

APK Signature Scheme v3 key rotation: v1/v2 signatures use the old key (Android 7-8
see the GitHub key), the v3 block carries a signed lineage old -> new key so
Android 9+ accepts either installed version.

Usage: tools\sign_release_apk.ps1 -In build\app\outputs\flutter-apk\app-release.apk -Out dist\AACStudio-android.apk
Keys and passwords never leave this machine; the lineage file is git-ignored.
#>
param(
    [Parameter(Mandatory)] [string] $In,
    [Parameter(Mandatory)] [string] $Out
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'C:\Android\Sdk' }
$buildTools = Get-ChildItem "$sdk\build-tools" -Directory | Sort-Object { [version]$_.Name } | Select-Object -Last 1
$apksigner = Join-Path $buildTools.FullName 'apksigner.bat'

$props = @{}
Get-Content "$root\android\key.properties" | Where-Object { $_ -match '=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2; $props[$k.Trim()] = $v.Trim()
}
$oldKs = "$env:USERPROFILE\.android\debug.keystore"
$newKs = Join-Path "$root\android\app" $props.storeFile
$lineage = "$root\android\app\release-key.lineage"
$env:AAC_NEW_STORE_PASS = $props.storePassword
$env:AAC_NEW_KEY_PASS = $props.keyPassword

$old = @('--ks', $oldKs, '--ks-key-alias', 'androiddebugkey', '--ks-pass', 'pass:android', '--key-pass', 'pass:android')
$new = @('--ks', $newKs, '--ks-key-alias', $props.keyAlias, '--ks-pass', 'env:AAC_NEW_STORE_PASS', '--key-pass', 'env:AAC_NEW_KEY_PASS')
try {
    if (-not (Test-Path $lineage)) {
        & $apksigner rotate --out $lineage --old-signer @old --new-signer @new
        if ($LASTEXITCODE) { throw 'apksigner rotate failed' }
    }
    & $apksigner sign @old --next-signer @new --lineage $lineage --rotation-min-sdk-version 28 --out $Out $In
    if ($LASTEXITCODE) { throw 'apksigner sign failed' }
    & $apksigner verify --print-certs --verbose $Out | Select-String 'Verified using|Signer #|SHA-256|minSdkVersion'
} finally {
    Remove-Item Env:AAC_NEW_STORE_PASS, Env:AAC_NEW_KEY_PASS -ErrorAction SilentlyContinue
}
