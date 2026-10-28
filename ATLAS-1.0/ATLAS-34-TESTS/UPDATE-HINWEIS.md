# Korrektur des ATLAS-34-Kategorien-Tests

Die Bewertung erkennt nun numerisch gleichwertige Antworten (z. B. x = 9, 150 cm², LaTeX-Brüche und 57,14 km/h). Tatsächlich falsche Zahlen bleiben falsch. Wortübersetzungen werden weiterhin streng bewertet.

**Bestehende Ergebnisse neu bewerten:** `NEU-BEWERTEN.command` starten. Der Befehl benutzt die gespeicherten Antworten und benötigt kein Ollama. Vorherige Statusänderungen werden mit `previous_status` dokumentiert.

**Echte KI-Tests:** Zum erneuten Testen der fehlgeschlagenen Aufgaben `python3 atlas_gesamt_test.py --retry-failed --limit 0` verwenden. Dabei werden die bisherigen Antworten dieser Aufgaben überschrieben; vorher die JSON-Datei sichern.

Diese Änderung verbessert die **Testauswertung**, nicht die Intelligenz des lokalen Sprachmodells. Tests auf Mac/Ollama sind weiterhin erforderlich.
