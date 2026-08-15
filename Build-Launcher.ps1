[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Join-Path $root 'NetCaptureLauncher.csproj'
$source = Join-Path $root 'NetCaptureLauncher.cs'
$targetDirectory = Join-Path $root 'third_party\launcher'
$target = Join-Path $targetDirectory 'NetCapture.exe'
$releaseExe = Join-Path $root 'bin\Release\net472\NetCapture.exe'

if (-not (Test-Path -LiteralPath $project) -or -not (Test-Path -LiteralPath $source)) {
    throw 'Das Projekt für den NetCapture-EXE-Launcher ist unvollständig.'
}

if (-not $Force -and (Test-Path -LiteralPath $target)) {
    $targetTime = (Get-Item -LiteralPath $target).LastWriteTimeUtc
    $sourceTime = (Get-Item -LiteralPath $source).LastWriteTimeUtc
    $projectTime = (Get-Item -LiteralPath $project).LastWriteTimeUtc
    if ($targetTime -ge $sourceTime -and $targetTime -ge $projectTime) {
        Write-Host "EXE-Launcher ist bereits vorhanden: $target" -ForegroundColor DarkGray
        return
    }
}

$dotnet = Get-Command dotnet.exe -ErrorAction SilentlyContinue
if (-not $dotnet) { $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue }
if (-not $dotnet) {
    throw 'NetCapture.exe fehlt. Zum Erstellen wird das .NET 8 SDK benötigt. Der GitHub-Windows-Build erledigt dies automatisch.'
}

Write-Host 'Erstelle den fensterlosen NetCapture-EXE-Launcher ...' -ForegroundColor Cyan
& $dotnet.Source build $project --configuration Release --nologo --verbosity minimal
if ($LASTEXITCODE -ne 0) {
    throw "Der .NET-Build des EXE-Launchers meldete Fehlercode $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $releaseExe)) {
    throw "Der .NET-Build lief durch, aber die erwartete Datei fehlt: $releaseExe"
}

New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
Copy-Item -LiteralPath $releaseExe -Destination $target -Force
Write-Host "EXE-Launcher erstellt: $target" -ForegroundColor Green
