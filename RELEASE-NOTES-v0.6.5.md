# Crazy_Batto NetCapture 0.6.5

## OBS auf demselben PC testen

- Der neue Schalter **Dieser PC testen** setzt SRT-Ziel und OBS-WebSocket-Host automatisch auf `127.0.0.1`.
- Dadurch können Bildschirm-, Fenster-, Spiel-, Ton- und UltraWide-Übertragung mit OBS auf demselben Rechner geprüft werden.
- Die zuvor eingetragenen Netzwerkadressen werden getrennt gespeichert und nach dem Ausschalten des lokalen Tests wiederhergestellt.
- Im lokalen Test weist NetCapture darauf hin, dass keine Firewall-Freigabe erforderlich ist und wie ein Endlos-Spiegeleffekt vermieden wird.
- Lokale SRT-Verbindungsfehler nennen jetzt die OBS-Medienquelle als wahrscheinlichste Ursache, statt fälschlich auf die Firewall zu verweisen.

## Weiter enthalten

- Der Installer bleibt ein vollständig zu entpackendes Mehrdatei-ZIP mit `UseSetupLdr=no` und installiert nach `C:\Program Files\Crazy_Batto\NetCapture`.
- OBS-WebSocket-Prüfung, automatische SRT-Empfänger, `connect_timeout=20000`, UltraWide Triple-Split, Fenster-/Spielaufnahme und Windows-WASAPI-Tonauswahl bleiben enthalten.
- CMD- und VBS-Startdateien werden nicht installiert.
- NDI wird nicht verwendet.
