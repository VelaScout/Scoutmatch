# Zusammenführung mit der vorhandenen Atlas-App

Status: Schnittstelle vorhanden; bestehende App noch nicht zugänglich oder eingebunden.

## Geplante gemeinsame Architektur

Eine Oberfläche, ein lokaler Atlas-Backendprozess, eine SQLite-Datenbank, ein Ollama-Dienst. Die vorhandene App soll ihre Gestaltung und sinnvolle Funktionen behalten. Doppelte Mikrofonaufnahme, getrennte Gedächtnisse und zwei parallel laufende Modellanfragen sollen vermieden werden. Die konkrete Umsetzung hängt vom tatsächlichen Framework ab.

Wenn die App eine WebView nutzt, kann sie die lokale Atlas-Oberfläche unter `http://127.0.0.1:8765/` laden. Dabei bleibt die Oberfläche im gleichen Ursprung wie ihre API. Eine statische `file://`-Seite soll nicht durch pauschal freigegebene CORS-Ursprünge angebunden werden. Für eine native Oberfläche muss anhand des Projekts ein geeigneter lokaler Adapter ergänzt werden. Tokens und Start-/Stop-Lebenszyklus dürfen nicht hartcodiert werden.

## Vorhandene API

Host bleibt `127.0.0.1:PORT`. Schreibanfragen brauchen `X-Atlas-Token`, dessen Wert pro Serverstart erzeugt und in die ausgelieferte Oberfläche eingebettet wird. Keine Cloud-URLs oder Cloudmodelle sind konfigurierbar.

| Route | Funktion |
|---|---|
| GET /api/state | Version, Verlauf, Erinnerungen, Sprachbereitschaft |
| GET /api/health | Ollama-Erreichbarkeit und installierte unterstützte Modelle |
| POST /api/chat/stream | JSON mit message, model, optional request_id; Ausgabe als NDJSON |
| POST /api/chat | Kompatibler synchroner Endpunkt mit answer |
| POST /api/chat/cancel | Anfrage anhand request_id abbrechen |
| POST /api/transcribe?language=de | Audiodaten, Rückgabe text und seconds; de/en/auto |
| POST /api/speak | Text über macOS ausgeben |
| POST /api/speak/stop | Nur die eigene laufende Sprachausgabe stoppen |
| POST /api/memory | Erinnerung anlegen |
| POST /api/memory/delete | Erinnerung nach numerischer id löschen |
| POST /api/clear | Verlauf löschen, Erinnerungen erhalten |
| POST /api/action/request | Vorgeschlagene Aktion prüfen und Bestätigungstoken erstellen |
| POST /api/action/confirm | Einmaliges Token, approved als bool; 60 Sekunden Ablauf |

Stream-Ereignisse: `start`, `delta`, `done`, `cancelled`, `error`. Ein `done` enthält die vollständige Antwort und Messwerte. Auch nach HTTP 200 können Fehlerereignisse erscheinen; die Oberfläche muss diese behandeln. Unterbrochene Streams sind keine erfolgreichen Antworten. Nur vollständig beendete Antworten werden gespeichert.

## Benötigte App-Unterlagen

Quellcode-ZIP mit Builddateien (z.B. package.json, Python-Konfiguration oder Xcode-Projekt), aktueller Startanleitung und bei Bedarf Screenshot der App. Keine Schlüssel oder persönlichen Konfigurationsdateien mitsenden. Erst nach Prüfung dieser Dateien können Änderungen an der bestehenden App, ein gemeinsamer Starter und ein belastbarer Integrationstest erstellt werden.
