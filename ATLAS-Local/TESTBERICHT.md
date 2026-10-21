# Testbericht ATLAS Local 0.4.1

Stand: 21.10.2026.

Die Entwicklungsumgebung ist ein Linux-Container: ohne Mac, ohne Swift-Compiler und ohne Ollama-Modelle. Die Netzwerkregel sperrt `ollama.com`, `registry.ollama.ai` und `huggingface.co`.

**Wichtig:** Kein Ergebnis in Abschnitt 1 ist ein Hardware- oder Echtmodelltest. Wo ein Modell beteiligt ist, war es simuliert (FakeOllama). Echte Modell-, Build- und Audiotests laufen erst auf dem Mac (Abschnitt 2).

## 0. Erster echter Mac-Test (von Ihnen, 21.10.2026, Version 0.4.0)

Ausschnitt der Diagnose mit `qwen3:4b` auf dem MacBook Pro M4:

- Erste Ausgabe nach 0,07–0,12 s.
- Rund 35 Tokens/s.
- Aber 8,8–14,9 s Gesamtzeit, auch für „Antworte exakt mit: Atlas bereit.“, also etwa 300 Tokens statt drei Wörtern.
- Spracherkennung mit synthetischer Stimme: fehlerfrei („Hallo Atlas, heute testen wir die lokale Spracherkennung.“).
- qwen3:8b war nicht installiert.

Diagnose: Das Modell schreibt vor der Antwort ein Selbstgespräch (Denk-Variante). Die Ergebnisse der 12 echten Aufgaben lagen mir nicht vor.

Reaktion in 0.4.1:

- Schnelle Variante ohne Denkschritt bevorzugen und automatisch laden.
- Denk-Modelle automatisch erkennen (einmalige Probeanfrage) und ihr Selbstgespräch nie anzeigen oder vorlesen.
- Gefunden dabei: Modellnamen mit Großbuchstaben (`q4_K_M`) wurden als ungültig verworfen. Behoben.

**Ob die Antwortzeit damit tatsächlich auf 1–2 s sinkt, zeigt erst der nächste Mac-Test.**

## 1. Hier tatsächlich ausgeführt

**157 Python-Tests bestanden** (0.2.3 hatte 82). Neu in 0.4.1: Denk-Modell-Erkennung und Ausblenden des Selbstgesprächs (auch zerstückelt im Stream, ohne Textverlust bei Fehleinschätzung), Bevorzugung der schnellen Variante, Großbuchstaben in Modellnamen, Zusammenfassung auf einem Bildschirm. Ausgeführt mit `-W error::ResourceWarning`. Rohprotokoll: `TESTRESULTS-0.4.1.txt`.

| Testdatei | Anzahl | Was echt läuft | Was simuliert ist |
|---|---|---|---|
| `test_tools.py` | 26 | Dateien, Ordner, PDF (pypdf), Excel (openpyxl), Papierkorb, Suche, Terminal mit echtem `ls`/`python3 -m unittest`, Zeitlimit, Pfad- und Symlink-Regeln, 43 Befehlsfälle der Terminal-Liste | macOS-Programme (`open`, `pgrep`, `osascript`, `screencapture`), Bildmodell, Webseiten |
| `test_agent.py` | 27 | HTTP-Server, Streaming, Rundreise zur App, Bestätigungen, Abbruch, 409, Lebenszeichen, Gedächtnisauswahl, Duplikate und veraltete Erinnerungen, Korrekturen, Englisch, Router | Sprachmodell |
| `test_robustness.py` | 9 | Ollama nicht erreichbar, kaputtes JSON, abgebrochener Stream, unbekanntes Werkzeug, falsche Argumente, kein Internet, Zeitlimit, Migration einer 0.2.x-Datenbank (50 Gespräche und 1 Erinnerung bleiben erhalten), Leistungsmessung | Sprachmodell, Internet |
| `test_realtests.py` | 3 | „Ordner sortieren“ und „Fehler beheben“ als mehrstufige Abläufe mit echtem Verschieben, echtem Testlauf (erst rot, nach Korrektur grün) und der Prüflogik der Echtmodell-Tests; ohne Bestätigung bleibt alles unverändert | die Entscheidungen des Modells (vorgegeben) |
| `test_scripts.py` | 6 | `ZURUECKSETZEN.command` in einem temporären HOME (Rückweg, nichts gelöscht, Daten nur auf Wunsch), Autostart-Datei, Syntax aller Skripte, Reihenfolge im Update (erst bauen und testen, dann ersetzen) | `launchctl` |
| Bestehende Tests von 0.2.3 (`test_atlas`, `test_native`, `test_intents`, `test_diagnostics`) | 82 | Chat, Daten, Abbruch, Audio-Codecs mit echtem ffmpeg, Rechnen, Befehle | Modell, Spracherkennung |

**Weitere Prüfungen:**
- 9 Chromium-Prüfgruppen der Weboberfläche bestanden (Playwright).
- Swift-Syntax aller geänderten Dateien mit tree-sitter geprüft. Das ist kein Compiler-Lauf.

**Gemessen** in der Linux-Umgebung, mit simuliertem Modell. Das zeigt nur den Eigenaufwand von ATLAS, nicht die Modellzeit:
- Bis zum ersten Wort: Median **1,1 ms**.
- Auswahl passender Erinnerungen aus 500 Einträgen: **9 ms**, Speicherspitze unter 0,1 MB.

## 2. Automatisch auf dem Mac, hier NICHT ausführbar

| Prüfung | Wo | Art |
|---|---|---|
| Xcode-Build, Signaturprüfung | `BAUEN.command` (vor jedem Update) | echt |
| Swift ⇄ Backend, 9 Prüfungen | `Tests/test_provider_mac.sh` | echtes Backend, Modell simuliert |
| Swift-Sprachtext-Tests | dito | echt |
| 157 Backend-Tests in der Atlas-Python-Umgebung | Update, `MAC_TESTEN.command` | wie oben |
| **12 Aufgaben mit dem echten Qwen**, Ergebnis jeweils in Dateien nachgeprüft, mit gemessenen Antwortzeiten | `MAC_TESTEN.command` → `build/MAC-ECHTE-MODELLTESTS.json` | **echtes Modell** |
| Dienstprüfung nach dem Update (Agent-Protokoll, Rechner) | `AKTUALISIEREN.command` | echt |
| Spracherkennung mit synthetischer Stimme | `atlas.doctor --audio` | echt, ohne Mikrofon |

Die 12 echten Aufgaben:
1. Rechnen
2. Prozent
3. Kurze Antwort
4. Englisch
5. Ordner und Datei
6. Excel
7. PDF
8. Systeminfo
9. Löschen abgelehnt
10. **Ordner nach Typ sortieren**
11. **Fehler im Projekt finden, beheben, Tests grün**
12. Keine erfundene E-Mail

Fehlt Ollama, steht im Bericht „nicht ausgeführt“, nicht „bestanden“.

## 3. Nur von Hand prüfbar

- Mikrofon, Wake-Word „Atlas“, Unterbrechen, Gesprächsende.
- Klang der Stimme.
- Darstellung der neuen Statuszeile und des Aufgabenfelds.
- Freigabe-Dialoge von macOS.
- Gefühlte Antwortqualität.

## 4. In dieser Runde gefundene und behobene Fehler

1. **Veralteter Python-Bytecode:** Korrigierte ATLAS eine Datei und testete in derselben Sekunde, lief der alte Code (gefunden durch einen echten Testlauf). Jetzt läuft jeder Projektlauf mit leerem Bytecode-Ordner.
2. **„Merk dir bitte, dass …“** speicherte „bitte, dass …“. Behoben.
3. **Duplikatprüfung:** Der Schnellweg „Merk dir …“ umging sie. Behoben.
4. **Semantische Nähe galt als Duplikat:** „Wohnt in Berlin“ und „wohnt in Hamburg“ wären zusammengefallen. Jetzt nur ein Hinweis an das Modell, die veraltete Erinnerung zu ersetzen.
5. **Rollback ohne Sicherung** brach stumm ab. Jetzt erscheint eine klare Meldung, und nichts wird verändert.
6. **Unklare Fehlermeldungen:** Bei ausgeschaltetem Ollama hieß es „kein Modell installiert“. Jetzt heißt es „Ollama ist nicht erreichbar …“. Kaputte Antworten und Zeitüberschreitungen werden ebenfalls klar gemeldet.
7. **Abschlussbericht:** Ein erst roter, dann behobener Testlauf stand als „fehlgeschlagen“ im Bericht. Jetzt gilt er als erledigt.

Behoben in früheren Runden (0.3.x): `~`-Auflösung, unnötiges Planen, Wortgrenzen im Router, abgelehnte Aktionen im Bericht, feste Ollama-Adresse, Prozentfragen, Verbindungsabbruch bei langen Aufgaben.
