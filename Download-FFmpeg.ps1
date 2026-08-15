[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path $root 'third_party\ffmpeg\ffmpeg.exe'
$downloadUrl = 'https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-9.0.1-essentials_build.zip'
$expectedSha256 = 'FEC81AE03971D9DD4BE3EBE02E263BD2EC1D789483F931BDBA5F5715E65DA2E9'

if ((Test-Path -LiteralPath $target) -and (Get-Item -LiteralPath $target).Length -gt 50000000) {
    Write-Host "FFmpeg ist bereits vorhanden: $target" -ForegroundColor DarkGray
    return
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('CrazyBatto-NetCapture-' + [Guid]::NewGuid().ToString('N'))
$archive = Join-Path $temporaryRoot 'ffmpeg.zip'
$expanded = Join-Path $temporaryRoot 'expanded'

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host 'Lade den geprüften FFmpeg-9.0.1-Build herunter ...' -ForegroundColor Cyan
    Invoke-WebRequest -Uri $downloadUrl -OutFile $archive -UseBasicParsing

    $actualSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if ($actualSha256 -ne $expectedSha256) {
        throw "Die FFmpeg-Prüfsumme stimmt nicht. Erwartet: $expectedSha256; erhalten: $actualSha256"
    }

    Expand-Archive -LiteralPath $archive -DestinationPath $expanded -Force
    $downloadedFfmpeg = Get-ChildItem -LiteralPath $expanded -Filter 'ffmpeg.exe' -File -Recurse |
        Select-Object -First 1
    if (-not $downloadedFfmpeg -or $downloadedFfmpeg.Length -le 50000000) {
        throw 'Das FFmpeg-Archiv enthält keine gültige ffmpeg.exe.'
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $downloadedFfmpeg.FullName -Destination $target -Force
    Write-Host "FFmpeg bereitgestellt: $target" -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
