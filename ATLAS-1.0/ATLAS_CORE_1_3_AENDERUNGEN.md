# ATLAS Core 1.3 – Änderungen und Grenzen

## Umgesetzt im Quellcode
- Dialog-Prompt: kurze gesprochene Antworten, Anschlussfragen und Unterbrechungen im Kontext berücksichtigen.
- System-Prompt: keine unzutreffende pauschale Behauptung, sämtliche Dienste liefen lokal; nur tatsächlich aktivierte Funktionen beschreiben.
- Gedächtnis: Speichern nur bei verfügbarem Werkzeug und zulässiger Speicherung, keine automatische Speicherung von Geheimnissen.
- Barge-in: „Atlas“ ist kein alleiniger Stopp-Befehl mehr, um versehentliche Unterbrechungen bei Namensnennung zu reduzieren.
- Vorhandene Änderungen aus 1.2 bleiben enthalten.

## Bereits im Bestand vorhandene Komponenten
Lokales Python-Backend, Sprachsteuerung, Speicher-/Lernfunktionen, Werkzeugkatalog, Sicherheits- und Bestätigungsmechanismen, Testdateien. Vorhandener Code bedeutet nicht automatisch funktionierende Integration.

## Nicht nachgewiesen
- macOS-Build, Mikrofon- und Lautsprechertests, zuverlässige Echo-Unterdrückung
- Leistungsgleichstand mit ChatGPT oder Claude
- Funktionsfähige Cloud-Integration: ClaudeProvider.swift ist derzeit nur ein Alias auf den lokalen Provider.
- Die vollständige Backend-Testsuite konnte innerhalb des verfügbaren Testzeitfensters nicht abgeschlossen werden.

## Mac-Test
1. Vorhandene App und Daten sichern.
2. Projekt mit Xcode beziehungsweise vorhandenem Buildskript bauen.
3. Barge-in in den Einstellungen ausdrücklich aktivieren und Echo-Unterdrückung prüfen.
4. 10 Unterbrechungen, 10 Gespräche ohne Unterbrechung, kurze Anschlussfragen und Fehlalarme prüfen.
5. Bei Fehlern Barge-in ausschalten und Logs für die nächste Reparatur sichern.

Keine API-Schlüssel in ZIP-Dateien speichern. Die Siri-Stimme bleibt unverändert.
