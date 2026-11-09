<#
Publishes the iPhone/Safari web app to GitHub Pages:
https://uranrog-01.github.io/aac-studio/

Builds the web app for the /aac-studio/ address, then replaces the
gh-pages branch of origin with that build (only the built site; no
source code or saved boards). Pages deploys it within a few minutes.
Run from the studio folder:  powershell -File tools\publish_pages.ps1
#>
param(
    [string]$Remote = 'origin',
    [string]$BasePath = '/aac-studio/',
    [string]$Flutter = 'C:/tools/flutter/bin/flutter.bat'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
$repo = $null
try {
    $site = Join-Path $root 'build\web-pages'
    & python -I tools/build_web.py --flutter $Flutter --base-href $BasePath --output build/web-pages
    if ($LASTEXITCODE -ne 0) { throw 'The web build failed.' }
    # GitHub's Jekyll step would otherwise hide or slow down Flutter files.
    New-Item -ItemType File (Join-Path $site '.nojekyll') -Force | Out-Null
    $url = (& git remote get-url $Remote).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Git remote $Remote was not found." }

    # A throwaway repository holds the single published commit, so the
    # project's own branch, index and files are not touched.
    $repo = Join-Path ([IO.Path]::GetTempPath()) ('aac-pages-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory $repo | Out-Null
    & git -C $repo init -q -b gh-pages
    & git -C $repo config core.autocrlf false
    & git -C $repo --work-tree $site add -A .
    if ($LASTEXITCODE -ne 0) { throw 'Could not stage the built site.' }
    $version = ([regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*(\S+)')).Groups[1].Value
    & git -C $repo -c user.name='AAC Studio Build' -c user.email='build@aac-studio.local' commit -q -m "AAC Studio $version web app for iPhone Safari"
    if ($LASTEXITCODE -ne 0) { throw 'Could not record the built site.' }
    & git -C $repo push --force $url gh-pages:gh-pages
    if ($LASTEXITCODE -ne 0) { throw 'Could not upload to GitHub. Check gh auth status.' }
    Write-Host "Published AAC Studio $version. GitHub Pages updates in a few minutes." -ForegroundColor Green
} finally {
    Pop-Location
    if ($repo) { Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue }
}
