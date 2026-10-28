# ATLAS 34-Kategorien-Tests – überarbeitete Version

- 102 Aufgaben, davon 45 automatisierte Kurzantwortprüfungen und 57 manuelle Praxisaufgaben.
- Start: `bash ATLAS_GESAMTTEST_STARTEN.command` aus diesem Ordner.
- Unterbrechung: Ctrl+C; die jeweils abgeschlossene Aufgabe wird sofort in `~/Downloads/ATLAS-Testberichte/atlas-34-kategorien.json` gespeichert.
- Nur prüfen, ohne Ollama: `python3 atlas_gesamt_test.py --verify`.
- Manuelle Selbstauskünfte werden ausdrücklich **nicht** als unabhängig bestanden gezählt.
- Bei Änderung des Testkatalogs ist ein neuer Ergebnisstand nötig.
- Dies ist kein validierter Vergleich mit ChatGPT oder Claude.

Die Backend-Softwaretests liegen im Schwesterordner `Backend/tests`. Die tatsächliche lokale Modellqualität muss auf dem Mac gemessen werden.
