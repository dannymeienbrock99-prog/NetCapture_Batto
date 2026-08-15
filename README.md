# Crazy_Batto NetCapture 0.6.3

Crazy_Batto NetCapture überträgt einen Windows-Monitor über das lokale Netzwerk an einen zweiten PC mit OBS Studio. Es funktioniert wie eine softwarebasierte Netzwerk-Capture-Karte und verwendet dafür SRT.

## Voraussetzungen

- Windows 10 oder Windows 11
- OBS Studio 28 oder neuer auf dem Empfänger-PC
- FFmpeg auf dem Sender-PC
- möglichst Gigabit-LAN; WLAN funktioniert, kann aber stärker schwanken

## Installation mit Setup.exe

Die normale Windows-Installation erfolgt mit `CrazyBatto-NetCapture-Setup-v0.6.3.zip`. Das ZIP muss zuerst vollständig entpackt werden. Danach wird `CrazyBatto-NetCapture-Setup-v0.6.3.exe` aus dem entpackten Ordner gestartet. Die danebenliegenden `.bin`-Dateien gehören zum Installer und dürfen nicht gelöscht oder einzeln verschoben werden. Diese Mehrdatei-Ausgabe verwendet `UseSetupLdr=no` und startet deshalb keinen Setup-Teil mehr aus dem Windows-TEMP-Ordner. Der Assistent bietet eine eigene Willkommensseite mit Team-Alpha-Logo, Lizenzseite, Startmenü- und Desktop-Verknüpfung sowie einen vollständigen Eintrag unter **Windows-Einstellungen → Apps → Installierte Apps**.

Der GitHub-Actions-Workflow `.github/workflows/build-windows-installer.yml` erstellt zuerst `AudioPipeCapture.dll` und den fensterlosen `NetCapture.exe`-Launcher. Danach wird automatisch der vollständige Inno-Setup-Installer erzeugt. Im installierten Programm werden keine CMD- oder VBS-Startdateien verwendet. Für einen lokalen Entwickler-Build werden das .NET 8 SDK und Inno Setup 6 benötigt; der Build wird mit `powershell.exe -ExecutionPolicy Bypass -File .\Build-Installer.ps1` gestartet.

Der erzeugte Installer ist technisch vollständig, aber noch nicht mit einem kostenpflichtigen Code-Signing-Zertifikat signiert. Windows SmartScreen kann deshalb beim ersten Start eine Rückfrage anzeigen.

## Schnellstart

1. `CrazyBatto-NetCapture-Setup-v0.6.3.zip` vollständig entpacken und anschließend `CrazyBatto-NetCapture-Setup-v0.6.3.exe` im entpackten Ordner starten.
2. Auf dem OBS-PC in OBS **Werkzeuge → WebSocket-Servereinstellungen** öffnen, den Server aktivieren und Port sowie Passwort merken. Standardport ist `4455`.
3. NetCapture öffnen. Unter **OBS WebSocket-Server** IP-Adresse des OBS-PCs, Port und Passwort eintragen und **Mit OBS verbinden** drücken.
4. Eine OBS-Szene auswählen, einen Quellennamen festlegen und **Quelle einrichten** drücken.
5. NetCapture erstellt oder aktualisiert automatisch eine SRT-Medienquelle in dieser Szene.
6. Für Ton einmal **Tonquellen laden** drücken und den gewünschten `PC-Ton:`-Ausgang oder ein `Mikrofon:` auswählen.
7. Danach **Übertragung starten** drücken.

Das WebSocket-Passwort wird nur für die laufende Verbindung verwendet und nicht in `settings.json` gespeichert.

## Aufnahmearten

Oben links kann die Quelle gewählt und mit **↻** neu eingelesen werden:

- **Bildschirm:** überträgt den ausgewählten vollständigen Monitor einschließlich optionalem Mauszeiger.
- **Fensteraufnahme:** zeigt alle sichtbaren, nicht minimierten Windows-Fenster und überträgt nur das ausgewählte Fenster.
- **Spielaufnahme:** zeigt große aktive Fenster, die sich für Spiele eignen, und verwendet einen größeren Echtzeitpuffer. Das Spiel sollte im Fenster- oder randlosen Vollbildmodus laufen.
- **UltraWide Triple-Split:** teilt einen von Windows als einen Monitor erkannten UltraWide-/NVIDIA-Surround-Bildschirm in drei gerade H.264-Teilbilder. NetCapture sendet diese gleichzeitig über drei SRT-Ports. Damit ist beispielsweise `11620×2160` als `3872×2160`, `3872×2160` und `3876×2160` möglich.

Die Spielaufnahme verwendet keine Prozessinjektion und keinen Anti-Cheat-relevanten Grafik-Hook. Exklusives Vollbild kann deshalb schwarz bleiben; in diesem Fall im Spiel **Randloses Fenster** einstellen oder als Aufnahmeart **Bildschirm** verwenden. Wird ein Zielfenster geschlossen oder sein Fenstertitel geändert, die Quellenliste mit **↻** aktualisieren.

## UltraWide 11620×2160 über drei Streams

Ein einzelner H.264-Stream kann diese Breite nicht zuverlässig codieren. Version 0.6.3 startet deshalb im Modus **UltraWide Triple-Split** drei getrennte FFmpeg-Prozesse:

1. NVIDIA Surround oder eine vergleichbare Windows-Anordnung muss die vollständige Fläche als **einen** Monitor mit `11620×2160` anzeigen.
2. In NetCapture **UltraWide Triple-Split**, den breiten Monitor, den Basisport `9000` und möglichst `NVIDIA NVENC (H.264)` wählen. Die Ausgabe bleibt automatisch auf **Original**.
3. Empfohlen sind zunächst `60 FPS`, `30.000–60.000 kbit/s` **pro Teilstream** und `180–300 ms` SRT-Puffer. Für drei Streams ist Gigabit-LAN erforderlich; die Grafikkarte muss drei gleichzeitige Encoder-Sitzungen und die Gesamtlast schaffen.
4. In OBS unter **Einstellungen → Video** die Basisleinwand auf die gesamte Auflösung, zum Beispiel `11620×2160`, stellen.
5. Über OBS WebSocket **Quelle einrichten** drücken. NetCapture erstellt automatisch `… - Links`, `… - Mitte` und `… - Rechts`, positioniert sie nebeneinander und verwendet die UDP-Ports `9000`, `9001` und `9002`.
6. Ton wird absichtlich nur über die linke Quelle übertragen, damit er in OBS nicht dreifach abgespielt wird.

Bei einer anderen UltraWide-Breite verteilt NetCapture die Pixel automatisch auf drei gerade Teilbreiten. Jeder Teil darf höchstens `4096×4096` Pixel groß sein. Die vollständige Breite darf daher höchstens `12288` Pixel betragen.

## SRT-Adressen für Kontrolle und Fehlersuche

Die von NetCapture automatisch in OBS eingetragenen Listener-Adressen können bei der Fehlersuche von Hand kontrolliert werden:

1. NetCapture über WebSocket mit OBS verbinden.
2. **Quelle einrichten** drücken und anschließend die erzeugte OBS-Medienquelle öffnen.
3. Prüfen, dass **Lokale Datei** deaktiviert ist.
4. Die OBS-Eingabe mit der von NetCapture angezeigten Listener-Adresse vergleichen.

Beispiel für OBS:

```text
srt://0.0.0.0:9000?mode=listener&transtype=live&latency=120000
```

Bei Triple-Split zeigt NetCapture drei Adressen an: Links mit Port `9000`, Mitte mit Port `9001` und Rechts mit Port `9002`. Die Quellen werden automatisch ohne Skalierung bei X=`0`, X=`3872` und X=`7744` positioniert; diese Werte gelten für `11620×2160`.

Auf dem Sender muss die IPv4-Adresse des OBS-PCs eingetragen werden. Sie findet sich auf dem OBS-PC mit `ipconfig`, meistens beispielsweise `192.168.178.40`. Dieselbe Adresse kann für SRT und OBS WebSocket verwendet werden.

## OBS-WebSocket-Verbindung

NetCapture spricht direkt das in aktuellen OBS-Versionen enthaltene obs-websocket-v5-Protokoll. Nach erfolgreicher Anmeldung lädt die App die Szenenliste. **Quelle einrichten** verwendet den OBS-Quellentyp `ffmpeg_source`, trägt die aktuelle SRT-Listener-Adresse ein und fügt die Quelle der gewählten Szene hinzu. Existiert die Medienquelle bereits, werden ihre SRT-Einstellungen aktualisiert.

Im UltraWide-Triple-Modus richtet derselbe Knopf drei Medienquellen ein, setzt ihre Positionen auf die Teilbildgrenzen und verwendet den Basisport sowie die zwei folgenden Ports.

NetCapture bereitet diese Quellen bei jedem Klick auf **Übertragung starten** erneut vor: Zuerst wird die OBS-WebSocket-Verbindung geprüft, danach werden die Szenenelemente aktiviert, die SRT-Adressen aktualisiert und die Medienquellen mit `TriggerMediaInputAction` neu gestartet. Nach einer kurzen Bereitschaftszeit werden die FFmpeg-Caller mit 20 Sekunden Verbindungszeit geöffnet. Ohne aktive OBS-WebSocket-Verbindung wird FFmpeg nicht gestartet; dadurch endet die Anwendung nicht mehr sofort mit dem irreführenden SRT-Code `-5`.

Die WebSocket-Steuerung transportiert nur Steuerbefehle. Das eigentliche Bild und der Ton laufen weiterhin über SRT. Deshalb müssen sowohl TCP-Port `4455` für die Steuerung als auch der gewählte UDP-Port, standardmäßig `9000`, zwischen den PCs erreichbar sein.

## Empfohlene Einstellungen

| Auflösung | FPS | Bitrate | SRT-Puffer |
| --- | ---: | ---: | ---: |
| 1920×1080 | 60 | 15.000–25.000 kbit/s | 120 ms |
| 2560×1440 | 60 | 25.000–40.000 kbit/s | 120–180 ms |
| 3840×2160 | 60 | 50.000–100.000 kbit/s | 180–300 ms |
| UltraWide-Teil bis 4096×2160 | 60 | 30.000–60.000 kbit/s je Stream | 180–300 ms |

Für NVIDIA-Grafikkarten ist `NVIDIA NVENC (H.264)` vorgesehen. Bei AMD `AMD AMF`, bei Intel `Quick Sync`. CPU x264 dient als Rückfallebene.

## SRT-Port

Der SRT-Port ist der UDP-Netzwerkanschluss für den eigentlichen Bild- und Tonstream. Standard ist `9000`. Derselbe Port muss in NetCapture und in der OBS-Medienquelle verwendet werden. Auf dem OBS-PC muss die Windows-Firewall eingehendes UDP für diesen Port erlauben.

Im Modus **UltraWide Triple-Split** ist das Feld ein Basisport. Bei `9000` werden automatisch `9000` für Links, `9001` für Mitte und `9002` für Rechts verwendet. Das Programm zeigt und kopiert dann drei OBS-Listener-Adressen.

Der SRT-Port ist unabhängig vom OBS-WebSocket-Port. Standardmäßig gilt:

| Funktion | Protokoll | Standardport |
| --- | --- | ---: |
| Bild- und Tonstream über SRT | UDP | `9000` |
| OBS-Fernsteuerung über WebSocket | TCP | `4455` |

## PC-Ton und Mikrofone

Die Tonquellen werden nicht mehr automatisch beim Programmstart gesucht. Dadurch öffnet sich das Fenster sofort. Nach einem Klick auf **Tonquellen laden** zeigt NetCapture alle aktiven Windows-Audiogeräte:

- `PC-Ton:` Lautsprecher, Headsets sowie HDMI-/DisplayPort-Ausgänge. Der komplette auf diesem Gerät wiedergegebene Ton wird per WASAPI-Loopback aufgenommen.
- `Mikrofon:` aktive Windows-Eingabegeräte.
- `Kein Ton:` überträgt ausschließlich das Monitorbild.

Stereo Mix ist für den PC-Ton nicht mehr erforderlich. Die gewählte Geräte-ID wird gespeichert; die Liste kann jederzeit mit **Neu laden** aktualisiert werden.

Seit Version 0.4.3 wird die NAudio-Brücke bereits beim Windows-Build zu `AudioPipeCapture.dll` kompiliert und vom Installer mitgeliefert. NetCapture erzeugt deshalb beim Start keine temporären C#-Dateien mehr und benötigt auf dem Nutzer-PC weder `csc.exe` noch eine `netstandard.dll`-Referenz für einen Laufzeit-Compiler.

## Verschlüsselung

Optional kann der SRT-Bild- und Tonstream mit AES-128 verschlüsselt werden. Dafür wird ein Passwort mit 10 bis 79 Zeichen eingetragen. NetCapture erzeugt automatisch die passende SRT-Adresse für OBS, damit Sender und Empfänger dasselbe Passwort verwenden. Bleibt das Feld leer, ist die SRT-Verschlüsselung ausgeschaltet.

Das SRT-Passwort wird nicht in den Einstellungen gespeichert und im Protokoll maskiert. Es ist unabhängig vom OBS-WebSocket-Passwort.

## Firewall

Falls kein Bild ankommt, muss Windows Defender Firewall eingehenden UDP-Verkehr für den gewählten Port auf dem OBS-PC erlauben. Standard ist UDP-Port `9000`; Triple-Split benötigt standardmäßig UDP `9000–9002`. Für die automatische OBS-Einrichtung muss zusätzlich der OBS-WebSocket-Port als eingehender TCP-Port erreichbar sein; Standard ist `4455`. FFmpeg und NetCapture auf dem Sender müssen ausgehenden Netzwerkverkehr verwenden dürfen.

Beispiel für eine als Administrator gestartete PowerShell auf dem OBS-PC:

```powershell
New-NetFirewallRule -DisplayName 'Crazy_Batto NetCapture SRT Triple' -Direction Inbound -Protocol UDP -LocalPort '9000-9002' -Action Allow
```

## Fehlerbehebung

- **OBS bleibt schwarz:** OBS-Medienquelle zuerst aktivieren, anschließend NetCapture starten.
- **WebSocket-Verbindung fehlgeschlagen:** WebSocket-Server in OBS aktivieren, IP-Adresse, TCP-Port `4455`, Passwort und Firewall prüfen.
- **Authentifizierung fehlgeschlagen:** Das WebSocket-Passwort aus OBS erneut in NetCapture eingeben. Es wird absichtlich nicht gespeichert.
- **Connection timed out:** IP-Adresse, UDP-Port und Firewall prüfen.
- **Unknown encoder:** Der gewählte Encoder ist in der installierten FFmpeg-Version nicht enthalten. Anderen Encoder auswählen.
- **No capable devices found:** Der gewählte Hardware-Encoder passt nicht zur Grafikkarte oder der Treiber fehlt.
- **Bild ruckelt:** Bitrate reduzieren, LAN verwenden oder den SRT-Puffer erhöhen.
- **Keine Tonquelle sichtbar:** **Tonquellen laden** beziehungsweise **Neu laden** drücken und prüfen, ob das Gerät in den Windows-Soundeinstellungen aktiv ist.
- **Kein PC-Ton:** Einen Eintrag mit `PC-Ton:` wählen. Ein `Mikrofon:`-Eintrag nimmt nur das jeweilige Eingabegerät auf.
- **SRT `I/O error` / Code -5:** NetCapture prüft und startet die OBS-Medienquelle jetzt automatisch vor FFmpeg. Tritt der Fehler trotzdem auf, auf dem OBS-PC eingehendes UDP für die verwendeten Ports freigeben und die eingetragene IPv4-Adresse prüfen. Alte OBS-Adressen mit `timeout=5000000` ersetzen.
- **Alle drei Triple-Streams melden gleichzeitig Code -5:** Die Bildschirmaufnahme ist in diesem Fall in Ordnung, aber OBS lauscht noch nicht auf `9000–9002`. Zuerst NetCapture per WebSocket mit OBS verbinden und **Quelle einrichten** drücken. Version 0.6.3 startet die Empfänger danach vor jeder Übertragung automatisch neu und lässt den SRT-Callern 20 Sekunden Verbindungszeit.
- **Nur ein Teil des UltraWide-Bildes kommt an:** In OBS müssen alle drei Medienquellen sichtbar sein und die drei Listener auf Basisport, Basisport +1 und Basisport +2 warten. Firewall und Portfreigaben für alle drei UDP-Ports prüfen.
- **Ein Triple-Stream meldet Encoderfehler:** Die Grafikkarte oder der Treiber unterstützt möglicherweise nicht drei gleichzeitige Sitzungen bei dieser Auflösung/FPS. Zuerst 30 FPS und eine niedrigere Bitrate testen oder einen anderen Encoder wählen.
- **AudioPipeCapture.dll fehlt:** Version 0.6.3 mit dem fertigen Setup erneut installieren. Die Quelldatei `AudioPipeCapture.cs` darf nicht mehr beim Programmstart kompiliert werden.
- **Fehler 4551 / Datei konnte nicht im temporären Ordner ausgeführt werden:** Nur das v0.6.3-ZIP verwenden, vollständig entpacken und alle `.exe`-/`.bin`-Teile im selben Ordner lassen. v0.6.3 verwendet keinen temporär gestarteten Inno-Setup-Loader mehr.
- **Alter `netstandard`-Fehler:** Eine ältere Version ist installiert. NetCapture 0.4.3 entfernt genau diese Laufzeit-Kompilierung.
- **Fehler „Liste hatte eine feste Größe“:** Dieser PowerShell-Listenfehler ist seit Version 0.4.2 korrigiert.
- **Geschütztes Video bleibt schwarz:** DRM-geschützte Inhalte können absichtlich von der Bildschirmaufnahme ausgeschlossen sein.

Das Protokoll liegt unter `%LOCALAPPDATA%\CrazyBatto\NetCapture\netcapture.log`.

## Deinstallation

NetCapture kann vollständig unter **Windows-Einstellungen → Apps → Installierte Apps** oder über **NetCapture deinstallieren** im Startmenü entfernt werden. Der Inno-Setup-Deinstaller löscht dabei auch die gespeicherten NetCapture-Einstellungen und Protokolle.

## Aktueller Umfang

Version 0.6.3 enthält einen richtigen Inno-Setup-Assistenten als vollständig zu entpackendes Mehrdatei-ZIP und einen eigenen fensterlosen `NetCapture.exe`-Launcher ohne installierte CMD-/VBS-Startdateien. `UseSetupLdr=no` verhindert den von Anwendungssteuerungsrichtlinien blockierten Start einer Setup-Datei aus `%TEMP%`. Hinzu kommen FFmpeg 9.0.1, OBS-WebSocket v5, automatische SRT-Medienquellen, Monitoraufnahme, auswählbare Fensteraufnahme, Spielaufnahme für Fenster/randloses Vollbild, Windows-WASAPI-Tonauswahl und UltraWide Triple-Split mit drei parallelen H.264-/SRT-Streams. Vor dem Streamstart wird die OBS-Verbindung geprüft; die Empfänger werden automatisch aktiviert und neu gestartet, bevor die SRT-Caller bis zu 20 Sekunden auf die Verbindung warten. Ein echter SRT-Verbindungsfehler wird getrennt von Encoder- und Aufnahmefehlern gemeldet. NDI wird nicht verwendet.
