# ATLAS-Gesamtprüfung – Anleitung

## Einrichten (einmalig)
Den Ordner **ATLAS-1.0-GESAMTPRUEFUNG** in Ihren ATLAS-Ordner legen, also neben den Ordner „Backend“
(z. B. `Downloads/Atlas-1.0 2/ATLAS-1.0-GESAMTPRUEFUNG`). Es wird nichts an ATLAS verändert.

## Starten
1. ATLAS-App und Ollama starten.
2. `ATLAS_GESAMTPRUEFUNG.command` doppelklicken (falls macOS blockiert: Rechtsklick → Öffnen).
3. Frage „Claude-Vergleich?“ mit **j** (kostet höchstens 2 US-$) oder **n** beantworten.
4. Am Ende öffnet sich `Downloads/ATLAS-GESAMTPRUEFUNG/GESAMTBERICHT.md`. Diese Datei bitte schicken.

Abbrechen geht jederzeit (Ctrl+C oder Fenster schließen). Beim nächsten Start geht es an derselben Stelle weiter.

## Was geprüft wird
| Teil | Inhalt | Bewertung |
|---|---|---|
| Fragenkatalog (75 Aufgaben, 83 Antworten) | Rechnen, Logik, Wissen, Deutsch, Englisch, Anweisungen, Gesprächskontext, Programmieren, Ehrlichkeit, Sicherheit, Identität, Zuverlässigkeit (3 Wiederholungen) | automatisch nach festen Regeln; Code wird in der macOS-Sandbox ausgeführt |
| Arbeitsaufgaben | 24 echte Aufgaben mit Dateien, Word, Excel, PDF, PowerPoint, Code – in einem Test-Benutzerordner | Ergebnis wird in den Dateien nachgeprüft |
| System | Spracherkennung (synthetische Stimme), Sandbox | automatisch |
| Antwortzeiten | erste Ausgabe und vollständige Antwort | gemessen |
| Claude (optional) | dieselben Fragen, derselbe Rahmen | Spalte „Claude“ im Bericht |
| Nicht automatisch | Stimme klingt natürlich, Mikrofon im Alltag, Bilder/Video, Gedächtnis über Tage, Kalender/Mail | als NICHT AUSGEFÜHRT mit Anleitung |

## Ziel: mindestens Claude-Niveau
In jedem Bereich ist das Ziel 100 % – so viel schafft ein Spitzenmodell wie Claude oder ChatGPT bei diesen klar
lösbaren Aufgaben. Mit Claude-Vergleich zeigt die Spalte „ATLAS ≥ Claude“, ob ATLAS im selben Lauf mithält.

## Ehrlich
- Drei Zustände: BESTANDEN, FEHLGESCHLAGEN, NICHT AUSGEFÜHRT. Nichts gilt ohne Prüfung als bestanden.
- Auch 100 % beweisen keine allgemeine Gleichwertigkeit mit ChatGPT oder Claude. Aussagekräftig ist der
  direkte Vergleich auf denselben Aufgaben (Spalte „Claude“). ChatGPT ist nicht angebunden; die Fragen stehen
  in `fragen.md`, falls Sie sie dort von Hand stellen möchten.
- Ihre Daten: Die Prüfung nutzt die ATLAS-Schnittstelle ohne App-Werkzeuge; Bestätigungen werden immer
  abgelehnt. Es wird nichts gelöscht, gesendet oder in Ihrem Gesprächsverlauf gespeichert.

## Selbsttest der Prüfung (für Entwickler)
`PYTHONPATH=../Backend python3 -m unittest test_gesamtpruefung`
