# ATLAS 1.0.9 – Vergleichstest über zehn Bereiche

**Ziel:** Reproduzierbare Fortschrittsmessung, nicht künstliche 100-%-Bewertung.

## Anwendung
1. ATLAS und Ollama auf dem Mac starten.
2. `ATLAS_109_VERGLEICH_STARTEN.command` doppelklicken.
3. `ATLAS-VERGLEICH-ERGEBNISSE/atlas_bericht.md` öffnen.
4. Praxisaufgaben aus der Liste separat durchführen. Die Ergebnisse und Beweise in der JSON-Datei dokumentieren (Status PASS/FAIL, `evidence` mit Log, Aufnahme, Datei oder Screenshot). Eine bloße Behauptung ist kein Nachweis.
5. Die gleichen Aufgaben mit ChatGPT und Claude wiederholen. Dabei Modellversion, Datum, Werkzeuge, Zugriffsrechte, Kosten und Laufzeit erfassen.

## Bewertung
- PASS: Kriterium nachweisbar erfüllt.
- FAIL: Kriterium nachweisbar nicht erfüllt.
- REVIEW: benötigt manuelle Bewertung bzw. praktische Durchführung.
- BLOCKED: technischer Test nicht möglich; zählt niemals als PASS.

**Vergleichbarkeit:** Die kurzen automatischen Tests laufen über den nativen ATLAS-Chat-Endpunkt. Die Praxisaufgaben zu Stimme, Erinnerung über Sitzungen, Web, Dateien und Bildern können nicht seriös durch reine Textantworten bestanden werden. Bei diesen Aufgaben müssen tatsächliche Aktionen bzw. Artefakte überprüft werden. Der Test enthält 40 Aufgaben, vier je Bereich; er ist ein Abnahmekatalog, kein allgemein anerkannter KI-Benchmark. Für ein Gleichwertigkeitsurteil sind zusätzliche Blindbewertungen, wiederholte Läufe und schwierigere unabhängige Testdaten erforderlich.

**Sicherheit:** Keine echten Zugangsdaten, persönlichen Dateien oder produktiven Ordner für die Tests verwenden. Dateiaktionen nur im separaten Testordner und mit Bestätigung durchführen.
