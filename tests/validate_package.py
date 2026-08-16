from pathlib import Path
import struct
import re


ROOT = Path(__file__).resolve().parents[1]


def require(path: str) -> str:
    target = ROOT / path
    assert target.is_file(), f"missing file: {path}"
    return target.read_text(encoding="utf-8-sig", errors="strict")


def main() -> None:
    script = require("NetCapture.ps1")
    audio_bridge = require("AudioPipeCapture.cs")
    audio_project = require("AudioPipeCapture.csproj")
    audio_builder = require("Build-AudioBridge.ps1")
    launcher = require("NetCaptureLauncher.cs")
    launcher_project = require("NetCaptureLauncher.csproj")
    launcher_builder = require("Build-Launcher.ps1")
    ffmpeg_downloader = require("Download-FFmpeg.ps1")
    builder = require("Build-Installer.ps1")
    installer = require("installer/NetCapture.iss")
    workflow = require(".github/workflows/build-windows-installer.yml")
    require("assets/NetCapture.svg")
    require("assets/WizardImage.svg")
    wizard_image = ROOT / "assets/WizardImage.bmp"
    wizard_small = ROOT / "assets/WizardSmallImage.bmp"
    team_logo = ROOT / "assets/TeamAlpha-Logo.jpeg"
    assert wizard_image.is_file() and wizard_image.read_bytes()[:2] == b"BM", "invalid wizard image"
    assert wizard_small.is_file() and wizard_small.read_bytes()[:2] == b"BM", "invalid small wizard image"
    assert team_logo.is_file() and team_logo.stat().st_size > 100_000, "missing Team Alpha logo source"
    assert struct.unpack_from("<ii", wizard_image.read_bytes(), 18) == (492, 942), "wrong wizard image size"
    assert struct.unpack_from("<ii", wizard_small.read_bytes(), 18) == (192, 192), "wrong small wizard image size"
    icon = ROOT / "assets/NetCapture.ico"
    assert icon.is_file(), "missing file: assets/NetCapture.ico"
    assert icon.read_bytes()[:4] == b"\x00\x00\x01\x00", "invalid Windows icon header"
    assert struct.unpack_from("<H", icon.read_bytes(), 4)[0] == 7, "Windows icon must contain seven sizes"
    assert icon.stat().st_size > 300_000, "Team Alpha icon was not embedded"
    readme = require("README.md")
    release_notes = require("RELEASE-NOTES-v0.6.8.md")
    require("LICENSE.txt")
    require("THIRD-PARTY-NOTICES.md")

    required_script_features = {
        "monitor enumeration": "[System.Windows.Forms.Screen]::AllScreens",
        "capture mode selection": "Fensteraufnahme",
        "borderless game capture": "Spielaufnahme",
        "UltraWide dual capture": "UltraWide Dual-Split",
        "dual segmentation": "Get-DualSegmentLayout",
        "two parallel FFmpeg processes": "$dualMode",
        "custom output resolution": "$cmbResolution.DropDownStyle = 'DropDown'",
        "UltraWide triple capture": "UltraWide Triple-Split",
        "even triple segmentation": "Get-TripleSegmentLayout",
        "three parallel FFmpeg processes": "$script:FfmpegProcesses",
        "window title input": "'title=' + [string]$segment.WindowTitle",
        "capture target refresh": "Refresh-CaptureTargets",
        "SRT caller": "mode=caller",
        "OBS listener": "mode=listener",
        "NVIDIA encoder": "h264_nvenc",
        "AMD encoder": "h264_amf",
        "Intel encoder": "h264_qsv",
        "software encoder": "libx264",
        "secret masking": "passphrase=********",
        "settings storage": "settings.json",
        "Windows audio device listing": "Get-WindowsAudioDevices",
        "automatic PC audio selection": "Automatisch gewählt:",
        "explicit no-audio logging": "Die Übertragung wird ohne Ton gestartet (-an).",
        "WASAPI audio bridge": "CrazyBatto.AudioPipeCapture",
        "precompiled audio bridge": "Get-NAudioFile 'AudioPipeCapture.dll'",
        "thread-safe FFmpeg log pump": "CrazyBatto.ProcessLogPump",
        "mutable FFmpeg argument list": "$arguments = [System.Collections.Generic.List[string]]::new()",
        "SRT port help": "SRT-Port erklärt",
        "SRT encryption help": "SRT-Verschlüsselung erklärt",
        "OBS WebSocket client": "System.Net.WebSockets.ClientWebSocket",
        "OBS WebSocket authentication": "Get-ObsAuthentication",
        "OBS scene loading": "GetSceneList",
        "OBS source creation": "CreateInput",
        "OBS source update": "SetInputSettings",
        "OBS media source kind": "ffmpeg_source",
        "OBS triple positioning": "SetSceneItemTransform",
        "OBS top-left alignment": "alignment = 5",
        "same-PC OBS test": "$chkLocalObsTest",
        "loopback streaming": "127.0.0.1",
        "local mode persistence": "localObsTest = $chkLocalObsTest.Checked",
        "local mode address restore": "Set-LocalObsTestMode",
        "non-enumerated OBS response": "Write-Output -NoEnumerate $responseProperty.Value",
        "scene response shape check": "$sceneList.PSObject.Properties['scenes']",
        "active scene fallback": "GetCurrentProgramScene",
        "OBS URI normalization": "[System.UriBuilder]::new('ws', $hostName, $wsPort)",
        "scene refresh keeps connection": "OBS ist verbunden, aber die Szenenliste konnte noch nicht geladen werden",
    }
    for name, marker in required_script_features.items():
        assert marker in script, f"missing feature marker: {name}"

    assert "srt://0.0.0.0:9000" in readme
    assert "connect_timeout=20000" in release_notes
    assert "NDI wird nicht verwendet" in release_notes
    assert "Lokale Datei" in readme
    assert "JRSoftware.InnoSetup" in builder
    assert "Build-Launcher.ps1" in builder
    assert "SkipLauncherBuild" in builder
    assert "PrivilegesRequired=admin" in installer
    assert "DefaultDirName={autopf}\\Crazy_Batto\\NetCapture" in installer
    assert "UsePreviousAppDir=no" in installer
    assert "Uninstallable=yes" in installer
    assert "[UninstallDelete]" in installer
    assert "DisableWelcomePage=no" in installer
    assert "WizardImageFile=" in installer
    assert "Willkommen beim Installations-Assistenten" in installer
    assert "third_party\\ffmpeg\\ffmpeg.exe" in installer
    assert "third_party\\launcher\\NetCapture.exe" in installer
    assert "RELEASE-NOTES-v0.6.8.md" in installer
    assert "OutputBaseFilename=CrazyBatto-NetCapture-Setup-v0.6.8" in installer
    assert "UseSetupLdr=no" in installer, "setup must not execute a loader from the Windows TEMP directory"
    assert "ArchitecturesAllowed=x64compatible" in installer
    assert "ArchitecturesInstallIn64BitMode=x64compatible" in installer
    assert "SetupArchitecture=" not in installer, "SetupArchitecture requires Inno Setup 7"
    assert "NetCapture.ico" in installer
    assert '#define MyAppExeName "NetCapture.exe"' in installer
    assert 'Filename: "{app}\\{#MyAppExeName}"' in installer
    assert "wscript.exe" not in installer
    assert ".cmd" not in installer.lower()
    assert ".vbs" not in installer.lower()
    assert "AudioPipeCapture.cs" not in installer
    assert "AudioPipeCapture.dll" in installer
    assert "NAudio.Core.dll" in installer
    assert "NAudio.Wasapi.dll" in installer
    generated_installer_sources = {
        "..\\third_party\\naudio\\AudioPipeCapture.dll",
        "..\\third_party\\launcher\\NetCapture.exe",
    }
    for source in re.findall(r'^Source: "([^"*?]+)"', installer, flags=re.MULTILINE):
        if source in generated_installer_sources:
            continue
        source_path = (ROOT / "installer" / source.replace("\\", "/")).resolve()
        assert source_path.is_file(), f"installer source is missing: {source}"
    ffmpeg = ROOT / "third_party/ffmpeg/ffmpeg.exe"
    assert ffmpeg.is_file(), "bundled ffmpeg.exe is missing"
    assert ffmpeg.stat().st_size > 50_000_000, "bundled ffmpeg.exe is unexpectedly small"
    require("third_party/ffmpeg/FFMPEG-LICENSE.txt")
    naudio_core = ROOT / "third_party/naudio/NAudio.Core.dll"
    naudio_wasapi = ROOT / "third_party/naudio/NAudio.Wasapi.dll"
    assert naudio_core.is_file() and naudio_core.read_bytes()[:2] == b"MZ", "invalid NAudio.Core.dll"
    assert naudio_wasapi.is_file() and naudio_wasapi.read_bytes()[:2] == b"MZ", "invalid NAudio.Wasapi.dll"
    require("third_party/naudio/NAUDIO-LICENSE.txt")
    assert "WasapiLoopbackCapture" in audio_bridge
    assert "WasapiCapture" in audio_bridge
    assert "NamedPipeServerStream" in audio_bridge
    assert "ConcurrentQueue<string>" in audio_bridge
    assert "class ProcessLogPump" in audio_bridge
    assert "this(process, queue, \"FFmpeg\")" in audio_bridge
    assert "queue.Enqueue(\"[\" + label + \"] \" + safeLine)" in audio_bridge
    assert "public bool SrtConnectionFailed" in audio_bridge
    assert "Interlocked.CompareExchange(ref srtHelpQueued" in audio_bridge
    assert "class CapturableWindow" in audio_bridge
    assert "class WindowCaptureHelper" in audio_bridge
    assert "EnumWindows" in audio_bridge
    assert "<TargetFramework>net472</TargetFramework>" in audio_project
    assert "NAudio.Core.dll" in audio_project and "NAudio.Wasapi.dll" in audio_project
    assert "dotnet" in audio_builder and "AudioPipeCapture.dll" in audio_builder
    assert "ProcessStartInfo" in launcher
    assert "FileName = powershellPath" in launcher
    assert "CreateNoWindow = true" in launcher
    assert "WindowStyle = ProcessWindowStyle.Hidden" in launcher
    assert '"WindowsPowerShell"' in launcher
    assert '"launcher.log"' in launcher
    assert "RedirectStandardError = true" in launcher
    assert "process.WaitForExit();" in launcher
    assert "NetCapture - Startfehler" in launcher
    assert "<OutputType>WinExe</OutputType>" in launcher_project
    assert "<TargetFramework>net472</TargetFramework>" in launcher_project
    assert "<ApplicationIcon>assets\\NetCapture.ico</ApplicationIcon>" in launcher_project
    assert "dotnet" in launcher_builder and "NetCapture.exe" in launcher_builder
    assert "$iconTime" in launcher_builder, "launcher must rebuild after icon changes"
    assert "FEC81AE03971D9DD4BE3EBE02E263BD2EC1D789483F931BDBA5F5715E65DA2E9" in ffmpeg_downloader
    assert "Get-FileHash" in ffmpeg_downloader
    assert "Build-AudioBridge.ps1 -Force" in workflow
    assert "Build-Launcher.ps1 -Force" in workflow
    assert "Download-FFmpeg.ps1" in workflow
    assert "Build-Installer.ps1 -SkipAudioBuild -SkipLauncherBuild" in workflow
    assert "CrazyBatto-NetCapture-Setup-v0.6.8.zip" in workflow
    assert "CrazyBatto-NetCapture-v0.6.8-Windows" in workflow
    assert "Compress-Archive" in builder
    assert "$setupParts.Count -lt 2" in builder
    assert "$script:AppVersion = '0.6.8'" in script
    assert "$txtTargetIp.Text = '127.0.0.1'" in script
    assert "$txtObsHost.Text = '127.0.0.1'" in script
    assert "Firewall-Freigabe sind nicht erforderlich" in script
    assert "timeout=5000000" not in script, "OBS listener must not expire after five seconds"
    assert "$script:SrtConnectTimeoutMs = 20000" in script, "SRT caller timeout must be 20 seconds"
    assert "connect_timeout=$script:SrtConnectTimeoutMs" in script, "SRT caller URL must use the configured timeout"
    assert "Invoke-ObsRequest -RequestType 'GetVersion'" in script, "OBS WebSocket must be checked before FFmpeg starts"
    assert "Set-ObsMediaSource -Silent -RestartInputs" in script, "OBS SRT listeners must be restarted before FFmpeg"
    assert "Start verhindert: OBS WebSocket ist nicht verbunden" in script, "stream start must be blocked without OBS preflight"
    assert "Trotzdem starten?" not in script, "unsafe start without OBS preflight must not remain"
    assert "SrtConnectionFailed" in script, "early FFmpeg errors must distinguish SRT failures"
    assert "includeAudio = $index -eq 0" in script, "triple mode must not duplicate audio in OBS"
    assert "if ($dualMode) { 2 } elseif ($tripleMode) { 3 }" in script, "OBS must create two or three SRT listeners for split modes"
    assert "basePort + [int]$segment.PortOffset" in script, "split streams must use consecutive ports"
    assert "resolution = [string]$cmbResolution.Text" in script, "custom output resolution must be persisted"
    assert "if (($baseWidth % 2) -ne 0)" in script, "H.264 triple widths must be even"
    dual_total_width = 11620
    dual_left_width = dual_total_width // 2
    if dual_left_width % 2:
        dual_left_width -= 1
    dual_widths = (dual_left_width, dual_total_width - dual_left_width)
    assert dual_widths == (5810, 5810)
    assert sum(dual_widths) == dual_total_width and all(width % 2 == 0 for width in dual_widths)
    triple_total_width = 11620
    triple_base_width = triple_total_width // 3
    if triple_base_width % 2:
        triple_base_width -= 1
    triple_widths = (triple_base_width, triple_base_width, triple_total_width - triple_base_width * 2)
    assert triple_widths == (3872, 3872, 3876)
    assert sum(triple_widths) == triple_total_width and all(width % 2 == 0 and width <= 4096 for width in triple_widths)
    assert "$script:FfmpegProcess =" not in script, "obsolete single-process state must not remain"
    assert "$script:FfmpegLogPump =" not in script, "obsolete single-log-pump state must not remain"
    assert not re.search(r"(?<!\[void\])\$arguments\.Add\(", script), "List.Add return values must not leak into Build-StreamSet output"
    assert audio_bridge.count("{") == audio_bridge.count("}"), "unbalanced C# curly braces"
    assert script.count("{") == script.count("}"), "unbalanced curly braces"
    assert script.count("(") == script.count(")"), "unbalanced parentheses"
    assert "PlaceholderText" not in script, "must remain compatible with Windows PowerShell 5.1"
    assert "NDI" not in script, "sender must not depend on NDI"
    assert "$args.Add" not in script, "must not mutate PowerShell's fixed-size automatic $args array"
    assert re.search(r"Load-Settings\s+Initialize-AudioSelection", script), "startup must not block on audio enumeration"
    assert "Add-Type -TypeDefinition $sourceCode" not in script, "audio bridge must not be compiled at runtime"
    assert "AudioPipeCapture.cs" not in script, "runtime must load the precompiled audio bridge"
    assert ".add_ErrorDataReceived" not in script, "PowerShell callbacks must not run on FFmpeg worker threads"
    assert ".add_Exited" not in script, "PowerShell callbacks must not run on FFmpeg worker threads"
    for obsolete_launcher in (
        "Build-Installer.cmd",
        "Install.cmd",
        "Start-NetCapture.cmd",
        "Run-NetCapture.vbs",
        "Publish-GitHub.cmd",
    ):
        assert not (ROOT / obsolete_launcher).exists(), f"obsolete command launcher remains: {obsolete_launcher}"

    print("NetCapture package validation passed")


if __name__ == "__main__":
    main()
