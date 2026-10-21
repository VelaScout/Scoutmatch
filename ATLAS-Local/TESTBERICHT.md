# Testbericht ATLAS Local 0.3.1

Stand: 21.10.2026. Entwicklungsumgebung: Linux-Container ohne Mac, ohne Swift-Compiler, ohne Ollama-Modelle.

Die Netzwerkregel der Umgebung sperrt `ollama.com`, `registry.ollama.ai` und `huggingface.co`.

## 1. Hier tatsächlich ausgeführt

**131 Python-Tests bestanden** (vorher 82; 49 neu). Rohprotokoll: `TESTRESULTS-0.3.1.txt`.

### Werkzeuge (`test_tools.py`, 25 Tests)

Echt ausgeführt, in einem temporären Home-Ordner:

- Ordner und Dateien anlegen, Inhalt zurücklesen.
- Überschreibschutz: Ersetzen geht nur mit Bestätigung.
- PDF-Text auslesen (echtes PDF, pypdf).
- Excel mit Formeln, Zahlen und fetter Kopfzeile anlegen und wieder einlesen (openpyxl). Ersatz als CSV, wenn openpyxl fehlt.
- Verschieben, Papierkorb statt endgültigem Löschen.
- Dateisuche.
- Terminalbefehle wirklich ausführen, mit Exit-Code, Arbeitsordner und Zeitlimit.
- Pfadregeln: außerhalb des Home-Ordners, `~/Library`, versteckte Ordner, Symlink-Ausbruch.
- Risikostufen für 15 Befehle.
- URL-Filter (`file:`, localhost, lokales Netz).
- Suchergebnisse auswerten, Webseitentext ohne Skripte.
- Rechnen mit Prozent und Dezimalkomma.
- Werkzeugschemas sind gültige Ollama-Funktionen.
- Neu in 0.3.1:
  - Bildschirmanalyse mit lokalem Bildmodell. Das Foto liegt nur temporär außerhalb Ihrer Ordner und wird gelöscht.
  - Klarer Hinweis, wenn kein Bildmodell installiert ist.
  - Bildanalyse von Dateien.
  - Safari-Seite lesen.
  - Projektanalyse: Art, Testbefehl, Git-Status, README.
- Simuliert dabei: Bildmodell, `screencapture`, `osascript`, `git`.

Simuliert: macOS-Programme (`open`, `pgrep`) und Webseiteninhalte.

### Agent über den echten HTTP-Server und Router (`test_agent.py`, 24 Tests)

Simuliertes Modell, alles andere echt:

- Rechnung ohne Modellaufruf.
- Smalltalk im Stream ohne Werkzeuge mit dem schnellen Modell.
- Ordner und Datei per Agent wirklich angelegt; der Agent wählt das größere Modell und sieht die Dateiwerkzeuge.
- Löschen:
  - Mit Bestätigungsrundreise.
  - Ablehnung wird respektiert und erscheint im Bericht nicht als Fehler.
  - Nach Zustimmung landet die Datei im Papierkorb.
- `sudo rm -rf /` wird gesperrt, ohne nachzufragen.
- Kalender-Rundreise zur App.
- Falsche Erfolgsbehauptung des Modells wird korrigiert.
- Keine Endlosschleife bei wiederholtem Fehler.
- Planmodus mit Bericht über offene Schritte.
- Abbruch, während der Agent auf die App wartet (unter 4 s).
- Lebenszeichen bei langen Modellläufen, damit die App die Verbindung nicht abbricht.
- Parallele Anfrage ergibt HTTP 409.
- Ungültige Anfragen und Cloud-Modelle werden abgewiesen.
- Ergebnisse nur mit Token.
- Werkzeugaufrufe als Text werden verstanden.
- Passende Erinnerungen werden semantisch ausgewählt.
- Englische Frage führt zur Anweisung, englisch zu antworten.
- Bei einer Korrektur bietet der Agent `remember` an, mit wenigen Werkzeugen, und die Vorliebe wird gespeichert.

### Router und Gedächtnis

- 9 Routing-Fälle aus dem Projektauftrag, darunter Korrektur und Bildschirmfrage.
- Spracherkennung Deutsch/Englisch.
- Lexikalische Erinnerungssuche.
- Zusammenfassungs-Cache.
- Sperre für Cloud-Modelle.

### Bestehende Tests von 0.2.3

Alle 82 erneut bestanden: Chat, Fehler, Daten, Abbruch, Audio-Codecs mit echtem ffmpeg, Diagnose, Befehle, Rechnen.

### Weitere Prüfungen

- **9 Chromium-Prüfgruppen** der Weboberfläche bestanden (Playwright; Modell, Spracherkennung und Betriebssystem simuliert).
- **Swift-Testumgebung geprüft:** `Tests/agent_fixture.py` (echtes Backend, simuliertes Modell) wurde mit einem Python-Client durchgespielt, der den Swift-Client nachbildet. Geprüft wurden Health, Stream, Rechnung, echter Ordner, Kalender-Rundreise, Löschen Nein/Ja und Fehlermeldung.
- **Swift-Syntax** der geänderten Dateien mit tree-sitter geprüft. Das ist kein Compiler-Lauf.

## 2. Automatisch auf dem Mac, hier NICHT ausführbar

| Prüfung | Wo | Art |
|---|---|---|
| Xcode-Build und Signatur | `BAUEN.command` (Teil von Update/Installation) | echt |
| Swift ⇄ Backend, 9 Prüfungen | `Tests/test_provider_mac.sh` | echtes Backend, Modell simuliert |
| Sprachtext-Tests (Swift) | dito | echt |
| 131 Backend-Tests in der Atlas-Python-Umgebung | Update und `MAC_TESTEN.command` | wie oben |
| **10 Aufgaben mit dem echten Qwen** | `MAC_TESTEN.command` → `build/MAC-ECHTE-MODELLTESTS.json` | **echte Modellaufrufe** |
| Antwortzeiten (erste Ausgabe, gesamt) je Aufgabe | dito | echt gemessen |
| Dienstprüfung nach dem Update (Agent-Protokoll, Rechner) | `AKTUALISIEREN.command` | echt |
| Spracherkennung mit synthetischer Stimme | `atlas.doctor --audio` | echt, ohne Mikrofon |

Die 10 echten Aufgaben werden am **Ergebnis** geprüft, nicht nur am Aufruf:

1. Rechnung
2. Prozent
3. Kurze Antwort (Paris)
4. Englisch (Tokyo)
5. Ordner plus Datei mit Inhalt
6. Excel mit Miete 1200
7. PDF-Umsatz 42000
8. Speicherplatz mit Systemwerkzeug
9. Löschen abgelehnt, die Datei bleibt
10. Keine erfundene E-Mail

Fehlt Ollama, steht im Bericht „nicht ausgeführt“, nicht „bestanden“.

## 3. Nur von Hand auf dem Mac prüfbar

- Mikrofon und Freigaben, Wake-Word „Atlas“, Unterbrechen während der Ausgabe.
- Klang der Stimme. Bitte eine Premium-Stimme laden.
- Echte Bestätigungsdialoge in der App, Kalender und Erinnerungen mit Ihren Daten, Safari-Öffnen.
- Datei-Freigabe-Dialoge von macOS für „python3“.
- Gefühlte Gesprächsqualität bei freien Fragen. Die automatischen Fälle sind eng und kein Qualitätsnachweis auf ChatGPT-Niveau.

## 4. Während der Entwicklung gefundene und behobene Fehler

1. `~` wurde auf das echte statt auf das konfigurierte Home-Verzeichnis aufgelöst. Gefunden durch den Pfadtest; behoben, mit Regressionstest.
2. Der Router plante einfache Zwei-Schritte-Aufgaben unnötig (eine zusätzliche Modellrunde). Ursache: „Schreibtisch“ wurde als Verb „schreib…“ gezählt. Behoben, mit Test.
3. Aufgabenwörter wie „erstelle“ und „speichere“ wurden wegen einer Wortgrenze nicht erkannt. Umgestellt auf Wortanfänge, mit Tests.
4. Eine abgelehnte Aktion erschien im Bericht als „fehlgeschlagen“. Jetzt steht sie als „nicht ausgeführt, weil abgelehnt“ da.
5. Die Health-Abfrage nutzte eine feste Ollama-Adresse statt der konfigurierten. Behoben (wichtig für die Swift-Testumgebung).
6. „Wie viel sind 19 Prozent von 2500“ ging ans Modell statt an den exakten Rechner. Behoben.
7. Bei der Durchsicht gefunden: Die App hätte lange Agenten-Aufgaben abgebrochen (75 s ohne Daten bzw. 180 s gesamt). Jetzt sendet das Backend alle 8 s ein Lebenszeichen, und die Gesamtgrenze liegt bei 15 Minuten. Mit Test.
