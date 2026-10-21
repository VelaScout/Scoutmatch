# ATLAS Local 0.3.0 – lokaler KI-Agent für den Mac

Native SwiftUI-App mit lokalem Python-Backend und Ollama. Gerechnet wird mit Qwen3 auf Ihrem MacBook M4, ohne Cloud-KI und ohne API-Schlüssel.

Neu in 0.3.0: ATLAS ist ein **Agent**. Er versteht Aufgaben, wählt selbst Werkzeuge, arbeitet sie Schritt für Schritt ab, prüft die Ergebnisse und berichtet ehrlich, was geklappt hat.

## Aktualisieren (vorhandene Installation)

1. ATLAS über die Menüleiste beenden.
2. ZIP entpacken, im Ordner **`AKTUALISIEREN.command`** öffnen. Falls macOS sie sperrt: Systemeinstellungen → Datenschutz & Sicherheit → „Trotzdem öffnen“.
3. Das Update arbeitet von allein:
   - Es baut die App und führt alle automatischen Tests aus.
   - Es richtet eine eigene Python-Umgebung für Excel und PDF ein.
   - Es lädt die Modelle `qwen3:8b` (ca. 5 GB) und `nomic-embed-text`. Mit `ATLAS_SKIP_MODELS=1` lässt sich das überspringen.
   - Erst dann ersetzt es App und Dienst. Vorher sichert es Backend, App, Datenbank und Autostart.
4. Danach **`MAC_TESTEN.command`** öffnen. Es prüft mit dem echten Qwen zehn Aufgaben und misst die Antwortzeiten.

Erstinstallation: `INSTALLIEREN.command`. Dafür müssen Homebrew und das vollständige Xcode installiert sein.

## Was ATLAS jetzt kann

| Sagen oder schreiben Sie … | Was passiert |
|---|---|
| „Was ist 17 mal 23?“, „19 Prozent von 2500“ | Exakte Rechnung ohne Modell, sofort. |
| „Erkläre mir kurz Quantencomputer.“ | Schnelle Antwort im Stream (qwen3:4b, ohne Werkzeuge). |
| „Öffne Safari und suche nach den neuesten KI-Entwicklungen.“ | Safari öffnet die Suche; ATLAS liest die Treffer und fasst sie zusammen. |
| „Erstelle auf dem Schreibtisch einen Ordner Ideen und speichere dort ein Dokument mit …“ | Ordner und Datei werden angelegt und nachgeprüft. |
| „Zeig mir meine nächsten Termine.“ | Kalender über die App (EventKit). |
| „Fasse die PDF Bericht in Downloads zusammen.“ | PDF-Text lesen (pypdf), Zusammenfassung. |
| „Erstelle eine Excel-Tabelle für meine Unternehmensfinanzen.“ | Echte .xlsx mit fetter Kopfzeile und Formeln. |
| „Wie viel Speicher ist noch frei?“ | Systeminfos (Speicher, Akku, macOS, RAM). |
| „Aufgabe: Untersuche mein Projekt ~/Code/X auf Fehler, behebe sie und teste es.“ | Plan → Dateien lesen → Tests im Terminal (mit Bestätigung) → Korrektur → Bericht: erledigt, fehlgeschlagen, offen. |
| „Merk dir: Ich möchte kurze Antworten.“ | Native Erinnerung; passende Erinnerungen fließen künftig automatisch in Antworten ein. |

Weitere Werkzeuge der App:

- Erinnerungen und Kontakte
- E-Mail (wenn verbunden)
- Spotify
- Timer und Kurzbefehle
- Zwischenablage
- Einstellungen

## Sicherheit: drei Stufen

- **Sicher, ohne Rückfrage:**
  - Lesen, auflisten, suchen
  - Neue Dateien und Ordner anlegen
  - Programme und Webseiten öffnen
  - Internetsuche, Systeminfos, Rechnen
  - Lesende Terminalbefehle (`ls`, `git status` …)
- **Nur mit Ihrer Bestätigung:**
  - Überschreiben, verschieben, löschen. Löschen heißt immer: in den Papierkorb, also wiederherstellbar.
  - Alle anderen Terminalbefehle
  - Senden von Nachrichten und E-Mails, Anrufe
- **Gesperrt:**
  - `sudo`, Systemschutz (`csrutil`, `spctl`, `tccutil`)
  - Festplatten formatieren, `curl | sh`
  - Schlüsselbund auslesen, Prozesse beenden, Neustart
- **Ordner:** ATLAS arbeitet nur in Ihrem Benutzerordner.
  - `~/Library`, versteckte Ordner und alles außerhalb sind tabu.
  - Weitere Ordner lassen sich in `~/.atlas-ai/settings.json` unter `"allowed_roots"` freigeben.
- **macOS-Schutz bleibt unangetastet:** Beim ersten Zugriff auf Schreibtisch oder Dokumente fragt macOS, ob „python3“ (der Atlas-Dienst) zugreifen darf.
- ATLAS behauptet keine Erfolge, die kein Werkzeug bestätigt hat. Die Antwort wird gegen die tatsächlichen Ergebnisse geprüft und notfalls korrigiert.

## Grenzen (ehrlich)

- Qwen3 8B ist deutlich schwächer als ChatGPT oder Claude.
  - Einfache und mittlere Aufgaben funktionieren.
  - Lange, unklare Aufträge können scheitern. Dann sagt ATLAS das und nennt offene Schritte.
- Fotos und angehängte PDFs sieht das Modell nicht direkt. PDFs in Downloads oder Dokumente legen und per Namen ansprechen.
- Bildschirm: ATLAS kann Bildschirmfotos machen, aber nicht „sehen“. Dafür fehlt ein lokales Bildmodell.
- Stimme: Es spricht die beste installierte Apple-Stimme. Bitte eine **Premium**-Stimme laden, siehe `docs/MODELLE-UND-STIMME.md`. Eine neuronale lokale Stimme ist geplant, aber noch nicht eingebaut.
- Die Swift-App konnte in dieser Entwicklungsumgebung nicht kompiliert werden (kein Mac). Der Build läuft im Update auf Ihrem Mac. Bei einem Fehler stoppt das Update, bevor etwas ersetzt wird; das Protokoll steht in `build/BUILD-LOG.txt`.

## Dokumente

- `TESTBERICHT.md`: was getestet wurde, was simuliert war und was nur auf dem Mac geprüft werden kann.
- `docs/ARCHITEKTUR-0.3.md`: Aufbau, Agenten-Ablauf, Protokoll.
- `docs/MODELLE-UND-STIMME.md`: Modellvergleich für M4/16 GB, Laufzeiten, Stimmen.

## Daten

- Gesprächsverlauf und Gedächtnis der App bleiben in der App (SwiftData). Die Bundle-ID ist unverändert.
- Backend-Daten liegen unter `~/.atlas-ai`, darin unter anderem der Zwischenspeicher für die Gedächtnissuche.
- Protokolle: `~/Library/Logs/AtlasLocal`.
- Sicherungen jedes Updates: `~/Library/Application Support/AtlasLocal/*-backup-*`. Zurück zur alten Version: den Backup-Ordner wieder umbenennen.
