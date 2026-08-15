[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = Join-Path $root 'AudioPipeCapture.csproj'
$source = Join-Path $root 'AudioPipeCapture.cs'
$target = Join-Path $root 'third_party\naudio\AudioPipeCapture.dll'
$releaseDll = Join-Path $root 'bin\Release\net472\AudioPipeCapture.dll'

if (-not (Test-Path -LiteralPath $project) -or -not (Test-Path -LiteralPath $source)) {
    throw 'Das Projekt für die Windows-Tonkomponente ist unvollständig.'
}

if (-not $Force -and (Test-Path -LiteralPath $target)) {
    $targetTime = (Get-Item -LiteralPath $target).LastWriteTimeUtc
    $sourceTime = (Get-Item -LiteralPath $source).LastWriteTimeUtc
    $projectTime = (Get-Item -LiteralPath $project).LastWriteTimeUtc
    if ($targetTime -ge $sourceTime -and $targetTime -ge $projectTime) {
        Write-Host "Audio-Komponente ist bereits vorhanden: $target" -ForegroundColor DarkGray
        return
    }
}

$dotnet = Get-Command dotnet.exe -ErrorAction SilentlyContinue
if (-not $dotnet) { $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue }
if (-not $dotnet) {
    throw 'AudioPipeCapture.dll fehlt. Zum Erstellen des Quellpakets wird das .NET 8 SDK benötigt. Der GitHub-Windows-Build erledigt dies automatisch.'
}

Write-Host 'Erstelle die vorab kompilierte Windows-Tonkomponente ...' -ForegroundColor Cyan
& $dotnet.Source build $project --configuration Release --nologo --verbosity minimal
if ($LASTEXITCODE -ne 0) {
    throw "Der .NET-Build der Tonkomponente meldete Fehlercode $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $releaseDll)) {
    throw "Der .NET-Build lief durch, aber die erwartete Datei fehlt: $releaseDll"
}

Copy-Item -LiteralPath $releaseDll -Destination $target -Force
Write-Host "Tonkomponente erstellt: $target" -ForegroundColor Green
