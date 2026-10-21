# Testbericht ATLAS Local 0.5.0

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

## 1. Hier ausgeführt: 170 Python-Tests, alle bestanden

Ausgeführt mit `-W error::ResourceWarning`. Rohprotokoll: `TESTRESULTS-0.5.0.txt`.

| Testdatei | Anzahl | Echt | Simuliert |
|---|---|---|---|
| `test_tools.py` | 31 | Dateien, PDF, Excel (5 Eingabeformen), Sortieren nach Typ, Textstelle ersetzen, Tests erkennen und ausführen (erst rot, dann grün), Datei von gestern, Terminal-Liste (43 Fälle), Pfadregeln | macOS-Programme, Bildmodell, Webseiten |
| `test_agent.py` | 34 | Server, Streaming, Rundreise zur App, Bestätigungen, Abbruch, Lebenszeichen, Gedächtnis, Router | Modell |
| ↳ darin neu | | Nachfassen bei Planungstext, nur einmal, kein Nachfassen bei normaler deutscher Antwort, englischer Schlusstext wird ersetzt, „Das war falsch“ als Korrektur, Denk-Modell-Selbstgespräch nie sichtbar, schnelles Modell bevorzugt | |
| `test_robustness.py` | 9 | Ollama aus, kaputtes JSON, abgebrochener Stream, falsche Werkzeuge und Argumente, offline, Zeitlimit, Migration 0.2.x, Leistung | Modell, Internet |
| `test_realtests.py` | 7 | Prüflogik der echten Aufgaben mit echten Dateien und echten Testläufen; Modellvergleich mit Eintrag des besten Modells | Entscheidungen des Modells |
| `test_scripts.py` | 7 | Rollback in temporärem HOME, Autostart-Datei, Zusammenfassung passt auf einen Bildschirm, Skriptsyntax, Reihenfolge im Update | `launchctl` |
| aus 0.2.3 | 82 | Chat, Daten, Audio-Codecs mit echtem ffmpeg, Rechnen, Befehle | Modell, Spracherkennung |

**Weitere Prüfungen:**
- 9 Chromium-Prüfgruppen der Weboberfläche bestanden.
- Swift-Syntax mit tree-sitter geprüft. Das ist kein Compiler-Lauf.

**Gemessen** (Linux, Modell simuliert, nur der Eigenaufwand von ATLAS):
- Bis zum ersten Wort: 1,3 ms.
- Erinnerungsauswahl aus 500 Einträgen: 11 ms.

## 2. Automatisch auf dem Mac (hier nicht ausführbar)

| Prüfung | Skript | Art |
|---|---|---|
| Xcode-Build und Signatur | `AKTUALISIEREN.command` → `BAUEN.command` | echt |
| Swift ⇄ Backend (9 Prüfungen) | `Tests/test_provider_mac.sh` | Backend echt, Modell simuliert |
| 170 Backend-Tests in der Atlas-Umgebung (mit openpyxl/pypdf, ohne Überspringen) | Update, `MAC_TESTEN.command` | wie oben |
| Kurztest mit echtem Modell (3 Aufgaben) | Ende von `AKTUALISIEREN.command` | **echtes Modell** |
| **16 echte Aufgaben**, Ergebnis in Dateien nachgeprüft, Zeiten gemessen; Modellvergleich, wenn mehrere installiert sind | `MAC_TESTEN.command` | **echtes Modell** |

## 3. Nur von Hand (Hardware)

- Mikrofon, Wake-Word „Atlas“, Unterbrechen, Gesprächsende.
- Klang der Stimme.
- Statuszeile und Aufgabenfeld.
- macOS-Freigaben.
- Gedächtnis nach einem Neustart: Die native Datenbank liegt in SwiftData und bleibt bei Updates unverändert. Ein Neustart-Test hat auf dem Mac aber noch nicht stattgefunden.

## 4. Liste aller behobenen Fehler

| Version | Fehler | Gefunden durch |
|---|---|---|
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
