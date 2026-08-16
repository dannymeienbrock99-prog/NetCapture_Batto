# Crazy_Batto NetCapture 0.6.9

## Desktop- und Startmenü-Logo korrigiert

- Die installierte Logo-Datei verwendet jetzt den versionsabhängigen Namen `NetCapture-v0.6.9.ico`.
- Dadurch kann Windows nicht länger das alte Monitor-Symbol vom bisherigen `NetCapture.ico`-Pfad aus dem Symbolcache übernehmen.
- Der Installer löscht während des Updates die vorhandene Desktop-Verknüpfung und erstellt sie anschließend mit dem Team-Alpha-Logo neu.
- Dasselbe gilt für die NetCapture-Verknüpfung im Startmenü.
- Der Eintrag unter **Windows-Einstellungen → Apps → Installierte Apps** verwendet ebenfalls das versionsabhängige Team-Alpha-Icon.
- Der Installer sendet nach der Installation zusätzlich eine Shell-Aktualisierung an Windows.

## Weiter enthalten

- UltraWide Dual-Split mit zwei SRT-Streams und frei einstellbarer Auflösung pro Teilbild.
- UltraWide Triple-Split mit drei SRT-Streams.
- Automatische OBS-WebSocket-v5-Medienquellen.
- Lokaler OBS-Test über `127.0.0.1`.
- SRT-Verbindungsaufbau mit `connect_timeout=20000`.
- NDI wird nicht verwendet.
