# Testbericht – Atlas 0.2.1

Datum: 21. Oktober 2026. Testumgebung hier: Linux x86_64, Python 3.12, Node 24, Chromium Headless 153 mit Playwright. Kein Zugriff auf den Mac des Nutzers. Die Ergebnisse der alten 0.2-Mac-Installation gelten nicht automatisch für diese neue Version.

## Erfolgreich ausgeführt

**54/54 Python-Tests**, ohne übersprungene Tests. Aufruf: `python3 -W error::ResourceWarning -m unittest discover -s tests -v`.

| Bereich | Tatsächlich geprüft |
|---|---|
| Chat | Echtes lokales HTTP zum Atlas-Server; Streaming-Format, erste Ausgabe vor Abschluss, persistente vollständige Antworten, alte synchrone Route |
| Antwortfehler | Leere/unvollständige Modellantwort, Netzwerkfehler, Längenlimit-Markierung, ausgeblendete Thinking-Felder und segmentierte Tags |
| Nebenläufigkeit | Zweite Anfrage erhält 409; Zustandsabfrage bleibt möglich; Chat-Löschen während Berechnung gesperrt; Locks nach Abbruch/Fehler freigegeben |
| Abbruch | Angeforderter Abbruch, keine Speicherung der Teilantwort, aktive Anfrage entfernt |
| Gedächtnis | Anlegen, lesen, löschen, Verlauf löschen ohne Verlust der Erinnerungen, Zeichenbudget für den Prompt |
| Zugriffsschutz | Falscher Host, fremder Origin, Cross-Site-Anfrage, falsches Sitzungstoken, ungültige JSON-Daten, zu große Requests |
| Modellwahl | Nur qwen3:4b und qwen3:8b; Cloud-/Fremdmodell wird abgewiesen |
| Mac-Aktionen | Erlaubnisliste, Bestätigung/Abbruch/Ablauf/Tokenwiederverwendung; Betriebssystemaufrufe simuliert |
| Sprachausgabe | Aufruf, eigener Prozessabbruch, fehlendes Programm; macOS-Prozess simuliert |
| Spracherkennung | Stille, kurze Aufnahme, Sprachwahl, parallele Aufnahme, Timeout, Textdateiausgabe; Whisper simuliert |
| Audiocodecs | **Echte ffmpeg-Kodierung und Dekodierung von MP4/AAC und WebM/Opus**; geprüftes 16-kHz-Mono-PCM-Ergebnis, Whisper danach simuliert |
| Diagnose | Synthetische Fragen, getrennte temporäre Datenbank, Fehlerberichte, Standardmodellpfad |

**9 erfolgreiche Browser-Prüfgruppen** mit echtem Chromium und laufendem lokalen Atlas-Testserver:

1. Laden der Oberfläche und Verbindungsstatus.
2. Teilantwort sichtbar vor Abschluss, Sendesperre und Zeitmessungsanzeige.
3. Erinnerung bleibt nach Neuladen erhalten; HTML im Erinnerungstext wird nicht als HTML ausgeführt.
4. Antwort abbrechen und sichtbare Kennzeichnung als unvollständig.
5. Verlauf löschen setzt auch den Vorlesezustand zurück.
6. Mac-Aktion abbrechen und bestätigen (OS simuliert).
7. Browseraufnahme über künstliches Mikrofon, Stoppen und Anzeige des Transkripts (STT simuliert).
8. Aufnahme automatisch senden und Antwort automatisch vorlesen (Modell/STT/OS simuliert).
9. Keine unbehandelten JavaScript-Fehler während dieser Abläufe.

Der reguläre Playwright-Browserdownload schlug in dieser Umgebung fehl. Stattdessen wurde für die tatsächlich erfolgreichen Läufe Chromium Headless aus `@sparticuz/chromium` verwendet. Das Ergebnis beweist keine Safari-Kompatibilität und keine Bedienbarkeit mit dem physischen Mac-Mikrofon.

Zusätzlich erfolgreich: JavaScript-Syntaxprüfung, Python-Kompilierung, Bash-Syntax aller fünf command-Skripte sowie ZIP-Integritätsprüfung und erneuter Python-Testlauf nach Entpacken.

## Nicht hier ausgeführt / weiter erforderlich

- Echte Inferenz und Antwortbewertung von Qwen3 4B und 8B mit dieser Version.
- Messung auf dem M4/16 GB: Zeit bis zur ersten Ausgabe, Modellwechsel, Arbeitsspeicher/GPU-Auslastung.
- Homebrew-Installation/Update auf macOS.
- Echte whisper.cpp-Erkennung und macOS-Sprachausgabe mit dieser Version.
- Safari, physisches Mikrofon, hörbare Aussprache, alle tatsächlichen App-/Ordnerziele.
- Zusammenführung mit der vorhandenen Atlas-App: deren Projektdateien fehlen.

`diagnose_atlas.command` liefert auf dem Mac die echten Modellantworten und Zeitmessungen sowie einen synthetischen Audiotest. Sechs Fragen pro Modell sind ein begrenzter Vergleich, kein allgemeiner Nachweis hoher Antwortqualität. Drei Antworten werden nach einfachen objektiven Kriterien geprüft; drei benötigen menschliche Bewertung.

## Einordnung

Die Programmabläufe wurden deutlich umfassender geprüft als in 0.2. Dass Atlas jetzt durchgehend gute Antworten gibt oder wie ein großer Cloud-Assistent klingt, ist damit **nicht nachgewiesen**. Streaming verbessert die sichtbare Rückmeldung; die tatsächliche Modellqualität und Sprachleistung müssen anhand der Mac-Ergebnisse weiterentwickelt werden.
