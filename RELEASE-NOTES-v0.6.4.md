# Crazy_Batto NetCapture 0.6.4

## Korrektur: Programmfenster öffnet sich nicht

- NetCapture wird jetzt mit Administratorrechten nach `C:\Program Files\Crazy_Batto\NetCapture` installiert.
- Der alte benutzerbeschreibbare Installationspfad unter `%LOCALAPPDATA%` wird nicht wiederverwendet.
- Damit liegen `NetCapture.exe`, `NetCapture.ps1`, FFmpeg und die Audio-DLLs im von den AppLocker-Standardregeln vorgesehenen Programmordner.
- Der EXE-Launcher verwendet den vollständigen Pfad zu Windows PowerShell 5.1.
- Der Launcher bleibt während der Programmlaufzeit aktiv und protokolliert Start sowie PowerShell-Fehler.
- Wenn PowerShell oder das Skript beendet beziehungsweise blockiert wird, erscheint jetzt eine sichtbare Fehlermeldung statt eines lautlosen Abbruchs.
- Das neue Diagnoseprotokoll liegt unter `%LOCALAPPDATA%\CrazyBatto\NetCapture\launcher.log`.

## Installer und Übertragung

- Der Installer bleibt ein vollständig zu entpackendes Mehrdatei-ZIP mit `UseSetupLdr=no`, sodass kein Setup-Teil aus `%TEMP%` gestartet wird.
- Das ZIP enthält die Setup-EXE, beide erforderlichen BIN-Dateien und `SHA256.txt`.
- OBS-WebSocket-Prüfung, automatische SRT-Empfänger, `connect_timeout=20000`, UltraWide Triple-Split, Fenster-/Spielaufnahme und Windows-WASAPI-Tonauswahl bleiben enthalten.
- CMD- und VBS-Startdateien werden nicht installiert.
- NDI wird nicht verwendet.
