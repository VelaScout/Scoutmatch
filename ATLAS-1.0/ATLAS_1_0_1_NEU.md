# ATLAS 1.0.1 – was neu ist

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
2. `ATLAS_1_0_1_UPDATE.command` doppelklicken. Erst laufen alle Tests; nur wenn sie bestehen, wird der Dienst ausgetauscht
   (mit Sicherung; startet der neue Dienst nicht, wird automatisch der alte wiederhergestellt).
3. ATLAS-App starten, dann `ATLAS-1.0-GESAMTPRUEFUNG/ATLAS_GESAMTPRUEFUNG.command` – am besten mit Claude-Vergleich.

## Ehrlich
- Geprüft hier: 386 Backend-Tests (Python 3.13 und 3.15) BESTANDEN; Gesamtprüfung gegen den echten ATLAS-Code mit
  simuliertem Modell BESTANDEN. **Nicht** geprüft: das echte Modell auf Ihrem Mac – das zeigt erst Ihre Gesamtprüfung.
- Die Schutzregeln sind feste Muster: Sie fangen die typischen Fälle sicher ab, aber nicht jede denkbare Umschreibung.
- Der Denkmodus verbessert Rechnen und Logik deutlich, macht ein 4B-Modell aber nicht in allem so stark wie Claude.
