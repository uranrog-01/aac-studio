$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$voiceDirectory = Join-Path $projectRoot 'assets/voices'
$voiceArchive = Join-Path $voiceDirectory 'piper-en-us-ljspeech-medium.tar.bz2'
$expectedHash = '3dfb4b759d8be032a4903a9538d128b0fda2a06ab1de6cbc2d93a97e2dd83dba'
$voiceUrl = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-ljspeech-medium.tar.bz2'

if ((Test-Path -LiteralPath $voiceArchive) -and
    ((Get-FileHash -LiteralPath $voiceArchive -Algorithm SHA256).Hash -eq $expectedHash)) {
    Write-Output 'Piper voice archive verified.'
    exit 0
}
New-Item -ItemType Directory -Path $voiceDirectory -Force | Out-Null
$downloadPath = $voiceArchive + '.download'
Invoke-WebRequest -Uri $voiceUrl -OutFile $downloadPath
if ((Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'Piper voice checksum mismatch. The downloaded file was not installed.'
}
Move-Item -LiteralPath $downloadPath -Destination $voiceArchive -Force
Write-Output 'Piper voice archive downloaded and verified.'
