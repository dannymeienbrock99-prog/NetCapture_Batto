[CmdletBinding()]
param(
    [switch]$SkipAudioBuild,
    [switch]$SkipLauncherBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerScript = Join-Path $root 'installer\NetCapture.iss'
$outputDirectory = Join-Path $root 'installer-output'
$audioBuilder = Join-Path $root 'Build-AudioBridge.ps1'
$audioBridge = Join-Path $root 'third_party\naudio\AudioPipeCapture.dll'
$launcherBuilder = Join-Path $root 'Build-Launcher.ps1'
$launcher = Join-Path $root 'third_party\launcher\NetCapture.exe'
$ffmpegDownloader = Join-Path $root 'Download-FFmpeg.ps1'
$bundledFfmpeg = Join-Path $root 'third_party\ffmpeg\ffmpeg.exe'

function Find-InnoCompiler {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }

    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

if (-not (Test-Path -LiteralPath $installerScript)) {
    throw "Installer-Skript fehlt: $installerScript"
}

if (-not $SkipAudioBuild) {
    if (-not (Test-Path -LiteralPath $audioBuilder)) {
        throw "Builder für die Windows-Tonkomponente fehlt: $audioBuilder"
    }
    & $audioBuilder
}
if (-not (Test-Path -LiteralPath $audioBridge)) {
    throw 'AudioPipeCapture.dll fehlt. Führe Build-AudioBridge.ps1 aus oder verwende den GitHub-Windows-Build.'
}
if (-not $SkipLauncherBuild) {
    if (-not (Test-Path -LiteralPath $launcherBuilder)) {
        throw "Builder für den EXE-Launcher fehlt: $launcherBuilder"
    }
    & $launcherBuilder
}
if (-not (Test-Path -LiteralPath $launcher)) {
    throw 'NetCapture.exe fehlt. Führe Build-Launcher.ps1 aus oder verwende den GitHub-Windows-Build.'
}
if (-not (Test-Path -LiteralPath $bundledFfmpeg)) {
    if (-not (Test-Path -LiteralPath $ffmpegDownloader)) {
        throw "FFmpeg fehlt und das Download-Skript wurde nicht gefunden: $ffmpegDownloader"
    }
    & $ffmpegDownloader
}
if (-not (Test-Path -LiteralPath $bundledFfmpeg)) {
    throw 'ffmpeg.exe fehlt. Der geprüfte Download konnte nicht bereitgestellt werden.'
}

$compiler = Find-InnoCompiler
if (-not $compiler) {
    Write-Host 'Inno Setup wurde nicht gefunden und wird jetzt installiert.' -ForegroundColor Yellow
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'Weder Inno Setup noch winget wurden gefunden. Installiere Inno Setup 6 und starte den Builder erneut.'
    }

    $process = Start-Process -FilePath $winget.Source -ArgumentList @(
        'install',
        '--id', 'JRSoftware.InnoSetup',
        '--exact',
        '--scope', 'user',
        '--accept-source-agreements',
        '--accept-package-agreements'
    ) -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "Die Installation von Inno Setup meldete Fehlercode $($process.ExitCode)."
    }
    $compiler = Find-InnoCompiler
}

if (-not $compiler) {
    throw 'ISCC.exe wurde nach der Installation nicht gefunden. Starte Windows einmal neu und versuche es erneut.'
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
Write-Host "Verwende Compiler: $compiler" -ForegroundColor DarkGray
Write-Host 'Erstelle CrazyBatto-NetCapture-Setup-v0.6.2.exe ...' -ForegroundColor Cyan

$build = Start-Process -FilePath $compiler -ArgumentList ('"' + $installerScript + '"') -Wait -PassThru -NoNewWindow
if ($build.ExitCode -ne 0) {
    throw "Inno Setup meldete Fehlercode $($build.ExitCode)."
}

$setup = Join-Path $outputDirectory 'CrazyBatto-NetCapture-Setup-v0.6.2.exe'
if (-not (Test-Path -LiteralPath $setup)) {
    throw "Der Compiler lief durch, aber die erwartete Setup-Datei fehlt: $setup"
}

$hash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash
Set-Content -LiteralPath (Join-Path $outputDirectory 'SHA256.txt') -Value "$hash  CrazyBatto-NetCapture-Setup-v0.6.2.exe" -Encoding ASCII

Write-Host 'Installer erfolgreich erstellt:' -ForegroundColor Green
Write-Host $setup -ForegroundColor White
Write-Host "SHA-256: $hash" -ForegroundColor DarkGray
Start-Process explorer.exe -ArgumentList ('/select,"' + $setup + '"')
