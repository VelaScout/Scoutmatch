# Testbericht ATLAS Local 0.6.0

Stand: 21.10.2026.

Die Entwicklungsumgebung ist ein Linux-Container ohne Mac, ohne Swift-Compiler und ohne Ollama-Modelle. Die Netzwerkregel sperrt `ollama.com`, `registry.ollama.ai` und `huggingface.co`.

Die Tests sind in drei Arten getrennt:

| Art | Bedeutung |
|---|---|
| **Simuliert** | Das Modell ist vorgegeben (FakeOllama). Alles andere läuft echt. |
| **Echtes Modell** | Qwen über Ollama. Läuft nur auf dem Mac. |
| **Hardware** | Mikrofon, Lautsprecher, Freigaben. Nur von Hand auf dem Mac. |

## 0. Ergebnisse von Ihrem Mac (Version 0.4.0, laut Ihren Angaben und Screenshots)

**Echte Modelltests: 6 von 12 bestanden.** Fehlgeschlagen sind:
1. Kurze Antwort
2. Ordner und Datei
3. Excel
4. PDF
5. Sortieren
6. Fehler beheben

Weitere Beobachtungen:
- Lange englische Überlegungen statt Werkzeugaufrufen.
- 30 bis über 100 s pro Aufgabe.
- **Diagnose:** `qwen3:4b` mit 35 Tokens/s, erste Ausgabe nach 0,07–0,12 s, aber 8,8–14,9 s für Kurzantworten.
- Spracherkennung (synthetische Stimme): fehlerfrei.
- **Backend-Tests:** 153 ausgeführt, davon 151 bestanden und 2 übersprungen (fehlendes openpyxl/pypdf in der genutzten Python-Umgebung).

**Ursachenanalyse:**
1. `qwen3:4b` ist bei Ollama die Denk-Variante (Selbstgespräch vor jeder Antwort, meist auf Englisch).
2. Weil `qwen3:8b` nicht installiert war, lief auch der Agent mit diesem Modell.
3. Kleine Modelle beschreiben Werkzeuge oft, statt sie aufzurufen.
4. Mehrschrittige Aufgaben (Sortieren: ca. 7 Aufrufe; Fehler beheben: ca. 5) überfordern sie leicht.

**Behebung in 0.4.1 und 0.5.0:** siehe Abschnitt 4.

**Ob die 16 echten Aufgaben jetzt bestehen, ist noch nicht gemessen.** Das zeigt erst `MAC_TESTEN.command` auf Ihrem Mac.

## 1. Hier ausgeführt: 210 Python-Tests, alle bestanden, keiner übersprungen

Ausgeführt mit `-W error::ResourceWarning`. Rohprotokoll: `TESTRESULTS-0.6.0.txt`; das alte Protokoll liegt in `docs/`.

| Testdatei | Anzahl | Echt | Simuliert |
|---|---|---|---|
| **`test_learning.py`** (neu) | 11 | Erfahrungsspeicher in SQLite, auch über einen simulierten Neustart; Ergebnisbewertung, Reflexion, Korrekturregeln, Kennzahlen, Export | Modell |
| **`test_skills.py`** (neu) | 8 | Statische Prüfung, Sandbox-Prozesse, Netzwerksperre, Schreibsperre, echte PowerPoint-Datei erzeugt und nachgelesen, Versionen, Rücksetzen, Freigabe, Paketfreigabe | Modell, das den Code schreibt |
| **`test_evolution.py`** (neu) | 21 | Wissen mit Belegprüfung gegen den Quelltext, Verbesserungsmotor mit automatischem Zurücknehmen, Code-Werkstatt mit echten Testläufen in Kopien und echter Sicherung/Wiederherstellung, Lernplaner (Pause, Limit, Netz, Neustart), Agent und Server-Schnittstelle | Modell, Websuche, Webseiten |
| `test_tools.py` | 31 | Dateien, PDF, Excel, Sortieren, Ersetzen, Tests ausführen, Terminal-Liste, Pfadregeln | macOS-Programme, Bildmodell, Webseiten |
| `test_agent.py` | 34 | Server, Streaming, Rundreise zur App, Bestätigungen, Abbruch, Lebenszeichen, Gedächtnis, Router | Modell |
| `test_robustness.py` | 9 | Ollama aus, kaputtes JSON, abgebrochener Stream, offline, Zeitlimit, Migration, Leistung | Modell, Internet |
| `test_realtests.py` | 7 | Prüflogik der 16 echten Aufgaben, Modellvergleich | Entscheidungen des Modells |
| `test_scripts.py` | 7 | Rollback, Autostart, Zusammenfassung, Skriptsyntax | `launchctl` |
| aus 0.2.3 | 82 | Chat, Daten, Audio mit echtem ffmpeg, Rechnen, Befehle | Modell, Spracherkennung |

### Nachweise für die vier geforderten Punkte

Alle vier sind **simuliert** im Sinne der Tabelle oben: Das Sprachmodell gibt die Antworten fest vor. Datenbank, Dateien, Prozesse, Sandbox und Rücksetzen laufen echt.

1. **Erfahrungen werden gespeichert:** `test_verified_success_is_reused_for_similar_task`.
   - Die Aufgabe wird gespeichert (Erfolg, bestätigt, Aufgabenart).
   - Bei einer ähnlichen Aufgabe steht der bewährte Ablauf im Prompt.
   - `test_failure_becomes_warning_not_proven`: Fehler werden Warnungen, keine „bewährten“ Abläufe.
2. **Korrekturen werden später angewandt:** `test_correction_is_learned_and_survives_restart`.
   - Auf „Atlas, das war nicht richtig. Du solltest die Datei in Dokumente speichern.“ legt ATLAS die Datei sofort in Dokumente an.
   - Nach einem Neustart steht die Regel bei einer neuen Datei-Aufgabe im Prompt, bei einer Plauderfrage nicht.
   - `test_durable_preference_applies_everywhere`: „ab jetzt immer“ gilt überall.
3. **Fähigkeiten entstehen in der Sandbox:** `test_new_skill_is_developed_tested_approved_and_used`.
   - Der erste Code-Entwurf besteht seine Tests nicht.
   - ATLAS bekommt die Fehlermeldung, der zweite Entwurf besteht.
   - Ohne Freigabe ist die Fähigkeit nicht aktiv. Nach der Freigabe erzeugt sie eine **echte .pptx**, die mit python-pptx nachgelesen wird.
   - Gefährlicher Code wird nie ausgeführt.
   - Netzwerk und Schreiben außerhalb der Sandbox schlagen fehl.
4. **Fehlgeschlagene Verbesserungen werden zurückgesetzt:**
   - `test_failed_improvement_is_rolled_back_automatically`: Ein Hinweis, nach dem der Fehler weiter auftritt, wird automatisch abgeschaltet.
   - `test_change_with_failing_tests_is_discarded`: Eine Code-Änderung mit roten Tests wird verworfen, das Original bleibt unberührt.
   - `test_failed_check_after_apply_restores_automatically`: Scheitert die Prüfung nach der Übernahme, wird das Original wiederhergestellt.
   - `test_tested_change_is_applied_only_after_approval_and_can_be_rolled_back`: Eine übernommene Änderung lässt sich zurücksetzen.
   - `test_versions_and_rollback`: Fähigkeiten gehen zurück auf die vorige Version.

**Weitere Prüfungen:**
- 9 Chromium-Prüfgruppen der Weboberfläche bestanden.
- Swift-Syntax aller Swift-Dateien mit tree-sitter geprüft: 0 Fehler. Das ist **kein** Compiler-Lauf.
- Übersicht „Learning & Evolution“ aus dem echten Server (Fixture mit simuliertem Modell) gegen alle Pflichtfelder der Swift-Strukturen geprüft, auch mit gefüllten Listen.

**Nicht hier geprüft:**
- Ob das echte `qwen3:4b-instruct` brauchbaren Fähigkeits-Code und brauchbare Wissensauszüge schreibt.
- Ob das `sandbox-exec`-Profil der Code-Werkstatt auf macOS wie gedacht greift.

## 2. Automatisch auf dem Mac (hier nicht ausführbar)

| Prüfung | Skript | Art |
|---|---|---|
| Xcode-Build und Signatur | `AKTUALISIEREN.command` → `BAUEN.command` | echt |
| Swift ⇄ Backend (9 Prüfungen + Learning-Übersicht dekodieren, Pause speichern) | `Tests/test_provider_mac.sh` | Backend echt, Modell simuliert |
| 210 Backend-Tests in der Atlas-Umgebung (mit openpyxl, pypdf, python-pptx) | Update, `MAC_TESTEN.command` | wie oben |
| Kurztest mit echtem Modell (3 Aufgaben) | Ende von `AKTUALISIEREN.command` | **echtes Modell** |
| **16 echte Aufgaben**, Ergebnis in Dateien nachgeprüft, Zeiten gemessen; Modellvergleich, wenn mehrere installiert sind | `MAC_TESTEN.command` | **echtes Modell** |

## 3. Nur von Hand (Hardware und echtes Modell)

- **Learning & Evolution mit echtem Modell:**
  1. „Lerne, wie man PowerPoint-Präsentationen erstellt“ sagen.
  2. Nach einigen Minuten das Gehirn-Symbol öffnen und die Freigabe prüfen.
  3. Freigeben, dann „Erstelle eine Präsentation über …“ sagen.
- **Wissen:** „Lerne alles über Unternehmensbewertung“, danach Quellen und Status der Aussagen ansehen.

- Mikrofon, Wake-Word „Atlas“, Unterbrechen, Gesprächsende.
- Klang der Stimme.
- Statuszeile und Aufgabenfeld.
- macOS-Freigaben.
- Gedächtnis nach einem Neustart: Die native Datenbank liegt in SwiftData und bleibt bei Updates unverändert. Ein Neustart-Test hat auf dem Mac aber noch nicht stattgefunden.

## 4. Liste aller behobenen Fehler

| Version | Fehler | Gefunden durch |
|---|---|---|
| 0.6.0 | Netzsperre der Sandbox ersetzte `socket.socket` durch eine Funktion; dadurch brach `import ssl` und mit ihm python-pptx | Test (echte PowerPoint-Fähigkeit) |
| 0.6.0 | Schreibschutz der Sandbox erlaubte ganz `/tmp`; jetzt nur ein eigener, leerer Temp-Ordner | Test |
| 0.5.0 | Modell beschreibt Werkzeuge bzw. plant auf Englisch, statt sie aufzurufen | Ihre Mac-Ergebnisse |
| 0.5.0 | Englische Überlegungen erschienen als Schlussantwort | Ihre Mac-Ergebnisse |
| 0.5.0 | Sortieren und Fehlerbehebung brauchten zu viele Einzelaufrufe für ein 4B-Modell | Ursachenanalyse |
| 0.5.0 | Excel scheiterte an verschachteltem Eingabeformat | Ursachenanalyse |
| 0.5.0 | „Das war falsch“ wurde nicht als Korrektur erkannt | Test |
| 0.4.1 | `qwen3:4b` (Denk-Variante) für alles benutzt; Selbstgespräch sichtbar | Ihr Diagnose-Screenshot |
| 0.4.1 | Modellnamen mit Großbuchstaben (`q4_K_M`) galten als ungültig | Test |
| 0.4.0 | Veralteter Python-Bytecode beim Testen nach einer Korrektur | echter Testlauf |
| 0.4.0 | „Merk dir bitte, dass …“ speicherte „bitte, dass …“ | Test |
| 0.4.0 | Duplikatprüfung umgangen; Berlin und Hamburg als Duplikat | Test |
| 0.4.0 | Rollback brach ohne Sicherung stumm ab | Test |
| 0.4.0 | Irreführende Fehlermeldung bei ausgeschaltetem Ollama | Test |
| 0.4.0 | Behobener Testlauf stand als Fehler im Bericht | Test |
| 0.3.x | `~`-Auflösung, unnötiges Planen, Wortgrenzen im Router, abgelehnte Aktionen als Fehler, feste Ollama-Adresse, Prozentfragen, Verbindungsabbruch bei langen Aufgaben | Tests, Durchsicht |
