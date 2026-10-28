# Atlas 1.0 – zusammengeführter Quellstand

**Wichtig:** Diese ZIP enthält ein vollständiges Xcode-Projekt und einen Mac-Installer, **keine bereits auf macOS kompilierte `.app`**. Die ausführbare App wird auf dem Apple-Silicon-Mac mit Xcode gebaut und anschließend unter `~/Applications/Atlas 1.0.app` abgelegt. Der Installer verändert alte Atlas-Apps nicht, außer er sichert eine vorherige `Atlas 1.0.app`.

## Installation
1. ZIP entpacken und den Ordner `ATLAS-Local 5` öffnen.
2. `ATLAS_1_0_INSTALLIEREN.command` doppelklicken. Eventuell über Rechtsklick → Öffnen.
3. Bei erfolgreichem Build wird `~/Applications/Atlas 1.0.app` gestartet.
4. Alte Atlas-Apps beenden und deren Dock-Symbole entfernen; **die neue App aus `~/Applications`** ins Dock ziehen.
5. Für die natürliche XTTS-Stimme muss der lokale Sprachserver auf Port 5002 laufen. Der Installer versucht, ihn über `uv` zu starten. Beim ersten Start kann das Laden dauern. Solange er fehlt, fällt die App auf die Apple-Stimme zurück.

## Zusammengeführt
- Basis: `ATLAS-Local 6(1).zip` (Quellprojekt).
- Gesprächsregeln: direkte Antworten, Formatvorgaben, Widersprüche und keine ungefragte englische Selbstvorstellung in Swift und Python.
- XTTS-v2: Swift-Sprachausgabe ruft lokalen `/tts`-Server auf und spielt 24-kHz-PCM als WAV ab; Fallback bei Nichterreichbarkeit.
- Versionsanzeige: 1.0.0 / Atlas 1.0.
- Bestehende Bundle-ID bleibt erhalten, um App-Daten nicht absichtlich zu migrieren.

## Ehrlicher Teststatus
Python-Quellen wurden syntaktisch geprüft. Der Swift-Code kann hier mangels Xcode/macOS **nicht kompiliert oder auf einem Mac gestartet werden**. Erst der Mac-Installer zeigt, ob die App wirklich baut und läuft. Die früheren 304 Backendtests und Modelltests gelten für die damaligen Stände, **nicht als Abnahme dieser neuen Integration**.

Falls der Build scheitert, die Datei `build/ATLAS-1.0-INSTALLATION.log` hier hochladen. Bei Roboterstimme: `curl http://127.0.0.1:5002/health` prüfen und `~/Library/Application Support/Atlas1.0/voice.log` ansehen.
