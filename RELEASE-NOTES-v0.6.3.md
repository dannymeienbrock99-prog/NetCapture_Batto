# Crazy_Batto NetCapture 0.6.3

## Installer-Korrektur für Fehler 4551

- Der Installer verwendet jetzt die offizielle Inno-Setup-Einstellung `UseSetupLdr=no`.
- Dadurch wird kein Setup-Teil mehr in den Windows-TEMP-Ordner kopiert und von dort gestartet.
- Das behebt die Ursache der Meldung **„Fehler 4551: Eine Anwendungssteuerungsrichtlinie hat diese Datei blockiert“**, wenn nur die temporäre Setup-Datei von AppLocker beziehungsweise Windows App Control blockiert wurde.
- GitHub veröffentlicht den Installer als `CrazyBatto-NetCapture-Setup-v0.6.3.zip`.
- Das ZIP muss vollständig entpackt werden. Die Setup-EXE und alle zugehörigen `.bin`-Dateien müssen beim Start im selben Ordner liegen.
- Der Installationsassistent, das Team-Alpha-Design, die Lizenzseite, Verknüpfungen und die normale Windows-Deinstallation bleiben erhalten.
- Das installierte Programm startet weiterhin über den fensterlosen `NetCapture.exe`-Launcher; CMD- und VBS-Startdateien werden nicht installiert.

## Übertragung

- Die OBS-WebSocket-Verbindung wird vor dem Start geprüft.
- SRT-Empfänger werden automatisch aktiviert und neu gestartet.
- Der SRT-Caller verwendet weiterhin `connect_timeout=20000`.
- UltraWide Triple-Split, Fensteraufnahme, Spielaufnahme und Windows-WASAPI-Tonauswahl bleiben enthalten.
- NDI wird nicht verwendet.
