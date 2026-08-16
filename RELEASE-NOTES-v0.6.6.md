# Crazy_Batto NetCapture 0.6.6

## OBS-Verbindung bleibt bestehen

- Die OBS-WebSocket-Antwort wird jetzt ohne unbeabsichtigte PowerShell-Aufzählung als ein zusammenhängendes Antwortobjekt verarbeitet.
- `GetSceneList` wird über seine tatsächlichen Antwortfelder ausgewertet, statt direkt auf eine möglicherweise fehlende Eigenschaft zuzugreifen.
- Falls OBS keine auswertbare Szenenliste liefert, fragt NetCapture zusätzlich die aktive Programmszene über `GetCurrentProgramScene` ab.
- Ein Fehler beim ersten Laden der Szenenliste trennt die bereits erfolgreiche OBS-WebSocket-Verbindung nicht mehr.
- Die Schaltfläche zum erneuten Laden der Szenen bleibt verfügbar; fehlt wirklich jede Szene, zeigt NetCapture eine verständliche Meldung.

## Host- und Portkorrektur

- Eingaben wie `127.0.0.1:4455` oder `ws://127.0.0.1:4455` werden in Host und Port zerlegt.
- Die WebSocket-Adresse wird mit `UriBuilder` erzeugt, wodurch der bisherige Fehler **Ungültiger URI: ungültiger Anschluss** vermieden wird.
- Der lokale Test verwendet weiterhin automatisch `127.0.0.1` für OBS-WebSocket und SRT.

## Weiter enthalten

- Der SRT-Caller verwendet weiterhin `connect_timeout=20000`.
- Installer mit `UseSetupLdr=no`, AudioPipeCapture, Fenster-/Spielaufnahme und UltraWide Triple-Split bleiben enthalten.
- NDI wird nicht verwendet.
