# Crazy_Batto NetCapture 0.6.8

## UltraWide Dual-Split

- Neuer Aufnahmemodus **UltraWide Dual-Split** für einen sehr breiten, von Windows als ein Monitor erkannten Bildschirm.
- Das Bild wird in eine linke und rechte Aufnahmehälfte geteilt und über zwei parallele FFmpeg-/SRT-Streams übertragen.
- Links verwendet den eingestellten Basisport, Rechts automatisch Basisport +1, beispielsweise UDP `9000–9001`.
- NetCapture erstellt per OBS WebSocket automatisch die Medienquellen `… - Links` und `… - Rechts` und positioniert sie lückenlos nebeneinander.
- Ton wird nur über die linke Quelle übertragen, damit er in OBS nicht doppelt abgespielt wird.

## Frei einstellbare Ausgabeauflösung

- Die Ausgabeauflösung gilt im Dual-Modus pro Teilbild.
- Neben den vorgegebenen Auflösungen können eigene Werte wie `3440x1440` oder `3840x2160` direkt eingetippt werden.
- Zulässig sind gerade Pixelmaße zwischen `160x120` und `4096x4096`, passend zur H.264-Grenze.
- Eigene Auflösungen werden in `settings.json` gespeichert und beim nächsten Start wiederhergestellt.
- Bei zwei Ausgaben mit `3840x2160` positioniert NetCapture die rechte OBS-Quelle automatisch bei X=`3840`; die Gesamtleinwand ist dann `7680x2160`.

## Weiter enthalten

- UltraWide Triple-Split mit drei SRT-Streams.
- Lokaler OBS-Test über `127.0.0.1`.
- OBS-WebSocket-v5-Einrichtung und automatischer Neustart der SRT-Empfänger.
- SRT-Verbindungsaufbau mit `connect_timeout=20000`.
- Team-Alpha-Logo für Setup, Programm und Verknüpfungen.
- NDI wird nicht verwendet.
