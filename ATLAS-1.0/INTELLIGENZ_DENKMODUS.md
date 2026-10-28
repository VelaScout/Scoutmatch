# ATLAS – Meilenstein 1: Allgemeine Intelligenz (Denkmodus)

## Tatsächliche Änderung
- `Backend/atlas/deliberation.py`: zweistufiger lokaler Antwortprozess (Entwurf, kritische Überprüfung, finale Antwort).
- `Backend/atlas/agent.py`: Aktivierung bei explizit anspruchsvollen Fragen; normales Streaming für einfache Gespräche bleibt erhalten.
- Bevorzugt das installierte Aufgabenmodell für den Denkmodus. Kein Cloud-Zugriff und keine zusätzlichen API-Kosten.
- Bei Fehlern wird kein Erfolg behauptet. Abbruchsignal wird berücksichtigt.

## Verifizierte Tests in der Entwicklungsumgebung
- 5 neue Unit-Tests: bestanden.
- 34 bestehende Agententests: bestanden.
- Python-Syntaxkompilierung der geänderten Dateien: bestanden.

## Einschränkungen
- **Kein** realer Ollama-Modelltest auf dem Mac durchgeführt.
- Zwei Modellaufrufe benötigen mehr Zeit und beweisen **nicht**, dass die Antwort besser ist.
- Die Qualität kann bei einem schwachen Modell auch nach Überprüfung falsch bleiben.
- Gleichwertigkeit mit ChatGPT oder Claude **nicht erreicht oder belegt**.

## Weiterer Messschritt
Auf dem Mac mit dem vorhandenen `INTELLIGENZ_BENCHMARK.command` echte lokale Modelltests ausführen und zusätzlich dieselben komplexen Fragen einmal mit und einmal ohne Denkmodus vergleichen.
