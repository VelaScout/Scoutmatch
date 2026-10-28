# ATLAS 1.0.11 – Vollständiger Mac-Selbsttest

1. Entpacke das Gesamtprojekt auf deinem Mac.
2. Starte ATLAS und Ollama wie gewohnt. Ohne laufendes Backend werden Live-Tests als BLOCKED ausgewiesen.
3. Doppelklicke `ATLAS_111_ALLE_TESTS_STARTEN.command`. Falls macOS das Skript blockiert, nutze im Finder Rechtsklick > Öffnen.
4. Öffne den automatisch erzeugten Bericht unter `~/Downloads/ATLAS-GESAMTTEST-.../GESAMTBERICHT.md`.
5. Sende mir `GESAMTBERICHT.md`, `gesamtbericht.json` und bei Fehlern `unit_tests.log`.

Der Test führt selbstständig vorhandene Python-Unit-Tests (max. 180 s) und die 12 automatisch bewertbaren ATLAS-Modellaufgaben aus. Die übrigen 28 Aufgaben sind echte Praxisprüfungen und werden nicht fälschlich als bestanden markiert. Systemfunktionen wie Mikrofon, Stimme, Video, Mac-Steuerung und persistentes Gedächtnis werden nur als vorhanden gewertet, wenn echte Nachweise vorliegen. Die automatischen Live-Tests laufen über das lokale ATLAS-Backend. Ein offener Port allein beweist keine funktionierende Sprach- oder Mac-Steuerung.

**Gleichwertigkeit:** Selbst 40/40 bestandene Aufgaben beweisen nicht allgemeine Gleichwertigkeit mit ChatGPT oder Claude. Für einen belastbaren Vergleich benötigen wir identische Aufgaben, wiederholte Läufe, vergleichbare Werkzeuge und unabhängige Bewertungen. Das Testsystem erhebt ausdrücklich keinen solchen Anspruch.
