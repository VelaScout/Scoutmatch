# ATLAS: direkte Antwort vs. Selbstprüfung

Neu: `INTELLIGENZ_AB_TESTEN.command` vergleicht dasselbe lokale Ollama-Modell auf denselben 28 Kurzantwort-Aufgaben in zwei Modi: einmal direkt, einmal mit zusätzlicher Selbstprüfung. Der Bericht erfasst Verbesserungen **und Verschlechterungen** sowie die zusätzliche Laufzeit. Eine Selbstprüfung wird **nicht** automatisch als bessere Intelligenz gewertet.

## Grenzen
- Hier lassen sich echte Ollama-Antworten auf dem Nutzer-Mac nicht ausführen.
- Das Benchmark ist zu klein und zu einfach für eine Aussage über ChatGPT-/Claude-Niveau.
- Eine etwaige Verbesserung in diesem Test belegt keine generelle Verbesserung bei offenen Fragen.
- `INTELLIGENZ_AB_TESTEN.command` nutzt standardmäßig `qwen3:8b` (vorher installieren).
