# Crazy_Batto NetCapture 0.6.2

## Richtige Windows-Installation ohne CMD/VBS

- GitHub erstellt einen vollständigen Inno-Setup-Installer namens `CrazyBatto-NetCapture-Setup-v0.6.2.exe`.
- Die installierte Anwendung besitzt einen eigenen fensterlosen `NetCapture.exe`-Launcher.
- Desktop- und Startmenü-Verknüpfungen zeigen direkt auf `NetCapture.exe`.
- Der Installer startet `NetCapture.exe` nach Abschluss direkt.
- Es werden keine CMD- oder VBS-Startdateien installiert.
- `NetCapture.exe`, `AudioPipeCapture.dll` und das Setup werden reproduzierbar im Windows-GitHub-Workflow gebaut.

## SRT-/OBS-Verbindungsfix aus 0.6.1

- NetCapture prüft OBS WebSocket vor dem Start.
- Die OBS-SRT-Empfänger werden vor FFmpeg erstellt, aktiviert und neu gestartet.
- Triple-Split verwendet automatisch den Basisport sowie Basisport +1 und +2.
- FFmpeg wartet mit `connect_timeout=20000` bis zu 20 Sekunden auf OBS.
- SRT-Verbindungsfehler werden von Encoder-, Treiber- und Aufnahmefehlern unterschieden.
- Das Programm bleibt bei Startfehlern geöffnet.

NDI wird nicht verwendet und ist keine Abhängigkeit dieses Projekts.
