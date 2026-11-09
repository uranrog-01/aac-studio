<#
Double-click build.bat, or run build.bat -SkipIos -NoPause for local APK/web.
build.bat -Simulator also builds the iPhone Simulator app (docs/BUILD.md).
iOS uses a GitHub Mac runner and includes saved, uncommitted app changes.
See docs/BUILD.md for the one-time GitHub login and output details.
#>
param(
    [switch]$SkipIos,
    [switch]$SkipWeb,
    [switch]$SkipAndroid,
    # Also build the iPhone Simulator app (debug) and screenshots from it.
    [switch]$Simulator,
    [switch]$NoPause,
    [string]$Flutter = '',
    [string]$Remote = 'origin'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$exitCode = 1
$transcribing = $false
$report = $null
$output = $null

function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed (exit $LASTEXITCODE). See build.log." }
}

function Get-Checked {
    param([string]$Exe, [string[]]$Arguments)
    $result = & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed (exit $LASTEXITCODE)." }
    return ($result -join "`n").Trim()
}

function Get-PackageHash {
    param([string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $stream.Dispose(); $hasher.Dispose() }
}

function Build-Ios {
    param([string]$Repository, [string]$FlutterVersion)
    # An isolated Git index stages only the inputs needed by iOS. It does not
    # change the user's branch, index, files, or commits on their current branch.
    $index = Join-Path $output 'snapshot.index'
    $previousIndex = $env:GIT_INDEX_FILE
    # A build/aac-sim-* branch tells the workflow to add the Simulator job.
    $prefix = if ($Simulator) { 'build/aac-sim-' } else { 'build/aac-' }
    $branch = $prefix + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    try {
        $env:GIT_INDEX_FILE = $index
        Invoke-Checked git @('read-tree', '--empty')
        Invoke-Checked git @('-c', 'core.safecrlf=false', 'add', '-A', '--', 'lib', 'assets', 'ios', 'android', 'web', 'pubspec.yaml', 'pubspec.lock', '.metadata', 'LICENSE', 'THIRD_PARTY_SYMBOLS.md', '.github/workflows/local-ios.yml')
        # The repository is public: never upload signing keys. They are
        # git-ignored; this stops the build if one is ever staged anyway.
        $staged = Get-Checked git @('ls-files', '--cached', '--', 'android')
        $secret = $staged -split "`n" | Where-Object { $_ -match '(key\.properties|\.jks|\.keystore|\.lineage|local\.properties)$' }
        if ($secret) { throw "Refusing to upload signing files: $($secret -join ', ')" }
        # Write the file without a BOM: piping text into git from Windows
        # PowerShell can prefix one, and the workflow then rejects the version.
        $versionFile = Join-Path $output 'flutter-version.txt'
        [System.IO.File]::WriteAllText($versionFile, $FlutterVersion + "`n", (New-Object System.Text.UTF8Encoding $false))
        $blob = Get-Checked git @('hash-object', '-w', '--', $versionFile)
        Remove-Item -LiteralPath $versionFile -Force -ErrorAction SilentlyContinue
        Invoke-Checked git @('update-index', '--add', '--cacheinfo', "100644,$blob,.build-flutter-version")
        $tree = Get-Checked git @('write-tree')
        $parent = Get-Checked git @('rev-parse', 'HEAD')
        $commit = Get-Checked git @('-c', 'user.name=AAC Studio Build', '-c', 'user.email=build@aac-studio.local', 'commit-tree', $tree, '-p', $parent, '-m', "Build AAC Studio $($report.version) from local source")
    } finally {
        $env:GIT_INDEX_FILE = $previousIndex
        # Delete only this run's known temporary index, never a user's index.
        Remove-Item -LiteralPath $index -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($index + '.lock') -Force -ErrorAction SilentlyContinue
    }
    $report.iosCommit = $commit
    $report.iosBranch = $branch
    Write-Host "Uploading current iOS source to $Repository ($branch)..."
    Invoke-Checked git @('push', $Remote, "${commit}:refs/heads/$branch")
    $run = $null
    $deadline = (Get-Date).AddMinutes(3)
    do {
        $runs = Get-Checked gh @('run', 'list', '--repo', $Repository, '--commit', $commit, '--event', 'push', '--json', 'databaseId,workflowName,url', '--limit', '30') | ConvertFrom-Json
        $run = $runs | Where-Object { $_.workflowName -eq 'AAC Studio local iOS build' } | Select-Object -First 1
        if (-not $run) { Start-Sleep -Seconds 5 }
    } while (-not $run -and (Get-Date) -lt $deadline)
    if (-not $run) { throw "No iOS workflow started. Enable GitHub Actions in $Repository and check branch $branch." }
    $report.iosRunId = $run.databaseId
    $report.iosRunUrl = $run.url
    Write-Host "Mac build: $($run.url)"
    # Polling also works with tokens that lack the checks:read scope required
    # by gh run watch. Bound the wait so a stuck/approval-blocked run is visible.
    $deadline = (Get-Date).AddMinutes(90)
    do {
        $state = Get-Checked gh @('run', 'view', "$($run.databaseId)", '--repo', $Repository, '--json', 'status,conclusion') | ConvertFrom-Json
        Write-Host "iOS build: $($state.status) ($(Get-Date -Format HH:mm:ss))"
        if ($state.status -eq 'completed') { break }
        Start-Sleep -Seconds 20
    } while ((Get-Date) -lt $deadline)
    if ($Simulator) {
        # Fetch the Simulator files even when that job failed: its screenshots
        # and log show what went wrong.
        & gh run download "$($run.databaseId)" --repo $Repository --name 'AACStudio-simulator' --dir $output | Out-Host
        if ($LASTEXITCODE -eq 0) {
            $report.simulator = if (Test-Path -LiteralPath (Join-Path $output 'AACStudio-simulator.zip')) { 'debug Simulator app and screenshots' } else { 'Simulator build failed; see simulator files and run log' }
        } else {
            $report.simulator = 'no Simulator files returned'
        }
        Write-Host "iPhone Simulator: $($report.simulator)"
    }
    if ($state.status -ne 'completed' -or $state.conclusion -ne 'success') {
        throw "iOS build did not succeed ($($state.status), $($state.conclusion)). See $($run.url)"
    }
    Invoke-Checked gh @('run', 'download', "$($run.databaseId)", '--repo', $Repository, '--name', 'AACStudio-unsigned-ipa', '--dir', $output)
    $ipa = Join-Path $output 'AACStudio-unsigned.ipa'
    if (-not (Test-Path -LiteralPath $ipa)) { throw 'The Mac build did not return the expected IPA.' }
    $report.ios = 'unsigned IPA built from current source; requires signing before installation'
    # Keep the branch for traceability/retry. Its exact name is in build.json.
}

try {
    Push-Location $root
    if (-not $Flutter) {
        if ($env:FLUTTER_ROOT) { $Flutter = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat' }
        elseif (Get-Command flutter -ErrorAction SilentlyContinue) { $Flutter = (Get-Command flutter).Source }
        elseif (Test-Path 'C:\tools\flutter\bin\flutter.bat') { $Flutter = 'C:\tools\flutter\bin\flutter.bat' }
        else { throw 'Flutter was not found. Add Flutter to PATH or pass -Flutter C:\path\to\flutter.bat.' }
    }
    $versionMatch = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)\s*$')
    if (-not $versionMatch.Success) { throw 'Expected version: major.minor.patch+build in pubspec.yaml.' }
    $version = $versionMatch.Groups[1].Value
    $runName = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
    $output = Join-Path $root "dist\builds\$version\$runName"
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    Start-Transcript -Path (Join-Path $output 'build.log') | Out-Null
    $transcribing = $true
    if ($Simulator -and $SkipIos) { throw '-Simulator uses the GitHub Mac build; remove -SkipIos.' }
    $report = [ordered]@{ version = $version; status = 'building'; output = $output; android = 'pending'; web = 'skipped'; ios = 'skipped'; started = (Get-Date).ToString('o') }
    if ($Simulator) { $report.simulator = 'pending' }
    Write-Host "AAC Studio $version"
    Write-Host "Output: $output"
    $flutterInfo = Get-Checked $Flutter @('--version', '--machine') | ConvertFrom-Json
    $report.flutter = $flutterInfo.frameworkVersion
    # Check cloud access early, but still produce the local files if login is missing.
    $iosSetupError = $null
    if (-not $SkipIos) {
        $report.ios = 'pending'
        try {
            foreach ($command in @('git', 'gh')) {
                if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Install $command and run gh auth login --scopes workflow." }
            }
            # Desktop vaults can redirect APPDATA/XDG_CONFIG_HOME while a
            # terminal login lives in the normal Windows profile. Reuse that
            # existing configuration without copying tokens or replacing an
            # explicitly selected CLI configuration.
            if (-not $env:GH_CONFIG_DIR) {
                $currentConfigExists = $false
                if ($env:APPDATA) { $currentConfigExists = Test-Path (Join-Path $env:APPDATA 'GitHub CLI\hosts.yml') }
                if ($env:XDG_CONFIG_HOME) { $currentConfigExists = $currentConfigExists -or (Test-Path (Join-Path $env:XDG_CONFIG_HOME 'gh\hosts.yml')) }
                $profileConfig = Join-Path $env:USERPROFILE 'AppData\Roaming\GitHub CLI'
                if (-not $currentConfigExists -and (Test-Path (Join-Path $profileConfig 'hosts.yml'))) {
                    $env:GH_CONFIG_DIR = $profileConfig
                }
            }
            Invoke-Checked gh @('auth', 'status', '--hostname', 'github.com')
            $remoteUrl = Get-Checked git @('remote', 'get-url', $Remote)
            if ($remoteUrl -notmatch '^(?:https://github\.com/|git@github\.com:)([^/]+/[^/]+?)(?:\.git)?/?$') {
                throw 'The selected Git remote must be a github.com repository.'
            }
            $repository = $Matches[1]
            $report.repository = $repository
        } catch {
            $iosSetupError = "iOS setup is incomplete: $($_.Exception.Message) Run gh auth login --hostname github.com --git-protocol https --scopes workflow, then gh auth setup-git. See docs/BUILD.md."
            Write-Warning $iosSetupError
        }
    }
    if ($SkipAndroid) {
        $report.android = 'skipped'
    } else {
        if (-not (Test-Path 'android\key.properties')) { throw 'Missing android/key.properties. Restore the existing release signing configuration before building updates.' }
        if (-not $env:ANDROID_HOME) {
            $sdkLine = Get-Content 'android\local.properties' -ErrorAction SilentlyContinue | Where-Object { $_ -match '^sdk\.dir=' } | Select-Object -First 1
            if ($sdkLine) { $env:ANDROID_HOME = ($sdkLine.Substring(8) -replace '\\\\', '\' -replace '\\:', ':') }
            elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_HOME = $env:ANDROID_SDK_ROOT }
            elseif (Test-Path 'C:\Android\Sdk') { $env:ANDROID_HOME = 'C:\Android\Sdk' }
        }
        if (-not $env:ANDROID_HOME -or -not (Test-Path -LiteralPath $env:ANDROID_HOME)) {
            throw 'Android SDK was not found. Set ANDROID_HOME to your Android SDK folder.'
        }
        Write-Host "Android SDK: $env:ANDROID_HOME"
    }
    if (-not $SkipWeb) { Invoke-Checked python @('--version') }
    Invoke-Checked $Flutter @('pub', 'get')
    if (-not $SkipAndroid) {
        Invoke-Checked $Flutter @('build', 'apk', '--release', '--no-pub', '--target-platform', 'android-arm,android-arm64')
        $apk = Join-Path $output 'AACStudio-android.apk'
        # Preserve the project's existing Android signing-key rotation for updates.
        & (Join-Path $PSScriptRoot 'sign_release_apk.ps1') -In (Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk') -Out $apk
        if ($LASTEXITCODE -ne 0) { throw 'Android signing or signature verification failed.' }
        if (-not (Test-Path -LiteralPath $apk)) { throw 'Android build did not produce an APK.' }
        $report.android = 'signed release APK'
    }
    if (-not $SkipWeb) {
        $report.web = 'pending'
        $webOutput = Join-Path $root "build\release-web-$runName"
        $webZip = Join-Path $output 'AACStudio-web.zip'
        Invoke-Checked python @('tools/build_web.py', '--flutter', $Flutter, '--output', $webOutput, '--archive', $webZip)
        $report.web = 'HTTPS website package'
    }
    $instructions = @'
AACStudio-android.apk: upload as an Android download.
AACStudio-web.zip (if built): extract and upload its CONTENTS to your HTTPS website root.
AACStudio-unsigned.ipa (if built): for signing/sideloading; cannot install directly from a website.
AACStudio-simulator.zip (if built with -Simulator): upload to a browser iPhone simulator such as Appetize.io; not for real iPhones.
See docs/BUILD.md for build options and iOS signing requirements.
'@
    Set-Content -LiteralPath (Join-Path $output 'UPLOAD.txt') -Value $instructions -Encoding UTF8
    if (-not $SkipIos) {
        if ($iosSetupError) { throw $iosSetupError }
        Build-Ios -Repository $repository -FlutterVersion $flutterInfo.frameworkVersion
    }
    $report.status = if ($SkipIos) { 'local build complete; iOS explicitly skipped' } else { 'complete; IPA requires signing' }
    $exitCode = 0
} catch {
    if ($report) { $report.status = 'failed'; $report.error = $_.Exception.Message }
    Write-Host "BUILD INCOMPLETE: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    if ($output -and $report) {
        $report.finished = (Get-Date).ToString('o')
        $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'build.json') -Encoding UTF8
        $checksums = Get-ChildItem -LiteralPath $output -File | Where-Object { $_.Extension -in @('.apk', '.ipa', '.zip') } | ForEach-Object {
            '{0}  {1}' -f (Get-PackageHash $_.FullName), $_.Name
        }
        $checksums | Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ASCII
        Write-Host "Files and log: $output"
        if ($exitCode -eq 0) { Write-Host 'BUILD FINISHED' -ForegroundColor Green }
    }
    if ($transcribing) { Stop-Transcript | Out-Null }
    Pop-Location
    if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
}
exit $exitCode
