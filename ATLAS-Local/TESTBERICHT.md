# Testbericht ATLAS 0.9.0

Stand: 22.10.2026. Rohprotokoll: `TESTRESULTS-0.9.0.txt`.

## Wo getestet wurde – und wo nicht

Getestet wurde in einem Linux-Container. Dort fehlen:
- ein Mac, Xcode und ein Swift-Compiler
- Mikrofon und Lautsprecher
- Ollama-Modelle (das Laden ist dort gesperrt)
- ein Anthropic-Schlüssel

**Deshalb gilt:** Alle hier bestandenen Tests laufen mit **simulierten Modellantworten** (vorgegebene Antworten), aber mit echter Datei-, Datenbank-, Prozess- und Netzwerkverarbeitung.

Ob das echte Qwen-Modell die Aufgaben selbst löst, zeigt erst `MAC_TESTEN.command` auf Ihrem Mac. Eine große Zahl bestandener Simulationstests beweist **keine** allgemeine Zuverlässigkeit.

| Kennzeichnung | Bedeutung |
|---|---|
| BESTANDEN | Test ausgeführt, Ergebnis geprüft, in Ordnung |
| FEHLGESCHLAGEN | Test ausgeführt, Ergebnis falsch |
| NICHT AUSGEFÜHRT | Test existiert, konnte hier nicht laufen (Grund genannt) |

## 1. Hier ausgeführt

| Prüfung | Ergebnis | Art |
|---|---|---|
| 276 Backend-Tests mit Python 3.13 (ResourceWarning = Fehler) | **274 BESTANDEN, 0 FEHLGESCHLAGEN, 2 NICHT AUSGEFÜHRT** (nur Mac: echte Sandbox) | Modell simuliert |
| Dieselben 276 Tests mit Python 3.15 (Beta 4; Ihr Mac nutzt 3.15) | **274 BESTANDEN, 2 NICHT AUSGEFÜHRT** | Modell simuliert |
| 9 Prüfgruppen der Weboberfläche in Chromium | **9 BESTANDEN** | Modell, Spracherkennung, macOS simuliert |
| Swift-Syntax aller Swift-Dateien (tree-sitter) | **BESTANDEN** (0 Fehler). Das ist **kein** Compiler-Lauf. | – |
| 9 Shell-Skripte (`bash -n`) | **BESTANDEN** | – |
| Übersicht „Learning & Evolution“ gegen alle Pflichtfelder der Swift-Strukturen | **BESTANDEN** | echter Server, Modell simuliert |

### Was die Tests konkret beweisen (Auswahl, nach Ihren Abnahmepunkten)

| Abnahmepunkt | Test (Datei) | Ergebnis |
|---|---|---|
| Echte Dateien: Format, Inhalt, Öffnen | `test_documents` (7): Word mit Überschrift-/Aufzählungsstilen, echtes ZIP-Office-Format, PDF beginnt mit `%PDF-` und enthält den Text, Excel-Zelle und Formel, CSV, PowerPoint lesen | BESTANDEN |
| Schutz vor Überschreiben | `test_documents`, `test_release_070`: bestehende Datei bleibt unverändert; Umwandeln wählt `-2` statt zu überschreiben; Änderungen nur mit Sicherung | BESTANDEN |
| Folgeaufträge, Kontext | `test_tasks`: „Speichere es als PDF“ nach einem **Neustart ohne Gesprächsverlauf** findet die richtige Word-Datei; die PDF enthält den Betrag | BESTANDEN |
| Abbruch und Wiederaufnahme | `test_tasks`: Abbruch während eines App-Schritts → „Mach weiter“ nach Neustart; erledigter Schritt wird nicht wiederholt | BESTANDEN |
| Doppelte Aktionen | `test_tasks`: gleiche E-Mail nach Wiederholung → Rückfrage statt zweitem Versand; andere E-Mail → normal | BESTANDEN |
| Teilweise fehlgeschlagene Schritte | `test_tasks`, `test_learning`: ein anderer späterer Erfolg markiert einen Fehlschlag **nicht** als gelöst | BESTANDEN |
| Fremde Anweisungen | `test_research`: Anweisung in Webseite und Datei wird entschärft, nicht an das Modell weitergegeben | BESTANDEN |
| Keine erfundenen Quellen | `test_research`: nicht abgerufene Adresse wird aus der Antwort entfernt, echte Quellen werden angehängt | BESTANDEN |
| Offline | `test_research`, `test_robustness`: ehrliche Meldung statt erfundener Antwort | BESTANDEN |
| Zeitüberschreitung, ungültige Modellantworten, Ollama aus | `test_robustness`, `test_release_070` | BESTANDEN |
| Korrekturen, widersprüchliche Erinnerungen | `test_learning` (Regel überlebt Neustart, gilt nur passend), `test_agent` (ähnliche ältere Erinnerung wird gemeldet) | BESTANDEN |
| Passwörter nie speichern | `test_privacy`: weder direkt („Merk dir …“) noch über das Modell; Erfahrungen/Journal geschwärzt | BESTANDEN |
| Fehlende Berechtigungen | `test_tools` (Pfade außerhalb, `~/Library`, Symlink-Ausbruch), `test_agent` (abgelehnte Bestätigung) | BESTANDEN |
| Kontrollierte Weiterentwicklung | `test_skills`, `test_evolution`, `test_sandbox`: gefährlicher Code wird nie ausgeführt; Tests dürfen nicht entfernt werden; Sandbox, die nicht schützt, wird nie benutzt; misslungene Änderung wird zurückgesetzt | BESTANDEN |
| Cloud nur nach Aktivierung | `test_cloud` (7): aus → nichts gesendet; abgelehnt → nichts gesendet; Kosten aus Token; Limit; Schlüssel nur über stdin. **Echtes SDK** gegen eine nachgebaute API. | BESTANDEN |
| Installation, Update, Rücksetzen, Datenerhalt | `test_scripts`: Rücksetzen in einem temporären Benutzerordner; Update ersetzt erst nach Build und Tests; `~/.atlas-ai` wird nie verschoben oder gelöscht | BESTANDEN |
| Ihr Mac-Testlauf 0.8.0: Ursachen der Fehlschläge | `test_mac_feedback_080`: „~/Schreibtisch“ landet im Desktop-Ordner; nach gescheitertem Schritt werden die übrigen Teile erledigt; Suche weicht auf andere Dienste aus und nennt die Ursache; Rechenfrage mit Formathinweis wird exakt berechnet | BESTANDEN |
| KI-Identität und Moduswechsel | `test_cloud`: „Wechsle in den Cloud-Modus“ nur mit Freigabe; „Lokal: …“ bleibt auf dem Mac; abgelehnte Übertragung → lokal, ohne Endlosschleife | BESTANDEN |
| Fähigkeit vorhanden oder neu lernen | `test_evolution`: „Ich möchte, dass du Excel-Dateien bearbeiten kannst“ → „Das kann ich bereits“, kein Lernauftrag; PowerPoint bearbeiten → Lernauftrag | BESTANDEN |
| Dokumente vergleichen | `test_documents`: Word gegen Text, Unterschied im Preis gefunden; gleiche Datei → „inhaltlich gleich“ | BESTANDEN |
| Quellenbewertung | `test_research`: offizielle Stelle, Wissenschaft, Wikipedia, Nachrichten, sonstige | BESTANDEN |
| Wissenspakete | `test_wissenspakete`: Vorschau schreibt nichts; richtige Auftragsart; keine Doppelungen; laufen nur eingeschaltet, im Tageslimit, mit Internet; ohne Internet warten sie | BESTANDEN |
| Stabilität bei längerer Nutzung | `test_stability`: 300 Anfragen (Gespräch, Werkzeuge, Fehler, Abbruch) ohne wachsende Threads, offene Dateien oder wartende App-Anfragen; Speicherzuwachs unter 1 MB | BESTANDEN |
| Prüflogik der 29 echten Arbeitsaufgaben | `test_realtests`: Jede Prüfung fällt durch, wenn das Modell nur behauptet statt handelt | BESTANDEN |

## 2. Hier NICHT AUSGEFÜHRT – läuft automatisch auf Ihrem Mac

| Prüfung | Wo | Status hier |
|---|---|---|
| Xcode-Build der App (neue Ansichten: Cloud-Einstellungen, Gedächtnis-Herkunft, Passwortschutz) | `AKTUALISIEREN.command` | NICHT AUSGEFÜHRT (kein Mac) |
| Swift ⇄ Dienst (inkl. Learning-Übersicht), Sprachtext, Passwortfilter in Swift | `Tests/test_provider_mac.sh` | NICHT AUSGEFÜHRT |
| Echte macOS-Sandbox (2 Tests + Selbstprüfung) | Update-Tests, `MAC_TESTEN.command` Schritt 5 | NICHT AUSGEFÜHRT |
| **29 Arbeitsaufgaben mit dem echten Qwen-Modell**, Ergebnis jeweils unabhängig vom Modell geprüft (Dateien, Inhalte, Tests) | `MAC_TESTEN.command` Schritt 3 | NICHT AUSGEFÜHRT |
| Antwortzeiten: erste Rückmeldung und vollständiges Ergebnis | ebenda | NICHT AUSGEFÜHRT |
| Neustart des Dienstes mit Prüfung des Datenerhalts | `MAC_TESTEN.command` Schritt 6 | NICHT AUSGEFÜHRT |
| Echtes Cloud-Modell | nur von Hand, mit Ihrem Schlüssel; kostet Geld | NICHT AUSGEFÜHRT |
| Modellvergleich Qwen/Llama/Mistral/Gemma/gpt-oss | `MODELLE_VERGLEICHEN.command` (optional, lädt Modelle) | NICHT AUSGEFÜHRT |
| Allgemeine Gesprächsqualität mit dem echten Modell | nur indirekt über die Arbeitsaufgaben (kurze_antwort, englisch, kontext, logik, gedaechtnis, identitaet) | NICHT AUSGEFÜHRT |
| Mikrofon, „Atlas“-Aktivierung, Unterbrechen, Stimme, englische Wörter in deutschen Sätzen | von Hand | NICHT AUSGEFÜHRT |
| Kalender, Erinnerungen, Mail mit echten Konten und macOS-Freigaben | von Hand | NICHT AUSGEFÜHRT |

## 3. Behobene Fehler in 0.8.1 und 0.9.0

| Fehler | Gefunden durch |
|---|---|
| ATLAS nannte sich „lokaler Assistent“; ein alter Text behauptete „kein Internetzugriff“ | Ihr Hinweis |
| Pfade wie `~/Schreibtisch/…` legten einen neuen Ordner „Schreibtisch“ an statt im Desktop zu speichern (vermutlich markdown_liste) | Ihr Mac-Testlauf |
| Nach einem gescheiterten ersten Schritt hörte das Modell auf, statt die übrigen Teile zu erledigen (teilweise_fehler) | Ihr Mac-Testlauf |
| „Was ist 17 mal 23? Antworte nur mit der Zahl.“ ging am exakten Rechner vorbei (Diagnose rechnung) | Ihr Mac-Testlauf |
| Recherche: nur ein Suchdienst; Zertifikats- und Sperrfehler wurden pauschal als „nicht erreichbar“ gemeldet | Ihr Mac-Testlauf |
| Wissenspakete: falsche Auftragsart, kein Schalter/Limit, ohne Internet dauerhaft blockiert | Durchsicht Ihres Pakets 0.8.0_2 |
| Lernauftrag für Fähigkeiten, die ATLAS bereits hat | Durchsicht |
| Im Cloud-Modus hätte ein Rückfall auf lokal eine Endlosschleife ausgelöst (vor Auslieferung gefunden) | Durchsicht |
| Dokumentvergleich zählte Formatmarken (# Überschrift) als Unterschied | Test |

## 4. Behobene Fehler in 0.8.0

| Fehler | Gefunden durch |
|---|---|
| Sandbox-Profil der Code-Werkstatt enthielt eine vermutlich ungültige Regel. Ein defektes Profil hätte unverständliche Testfehler erzeugt. | Durchsicht nach Ihrem Mac-Screenshot |
| Aufträge wie „Ändere in Vertrag.docx …“ wurden als Plauderei statt als Aufgabe erkannt | neuer Arbeitsaufgaben-Test |
| „Passwort für das Online-Banking: …“ wurde nicht als Zugangsdaten erkannt | neuer Test |
| Word-Dateien entstanden nur über macOS-`textutil` und wurden nicht inhaltlich geprüft | Durchsicht |
| Ein 0.7.0-Test ersetzte alle Systemaufrufe und hätte die neue Sandbox-Prüfung verdeckt (Test angepasst, gleiche Aussage) | Testlauf |

Behoben in 0.7.0 (übernommen, geprüft): fehlender Temp-Ordner im Sandbox-Kindprozess („No usable temporary directory found“).
