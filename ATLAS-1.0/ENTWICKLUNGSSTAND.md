# ATLAS – geprüfter Entwicklungsstand

Diese Arbeitsversion ergänzt den schreibgeschützten JSON-Export von Wissen samt Quellen (`Backend/tools/wissen_export.py`). Aufruf: `python3 Backend/tools/wissen_export.py`. Die Datei wird standardmäßig in `~/Downloads/atlas-wissen-export.json` abgelegt. Der Export erzeugt **kein** zusätzliches Wissen und trainiert **keine** Modellgewichte. Er eignet sich für Datensicherung, externe Prüfung und spätere Migration.

## Lokal geprüfte Tests
- 2 neue Exporttests erfolgreich.
- 3 Tests zur Wissensskalierung erfolgreich.
- 11 Tests zum Lernen erfolgreich.

## Nicht bestätigt
- Installation/Build auf macOS, tatsächliche Audioqualität, reale Internetrecherche, LLM-Leistung, Ende-zu-Ende-App-Verhalten.
- Keine Behauptung einer perfekten KI oder autonomer Modellverbesserung.

## Für einen stabilen Release noch nötig
- Reale macOS-Tests mit Hardware, Mikrofon und Ollama.
- Verifizierte End-to-End-Recherche, Sicherheitsprüfung fremder Webseiten und Qualitätsbenchmark für Antworten.
- Evaluation der Stimme im Livebetrieb, einschließlich Unterbrechung und Sprachwechsel.
