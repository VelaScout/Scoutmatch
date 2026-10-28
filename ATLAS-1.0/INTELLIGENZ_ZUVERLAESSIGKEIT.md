# ATLAS – Zuverlässigkeitsvergleich

Neu: `python3 -m atlas.intelligence_benchmark --runs 2 --output bericht.json` testet jedes lokal installierte Ollama-Modell mehrfach. Gewertet werden Gesamtgenauigkeit und der Anteil der Aufgaben, die in allen Durchläufen richtig waren. Fehlerhafte oder unvollständige Testläufe verhindern die Empfehlung eines Modells.

Prüfung in der Entwicklungsumgebung: 11 gezielte Unit-Tests bestanden. **Keine Ollama-Inferenz auf dem Mac ausgeführt.** Kein Beleg für ChatGPT-ähnliche allgemeine Intelligenz. Die 28 kurzen Aufgaben sind als Benchmark begrenzt.

Hinweis: Ein vollständiger Modellvergleich kann je nach Modell und Hardware lange dauern. Für einen einzelnen Durchlauf `--runs 1` verwenden.
