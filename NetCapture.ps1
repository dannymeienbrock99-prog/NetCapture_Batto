[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web

try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NetCaptureDpi {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
'@ -ErrorAction SilentlyContinue
    [NetCaptureDpi]::SetProcessDPIAware() | Out-Null
}
catch { }

$script:AppName = 'Crazy_Batto NetCapture'
$script:AppVersion = '0.6.7'
$script:SrtConnectTimeoutMs = 20000
$script:BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath = Join-Path $env:APPDATA 'CrazyBatto\NetCapture\settings.json'
$script:LogPath = Join-Path $env:LOCALAPPDATA 'CrazyBatto\NetCapture\netcapture.log'
$script:FfmpegProcesses = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$script:FfmpegLogPumps = [System.Collections.Generic.List[object]]::new()
$script:LogQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$script:Monitors = @()
$script:CaptureWindows = @()
$script:SavedCaptureWindowTitle = $null
$script:SavedMonitorIndex = 0
$script:AudioDevices = @()
$script:AudioCaptureSession = $null
$script:StreamStartedAt = $null
$script:StoppingStream = $false
$script:SavedAudioDeviceId = $null
$script:SavedAudioDeviceKind = $null
$script:ObsSocket = $null
$script:ObsConnected = $false
$script:RemoteTargetIp = '192.168.178.50'
$script:RemoteObsHost = '192.168.178.50'
$script:ApplyingLocalObsTestMode = $false

function Add-Log {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $line = "[$timestamp] $Text"
    $script:LogQueue.Enqueue($line)
    try {
        $directory = Split-Path -Parent $script:LogPath
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
    }
    catch { }
}

function Find-FFmpeg {
    $candidates = @(
        (Join-Path $script:BasePath 'ffmpeg.exe'),
        (Join-Path $script:BasePath 'ffmpeg\bin\ffmpeg.exe'),
        (Join-Path $script:BasePath 'third_party\ffmpeg\ffmpeg.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\ffmpeg.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    $command = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $wingetPackages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $wingetPackages) {
        $wingetFfmpeg = Get-ChildItem -LiteralPath $wingetPackages -Filter 'ffmpeg.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($wingetFfmpeg) { return $wingetFfmpeg.FullName }
    }
    return $null
}

function Get-LanAddresses {
    $addresses = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($adapter in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            if ($adapter.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
            foreach ($unicast in $adapter.GetIPProperties().UnicastAddresses) {
                $address = $unicast.Address
                if ($address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { continue }
                $text = $address.IPAddressToString
                if ($text -eq '127.0.0.1' -or $text.StartsWith('169.254.')) { continue }
                if (-not $addresses.Contains($text)) { [void]$addresses.Add($text) }
            }
        }
    }
    catch {
        [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
            Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
            ForEach-Object { if (-not $addresses.Contains($_.IPAddressToString)) { [void]$addresses.Add($_.IPAddressToString) } }
    }
    return $addresses.ToArray()
}

function Refresh-Monitors {
    $script:Monitors = @([System.Windows.Forms.Screen]::AllScreens)
}

function Refresh-CaptureTargets {
    $selectedMode = [string]$cmbCaptureMode.SelectedItem
    $cmbMonitor.Items.Clear()
    $script:CaptureWindows = @()

    if ($selectedMode -eq 'Bildschirm' -or $selectedMode -eq 'UltraWide Triple-Split') {
        $lblCaptureTarget.Text = if ($selectedMode -eq 'Bildschirm') { 'Bildschirm' } else { 'UltraWide-Bildschirm' }
        Refresh-Monitors
        for ($i = 0; $i -lt $script:Monitors.Count; $i++) {
            $screen = $script:Monitors[$i]
            $primary = if ($screen.Primary) { ' – Hauptmonitor' } else { '' }
            [void]$cmbMonitor.Items.Add(('Monitor {0}: {1}x{2} bei {3},{4}{5}' -f ($i + 1), $screen.Bounds.Width, $screen.Bounds.Height, $screen.Bounds.X, $screen.Bounds.Y, $primary))
        }
        if ($script:SavedMonitorIndex -ge 0 -and $script:SavedMonitorIndex -lt $cmbMonitor.Items.Count) {
            $cmbMonitor.SelectedIndex = $script:SavedMonitorIndex
        }
        elseif ($cmbMonitor.Items.Count -gt 0) {
            $cmbMonitor.SelectedIndex = 0
        }
        return
    }

    $lblCaptureTarget.Text = if ($selectedMode -eq 'Fensteraufnahme') { 'Fenster' } else { 'Spiel-Fenster' }
    try {
        Initialize-AudioSupport
        $windows = @([CrazyBatto.WindowCaptureHelper]::GetWindows())
        if ($selectedMode -eq 'Spielaufnahme') {
            $excludedProcesses = @('ApplicationFrameHost', 'explorer', 'SearchHost', 'ShellExperienceHost', 'StartMenuExperienceHost', 'TextInputHost')
            $windows = @($windows | Where-Object {
                $_.Width -ge 640 -and $_.Height -ge 360 -and $excludedProcesses -notcontains $_.ProcessName
            })
        }
        $script:CaptureWindows = $windows
        foreach ($window in $windows) { [void]$cmbMonitor.Items.Add($window) }

        $selectedIndex = -1
        if ($script:SavedCaptureWindowTitle) {
            for ($index = 0; $index -lt $windows.Count; $index++) {
                if ($windows[$index].Title -eq $script:SavedCaptureWindowTitle) {
                    $selectedIndex = $index
                    break
                }
            }
        }
        if ($selectedIndex -lt 0 -and $cmbMonitor.Items.Count -gt 0) { $selectedIndex = 0 }
        $cmbMonitor.SelectedIndex = $selectedIndex

        if ($windows.Count -eq 0) {
            Add-Log "Keine geeigneten Fenster für '$selectedMode' gefunden. Fenster öffnen oder aus dem Vollbild minimieren und Quelle neu laden."
        }
        else {
            Add-Log "$($windows.Count) Quelle(n) für '$selectedMode' gefunden."
        }
    }
    catch {
        Add-Log "Fensterliste konnte nicht geladen werden: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("Fensterliste konnte nicht geladen werden:`r`n`r`n$($_.Exception.Message)", $script:AppName, 'OK', 'Error') | Out-Null
    }
}

function Get-NAudioFile {
    param([string]$Name)
    $candidates = @(
        (Join-Path $script:BasePath "audio\$Name"),
        (Join-Path $script:BasePath "third_party\naudio\$Name")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

function Initialize-AudioSupport {
    if (('CrazyBatto.AudioPipeCapture' -as [type]) -and
        ('CrazyBatto.ProcessLogPump' -as [type]) -and
        ('CrazyBatto.WindowCaptureHelper' -as [type])) { return }

    $coreDll = Get-NAudioFile 'NAudio.Core.dll'
    $wasapiDll = Get-NAudioFile 'NAudio.Wasapi.dll'
    $bridgeDll = Get-NAudioFile 'AudioPipeCapture.dll'
    if (-not $coreDll -or -not $wasapiDll -or -not $bridgeDll) {
        throw 'Die Komponenten für die Windows-Tonaufnahme fehlen. NetCapture bitte neu installieren.'
    }

    [void][System.Reflection.Assembly]::LoadFrom($coreDll)
    [void][System.Reflection.Assembly]::LoadFrom($wasapiDll)
    $bridgeAssembly = [System.Reflection.Assembly]::LoadFrom($bridgeDll)
    if (-not $bridgeAssembly.GetType('CrazyBatto.AudioPipeCapture', $false) -or
        -not $bridgeAssembly.GetType('CrazyBatto.ProcessLogPump', $false) -or
        -not $bridgeAssembly.GetType('CrazyBatto.WindowCaptureHelper', $false)) {
        throw 'AudioPipeCapture.dll ist ungültig. NetCapture bitte neu installieren.'
    }
}

function Get-WindowsAudioDevices {
    Initialize-AudioSupport
    $result = [System.Collections.Generic.List[object]]::new()
    $enumerator = [NAudio.CoreAudioApi.MMDeviceEnumerator]::new()
    try {
        $outputs = $enumerator.EnumerateAudioEndPoints(
            [NAudio.CoreAudioApi.DataFlow]::Render,
            [NAudio.CoreAudioApi.DeviceState]::Active
        )
        for ($index = 0; $index -lt $outputs.Count; $index++) {
            $device = $outputs[$index]
            try {
                [void]$result.Add([pscustomobject]@{
                    Id = [string]$device.ID
                    Kind = 'Loopback'
                    DisplayName = "PC-Ton: $($device.FriendlyName)"
                })
            }
            finally { $device.Dispose() }
        }

        $inputs = $enumerator.EnumerateAudioEndPoints(
            [NAudio.CoreAudioApi.DataFlow]::Capture,
            [NAudio.CoreAudioApi.DeviceState]::Active
        )
        for ($index = 0; $index -lt $inputs.Count; $index++) {
            $device = $inputs[$index]
            try {
                [void]$result.Add([pscustomobject]@{
                    Id = [string]$device.ID
                    Kind = 'Input'
                    DisplayName = "Mikrofon: $($device.FriendlyName)"
                })
            }
            finally { $device.Dispose() }
        }
    }
    finally { $enumerator.Dispose() }
    return $result.ToArray()
}

function Initialize-AudioSelection {
    $script:AudioDevices = @()
    $cmbAudio.Items.Clear()
    [void]$cmbAudio.Items.Add('Kein Ton')
    $cmbAudio.SelectedIndex = 0
    $lblAudioHint.Text = '„Tonquellen laden“ zeigt PC-Ausgänge und Mikrofone.'
}

function Refresh-AudioDevices {
    $btnAudioRefresh.Enabled = $false
    $btnAudioRefresh.Text = 'Lädt …'
    $lblAudioHint.Text = 'Windows-Tonquellen werden gelesen …'
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $devices = @(Get-WindowsAudioDevices)
        $script:AudioDevices = $devices
        $cmbAudio.Items.Clear()
        [void]$cmbAudio.Items.Add('Kein Ton')
        foreach ($device in $devices) { [void]$cmbAudio.Items.Add($device.DisplayName) }

        $selectedIndex = 0
        for ($index = 0; $index -lt $devices.Count; $index++) {
            if ($devices[$index].Id -eq $script:SavedAudioDeviceId -and $devices[$index].Kind -eq $script:SavedAudioDeviceKind) {
                $selectedIndex = $index + 1
                break
            }
        }
        if ($selectedIndex -eq 0) {
            for ($index = 0; $index -lt $devices.Count; $index++) {
                if ($devices[$index].Kind -eq 'Loopback') {
                    $selectedIndex = $index + 1
                    break
                }
            }
        }
        $cmbAudio.SelectedIndex = $selectedIndex
        if ($selectedIndex -gt 0) {
            $lblAudioHint.Text = "$($devices.Count) Tonquelle(n) gefunden – gewählt: $($cmbAudio.SelectedItem)"
            Add-Log "$($devices.Count) Windows-Tonquelle(n) gefunden. Automatisch gewählt: $($cmbAudio.SelectedItem)"
        }
        else {
            $lblAudioHint.Text = "$($devices.Count) Tonquelle(n) gefunden – PC-Ton oder Mikrofon auswählen."
            Add-Log "$($devices.Count) Windows-Tonquelle(n) gefunden."
        }
    }
    catch {
        Initialize-AudioSelection
        $lblAudioHint.Text = 'Tonquellen konnten nicht geladen werden – Protokoll prüfen.'
        Add-Log "Windows-Tonquellen konnten nicht geladen werden: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("Tonquellen konnten nicht geladen werden:`r`n`r`n$($_.Exception.Message)", $script:AppName, 'OK', 'Error') | Out-Null
    }
    finally {
        $btnAudioRefresh.Text = 'Neu laden'
        $btnAudioRefresh.Enabled = $true
    }
}

function Test-TargetAddress {
    param([string]$Address)
    $parsed = $null
    if ([System.Net.IPAddress]::TryParse($Address, [ref]$parsed)) {
        return $parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
    }
    return $false
}

function Get-Resolution {
    param([int]$SourceWidth, [int]$SourceHeight, [string]$Selection)
    switch ($Selection) {
        '1280x720'  { return @(1280, 720) }
        '1920x1080' { return @(1920, 1080) }
        '2560x1440' { return @(2560, 1440) }
        '3840x2160' { return @(3840, 2160) }
        default     { return @($SourceWidth, $SourceHeight) }
    }
}

function Escape-Argument {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Join-Arguments {
    param([string[]]$Arguments)
    return (($Arguments | ForEach-Object { Escape-Argument $_ }) -join ' ')
}

function Add-VideoEncoderArguments {
    param(
        [System.Collections.Generic.List[string]]$Arguments,
        [int]$Fps,
        [int]$Bitrate
    )
    $bitrateValue = "${Bitrate}k"
    $bufferValue = "$([Math]::Max(1000, $Bitrate * 2))k"
    $values = switch ([string]$cmbEncoder.SelectedItem) {
        'NVIDIA NVENC (H.264)' {
            @('-c:v', 'h264_nvenc', '-preset', 'p3', '-tune', 'll', '-rc', 'cbr', '-b:v', $bitrateValue, '-maxrate', $bitrateValue, '-bufsize', $bufferValue, '-g', "$Fps", '-bf', '0')
        }
        'AMD AMF (H.264)' {
            @('-c:v', 'h264_amf', '-usage', 'lowlatency', '-quality', 'speed', '-rc', 'cbr', '-b:v', $bitrateValue, '-maxrate', $bitrateValue, '-bufsize', $bufferValue, '-g', "$Fps", '-bf', '0')
        }
        'Intel Quick Sync (H.264)' {
            @('-c:v', 'h264_qsv', '-preset', 'veryfast', '-b:v', $bitrateValue, '-maxrate', $bitrateValue, '-bufsize', $bufferValue, '-g', "$Fps", '-bf', '0', '-look_ahead', '0')
        }
        default {
            @('-c:v', 'libx264', '-preset', 'ultrafast', '-tune', 'zerolatency', '-b:v', $bitrateValue, '-maxrate', $bitrateValue, '-bufsize', $bufferValue, '-g', "$Fps", '-bf', '0')
        }
    }
    $values | ForEach-Object { [void]$Arguments.Add([string]$_) }
}

function Get-TripleSegmentLayout {
    if ($cmbMonitor.SelectedIndex -lt 0 -or $cmbMonitor.SelectedIndex -ge $script:Monitors.Count) {
        throw 'Bitte einen UltraWide-/Surround-Bildschirm auswählen.'
    }
    $screen = $script:Monitors[$cmbMonitor.SelectedIndex]
    $totalWidth = [int]$screen.Bounds.Width
    $height = [int]$screen.Bounds.Height
    if (($totalWidth % 2) -ne 0 -or ($height % 2) -ne 0) {
        throw "Für H.264 muss die UltraWide-Auflösung gerade Pixelmaße haben. Gefunden: ${totalWidth}x${height}."
    }
    $baseWidth = [int][Math]::Floor($totalWidth / 3)
    if (($baseWidth % 2) -ne 0) { $baseWidth-- }
    $widths = @($baseWidth, $baseWidth, ($totalWidth - ($baseWidth * 2)))
    $labels = @('Links', 'Mitte', 'Rechts')
    $result = [System.Collections.Generic.List[object]]::new()
    $relativeX = 0
    for ($index = 0; $index -lt 3; $index++) {
        $width = [int]$widths[$index]
        if ($width -lt 160 -or $height -lt 120) { throw 'Der ausgewählte Bildschirm ist für Triple-Split zu klein.' }
        if ($width -gt 4096 -or $height -gt 4096) {
            throw "Triple-Split überschreitet pro Teil die H.264-Grenze von 4096x4096. Teil ${index}: ${width}x${height}."
        }
        [void]$result.Add([pscustomobject]@{
            Label = $labels[$index]
            Width = $width
            Height = $height
            RelativeX = $relativeX
            CaptureX = ([int]$screen.Bounds.X + $relativeX)
            CaptureY = [int]$screen.Bounds.Y
            PortOffset = $index
        })
        $relativeX += $width
    }
    return $result.ToArray()
}

function Build-StreamSet {
    $ffmpeg = Find-FFmpeg
    if (-not $ffmpeg) { throw 'FFmpeg wurde nicht gefunden. Klicke auf „FFmpeg installieren“.' }
    if ($cmbCaptureMode.SelectedIndex -lt 0 -or $cmbMonitor.SelectedIndex -lt 0) { throw 'Bitte eine Aufnahmeart und eine Quelle auswählen.' }
    if (-not (Test-TargetAddress $txtTargetIp.Text.Trim())) { throw 'Bitte eine gültige IPv4-Adresse des OBS-PCs eingeben.' }

    $basePort = 0
    if (-not [int]::TryParse($txtPort.Text.Trim(), [ref]$basePort) -or $basePort -lt 1024 -or $basePort -gt 65535) {
        throw 'Der Port muss zwischen 1024 und 65535 liegen.'
    }

    $captureMode = [string]$cmbCaptureMode.SelectedItem
    $tripleMode = $captureMode -eq 'UltraWide Triple-Split'
    if ($tripleMode -and $basePort -gt 65533) { throw 'Für Triple-Split muss der Basisport höchstens 65533 sein.' }
    $fps = [int]$cmbFps.SelectedItem
    $bitrate = [int]$numBitrate.Value
    $latencyMs = [int]$numLatency.Value
    $captureSegments = [System.Collections.Generic.List[object]]::new()

    if ($tripleMode) {
        foreach ($segment in @(Get-TripleSegmentLayout)) { [void]$captureSegments.Add($segment) }
        $captureDescription = [string]$cmbMonitor.SelectedItem
        Add-Log "UltraWide Triple-Split: $captureDescription wird in $($captureSegments[0].Width)x$($captureSegments[0].Height), $($captureSegments[1].Width)x$($captureSegments[1].Height) und $($captureSegments[2].Width)x$($captureSegments[2].Height) geteilt."
    }
    elseif ($captureMode -eq 'Bildschirm') {
        if ($cmbMonitor.SelectedIndex -ge $script:Monitors.Count) { throw 'Der gewählte Bildschirm ist nicht mehr verfügbar. Bitte die Quellenliste aktualisieren.' }
        $screen = $script:Monitors[$cmbMonitor.SelectedIndex]
        $size = Get-Resolution -SourceWidth $screen.Bounds.Width -SourceHeight $screen.Bounds.Height -Selection ([string]$cmbResolution.SelectedItem)
        [void]$captureSegments.Add([pscustomobject]@{
            Label = 'Bildschirm'
            Width = [int]$size[0]
            Height = [int]$size[1]
            SourceWidth = [int]$screen.Bounds.Width
            SourceHeight = [int]$screen.Bounds.Height
            CaptureX = [int]$screen.Bounds.X
            CaptureY = [int]$screen.Bounds.Y
            PortOffset = 0
        })
        $captureDescription = [string]$cmbMonitor.SelectedItem
    }
    else {
        if ($cmbMonitor.SelectedIndex -ge $script:CaptureWindows.Count) { throw 'Das gewählte Fenster ist nicht mehr verfügbar. Bitte die Quellenliste aktualisieren.' }
        $captureWindow = $script:CaptureWindows[$cmbMonitor.SelectedIndex]
        if ([string]::IsNullOrWhiteSpace([string]$captureWindow.Title)) { throw 'Das gewählte Fenster besitzt keinen gültigen Titel.' }
        $size = Get-Resolution -SourceWidth $captureWindow.Width -SourceHeight $captureWindow.Height -Selection ([string]$cmbResolution.SelectedItem)
        [void]$captureSegments.Add([pscustomobject]@{
            Label = if ($captureMode -eq 'Spielaufnahme') { 'Spiel' } else { 'Fenster' }
            Width = [int]$size[0]
            Height = [int]$size[1]
            SourceWidth = [int]$captureWindow.Width
            SourceHeight = [int]$captureWindow.Height
            WindowTitle = [string]$captureWindow.Title
            PortOffset = 0
            GameMode = $captureMode -eq 'Spielaufnahme'
        })
        $captureDescription = [string]$captureWindow
    }

    $query = "mode=caller&transtype=live&latency=$($latencyMs * 1000)&pkt_size=1316&connect_timeout=$script:SrtConnectTimeoutMs"
    $passphrase = $txtPassphrase.Text
    if (-not [string]::IsNullOrWhiteSpace($passphrase)) {
        if ($passphrase.Length -lt 10 -or $passphrase.Length -gt 79) { throw 'Das SRT-Passwort muss 10 bis 79 Zeichen lang sein.' }
        $encodedPassphrase = [System.Uri]::EscapeDataString($passphrase)
        $query += "&pbkeylen=16&passphrase=$encodedPassphrase"
    }

    $audioCapture = $null
    $audioPipeName = $null
    if ($cmbAudio.SelectedIndex -gt 0) {
        $deviceIndex = $cmbAudio.SelectedIndex - 1
        if ($deviceIndex -lt 0 -or $deviceIndex -ge $script:AudioDevices.Count) {
            throw 'Die gewählte Tonquelle ist nicht mehr verfügbar. Bitte die Tonquellen neu laden.'
        }
        $audioDevice = $script:AudioDevices[$deviceIndex]
        Initialize-AudioSupport
        $audioCapture = [CrazyBatto.AudioPipeCapture]::new(
            [string]$audioDevice.Id,
            ($audioDevice.Kind -eq 'Loopback')
        )
        $audioPipeName = 'CrazyBatto-NetCapture-' + [System.Guid]::NewGuid().ToString('N')
    }
    elseif (-not $audioCapture) {
        Add-Log 'Hinweis: „Kein Ton“ ist ausgewählt. Die Übertragung wird ohne Ton gestartet (-an).'
    }

    $streamPlans = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $captureSegments.Count; $index++) {
        $segment = $captureSegments[$index]
        $arguments = [System.Collections.Generic.List[string]]::new()
        @('-hide_banner', '-loglevel', 'info', '-nostats', '-thread_queue_size', '1024') | ForEach-Object { [void]$arguments.Add([string]$_) }

        if ($tripleMode -or $captureMode -eq 'Bildschirm') {
            $captureWidth = if ($tripleMode) { [int]$segment.Width } else { [int]$segment.SourceWidth }
            $captureHeight = if ($tripleMode) { [int]$segment.Height } else { [int]$segment.SourceHeight }
            @('-f', 'gdigrab', '-framerate', "$fps", '-draw_mouse', $(if ($chkMouse.Checked) { '1' } else { '0' }), '-offset_x', "$($segment.CaptureX)", '-offset_y', "$($segment.CaptureY)", '-video_size', "${captureWidth}x${captureHeight}", '-i', 'desktop') |
                ForEach-Object { [void]$arguments.Add([string]$_) }
        }
        else {
            if ($segment.GameMode) { @('-rtbufsize', '512M') | ForEach-Object { [void]$arguments.Add([string]$_) } }
            @('-f', 'gdigrab', '-framerate', "$fps", '-draw_mouse', $(if ($chkMouse.Checked) { '1' } else { '0' }), '-i', ('title=' + [string]$segment.WindowTitle)) |
                ForEach-Object { [void]$arguments.Add([string]$_) }
        }

        $includeAudio = $index -eq 0 -and $audioCapture
        if ($includeAudio) {
            @('-thread_queue_size', '1024', '-f', [string]$audioCapture.SampleFormat, '-ar', [string]$audioCapture.SampleRate, '-ac', [string]$audioCapture.Channels, '-i', "\\.\pipe\$audioPipeName") |
                ForEach-Object { [void]$arguments.Add([string]$_) }
        }

        $outWidth = [int]$segment.Width
        $outHeight = [int]$segment.Height
        $filter = "scale=${outWidth}:${outHeight}:force_original_aspect_ratio=decrease:flags=fast_bilinear,pad=${outWidth}:${outHeight}:(ow-iw)/2:(oh-ih)/2,format=yuv420p"
        @('-vf', $filter, '-r', "$fps") | ForEach-Object { [void]$arguments.Add([string]$_) }
        Add-VideoEncoderArguments -Arguments $arguments -Fps $fps -Bitrate $bitrate

        if ($includeAudio) {
            @('-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2') | ForEach-Object { [void]$arguments.Add([string]$_) }
        }
        else { [void]$arguments.Add('-an') }

        $streamPort = $basePort + [int]$segment.PortOffset
        $targetUrl = "srt://$($txtTargetIp.Text.Trim()):${streamPort}?$query"
        @('-flush_packets', '1', '-muxdelay', '0', '-f', 'mpegts', $targetUrl) | ForEach-Object { [void]$arguments.Add([string]$_) }
        [void]$streamPlans.Add([pscustomobject]@{
            Label = [string]$segment.Label
            Executable = $ffmpeg
            Arguments = $arguments.ToArray()
            TargetUrl = $targetUrl
            Port = $streamPort
            Width = $outWidth
            Height = $outHeight
        })
    }

    Add-Log "Aufnahmequelle: $captureMode – $captureDescription"
    return [pscustomobject]@{
        Streams = $streamPlans.ToArray()
        Executable = $ffmpeg
        AudioCapture = $audioCapture
        AudioPipeName = $audioPipeName
        TripleMode = $tripleMode
    }
}

function Get-ObsUrls {
    $basePort = 9000
    $parsedPort = 0
    if ([int]::TryParse($txtPort.Text.Trim(), [ref]$parsedPort) -and $parsedPort -ge 1 -and $parsedPort -le 65535) {
        $basePort = $parsedPort
    }
    $latencyUs = ([int]$numLatency.Value) * 1000
    $query = "mode=listener&transtype=live&latency=$latencyUs"
    if (-not [string]::IsNullOrWhiteSpace($txtPassphrase.Text)) {
        $query += "&pbkeylen=16&passphrase=$([System.Uri]::EscapeDataString($txtPassphrase.Text))"
    }
    $count = if ($cmbCaptureMode.SelectedItem -eq 'UltraWide Triple-Split') { 3 } else { 1 }
    $urls = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $count; $index++) {
        $port = $basePort + $index
        [void]$urls.Add("srt://0.0.0.0:${port}?$query")
    }
    return $urls.ToArray()
}

function Get-ObsUrl {
    return [string](@(Get-ObsUrls)[0])
}

function Mask-Secret {
    param([string]$Text)
    return ($Text -replace 'passphrase=[^&\s"]+', 'passphrase=********')
}

function Get-ObsAuthentication {
    param(
        [string]$Password,
        [string]$Salt,
        [string]$Challenge
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $secretBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Password + $Salt))
        $secret = [System.Convert]::ToBase64String($secretBytes)
        $authBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($secret + $Challenge))
        return [System.Convert]::ToBase64String($authBytes)
    }
    finally {
        $sha256.Dispose()
    }
}

function Send-ObsMessage {
    param([System.Collections.IDictionary]$Message)

    if (-not $script:ObsSocket -or $script:ObsSocket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        throw 'Die OBS-WebSocket-Verbindung ist nicht geöffnet.'
    }

    $json = $Message | ConvertTo-Json -Depth 20 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $segment = [System.ArraySegment[byte]]::new($bytes)
    $task = $script:ObsSocket.SendAsync(
        $segment,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        [System.Threading.CancellationToken]::None
    )
    if (-not $task.Wait(5000)) { throw 'Zeitüberschreitung beim Senden an OBS.' }
    [void]$task.GetAwaiter().GetResult()
}

function Receive-ObsMessage {
    param([int]$TimeoutMs = 8000)

    if (-not $script:ObsSocket) { throw 'Es besteht keine OBS-WebSocket-Verbindung.' }
    $buffer = New-Object byte[] 65536
    $memory = New-Object System.IO.MemoryStream
    try {
        do {
            $segment = [System.ArraySegment[byte]]::new($buffer)
            $task = $script:ObsSocket.ReceiveAsync($segment, [System.Threading.CancellationToken]::None)
            if (-not $task.Wait($TimeoutMs)) { throw 'Zeitüberschreitung beim Warten auf OBS.' }
            $result = $task.GetAwaiter().GetResult()
            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw 'OBS hat die WebSocket-Verbindung geschlossen.'
            }
            if ($result.Count -gt 0) { $memory.Write($buffer, 0, $result.Count) }
        } while (-not $result.EndOfMessage)

        $json = [System.Text.Encoding]::UTF8.GetString($memory.ToArray())
        if ([string]::IsNullOrWhiteSpace($json)) { throw 'OBS hat eine leere Antwort gesendet.' }
        return $json | ConvertFrom-Json
    }
    finally {
        $memory.Dispose()
    }
}

function Invoke-ObsRequest {
    param(
        [string]$RequestType,
        [System.Collections.IDictionary]$RequestData = @{}
    )

    $requestId = [System.Guid]::NewGuid().ToString('N')
    [void](Send-ObsMessage -Message ([ordered]@{
        op = 6
        d = [ordered]@{
            requestType = $RequestType
            requestId = $requestId
            requestData = $RequestData
        }
    }))

    while ($true) {
        $message = Receive-ObsMessage
        if ([int]$message.op -ne 7) { continue }
        if ([string]$message.d.requestId -ne $requestId) { continue }

        if (-not [bool]$message.d.requestStatus.result) {
            $comment = 'Unbekannter OBS-Fehler.'
            $commentProperty = $message.d.requestStatus.PSObject.Properties['comment']
            if ($commentProperty -and $commentProperty.Value) { $comment = [string]$commentProperty.Value }
            throw "$RequestType fehlgeschlagen (Code $($message.d.requestStatus.code)): $comment"
        }

        $responseProperty = $message.d.PSObject.Properties['responseData']
        if ($responseProperty -and $null -ne $responseProperty.Value) {
            Write-Output -NoEnumerate $responseProperty.Value
            return
        }
        return [pscustomobject]@{}
    }
}

function Disconnect-ObsWebSocket {
    if ($script:ObsSocket) {
        try {
            if ($script:ObsSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                $task = $script:ObsSocket.CloseAsync(
                    [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                    'NetCapture wird getrennt.',
                    [System.Threading.CancellationToken]::None
                )
                [void]$task.Wait(1200)
            }
        }
        catch { try { $script:ObsSocket.Abort() } catch { } }
        finally {
            try { $script:ObsSocket.Dispose() } catch { }
            $script:ObsSocket = $null
        }
    }

    $script:ObsConnected = $false
    if ($null -ne $btnObsConnect) {
        $btnObsConnect.Text = if ($chkLocalObsTest.Checked) { 'Lokal mit OBS verbinden' } else { 'Mit OBS verbinden' }
    }
    if ($null -ne $btnObsCreateSource) { $btnObsCreateSource.Enabled = $false }
    if ($null -ne $btnObsRefresh) { $btnObsRefresh.Enabled = $false }
    if ($null -ne $cmbObsScene) { $cmbObsScene.Items.Clear() }
    if ($null -ne $lblObsStatus) {
        $lblObsStatus.Text = '● NICHT VERBUNDEN'
        $lblObsStatus.ForeColor = [System.Drawing.Color]::FromArgb(159, 168, 190)
    }
}

function Refresh-ObsScenes {
    $sceneResponses = @(Invoke-ObsRequest -RequestType 'GetSceneList')
    if ($sceneResponses.Count -eq 0) { throw 'OBS hat keine Antwort auf GetSceneList geliefert.' }
    $sceneList = $sceneResponses[$sceneResponses.Count - 1]
    $cmbObsScene.Items.Clear()

    $scenesProperty = $sceneList.PSObject.Properties['scenes']
    if ($scenesProperty) {
        foreach ($scene in @($scenesProperty.Value)) {
            $sceneNameProperty = $scene.PSObject.Properties['sceneName']
            if ($sceneNameProperty -and $sceneNameProperty.Value) {
                [void]$cmbObsScene.Items.Add([string]$sceneNameProperty.Value)
            }
        }
    }

    $currentSceneName = $null
    $currentSceneProperty = $sceneList.PSObject.Properties['currentProgramSceneName']
    if ($currentSceneProperty -and $currentSceneProperty.Value) {
        $currentSceneName = [string]$currentSceneProperty.Value
    }

    if ($cmbObsScene.Items.Count -eq 0) {
        $fields = @($sceneList.PSObject.Properties | ForEach-Object { $_.Name }) -join ', '
        Add-Log "OBS GetSceneList enthielt keine auswertbare Szenenliste. Antwortfelder: $(if ($fields) { $fields } else { 'keine' }). Versuche die aktive Szene."
        if (-not $currentSceneName) {
            $currentResponses = @(Invoke-ObsRequest -RequestType 'GetCurrentProgramScene')
            if ($currentResponses.Count -gt 0) {
                $currentResponse = $currentResponses[$currentResponses.Count - 1]
                foreach ($propertyName in @('sceneName', 'currentProgramSceneName')) {
                    $property = $currentResponse.PSObject.Properties[$propertyName]
                    if ($property -and $property.Value) {
                        $currentSceneName = [string]$property.Value
                        break
                    }
                }
            }
        }
        if ($currentSceneName) { [void]$cmbObsScene.Items.Add($currentSceneName) }
    }

    if ($currentSceneName -and $cmbObsScene.Items.Contains($currentSceneName)) {
        $cmbObsScene.SelectedItem = $currentSceneName
    }
    elseif ($cmbObsScene.Items.Count -gt 0) {
        $cmbObsScene.SelectedIndex = 0
    }
    $btnObsCreateSource.Enabled = $cmbObsScene.Items.Count -gt 0
    if ($cmbObsScene.Items.Count -eq 0) {
        throw 'OBS ist verbunden, hat aber keine verwendbare Szene geliefert. Lege in OBS mindestens eine Szene an und drücke danach Szenen neu laden.'
    }
    Add-Log "$($cmbObsScene.Items.Count) OBS-Szene(n) geladen."
}

function Connect-ObsWebSocket {
    if ($script:ObsConnected) {
        Disconnect-ObsWebSocket
        Add-Log 'OBS-WebSocket wurde getrennt.'
        return
    }

    $hostName = $txtObsHost.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = $txtTargetIp.Text.Trim() }
    $wsPort = 0
    if (-not [int]::TryParse($txtObsWsPort.Text.Trim(), [ref]$wsPort) -or $wsPort -lt 1 -or $wsPort -gt 65535) {
        throw 'Der OBS-WebSocket-Port muss zwischen 1 und 65535 liegen.'
    }

    if ($hostName -match '^wss?://') {
        $pastedUri = $null
        if (-not [System.Uri]::TryCreate($hostName, [System.UriKind]::Absolute, [ref]$pastedUri)) {
            throw 'Die eingegebene OBS-WebSocket-Adresse ist ungültig.'
        }
        $hostName = $pastedUri.Host
        if (-not $pastedUri.IsDefaultPort) { $wsPort = $pastedUri.Port }
    }
    elseif ($hostName -match '^(?<host>[^:]+):(?<port>[0-9]+)$') {
        $hostName = $Matches['host']
        $parsedPort = 0
        if (-not [int]::TryParse($Matches['port'], [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
            throw 'Der Anschluss in der OBS-Adresse muss zwischen 1 und 65535 liegen.'
        }
        $wsPort = $parsedPort
    }
    if ([string]::IsNullOrWhiteSpace($hostName) -or $hostName -match '[\s/\\]') {
        throw 'Bitte eine gültige IP-Adresse oder einen Hostnamen für OBS eingeben.'
    }

    Disconnect-ObsWebSocket
    $socket = New-Object System.Net.WebSockets.ClientWebSocket
    $socket.Options.KeepAliveInterval = [System.TimeSpan]::FromSeconds(15)
    $script:ObsSocket = $socket
    try {
        $uriBuilder = [System.UriBuilder]::new('ws', $hostName, $wsPort)
        $uri = $uriBuilder.Uri
        $connectTask = $socket.ConnectAsync($uri, [System.Threading.CancellationToken]::None)
        if (-not $connectTask.Wait(6000)) { throw 'Zeitüberschreitung beim Verbinden mit OBS.' }
        [void]$connectTask.GetAwaiter().GetResult()

        $hello = Receive-ObsMessage
        if ([int]$hello.op -ne 0) { throw 'OBS hat kein gültiges WebSocket-v5-Hello gesendet.' }

        $identifyData = [ordered]@{ rpcVersion = 1; eventSubscriptions = 0 }
        $authProperty = $hello.d.PSObject.Properties['authentication']
        if ($authProperty) {
            if ([string]::IsNullOrEmpty($txtObsPassword.Text)) { throw 'Dieser OBS-WebSocket-Server verlangt ein Passwort.' }
            $identifyData['authentication'] = Get-ObsAuthentication -Password $txtObsPassword.Text -Salt ([string]$authProperty.Value.salt) -Challenge ([string]$authProperty.Value.challenge)
        }

        [void](Send-ObsMessage -Message ([ordered]@{ op = 1; d = $identifyData }))
        $identified = Receive-ObsMessage
        if ([int]$identified.op -ne 2) { throw 'OBS hat die Anmeldung abgelehnt.' }

        $script:ObsConnected = $true
        $txtObsHost.Text = $hostName
        $txtObsWsPort.Text = [string]$wsPort
        $btnObsConnect.Text = 'OBS trennen'
        $btnObsRefresh.Enabled = $true
        $lblObsStatus.Text = '● VERBUNDEN'
        $lblObsStatus.ForeColor = [System.Drawing.Color]::FromArgb(61, 220, 151)
        try {
            Refresh-ObsScenes
        }
        catch {
            Add-Log "OBS ist verbunden, aber die Szenenliste konnte noch nicht geladen werden: $($_.Exception.Message)"
            $btnObsCreateSource.Enabled = $false
        }
        Save-Settings
        Add-Log "Mit OBS WebSocket auf ${hostName}:${wsPort} verbunden."
    }
    catch {
        Disconnect-ObsWebSocket
        throw
    }
}

function Ensure-ObsMediaSource {
    param(
        [string]$SceneName,
        [string]$SourceName,
        [string]$InputUrl
    )

    $inputSettings = [ordered]@{
        is_local_file = $false
        input = $InputUrl
        input_format = ''
        buffering_mb = 2
        reconnect_delay_sec = 2
        hw_decode = $true
        clear_on_media_end = $true
        restart_on_activate = $true
        close_when_inactive = $false
    }

    $inputList = Invoke-ObsRequest -RequestType 'GetInputList'
    $existing = @($inputList.inputs) | Where-Object { $_.inputName -eq $SourceName } | Select-Object -First 1
    if ($existing) {
        if ($existing.inputKind -ne 'ffmpeg_source' -and $existing.unversionedInputKind -ne 'ffmpeg_source') {
            throw "In OBS gibt es bereits eine Quelle namens '$SourceName', die keine Medienquelle ist."
        }
        Invoke-ObsRequest -RequestType 'SetInputSettings' -RequestData ([ordered]@{
            inputName = $SourceName
            inputSettings = $inputSettings
            overlay = $true
        }) | Out-Null

        try {
            $sceneItem = Invoke-ObsRequest -RequestType 'GetSceneItemId' -RequestData ([ordered]@{ sceneName = $SceneName; sourceName = $SourceName })
        }
        catch {
            Invoke-ObsRequest -RequestType 'CreateSceneItem' -RequestData ([ordered]@{ sceneName = $SceneName; sourceName = $SourceName; sceneItemEnabled = $true }) | Out-Null
            $sceneItem = Invoke-ObsRequest -RequestType 'GetSceneItemId' -RequestData ([ordered]@{ sceneName = $SceneName; sourceName = $SourceName })
        }
        $action = 'aktualisiert'
    }
    else {
        Invoke-ObsRequest -RequestType 'CreateInput' -RequestData ([ordered]@{
            sceneName = $SceneName
            inputName = $SourceName
            inputKind = 'ffmpeg_source'
            inputSettings = $inputSettings
            sceneItemEnabled = $true
        }) | Out-Null
        $sceneItem = Invoke-ObsRequest -RequestType 'GetSceneItemId' -RequestData ([ordered]@{ sceneName = $SceneName; sourceName = $SourceName })
        $action = 'erstellt'
    }

    Invoke-ObsRequest -RequestType 'SetSceneItemEnabled' -RequestData ([ordered]@{
        sceneName = $SceneName
        sceneItemId = [int]$sceneItem.sceneItemId
        sceneItemEnabled = $true
    }) | Out-Null

    return [pscustomobject]@{
        SceneItemId = [int]$sceneItem.sceneItemId
        Action = $action
    }
}

function Set-ObsMediaSource {
    param(
        [switch]$Silent,
        [switch]$RestartInputs
    )

    if (-not $script:ObsConnected) { throw 'Zuerst mit dem OBS-WebSocket-Server verbinden.' }
    if ($cmbObsScene.SelectedIndex -lt 0) { throw 'Bitte eine OBS-Szene auswählen.' }
    $baseSourceName = $txtObsSourceName.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($baseSourceName)) { throw 'Bitte einen Namen für die OBS-Quelle eingeben.' }
    $basePort = 0
    if (-not [int]::TryParse($txtPort.Text.Trim(), [ref]$basePort) -or $basePort -lt 1024 -or $basePort -gt 65535) {
        throw 'Der SRT-Basisport muss zwischen 1024 und 65535 liegen.'
    }

    $sceneName = [string]$cmbObsScene.SelectedItem
    $urls = @(Get-ObsUrls)
    $tripleMode = $cmbCaptureMode.SelectedItem -eq 'UltraWide Triple-Split'
    if ($tripleMode -and $basePort -gt 65533) { throw 'Für Triple-Split muss der SRT-Basisport höchstens 65533 sein.' }
    $sourceCount = if ($tripleMode) { 3 } else { 1 }
    $segments = if ($tripleMode) { @(Get-TripleSegmentLayout) } else { @($null) }
    $preparedSources = [System.Collections.Generic.List[string]]::new()

    for ($index = 0; $index -lt $sourceCount; $index++) {
        $sourceName = if ($tripleMode) { "$baseSourceName - $($segments[$index].Label)" } else { $baseSourceName }
        $result = Ensure-ObsMediaSource -SceneName $sceneName -SourceName $sourceName -InputUrl $urls[$index]

        if ($tripleMode) {
            Invoke-ObsRequest -RequestType 'SetSceneItemTransform' -RequestData ([ordered]@{
                sceneName = $sceneName
                sceneItemId = [int]$result.SceneItemId
                sceneItemTransform = [ordered]@{
                    positionX = [double]$segments[$index].RelativeX
                    positionY = 0.0
                    scaleX = 1.0
                    scaleY = 1.0
                    alignment = 5
                    rotation = 0.0
                    cropLeft = 0
                    cropRight = 0
                    cropTop = 0
                    cropBottom = 0
                    boundsType = 'OBS_BOUNDS_NONE'
                }
            }) | Out-Null
        }
        [void]$preparedSources.Add($sourceName)
        Add-Log "OBS-Medienquelle '$sourceName' wurde in Szene '$sceneName' $($result.Action)."
    }

    if ($RestartInputs) {
        foreach ($sourceName in $preparedSources) {
            Invoke-ObsRequest -RequestType 'TriggerMediaInputAction' -RequestData ([ordered]@{
                inputName = $sourceName
                mediaAction = 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART'
            }) | Out-Null
        }
        Add-Log "$($preparedSources.Count) OBS-SRT-Empfänger wurden aktiviert und neu gestartet."
    }

    Save-Settings
    $message = if ($tripleMode) {
        "Drei Medienquellen wurden in OBS eingerichtet und nebeneinander positioniert.`r`n`r`nLinks: Port $basePort`r`nMitte: Port $($basePort + 1)`r`nRechts: Port $($basePort + 2)`r`n`r`nDie OBS-Basisleinwand sollte der gesamten UltraWide-Auflösung entsprechen. Jetzt in NetCapture die Übertragung starten."
    }
    else {
        "Die Medienquelle '$baseSourceName' wurde in OBS eingerichtet.`r`n`r`nJetzt in NetCapture die Übertragung starten."
    }
    if (-not $Silent) {
        [System.Windows.Forms.MessageBox]::Show($message, $script:AppName, 'OK', 'Information') | Out-Null
    }
}

function Start-Streaming {
    foreach ($runningProcess in @($script:FfmpegProcesses)) {
        try { if (-not $runningProcess.HasExited) { return } } catch { }
    }
    if ($script:FfmpegProcesses.Count -gt 0 -or $script:AudioCaptureSession) { Stop-Streaming }

    $streamSet = $null
    $localProcesses = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
    $localPumps = [System.Collections.Generic.List[object]]::new()
    try {
        $streamSet = Build-StreamSet
        if (-not $script:ObsConnected) {
            $requiredPorts = (@($streamSet.Streams) | ForEach-Object { [string]$_.Port }) -join ', '
            Add-Log "Start verhindert: OBS WebSocket ist nicht verbunden; SRT-Empfänger auf UDP $requiredPorts konnten nicht vorbereitet werden."
            if ($streamSet.AudioCapture) { try { $streamSet.AudioCapture.Dispose() } catch { } }
            [System.Windows.Forms.MessageBox]::Show(
                "Die Übertragung wurde noch nicht gestartet, weil OBS WebSocket nicht verbunden ist.`r`n`r`n1. OBS WebSocket auf dem OBS-PC aktivieren.`r`n2. In NetCapture mit OBS verbinden.`r`n3. Danach erneut auf 'Übertragung starten' klicken.`r`n`r`nNetCapture richtet dann die SRT-Empfänger auf UDP $requiredPorts automatisch ein und startet sie vor FFmpeg.",
                'Zuerst mit OBS verbinden',
                'OK',
                'Warning'
            ) | Out-Null
            return
        }

        Add-Log 'Prüfe OBS WebSocket und bereite die SRT-Empfänger vor ...'
        try {
            Invoke-ObsRequest -RequestType 'GetVersion' | Out-Null
            Set-ObsMediaSource -Silent -RestartInputs
            Start-Sleep -Milliseconds 1200
            Add-Log "OBS-SRT-Empfänger sind vorbereitet. FFmpeg erhält bis zu $script:SrtConnectTimeoutMs ms Verbindungszeit."
        }
        catch {
            Disconnect-ObsWebSocket
            throw "OBS konnte die SRT-Empfänger nicht vorbereiten. Die Übertragung wurde nicht gestartet: $($_.Exception.Message)"
        }

        if ($streamSet.AudioCapture) {
            $streamSet.AudioCapture.Start([string]$streamSet.AudioPipeName)
            $script:AudioCaptureSession = $streamSet.AudioCapture
            Add-Log "Windows-Tonaufnahme gestartet: $($cmbAudio.SelectedItem)"
        }

        foreach ($plan in @($streamSet.Streams)) {
            Add-Log ("Starte Stream [$($plan.Label)] auf UDP $($plan.Port): " + (Mask-Secret (Join-Arguments $plan.Arguments)))
            $info = New-Object System.Diagnostics.ProcessStartInfo
            $info.FileName = $plan.Executable
            $info.Arguments = Join-Arguments $plan.Arguments
            $info.UseShellExecute = $false
            $info.CreateNoWindow = $true
            $info.RedirectStandardError = $false
            $info.RedirectStandardOutput = $false
            $info.RedirectStandardInput = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $info
            $process.EnableRaisingEvents = $true
            $logPump = $null
            try {
                Initialize-AudioSupport
                $info.RedirectStandardError = $true
                $logPump = [CrazyBatto.ProcessLogPump]::new($process, $script:LogQueue, [string]$plan.Label)
                $logPump.Attach()
            }
            catch {
                Add-Log "FFmpeg-Protokollpuffer für '$($plan.Label)' nicht verfügbar: $($_.Exception.Message)"
                $info.RedirectStandardError = $false
                if ($logPump) { try { $logPump.Dispose() } catch { }; $logPump = $null }
            }

            [void]$localProcesses.Add($process)
            if ($logPump) {
                [void]$localPumps.Add($logPump)
            }
            if (-not $process.Start()) { throw "FFmpeg-Stream '$($plan.Label)' konnte nicht gestartet werden." }
            if ($logPump) { $logPump.BeginRead() }
        }

        $script:FfmpegProcesses.Clear()
        foreach ($process in $localProcesses) { [void]$script:FfmpegProcesses.Add($process) }
        $script:FfmpegLogPumps.Clear()
        foreach ($pump in $localPumps) { [void]$script:FfmpegLogPumps.Add($pump) }
        $script:StreamStartedAt = Get-Date

        $btnStart.Enabled = $false
        $btnStop.Enabled = $true
        $lblStatus.Text = if ($streamSet.TripleMode) { '● 3 STREAMS LAUFEN' } else { '● ÜBERTRAGUNG LÄUFT' }
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(61, 220, 151)
        Save-Settings
    }
    catch {
        foreach ($process in @($localProcesses)) {
            try {
                if (-not $process.HasExited) {
                    try { $process.StandardInput.WriteLine('q') } catch { }
                    if (-not $process.WaitForExit(1000)) { $process.Kill() }
                }
            }
            catch { }
        }
        foreach ($pump in @($localPumps)) { try { $pump.Dispose() } catch { } }
        foreach ($process in @($localProcesses)) { try { $process.Dispose() } catch { } }
        $script:FfmpegProcesses.Clear()
        $script:FfmpegLogPumps.Clear()
        $script:StreamStartedAt = $null
        $script:StoppingStream = $false
        if ($script:AudioCaptureSession) {
            try { $script:AudioCaptureSession.Dispose() } catch { }
            $script:AudioCaptureSession = $null
        }
        elseif ($streamSet -and $streamSet.AudioCapture) {
            try { $streamSet.AudioCapture.Dispose() } catch { }
        }
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:AppName, 'OK', 'Error') | Out-Null
        Add-Log "Startfehler: $($_.Exception.Message)"
    }
}

function Stop-Streaming {
    if ($script:FfmpegProcesses.Count -eq 0 -and -not $script:AudioCaptureSession) { return }
    $script:StoppingStream = $true
    try {
        foreach ($process in @($script:FfmpegProcesses)) {
            try { if (-not $process.HasExited) { $process.StandardInput.WriteLine('q') } } catch { }
        }
        foreach ($process in @($script:FfmpegProcesses)) {
            try {
                if (-not $process.HasExited -and -not $process.WaitForExit(2500)) { $process.Kill() }
            }
            catch { }
        }
    }
    catch { Add-Log "Stopfehler: $($_.Exception.Message)" }
    finally {
        foreach ($pump in @($script:FfmpegLogPumps)) { try { $pump.Dispose() } catch { } }
        foreach ($process in @($script:FfmpegProcesses)) { try { $process.Dispose() } catch { } }
        $script:FfmpegLogPumps.Clear()
        $script:FfmpegProcesses.Clear()
        $script:StreamStartedAt = $null
        if ($script:AudioCaptureSession) {
            try { $script:AudioCaptureSession.Dispose() } catch { }
            $script:AudioCaptureSession = $null
        }
        $btnStart.Enabled = [bool](Find-FFmpeg)
        $btnStop.Enabled = $false
        $lblStatus.Text = '● BEREIT'
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(159, 168, 190)
        Add-Log 'Übertragung gestoppt.'
        $script:StoppingStream = $false
    }
}

function Save-Settings {
    try {
        $directory = Split-Path -Parent $script:ConfigPath
        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        $selectedAudioId = $null
        $selectedAudioKind = $null
        if ($cmbAudio.SelectedIndex -gt 0 -and ($cmbAudio.SelectedIndex - 1) -lt $script:AudioDevices.Count) {
            $selectedAudioDevice = $script:AudioDevices[$cmbAudio.SelectedIndex - 1]
            $selectedAudioId = [string]$selectedAudioDevice.Id
            $selectedAudioKind = [string]$selectedAudioDevice.Kind
        }
        $selectedCaptureWindowTitle = $null
        if ($cmbCaptureMode.SelectedItem -ne 'Bildschirm' -and
            $cmbCaptureMode.SelectedItem -ne 'UltraWide Triple-Split' -and
            $cmbMonitor.SelectedIndex -ge 0 -and
            $cmbMonitor.SelectedIndex -lt $script:CaptureWindows.Count) {
            $selectedCaptureWindowTitle = [string]$script:CaptureWindows[$cmbMonitor.SelectedIndex].Title
        }
        if (($cmbCaptureMode.SelectedItem -eq 'Bildschirm' -or $cmbCaptureMode.SelectedItem -eq 'UltraWide Triple-Split') -and $cmbMonitor.SelectedIndex -ge 0) {
            $script:SavedMonitorIndex = $cmbMonitor.SelectedIndex
        }
        if (-not $chkLocalObsTest.Checked) {
            $script:RemoteTargetIp = $txtTargetIp.Text.Trim()
            $script:RemoteObsHost = $txtObsHost.Text.Trim()
        }
        $settings = [ordered]@{
            monitor = $script:SavedMonitorIndex
            captureMode = [string]$cmbCaptureMode.SelectedItem
            captureWindowTitle = $selectedCaptureWindowTitle
            targetIp = $script:RemoteTargetIp
            localObsTest = $chkLocalObsTest.Checked
            port = $txtPort.Text.Trim()
            fps = [string]$cmbFps.SelectedItem
            resolution = [string]$cmbResolution.SelectedItem
            bitrate = [int]$numBitrate.Value
            latency = [int]$numLatency.Value
            encoder = [string]$cmbEncoder.SelectedItem
            drawMouse = $chkMouse.Checked
            audioDeviceId = $selectedAudioId
            audioDeviceKind = $selectedAudioKind
            obsHost = $script:RemoteObsHost
            obsWebSocketPort = $txtObsWsPort.Text.Trim()
            obsSourceName = $txtObsSourceName.Text.Trim()
        }
        $settings | ConvertTo-Json | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
    }
    catch { Add-Log "Einstellungen konnten nicht gespeichert werden: $($_.Exception.Message)" }
}

function Load-Settings {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) { return }
    try {
        $settings = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json
        $captureWindowProperty = $settings.PSObject.Properties['captureWindowTitle']
        if ($captureWindowProperty -and $captureWindowProperty.Value) { $script:SavedCaptureWindowTitle = [string]$captureWindowProperty.Value }
        $monitorProperty = $settings.PSObject.Properties['monitor']
        if ($monitorProperty -and $monitorProperty.Value -ge 0) { $script:SavedMonitorIndex = [int]$monitorProperty.Value }
        $captureModeProperty = $settings.PSObject.Properties['captureMode']
        if ($captureModeProperty -and $captureModeProperty.Value -and $cmbCaptureMode.Items.Contains([string]$captureModeProperty.Value)) {
            $cmbCaptureMode.SelectedItem = [string]$captureModeProperty.Value
        }
        Refresh-CaptureTargets
        if ($settings.targetIp) {
            $script:RemoteTargetIp = [string]$settings.targetIp
            $txtTargetIp.Text = $script:RemoteTargetIp
        }
        if ($settings.port) { $txtPort.Text = [string]$settings.port }
        if ($settings.fps -and $cmbFps.Items.Contains([string]$settings.fps)) { $cmbFps.SelectedItem = [string]$settings.fps }
        if ($settings.resolution -and $cmbResolution.Items.Contains([string]$settings.resolution)) { $cmbResolution.SelectedItem = [string]$settings.resolution }
        if ($settings.encoder -and $cmbEncoder.Items.Contains([string]$settings.encoder)) { $cmbEncoder.SelectedItem = [string]$settings.encoder }
        if ($settings.bitrate) { $numBitrate.Value = [decimal]$settings.bitrate }
        if ($settings.latency) { $numLatency.Value = [decimal]$settings.latency }
        if ($null -ne $settings.drawMouse) { $chkMouse.Checked = [bool]$settings.drawMouse }
        $audioIdProperty = $settings.PSObject.Properties['audioDeviceId']
        if ($audioIdProperty -and $audioIdProperty.Value) { $script:SavedAudioDeviceId = [string]$audioIdProperty.Value }
        $audioKindProperty = $settings.PSObject.Properties['audioDeviceKind']
        if ($audioKindProperty -and $audioKindProperty.Value) { $script:SavedAudioDeviceKind = [string]$audioKindProperty.Value }
        $obsHostProperty = $settings.PSObject.Properties['obsHost']
        if ($obsHostProperty -and $obsHostProperty.Value) {
            $script:RemoteObsHost = [string]$obsHostProperty.Value
            $txtObsHost.Text = $script:RemoteObsHost
        }
        $obsPortProperty = $settings.PSObject.Properties['obsWebSocketPort']
        if ($obsPortProperty -and $obsPortProperty.Value) { $txtObsWsPort.Text = [string]$obsPortProperty.Value }
        $obsSourceProperty = $settings.PSObject.Properties['obsSourceName']
        if ($obsSourceProperty -and $obsSourceProperty.Value) { $txtObsSourceName.Text = [string]$obsSourceProperty.Value }
        $localObsTestProperty = $settings.PSObject.Properties['localObsTest']
        $localObsTestEnabled = $localObsTestProperty -and [bool]$localObsTestProperty.Value
        $script:ApplyingLocalObsTestMode = $true
        try { $chkLocalObsTest.Checked = $localObsTestEnabled }
        finally { $script:ApplyingLocalObsTestMode = $false }
        Set-LocalObsTestMode -Enabled $localObsTestEnabled -CaptureRemoteValues $false
        if ($cmbCaptureMode.SelectedItem -eq 'UltraWide Triple-Split') {
            $cmbResolution.SelectedItem = 'Original'
            $cmbResolution.Enabled = $false
            if ($numBitrate.Value -lt 30000) { $numBitrate.Value = 30000 }
        }
    }
    catch { Add-Log "Einstellungen konnten nicht geladen werden: $($_.Exception.Message)" }
}

function Set-LocalObsTestMode {
    param(
        [bool]$Enabled,
        [bool]$CaptureRemoteValues = $true
    )

    if ($Enabled) {
        if ($CaptureRemoteValues) {
            $targetIp = $txtTargetIp.Text.Trim()
            $obsHost = $txtObsHost.Text.Trim()
            if ($targetIp -and $targetIp -ne '127.0.0.1') { $script:RemoteTargetIp = $targetIp }
            if ($obsHost -and $obsHost -ne '127.0.0.1') { $script:RemoteObsHost = $obsHost }
        }
        $txtTargetIp.Text = '127.0.0.1'
        $txtObsHost.Text = '127.0.0.1'
        $txtTargetIp.ReadOnly = $true
        $txtObsHost.ReadOnly = $true
        $btnPing.Text = 'Dieser PC'
        $btnObsConnect.Text = 'Lokal mit OBS verbinden'
        $rightHeader.Text = 'VERBINDUNG ZU OBS - LOKAL'
        Add-Log 'Lokaler OBS-Test aktiv: SRT und OBS-WebSocket verwenden 127.0.0.1. Ein zweiter PC und eine Firewall-Freigabe sind nicht erforderlich.'
    }
    else {
        $txtTargetIp.ReadOnly = $false
        $txtObsHost.ReadOnly = $false
        $txtTargetIp.Text = $script:RemoteTargetIp
        $txtObsHost.Text = $script:RemoteObsHost
        $btnPing.Text = 'PC testen'
        $btnObsConnect.Text = 'Mit OBS verbinden'
        $rightHeader.Text = 'VERBINDUNG ZUM OBS-PC'
        Add-Log 'Netzwerkmodus aktiv: Die gespeicherte Adresse des OBS-PCs wurde wiederhergestellt.'
    }
}

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 180)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, 22)
    $label.ForeColor = [System.Drawing.Color]::FromArgb(181, 190, 211)
    $label.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    return $label
}

function Style-Control {
    param([System.Windows.Forms.Control]$Control)
    $Control.BackColor = [System.Drawing.Color]::FromArgb(27, 33, 49)
    $Control.ForeColor = [System.Drawing.Color]::White
    $Control.Font = New-Object System.Drawing.Font('Segoe UI', 9)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "$($script:AppName) $($script:AppVersion)"
$form.ClientSize = New-Object System.Drawing.Size(920, 875)
$form.MinimumSize = New-Object System.Drawing.Size(936, 914)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::FromArgb(12, 16, 27)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'CRAZY_BATTO  /  NETCAPTURE'
$title.Location = New-Object System.Drawing.Point(28, 22)
$title.Size = New-Object System.Drawing.Size(520, 36)
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 18)
$title.ForeColor = [System.Drawing.Color]::FromArgb(79, 157, 255)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Bildschirm, Fenster oder Spiel werden wie eine Netzwerk-Capture-Karte an OBS übertragen.'
$subtitle.Location = New-Object System.Drawing.Point(30, 58)
$subtitle.Size = New-Object System.Drawing.Size(650, 24)
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(159, 168, 190)
$form.Controls.Add($subtitle)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = '● BEREIT'
$lblStatus.TextAlign = 'MiddleRight'
$lblStatus.Location = New-Object System.Drawing.Point(690, 26)
$lblStatus.Size = New-Object System.Drawing.Size(190, 30)
$lblStatus.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(159, 168, 190)
$form.Controls.Add($lblStatus)

$left = New-Object System.Windows.Forms.Panel
$left.Location = New-Object System.Drawing.Point(28, 100)
$left.Size = New-Object System.Drawing.Size(420, 430)
$left.BackColor = [System.Drawing.Color]::FromArgb(18, 23, 37)
$form.Controls.Add($left)

$right = New-Object System.Windows.Forms.Panel
$right.Location = New-Object System.Drawing.Point(466, 100)
$right.Size = New-Object System.Drawing.Size(426, 430)
$right.BackColor = [System.Drawing.Color]::FromArgb(18, 23, 37)
$form.Controls.Add($right)

$leftHeader = New-Label 'BILD UND TON' 20 18 300
$leftHeader.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
$leftHeader.ForeColor = [System.Drawing.Color]::FromArgb(79, 157, 255)
$left.Controls.Add($leftHeader)

$left.Controls.Add((New-Label 'Aufnahmeart' 20 58 140))
$lblCaptureTarget = New-Label 'Bildschirm' 170 58 210
$left.Controls.Add($lblCaptureTarget)

$cmbCaptureMode = New-Object System.Windows.Forms.ComboBox
$cmbCaptureMode.Location = New-Object System.Drawing.Point(20, 80)
$cmbCaptureMode.Size = New-Object System.Drawing.Size(140, 28)
$cmbCaptureMode.DropDownStyle = 'DropDownList'
@('Bildschirm', 'Fensteraufnahme', 'Spielaufnahme', 'UltraWide Triple-Split') | ForEach-Object { [void]$cmbCaptureMode.Items.Add($_) }
$cmbCaptureMode.SelectedItem = 'Bildschirm'
$cmbCaptureMode.DropDownWidth = 210
Style-Control $cmbCaptureMode
$left.Controls.Add($cmbCaptureMode)

$cmbMonitor = New-Object System.Windows.Forms.ComboBox
$cmbMonitor.Location = New-Object System.Drawing.Point(170, 80)
$cmbMonitor.Size = New-Object System.Drawing.Size(190, 28)
$cmbMonitor.DropDownWidth = 610
$cmbMonitor.DropDownStyle = 'DropDownList'
Style-Control $cmbMonitor
$left.Controls.Add($cmbMonitor)

$btnCaptureRefresh = New-Object System.Windows.Forms.Button
$btnCaptureRefresh.Text = '↻'
$btnCaptureRefresh.Location = New-Object System.Drawing.Point(368, 78)
$btnCaptureRefresh.Size = New-Object System.Drawing.Size(32, 31)
Style-Control $btnCaptureRefresh
$left.Controls.Add($btnCaptureRefresh)

$captureToolTip = New-Object System.Windows.Forms.ToolTip
$captureToolTip.SetToolTip($cmbCaptureMode, 'UltraWide Triple-Split teilt einen breiten Surround-Bildschirm auf drei SRT-Streams und Ports auf.')
$captureToolTip.SetToolTip($btnCaptureRefresh, 'Liste der Bildschirme, Fenster oder Spiele aktualisieren')

$left.Controls.Add((New-Label 'Ausgabeauflösung' 20 123 170))
$left.Controls.Add((New-Label 'Bildrate' 216 123 120))
$cmbResolution = New-Object System.Windows.Forms.ComboBox
$cmbResolution.Location = New-Object System.Drawing.Point(20, 145)
$cmbResolution.Size = New-Object System.Drawing.Size(176, 28)
$cmbResolution.DropDownStyle = 'DropDownList'
@('Original', '1280x720', '1920x1080', '2560x1440', '3840x2160') | ForEach-Object { [void]$cmbResolution.Items.Add($_) }
$cmbResolution.SelectedItem = '1920x1080'
Style-Control $cmbResolution
$left.Controls.Add($cmbResolution)

$cmbFps = New-Object System.Windows.Forms.ComboBox
$cmbFps.Location = New-Object System.Drawing.Point(216, 145)
$cmbFps.Size = New-Object System.Drawing.Size(184, 28)
$cmbFps.DropDownStyle = 'DropDownList'
@('30', '60', '120') | ForEach-Object { [void]$cmbFps.Items.Add($_) }
$cmbFps.SelectedItem = '60'
Style-Control $cmbFps
$left.Controls.Add($cmbFps)

$left.Controls.Add((New-Label 'Encoder' 20 188))
$cmbEncoder = New-Object System.Windows.Forms.ComboBox
$cmbEncoder.Location = New-Object System.Drawing.Point(20, 210)
$cmbEncoder.Size = New-Object System.Drawing.Size(380, 28)
$cmbEncoder.DropDownStyle = 'DropDownList'
@('NVIDIA NVENC (H.264)', 'AMD AMF (H.264)', 'Intel Quick Sync (H.264)', 'CPU x264 (H.264)') | ForEach-Object { [void]$cmbEncoder.Items.Add($_) }
$cmbEncoder.SelectedIndex = 0
Style-Control $cmbEncoder
$left.Controls.Add($cmbEncoder)

$left.Controls.Add((New-Label 'Bitrate (kbit/s)' 20 252 170))
$left.Controls.Add((New-Label 'SRT-Puffer (ms)' 216 252 170))
$numBitrate = New-Object System.Windows.Forms.NumericUpDown
$numBitrate.Location = New-Object System.Drawing.Point(20, 274)
$numBitrate.Size = New-Object System.Drawing.Size(176, 28)
$numBitrate.Minimum = 1000
$numBitrate.Maximum = 150000
$numBitrate.Increment = 1000
$numBitrate.Value = 20000
Style-Control $numBitrate
$left.Controls.Add($numBitrate)

$numLatency = New-Object System.Windows.Forms.NumericUpDown
$numLatency.Location = New-Object System.Drawing.Point(216, 274)
$numLatency.Size = New-Object System.Drawing.Size(184, 28)
$numLatency.Minimum = 40
$numLatency.Maximum = 2000
$numLatency.Increment = 20
$numLatency.Value = 120
Style-Control $numLatency
$left.Controls.Add($numLatency)

$left.Controls.Add((New-Label 'Tonquelle (Windows-WASAPI)' 20 316 260))
$cmbAudio = New-Object System.Windows.Forms.ComboBox
$cmbAudio.Location = New-Object System.Drawing.Point(20, 338)
$cmbAudio.Size = New-Object System.Drawing.Size(260, 28)
$cmbAudio.DropDownStyle = 'DropDownList'
Style-Control $cmbAudio
$left.Controls.Add($cmbAudio)

$btnAudioRefresh = New-Object System.Windows.Forms.Button
$btnAudioRefresh.Text = 'Tonquellen laden'
$btnAudioRefresh.Location = New-Object System.Drawing.Point(290, 337)
$btnAudioRefresh.Size = New-Object System.Drawing.Size(110, 30)
Style-Control $btnAudioRefresh
$left.Controls.Add($btnAudioRefresh)

$lblAudioHint = New-Label '„Tonquellen laden“ zeigt PC-Ausgänge und Mikrofone.' 20 369 380
$lblAudioHint.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$left.Controls.Add($lblAudioHint)

$chkMouse = New-Object System.Windows.Forms.CheckBox
$chkMouse.Text = 'Mauszeiger mit übertragen'
$chkMouse.Location = New-Object System.Drawing.Point(20, 395)
$chkMouse.Size = New-Object System.Drawing.Size(240, 25)
$chkMouse.Checked = $true
$chkMouse.ForeColor = [System.Drawing.Color]::White
$left.Controls.Add($chkMouse)

$rightHeader = New-Label 'VERBINDUNG ZUM OBS-PC' 20 18 244
$rightHeader.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
$rightHeader.ForeColor = [System.Drawing.Color]::FromArgb(79, 157, 255)
$right.Controls.Add($rightHeader)

$chkLocalObsTest = New-Object System.Windows.Forms.CheckBox
$chkLocalObsTest.Text = 'Dieser PC testen'
$chkLocalObsTest.Location = New-Object System.Drawing.Point(272, 16)
$chkLocalObsTest.Size = New-Object System.Drawing.Size(132, 26)
$chkLocalObsTest.ForeColor = [System.Drawing.Color]::FromArgb(112, 193, 255)
$chkLocalObsTest.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 8)
$right.Controls.Add($chkLocalObsTest)

$localObsTestToolTip = New-Object System.Windows.Forms.ToolTip
$localObsTestToolTip.SetToolTip($chkLocalObsTest, 'Verwendet 127.0.0.1 für SRT und OBS-WebSocket. Damit kann OBS auf demselben PC getestet werden.')

$right.Controls.Add((New-Label 'IPv4-Adresse des OBS-PCs' 20 58 250))
$txtTargetIp = New-Object System.Windows.Forms.TextBox
$txtTargetIp.Location = New-Object System.Drawing.Point(20, 80)
$txtTargetIp.Size = New-Object System.Drawing.Size(260, 28)
$txtTargetIp.Text = '192.168.178.50'
Style-Control $txtTargetIp
$right.Controls.Add($txtTargetIp)

$btnPing = New-Object System.Windows.Forms.Button
$btnPing.Text = 'PC testen'
$btnPing.Location = New-Object System.Drawing.Point(292, 78)
$btnPing.Size = New-Object System.Drawing.Size(112, 31)
Style-Control $btnPing
$right.Controls.Add($btnPing)

$right.Controls.Add((New-Label 'SRT-Basisport (UDP)' 20 123 180))
$txtPort = New-Object System.Windows.Forms.TextBox
$txtPort.Location = New-Object System.Drawing.Point(20, 145)
$txtPort.Size = New-Object System.Drawing.Size(176, 28)
$txtPort.Text = '9000'
Style-Control $txtPort
$right.Controls.Add($txtPort)

$btnSrtHelp = New-Object System.Windows.Forms.Button
$btnSrtHelp.Text = '?'
$btnSrtHelp.Location = New-Object System.Drawing.Point(204, 143)
$btnSrtHelp.Size = New-Object System.Drawing.Size(32, 30)
Style-Control $btnSrtHelp
$right.Controls.Add($btnSrtHelp)

$lblSrtHelp = New-Label 'Bild/Ton: gleicher UDP-Port in NetCapture, OBS und Firewall.' 20 173 384
$lblSrtHelp.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$right.Controls.Add($lblSrtHelp)

$right.Controls.Add((New-Label 'SRT-AES-Verschlüsselung (optional)' 20 194 300))
$txtPassphrase = New-Object System.Windows.Forms.TextBox
$txtPassphrase.Location = New-Object System.Drawing.Point(20, 216)
$txtPassphrase.Size = New-Object System.Drawing.Size(344, 28)
$txtPassphrase.UseSystemPasswordChar = $true
Style-Control $txtPassphrase
$right.Controls.Add($txtPassphrase)

$btnEncryptionHelp = New-Object System.Windows.Forms.Button
$btnEncryptionHelp.Text = '?'
$btnEncryptionHelp.Location = New-Object System.Drawing.Point(372, 214)
$btnEncryptionHelp.Size = New-Object System.Drawing.Size(32, 30)
Style-Control $btnEncryptionHelp
$right.Controls.Add($btnEncryptionHelp)

$lblEncryptionHelp = New-Label 'AES-128 für den SRT-Stream; leer = aus; Passwort: 10–79 Zeichen.' 20 246 384
$lblEncryptionHelp.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$right.Controls.Add($lblEncryptionHelp)

$right.Controls.Add((New-Label 'In OBS als Medienquelle eintragen:' 20 270 330))
$txtObsUrl = New-Object System.Windows.Forms.TextBox
$txtObsUrl.Location = New-Object System.Drawing.Point(20, 292)
$txtObsUrl.Size = New-Object System.Drawing.Size(384, 52)
$txtObsUrl.Multiline = $true
$txtObsUrl.ReadOnly = $true
$txtObsUrl.Text = 'srt://0.0.0.0:9000?mode=listener&transtype=live&latency=120000'
Style-Control $txtObsUrl
$right.Controls.Add($txtObsUrl)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = 'OBS-Adresse kopieren'
$btnCopy.Location = New-Object System.Drawing.Point(20, 357)
$btnCopy.Size = New-Object System.Drawing.Size(184, 38)
$btnCopy.BackColor = [System.Drawing.Color]::FromArgb(36, 93, 166)
$btnCopy.ForeColor = [System.Drawing.Color]::White
$btnCopy.FlatStyle = 'Flat'
$right.Controls.Add($btnCopy)

$btnFfmpeg = New-Object System.Windows.Forms.Button
$btnFfmpeg.Text = 'FFmpeg installieren'
$btnFfmpeg.Location = New-Object System.Drawing.Point(220, 357)
$btnFfmpeg.Size = New-Object System.Drawing.Size(184, 38)
$btnFfmpeg.BackColor = [System.Drawing.Color]::FromArgb(48, 55, 74)
$btnFfmpeg.ForeColor = [System.Drawing.Color]::White
$btnFfmpeg.FlatStyle = 'Flat'
$right.Controls.Add($btnFfmpeg)

$lblLocalIps = New-Label 'Lokale IPs dieses PCs: wird geladen …' 20 404 386
$lblLocalIps.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$right.Controls.Add($lblLocalIps)

$obsPanel = New-Object System.Windows.Forms.Panel
$obsPanel.Location = New-Object System.Drawing.Point(28, 546)
$obsPanel.Size = New-Object System.Drawing.Size(864, 174)
$obsPanel.BackColor = [System.Drawing.Color]::FromArgb(18, 23, 37)
$form.Controls.Add($obsPanel)

$obsHeader = New-Label 'OBS WEBSOCKET-SERVER' 20 13 300
$obsHeader.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
$obsHeader.ForeColor = [System.Drawing.Color]::FromArgb(79, 157, 255)
$obsPanel.Controls.Add($obsHeader)

$lblObsStatus = New-Label '● NICHT VERBUNDEN' 620 13 215
$lblObsStatus.TextAlign = 'MiddleRight'
$lblObsStatus.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$obsPanel.Controls.Add($lblObsStatus)

$obsPanel.Controls.Add((New-Label 'OBS-PC / Hostname' 20 45 220))
$txtObsHost = New-Object System.Windows.Forms.TextBox
$txtObsHost.Location = New-Object System.Drawing.Point(20, 67)
$txtObsHost.Size = New-Object System.Drawing.Size(245, 28)
$txtObsHost.Text = '192.168.178.50'
Style-Control $txtObsHost
$obsPanel.Controls.Add($txtObsHost)

$obsPanel.Controls.Add((New-Label 'Port' 280 45 80))
$txtObsWsPort = New-Object System.Windows.Forms.TextBox
$txtObsWsPort.Location = New-Object System.Drawing.Point(280, 67)
$txtObsWsPort.Size = New-Object System.Drawing.Size(90, 28)
$txtObsWsPort.Text = '4455'
Style-Control $txtObsWsPort
$obsPanel.Controls.Add($txtObsWsPort)

$obsPanel.Controls.Add((New-Label 'WebSocket-Passwort' 385 45 200))
$txtObsPassword = New-Object System.Windows.Forms.TextBox
$txtObsPassword.Location = New-Object System.Drawing.Point(385, 67)
$txtObsPassword.Size = New-Object System.Drawing.Size(200, 28)
$txtObsPassword.UseSystemPasswordChar = $true
Style-Control $txtObsPassword
$obsPanel.Controls.Add($txtObsPassword)

$btnObsConnect = New-Object System.Windows.Forms.Button
$btnObsConnect.Text = 'Mit OBS verbinden'
$btnObsConnect.Location = New-Object System.Drawing.Point(600, 65)
$btnObsConnect.Size = New-Object System.Drawing.Size(235, 31)
$btnObsConnect.BackColor = [System.Drawing.Color]::FromArgb(36, 93, 166)
$btnObsConnect.ForeColor = [System.Drawing.Color]::White
$btnObsConnect.FlatStyle = 'Flat'
$obsPanel.Controls.Add($btnObsConnect)

$obsPanel.Controls.Add((New-Label 'OBS-Szene' 20 105 220))
$cmbObsScene = New-Object System.Windows.Forms.ComboBox
$cmbObsScene.Location = New-Object System.Drawing.Point(20, 127)
$cmbObsScene.Size = New-Object System.Drawing.Size(245, 28)
$cmbObsScene.DropDownStyle = 'DropDownList'
Style-Control $cmbObsScene
$obsPanel.Controls.Add($cmbObsScene)

$obsPanel.Controls.Add((New-Label 'Name der Medienquelle' 280 105 260))
$txtObsSourceName = New-Object System.Windows.Forms.TextBox
$txtObsSourceName.Location = New-Object System.Drawing.Point(280, 127)
$txtObsSourceName.Size = New-Object System.Drawing.Size(305, 28)
$txtObsSourceName.Text = 'Crazy_Batto NetCapture'
Style-Control $txtObsSourceName
$obsPanel.Controls.Add($txtObsSourceName)

$btnObsRefresh = New-Object System.Windows.Forms.Button
$btnObsRefresh.Text = 'Szenen ↻'
$btnObsRefresh.Location = New-Object System.Drawing.Point(600, 125)
$btnObsRefresh.Size = New-Object System.Drawing.Size(90, 31)
$btnObsRefresh.Enabled = $false
Style-Control $btnObsRefresh
$obsPanel.Controls.Add($btnObsRefresh)

$btnObsCreateSource = New-Object System.Windows.Forms.Button
$btnObsCreateSource.Text = 'Quelle einrichten'
$btnObsCreateSource.Location = New-Object System.Drawing.Point(700, 125)
$btnObsCreateSource.Size = New-Object System.Drawing.Size(135, 31)
$btnObsCreateSource.Enabled = $false
$btnObsCreateSource.BackColor = [System.Drawing.Color]::FromArgb(34, 126, 82)
$btnObsCreateSource.ForeColor = [System.Drawing.Color]::White
$btnObsCreateSource.FlatStyle = 'Flat'
$obsPanel.Controls.Add($btnObsCreateSource)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = 'ÜBERTRAGUNG STARTEN'
$btnStart.Location = New-Object System.Drawing.Point(28, 738)
$btnStart.Size = New-Object System.Drawing.Size(270, 48)
$btnStart.BackColor = [System.Drawing.Color]::FromArgb(34, 126, 82)
$btnStart.ForeColor = [System.Drawing.Color]::White
$btnStart.FlatStyle = 'Flat'
$btnStart.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$form.Controls.Add($btnStart)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = 'STOPPEN'
$btnStop.Location = New-Object System.Drawing.Point(310, 738)
$btnStop.Size = New-Object System.Drawing.Size(138, 48)
$btnStop.BackColor = [System.Drawing.Color]::FromArgb(145, 53, 67)
$btnStop.ForeColor = [System.Drawing.Color]::White
$btnStop.FlatStyle = 'Flat'
$btnStop.Enabled = $false
$form.Controls.Add($btnStop)

$btnOpenLog = New-Object System.Windows.Forms.Button
$btnOpenLog.Text = 'Protokoll öffnen'
$btnOpenLog.Location = New-Object System.Drawing.Point(466, 738)
$btnOpenLog.Size = New-Object System.Drawing.Size(140, 48)
Style-Control $btnOpenLog
$form.Controls.Add($btnOpenLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(28, 800)
$txtLog.Size = New-Object System.Drawing.Size(864, 54)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(8, 11, 19)
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(159, 168, 190)
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 8)
$form.Controls.Add($txtLog)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 350
$timer.Add_Tick({
    try {
        $line = $null
        $added = 0
        while ($added -lt 20 -and $script:LogQueue.TryDequeue([ref]$line)) {
            $txtLog.AppendText($line + [Environment]::NewLine)
            $added++
        }
        foreach ($process in @($script:FfmpegProcesses)) {
            if ($process.HasExited) {
                $failedEarly = -not $script:StoppingStream -and $script:StreamStartedAt -and (((Get-Date) - $script:StreamStartedAt).TotalSeconds -lt 30)
                $exitCode = $null
                try { $exitCode = [int]$process.ExitCode } catch { }
                $srtConnectionFailed = $false
                foreach ($pump in @($script:FfmpegLogPumps)) {
                    try {
                        if ([bool]$pump.SrtConnectionFailed) {
                            $srtConnectionFailed = $true
                            break
                        }
                    }
                    catch { }
                }
                Stop-Streaming
                if ($failedEarly) {
                    $failureText = if ($srtConnectionFailed -and $chkLocalObsTest.Checked) {
                        "Der lokale SRT-Empfänger in OBS ist nicht erreichbar.`r`n`r`nPrüfe, ob die NetCapture-Medienquelle in der gewählten OBS-Szene sichtbar und aktiv ist. Im lokalen Test ist keine Firewall-Freigabe erforderlich."
                    }
                    elseif ($srtConnectionFailed) {
                        "OBS wurde vorbereitet, aber die SRT-Verbindung ist trotzdem fehlgeschlagen.`r`n`r`nPrüfe auf dem OBS-PC die Windows-Firewall für die verwendeten UDP-Ports und kontrolliere, ob NetCapture die richtige IPv4-Adresse des OBS-PCs verwendet."
                    }
                    else {
                        "Ein FFmpeg-Stream wurde direkt nach dem Start beendet$(if ($null -ne $exitCode) { " (Code $exitCode)" } else { '' }).`r`n`r`nDas ist nicht automatisch ein SRT-Portfehler. Mögliche Ursachen sind der gewählte Encoder, der Grafikkartentreiber, eine ungültige Aufnahmequelle oder eine zu hohe Auflösung."
                    }
                    [System.Windows.Forms.MessageBox]::Show(
                        "$failureText`r`n`r`nDetails stehen im Protokoll.",
                        $(if ($srtConnectionFailed) { 'SRT-Empfänger nicht erreichbar' } else { 'FFmpeg wurde beendet' }),
                        'OK',
                        'Error'
                    ) | Out-Null
                }
                break
            }
        }
    }
    catch {
        Add-Log "Statusaktualisierung abgefangen: $($_.Exception.Message)"
    }
})

$updateObsUrl = {
    try { $txtObsUrl.Text = (@(Get-ObsUrls) -join [Environment]::NewLine) } catch { }
}
$txtPort.Add_TextChanged($updateObsUrl)
$numLatency.Add_ValueChanged($updateObsUrl)
$txtPassphrase.Add_TextChanged($updateObsUrl)

$chkLocalObsTest.Add_CheckedChanged({
    if ($script:ApplyingLocalObsTestMode) { return }
    if ($script:ObsConnected) { Disconnect-ObsWebSocket }
    Set-LocalObsTestMode -Enabled $chkLocalObsTest.Checked -CaptureRemoteValues $true
    if ($chkLocalObsTest.Checked) {
        [System.Windows.Forms.MessageBox]::Show(
            "Lokaler Test ist aktiv.`r`n`r`n1. OBS auf diesem PC starten.`r`n2. In OBS unter Werkzeuge -> WebSocket-Servereinstellungen den Server aktivieren.`r`n3. Hier auf 'Lokal mit OBS verbinden' klicken.`r`n4. Szene wählen und 'Quelle einrichten' klicken.`r`n5. Danach die Übertragung starten.`r`n`r`nTipp: Bei Bildschirmaufnahme OBS minimieren oder Fenster-/Spielaufnahme wählen, damit kein Endlos-Spiegeleffekt entsteht.",
            'OBS auf diesem PC testen',
            'OK',
            'Information'
        ) | Out-Null
    }
})

$btnStart.Add_Click({ Start-Streaming })
$btnStop.Add_Click({ Stop-Streaming })
$cmbCaptureMode.Add_SelectedIndexChanged({
    $tripleMode = $cmbCaptureMode.SelectedItem -eq 'UltraWide Triple-Split'
    $cmbResolution.Enabled = -not $tripleMode
    if ($tripleMode) {
        $cmbResolution.SelectedItem = 'Original'
        if ($numBitrate.Value -lt 30000) { $numBitrate.Value = 30000 }
        $lblSrtHelp.Text = 'Triple-Split nutzt Basisport, Basisport +1 und +2 (z. B. 9000–9002).'
    }
    else {
        $lblSrtHelp.Text = 'Bild/Ton: gleicher UDP-Port in NetCapture, OBS und Firewall.'
    }
    Refresh-CaptureTargets
    & $updateObsUrl
})
$cmbMonitor.Add_SelectedIndexChanged({
    if (($cmbCaptureMode.SelectedItem -eq 'Bildschirm' -or $cmbCaptureMode.SelectedItem -eq 'UltraWide Triple-Split') -and $cmbMonitor.SelectedIndex -ge 0) {
        $script:SavedMonitorIndex = $cmbMonitor.SelectedIndex
    }
    elseif ($cmbMonitor.SelectedIndex -ge 0 -and $cmbMonitor.SelectedIndex -lt $script:CaptureWindows.Count) {
        $script:SavedCaptureWindowTitle = [string]$script:CaptureWindows[$cmbMonitor.SelectedIndex].Title
    }
})
$btnCaptureRefresh.Add_Click({ Refresh-CaptureTargets })
$btnAudioRefresh.Add_Click({ Refresh-AudioDevices })
$btnSrtHelp.Add_Click({
    [System.Windows.Forms.MessageBox]::Show(
        "Der SRT-Port ist der UDP-Netzwerkanschluss für Bild und Ton.`r`n`r`nStandard: 9000`r`n`r`nIm normalen Modus wird nur dieser Port verwendet. UltraWide Triple-Split verwendet den Basisport sowie die nächsten zwei Ports, also bei 9000 die UDP-Ports 9000, 9001 und 9002. Alle verwendeten Ports müssen auf dem OBS-PC in der Windows-Firewall für eingehendes UDP freigegeben sein.`r`n`r`nSRT-Port 9000 ist nicht der OBS-WebSocket-Port 4455.",
        'SRT-Port erklärt',
        'OK',
        'Information'
    ) | Out-Null
})
$btnEncryptionHelp.Add_Click({
    [System.Windows.Forms.MessageBox]::Show(
        "Diese Einstellung verschlüsselt ausschließlich den SRT-Bild- und Tonstream mit AES-128.`r`n`r`nLeer lassen: SRT läuft ohne Verschlüsselung.`r`nPasswort eintragen: 10 bis 79 Zeichen. NetCapture trägt dasselbe Passwort automatisch in die OBS-Adresse ein.`r`n`r`nDas SRT-Passwort wird nicht gespeichert. Es ist unabhängig vom OBS-WebSocket-Passwort.",
        'SRT-Verschlüsselung erklärt',
        'OK',
        'Information'
    ) | Out-Null
})
$btnCopy.Add_Click({
    [System.Windows.Forms.Clipboard]::SetText((@(Get-ObsUrls) -join [Environment]::NewLine))
    Add-Log 'OBS-Adresse(n) wurden in die Zwischenablage kopiert.'
})
$btnPing.Add_Click({
    $address = $txtTargetIp.Text.Trim()
    if (-not (Test-TargetAddress $address)) {
        [System.Windows.Forms.MessageBox]::Show('Ungültige IPv4-Adresse.', $script:AppName, 'OK', 'Warning') | Out-Null
        return
    }
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send($address, 1200)
        if ($reply.Status -eq 'Success') {
            [System.Windows.Forms.MessageBox]::Show("PC antwortet in $($reply.RoundtripTime) ms.", $script:AppName, 'OK', 'Information') | Out-Null
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("Keine Ping-Antwort ($($reply.Status)). Der Stream kann trotzdem funktionieren, falls Ping blockiert wird.", $script:AppName, 'OK', 'Warning') | Out-Null
        }
    }
    catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:AppName, 'OK', 'Error') | Out-Null }
})
$btnObsConnect.Add_Click({
    $btnObsConnect.Enabled = $false
    try { Connect-ObsWebSocket }
    catch {
        Add-Log "OBS-WebSocket-Fehler: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("Verbindung zu OBS fehlgeschlagen:`r`n`r`n$($_.Exception.Message)`r`n`r`nPrüfe in OBS: Werkzeuge → WebSocket-Servereinstellungen, Port 4455 und Windows-Firewall.", $script:AppName, 'OK', 'Error') | Out-Null
    }
    finally { $btnObsConnect.Enabled = $true }
})
$btnObsRefresh.Add_Click({
    try { Refresh-ObsScenes }
    catch {
        Add-Log "OBS-Szenen konnten nicht geladen werden: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:AppName, 'OK', 'Error') | Out-Null
    }
})
$btnObsCreateSource.Add_Click({
    $btnObsCreateSource.Enabled = $false
    try { Set-ObsMediaSource }
    catch {
        Add-Log "OBS-Quelle konnte nicht eingerichtet werden: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, $script:AppName, 'OK', 'Error') | Out-Null
    }
    finally { $btnObsCreateSource.Enabled = $script:ObsConnected -and $cmbObsScene.SelectedIndex -ge 0 }
})
$btnFfmpeg.Add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show('FFmpeg wird mit Windows Package Manager (winget) installiert. Fortfahren?', $script:AppName, 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }
    try {
        $winget = Get-Command winget.exe -ErrorAction Stop
        $installer = Start-Process -FilePath $winget.Source -ArgumentList @('install', '--id', 'Gyan.FFmpeg', '--exact', '--scope', 'user', '--accept-source-agreements', '--accept-package-agreements') -Wait -PassThru
        if ($installer.ExitCode -ne 0) { throw "winget meldete Fehlercode $($installer.ExitCode)." }
        $installedFfmpeg = Find-FFmpeg
        if (-not $installedFfmpeg) { throw 'Die Installation wurde beendet, aber ffmpeg.exe konnte danach nicht gefunden werden.' }
        $btnFfmpeg.Text = 'FFmpeg vorhanden ✓'
        $btnFfmpeg.Enabled = $false
        $btnStart.Enabled = $true
        $lblStatus.Text = '● BEREIT'
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(159, 168, 190)
        Refresh-AudioDevices
        Add-Log "FFmpeg erfolgreich eingerichtet: $installedFfmpeg"
        [System.Windows.Forms.MessageBox]::Show('FFmpeg wurde erfolgreich installiert. NetCapture ist jetzt bereit.', $script:AppName, 'OK', 'Information') | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Automatische Installation fehlgeschlagen: $($_.Exception.Message)`r`n`r`nAlternativ ffmpeg.exe in den NetCapture-Ordner legen.", $script:AppName, 'OK', 'Error') | Out-Null
    }
})
$btnOpenLog.Add_Click({
    if (Test-Path -LiteralPath $script:LogPath) { Start-Process -FilePath 'notepad.exe' -ArgumentList $script:LogPath }
    else { Add-Log 'Noch kein Protokoll vorhanden.' }
})
$form.Add_FormClosing({ Stop-Streaming; Disconnect-ObsWebSocket; Save-Settings })
$form.Add_Shown({
    try {
        $timer.Start()
        Refresh-Monitors
        Load-Settings
        Initialize-AudioSelection
        $addresses = @(Get-LanAddresses)
        $lblLocalIps.Text = 'Lokale IPs dieses PCs: ' + $(if ($addresses.Count) { $addresses -join ', ' } else { 'keine gefunden' })
        $ffmpeg = Find-FFmpeg
        if ($ffmpeg) {
            Add-Log "FFmpeg gefunden: $ffmpeg"
            $btnFfmpeg.Text = 'FFmpeg vorhanden ✓'
            $btnFfmpeg.Enabled = $false
        }
        else {
            Add-Log 'FFmpeg fehlt. Bitte über die Schaltfläche installieren.'
            $btnStart.Enabled = $false
            $lblStatus.Text = '● FFMPEG FEHLT'
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(240, 174, 72)
        }
    }
    catch {
        Add-Log "Startinitialisierung fehlgeschlagen, das Fenster bleibt geöffnet: $($_.Exception.Message)"
        $lblStatus.Text = '● STARTFEHLER – PROTOKOLL PRÜFEN'
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(235, 91, 112)
        [System.Windows.Forms.MessageBox]::Show("NetCapture konnte nicht vollständig initialisiert werden, bleibt aber geöffnet:`r`n`r`n$($_.Exception.Message)`r`n`r`nÖffne das Protokoll für weitere Details.", $script:AppName, 'OK', 'Error') | Out-Null
    }
})

try {
    [void]$form.ShowDialog()
}
catch {
    Add-Log "Unerwarteter Programmfehler: $($_.Exception.ToString())"
    [System.Windows.Forms.MessageBox]::Show("NetCapture hat einen unerwarteten Fehler abgefangen:`r`n`r`n$($_.Exception.Message)`r`n`r`nDas Protokoll wurde gespeichert unter:`r`n$script:LogPath", $script:AppName, 'OK', 'Error') | Out-Null
}
finally {
    try { Stop-Streaming } catch { }
    try { Disconnect-ObsWebSocket } catch { }
    try { $timer.Stop() } catch { }
}
