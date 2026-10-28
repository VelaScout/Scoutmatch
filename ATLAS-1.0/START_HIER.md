# Atlas 1.0 – konsolidierter Entwicklungsstand

Dies ist das vollständige **Quellprojekt**, nicht eine bereits kompilierte macOS-App.

## Installation
1. Entpacken.
2. `ATLAS_1_0_INSTALLIEREN.command` per Rechtsklick → Öffnen starten.
3. Die App liegt danach unter `~/Applications/Atlas 1.0.app`. Alte Dock-Verknüpfungen entfernen und die neue App aus diesem Ordner ins Dock ziehen.
4. In Atlas die Sprache **Deutsch** auswählen.
5. Der Installer registriert einen lokalen XTTS-Startdienst; die erste Initialisierung kann dauern. Mit `curl --noproxy '*' http://127.0.0.1:5002/health` prüfen.

## Zusammengeführt
- Vollständiger Stand aus dem vorherigen Atlas-1.0-Quellprojekt mit Swift-App, Backend, Werkzeugen, Gedächtnis, Tests, VoiceServer.
- Sprachsynthese: XTTS-Verbindung wird bei jedem Textstück erneut versucht; ein temporärer Ausfall sperrt die KI-Stimme nicht dauerhaft.
- XTTS startet als Benutzer-LaunchAgent nach der Installation und bei Anmeldung.
- Gesprächs-Prompt: Deutsch bei deutschen Nutzerfragen ausdrücklich bevorzugt.

## Einschränkungen
- **Nicht** auf macOS kompiliert oder mit echtem Mikrofon getestet; Xcode-Build erfolgt auf deinem Mac.
- Eine Roboterstimme bedeutet: XTTS nicht bereit, Antwort nicht von XTTS übernommen oder Fallback; `voice.log` prüfen.
- Der gespeicherte Sprachmodus wird nicht ungefragt überschrieben; bitte Deutsch in Einstellungen auswählen.
- Frühere Tests beweisen nicht die Funktionsfähigkeit dieser Integration.
- Für kostenpflichtige Cloud-Dienste gelten weiterhin die bestehenden Einstellungen; keine automatische Aktivierung.
