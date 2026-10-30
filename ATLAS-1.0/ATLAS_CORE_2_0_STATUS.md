# ATLAS Core 2.0 – Entwicklungspaket (nicht produktionsreif)

## Bestehende Funktionen erhalten
Das Projekt basiert auf Core 1.3. Vorhanden sind Swift-Mac-App, lokales Python-Backend, Ollama, Sprachsteuerung, Barge-in-Code, Langzeitgedächtnis, Werkzeug- und Freigabesystem, Claude-Cloud-Anbindung als **optionale** Backend-Funktion sowie OpenAI-Realtime-Code. **Vorhanden heißt nicht auf dem Mac nachgewiesen.** Die Cloud bleibt standardmäßig aus und benötigt einen eigenen API-Schlüssel und ausdrückliche Zustimmung.

## Neue Änderungen
- Lokaler Modellbenchmark lehnt nicht-lokale Ollama-URLs ausdrücklich ab, um versehentliche Datenübertragung beim Testen zu verhindern.
- Reproduzierbares Offline-Audit der wesentlichen Komponenten, ohne Netzwerk oder API-Schlüssel.
- Regressionstests für Audit und lokale Benchmark-URL-Sperre.
- Bestehende Code- und Testbasis aus 1.3 unverändert erhalten.

## Testen auf dem Mac
1. Vorhandene ATLAS-App und Daten sichern, dieses Paket separat entpacken.
2. Im Terminal im Projektordner: `PYTHONPATH=Backend python3 -m atlas.offline_audit --root .`
3. `cd Backend && python3 -m unittest discover -s tests -p 'test_offline_audit.py' -v`
4. Bestehende `BAUEN.command` mit Xcode ausführen; danach Live-Audio und Barge-in prüfen.
5. Ollama-Modellvergleiche erst auf dem Mac durchführen; die lokalen Benchmarks sind **kein** ChatGPT-/Claude-Leistungsnachweis.

## Offene Punkte
Kein macOS-Build in dieser Linux-Umgebung, keine Audio-/Hardwaretests, keine neuen externen API-Verbindungen aktiviert, keine Behauptung eines ChatGPT-/Claude-Gleichstands. Für einen umfassenden autonomen Agenten sind zusätzliche Architekturarbeit und reale Integrationstests notwendig.
