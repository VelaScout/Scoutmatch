# ATLAS 1.0.10 – Belegbasierte Prüfungen

Version 1.0.9 hatte 28 manuelle Aufgaben, die absichtlich nicht automatisch als bestanden gelten. Mit 1.0.10 können die tatsächlichen Nachweise nun geprüft, mit SHA-256 protokolliert und der passenden Aufgabe zugeordnet werden.

## Auf dem Mac

1. `ATLAS_109_VERGLEICH_STARTEN.command` ausführen (erzeugt `ATLAS-VERGLEICH-ERGEBNISSE/atlas_ergebnisse.json`).
2. Für jede tatsächlich geprüfte Praxisaufgabe einen Nachweis speichern, z.B. `ATLAS-VERGLEICH-ERGEBNISSE/belege/s01.wav`.
3. `ATLAS-VERGLEICH-ERGEBNISSE/manuelle_belege.json` mit folgendem Format anlegen:

```json
{"reviews":[{"id":"s01","verdict":"PASS","reviewer":"Name des Prüfers","rationale":"Aufnahme mit Referenzsatz abgeglichen; Aussprache, Pausen und Betonung bewertet.","evidence_file":"belege/s01.wav"}]}
```

4. `ATLAS_110_BELEGE_PRUEFEN.command` ausführen. Ergebnis: `atlas_geprueft.json`. Fehlende Dateien, doppelte IDs, kurze unbegründete Bewertungen und Manipulation automatisch bewerteter Fälle werden abgelehnt. Ein Dateinachweis belegt **nicht von selbst** die Qualität des Inhalts: Die menschliche Bewertung bleibt erforderlich.

## Vergleich mit ChatGPT und Claude

Die 40 Aufgaben sind ein projektspezifischer Abnahmekatalog, **kein Beweis der Gleichwertigkeit**. Vergleichstests müssen dieselben Eingaben, Versionen, Werkzeugrechte, Referenzdaten und möglichst unabhängige Blindbewertungen verwenden. Die Aufgaben zu Gedächtnis und Autonomie erfordern Sitzungen und tatsächliche Aktionen. Ein einzelner Prompt ersetzt das nicht.

**Bekannte Grenze:** Der ursprüngliche `g02`-Kurztest fragt die Teamzahl im selben Prompt ab. Das ist ein Kurzkontexttest, kein Langzeitgedächtnisnachweis. Er sollte in einer künftigen Testsuite durch einen sitzungsübergreifenden Test ersetzt werden.
