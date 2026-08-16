# Crazy_Batto NetCapture 0.6.7

## Team-Alpha-Logo als Windows-Symbol

- Das alte blaue Monitor-Symbol wurde vollständig durch das Team-Alpha-Logo ersetzt.
- Die Setup-EXE verwendet jetzt das Team-Alpha-Logo.
- `NetCapture.exe` enthält das Logo als eingebettetes Programmsymbol.
- Desktop- und Startmenü-Verknüpfung verwenden das neue Logo ausdrücklich über `NetCapture.ico`.
- Auch der Eintrag unter **Windows-Einstellungen → Apps → Installierte Apps** verwendet das Team-Alpha-Logo.
- Das ICO enthält passende Windows-Größen von 16 bis 256 Pixeln.
- Der lokale Launcher-Build erkennt Änderungen an der ICO-Datei und erstellt `NetCapture.exe` automatisch neu.

## Weiter enthalten

- OBS-WebSocket-v5-Verbindung mit korrigierter Szenenantwort und Fallback auf die aktive Szene.
- Lokaler OBS-Test über `127.0.0.1` ohne zweiten PC.
- Automatische OBS-SRT-Medienquellen und ein SRT-Verbindungsaufbau mit `connect_timeout=20000`.
- Monitor-, Fenster-, Spiel- und UltraWide-Triple-Split-Aufnahme.
- Windows-WASAPI-Tonauswahl über eine vorab kompilierte Audiokomponente.
- Mehrdatei-Installer mit `UseSetupLdr=no`, damit kein Setup-Teil aus dem Windows-TEMP-Ordner gestartet wird.
- NDI wird nicht verwendet.
