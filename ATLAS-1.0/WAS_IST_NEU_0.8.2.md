# ATLAS 0.8.2 – kostenloser Ausbauschritt

## Tatsächlich umgesetzt

- Dauerhafte SQLite-FTS5-Volltextsuche für bereits gespeicherte Wissensfakten; Datenbestände werden beim Öffnen indexiert. Die bestehende Suche wird bei nicht passender Tokenisierung weiterhin als Rückfalllösung verwendet.
- Einträge werden bei Änderungen und Löschungen automatisch im Index aktualisiert.
- Offline-Wissensaudit `WISSEN_PRUEFEN.command`: Anzahl Fakten/Themen, fehlende URLs, veraltete Abrufe, Widersprüche, Themen mit weniger als drei Fakten und FTS-Verfügbarkeit.
- Bestehende 193 Themenpakete und der Installer aus 0.8.1 bleiben erhalten.
- XTTS-Sprachserver: Markdown-/URL-Bereinigung vor der Aussprache, längere Eingaben begrenzt; Server bindet standardmäßig nur localhost statt alle Netzwerkschnittstellen. Für expliziten LAN-Zugriff kann `ATLAS_VOICE_HOST` gesetzt werden.
- Zusätzliche Offline-Integrationstests für Volltextindex und Audit.

## Wichtige Grenzen

- Kein Training der Modellgewichte. Neue gespeicherte Fakten sind abrufbares Wissen, keine automatische Modellveränderung.
- Die 193 Lernaufträge wurden **nicht** im Internet abgearbeitet. Internet, Ollama und XTTS müssen auf dem Mac laufen; eine vollständige Funktionserprobung dort ist noch erforderlich.
- Eine Indexsuche verbessert Geschwindigkeit bei großer Wissensmenge, nicht die Intelligenz des verwendeten Sprachmodells.
- Der XTTS-Sprachserver existierte bereits. Die Textbereinigung verbessert Aussprache bestimmter Inhalte, garantiert aber keine menschlich klingende Stimme. In der Weboberfläche gibt es weiterhin einen macOS-`say`-Ausgabeweg; Auswahl/Integration von XTTS müssen auf dem Mac geprüft werden.
- Modellqualität, Stabilität und Sprachlatenz auf Apple Silicon wurden hier nicht gemessen.

## Installation

ZIP entpacken, `ATLAS-Local-0.8.0` öffnen, `WISSEN_INSTALLIEREN.command` zum Einreihen der Themen starten. `WISSEN_PRUEFEN.command` erstellt einen Wissensbericht. Neue App-Builds erfolgen weiterhin mit den vorhandenen Mac-/Xcode-Skripten. Bei bestehender Installation vor Aktualisierung Datenbank und App sichern.

## Sicherheit

Die Wissens- und Indexdaten bleiben in der bisherigen lokalen SQLite-Datenbank. Die Sprachserverbindung ist standardmäßig auf `127.0.0.1` beschränkt. Cloudmodelle wurden nicht aktiviert und verursachen keine neuen API-Gebühren.
