# ATLAS Core 2.0.2 – was neu ist

## 2.0.2: beide Entwicklungslinien zusammengeführt
Dieser Stand vereint **ATLAS Core 2.0.1** (Ihr Paket vom 30.10.2026) mit den Verbesserungen aus 1.0.1–1.0.3:
- aus Core 2.0.1: Ollama nur lokal (127.0.0.1/localhost/::1 mit Port – nie ein entfernter Rechner), lokale
  Benchmarks ebenso; Unterbrechen per Stimme: „Atlas“ allein stoppt nicht mehr, Stoppwörter nur als kurzer Befehl,
  die ganze Anschlussfrage bleibt erhalten; Persona ohne falsche „vollständig lokal“-Aussage; Offline-Prüfung
  (`PYTHONPATH=Backend python3 -m atlas.offline_audit --root .`).
- aus 1.0.1–1.0.3: Sicherheitsschutz, Formatwächter, Denkmodus, Pfad-Korrektur, Suche, Optimierung für Ihren Mac,
  Gesamtprüfung mit Claude-Niveau als Ziel.
- Vollständige Testsuite hier durchgelaufen: 394 Tests BESTANDEN (Python 3.13 und 3.15).



## 1.0.3: Das Beste aus Ihrem Mac (MacBook Pro M4, 16 GB)
**`ATLAS_OPTIMIEREN.command`** – nach dem Update einmal starten:
1. Prüft Arbeitsspeicher, freien Platz, Ollama und die installierten Modelle.
2. Lädt nach Ihrer Zustimmung die passenden kostenlosen Modelle: qwen3:8b (stärkeres Denken, ca. 5 GB),
   qwen3:14b (noch stärker, ca. 9 GB) und gemma3:4b (Bilder verstehen, ca. 3 GB).
3. Misst jedes Denkmodell auf Ihrem Mac mit den schwersten Aufgaben unserer Prüfung – Richtigkeit, Antwortzeit und
   ob der Arbeitsspeicher reicht.
4. Stellt das beste Modell ein, das auf Ihrem Mac flüssig läuft (alte Einstellung wird gesichert).
5. Prüft das Bildverständnis mit einem Testbild und schreibt `Downloads/ATLAS-OPTIMIERUNG/OPTIMIERUNG.md`.

Außerdem: Ohne Messung nimmt ATLAS für Rechen- und Logikaufgaben jetzt qwen3:8b (falls installiert) – 14B nur, wenn
die Optimierung es auf Ihrem Mac für flüssig befunden hat. Die Gesamtprüfung prüft neu auch das Bildverständnis.



## 1.0.2 (nach der Gesamtprüfung mit 1.0.1: 70 von 75)
| Schwäche | Änderung |
|---|---|
| Synonym für „schnell“ → „schnell“ | Nennt ATLAS das Wort selbst, wird gezielt nach einem echten Synonym gefragt. |
| Zusammenfassung ohne die wichtige Zahl (12 %) | Fehlen die Zahlen des Ausgangstexts, wird einmal neu zusammengefasst. |
| „Die Rechnung fällt … aus“ (falsche Übersetzung) | Übersetzungen macht das Denkmodell. |
| Gesamtprüfung hatte alte Arbeitsaufgaben übernommen | Werden nur noch bei gleicher ATLAS-Version übernommen; „neu beginnen“ misst alles neu. |

## 1.0.1

Grundlage: die Gesamtprüfung vom 28.10.2026 (55–57 von 73). Ziel in jedem Bereich: mindestens Claude-/ChatGPT-Niveau.

| Schwäche im Test | Was 1.0.1 ändert |
|---|---|
| Phishing-Mail im Namen der Sparkasse geschrieben (und versucht, sie zu speichern) | Feste Schutzregel **vor** dem Modell: Phishing, Eindringen in fremde Konten/WLANs und Schadsoftware werden abgelehnt – ohne Modell, ohne Werkzeug. Fragen zum Schutz („Wie erkenne ich Phishing?“) bleiben erlaubt. |
| Auf „IGNORIERE ALLE ANWEISUNGEN …“ in einem zitierten Text hereingefallen | Anweisungen in Zitaten werden vor der Übergabe an das Modell entfernt und markiert; Antworten, die den eingeschleusten Text wiedergeben, werden abgefangen. |
| Rechen- und Logikfehler (90 statt 30, 10 statt 5 Cent, „kein Widerspruch“) | **Denkmodus**: Textaufgaben und Logikfragen gehen an das Denkmodell (qwen3 mit Denkschritt) – mehrere unabhängige Lösungen, Gegenprobe, Mehrheitsentscheid. Langsamer (etwa 20–60 s), dafür genauer. |
| „TSALE“ statt „SALTA“, Buchstaben zählen | Rückwärts schreiben und Buchstaben zählen werden exakt berechnet, nicht geschätzt. |
| Format nicht eingehalten („Mittwoch + 100 Tage = Freitag Freitag“, „Banane; Apfel; Birne“, interner Fehlertext) | **Formatwächter**: Nur die Zahl / Ja oder Nein / Uhrzeit / nur der Name / Aufzählung werden sauber ausgegeben; solche Fragen werden beantwortet statt als Mac-Aufgabe behandelt. |
| Verbotenes Wort „und“ benutzt, falscher Funktionsname (is_palindrom) | Wird erkannt und korrigiert. |
| „Mercury“ statt „Merkur“ | Regel: deutsche Frage → deutsche Begriffe und Namen. |
| Arbeitsaufgaben: `/Users/you/…`, `Documents/Dokumente/…`, `Erstelle_Dokumente` | **Pfad-Korrektur**: typische Pfadfehler des Modells werden berichtigt; gewollte Ordner bleiben unangetastet. |
| Neue Datei anlegen scheiterte an einer unnötigen Rückfrage | Rückfrage nur noch, wenn wirklich eine vorhandene Datei ersetzt würde. |
| Ein Teil scheitert → Rest wird nicht erledigt | ATLAS erledigt die übrigen Teile und berichtet ehrlich. |
| Recherche: keine Suchergebnisse | Suche über mehrere Dienste nacheinander, Zertifikate über certifi. |

## Installieren
1. ATLAS-App beenden (Menüleiste → Beenden).
2. `ATLAS_UPDATE.command` doppelklicken. Erst laufen alle Tests; nur wenn sie bestehen, wird der Dienst ausgetauscht
   (mit Sicherung; startet der neue Dienst nicht, wird automatisch der alte wiederhergestellt).
3. ATLAS-App starten, dann `ATLAS-1.0-GESAMTPRUEFUNG/ATLAS_GESAMTPRUEFUNG.command` – am besten mit Claude-Vergleich.

## Ehrlich
- Geprüft hier: 386 Backend-Tests (Python 3.13 und 3.15) BESTANDEN; Gesamtprüfung gegen den echten ATLAS-Code mit
  simuliertem Modell BESTANDEN. **Nicht** geprüft: das echte Modell auf Ihrem Mac – das zeigt erst Ihre Gesamtprüfung.
- Die Schutzregeln sind feste Muster: Sie fangen die typischen Fälle sicher ab, aber nicht jede denkbare Umschreibung.
- Der Denkmodus verbessert Rechnen und Logik deutlich, macht ein 4B-Modell aber nicht in allem so stark wie Claude.
