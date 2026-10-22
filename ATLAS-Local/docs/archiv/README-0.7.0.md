# ATLAS Local 0.7.0 – lokaler KI-Agent für den Mac

Native SwiftUI-App mit lokalem Python-Backend und Ollama. Gerechnet wird mit Qwen3 auf Ihrem MacBook M4, ohne Cloud-KI und ohne API-Schlüssel.

Seit 0.3 ist ATLAS ein **Agent**. Er versteht Aufgaben, wählt selbst Werkzeuge, arbeitet sie Schritt für Schritt ab, prüft die Ergebnisse und berichtet ehrlich, was geklappt hat.


## Neu in 0.7.0 (22.10.2026)

- Korrektur für „No usable temporary directory found“ bei Fähigkeits-Tests: eigener temporärer Ordner wird ausdrücklich an den Kindprozess übergeben und nachher entfernt. Kein Freigeben globaler Temp-Ordner nötig.
- Update schreibt `build/UPDATE-PROTOKOLL.txt`, auch wenn die Prüfung abbricht.
- Feste Werkzeuge `create_pdf` und `create_presentation`: echte PDF-/PowerPoint-Dateien, strukturell geprüft, kein stilles Überschreiben. PowerPoint: einfache Textfolien (1–40, maximal 6 Stichpunkte pro Folie). PDF: Text mit Seitenumbrüchen; kein allgemeines Layoutprogramm.
- Kurze Folgeaufträge wie „Mach das bitte“ berücksichtigen die vorherige Nutzeraufgabe bei der Werkzeugauswahl. Heuristische Zuordnung, kein allgemeines Sprachverständnisversprechen.
- Werkzeugaufrufe über dem Rundenlimit werden ausdrücklich als nicht ausgeführt zurückgemeldet. Das Modell kann sie in der nächsten Runde wiederholen.
- Fehlerhafte Modellantworten führen zu verständlichen Modellfehlern.
- Erfahrungslernen zählt unterschiedliche Ziele und abgelehnte Teilschritte nicht mehr als vollständigen Erfolg.
- 18 vorbereitete Echtmodell-Aufgaben, einschließlich PDF und PowerPoint.

**Prüfstatus:** Siehe `TESTBERICHT-0.7.0.md`. Hier auf Linux getestet; kein Xcode-Build, Mikrofon- oder Qwen-Qualitätsnachweis auf Ihrem M4. Diese Version ist eine Weiterentwicklung, keine für jede beliebige Aufgabe fertige Universal-KI.

Beispiele: „Erstelle in Dokumente eine PDF Trainingsplan.pdf mit meinem Wochenplan.“ / „Erstelle eine PowerPoint mit drei Folien über mein Unternehmen.“

Neu in 0.6.0: **Learning & Evolution**. ATLAS lernt aus Erfahrung und aus Ihren Korrekturen, entwickelt fehlende Fähigkeiten selbst und baut Wissen mit Quellen auf. Er verändert sich nie still: Dauerhaftes wird erst nach Ihrer Freigabe aktiv. Einzelheiten stehen in `docs/LEARNING-UND-EVOLUTION.md`.

- **Erfahrungsspeicher:**
  - Zu jeder Aufgabe speichert ATLAS Ziel, Vorgehen, Werkzeuge, Ergebnis, Fehler und Lehre.
  - Bewährte Abläufe und frühere Probleme fließen bei ähnlichen Aufgaben ein.
  - „Bewährt“ ist nur, was Werkzeuge bestätigt haben.
- **Korrekturen werden Regeln:** „Das war nicht richtig. Du solltest die Datei in Dokumente speichern.“
  - ATLAS macht es sofort richtig und merkt es sich, auch über Neustarts.
  - Mit „ab jetzt“ oder „immer“ gilt die Regel überall.
- **Neue Fähigkeiten selbst entwickeln** („Lerne, wie man PowerPoint-Präsentationen erstellt“):
  - Code und Tests entstehen in einer abgeschotteten Sandbox.
  - Fehlgeschlagene Versuche werden verworfen.
  - Aktiv wird die Fähigkeit erst nach Freigabe; jede Version ist rücksetzbar.
- **Wissen aufbauen** („Lerne alles über Unternehmensbewertung“):
  - Jede Aussage hat Quelle und Datum und wird gegen den Quelltext geprüft.
  - Mehrfach belegte Aussagen, Vermutungen, Widersprüche und Lücken sind gekennzeichnet.
- **Verbesserungsmotor:** Aus wiederkehrenden Fehlern werden Vorschläge. Wirkungslose nimmt ATLAS automatisch zurück.
- **Code-Werkstatt:** Eigene Code-Änderungen nur in einer Kopie und nur, wenn alle Tests bestehen. Übernahme nach Freigabe, mit Sicherung und automatischem Rücksetzen.
- **App-Bereich „ATLAS – Learning & Evolution“** (Gehirn-Symbol oben):
  - Freigaben, Kennzahlen mit Verlauf, Regeln, Fähigkeiten, Wissen, Verbesserungen, Erfahrungen und Lernaufträge.
  - Alles lässt sich korrigieren, abschalten und löschen.
- **Lernzyklen im Hintergrund:** anfangs aus, pausierbar, mit Tageslimit, ohne Kosten.
- Kein automatisches Modelltraining. Die Abwägung steht in `docs/FINE-TUNING-STUDIE.md`.

Neu in 0.5.0, gezielt für die 6 fehlgeschlagenen echten Aufgaben (kurze Antwort, Ordner und Datei, Excel, PDF, Sortieren, Fehler beheben):

- **Nachfassen statt Planungstext:** Schreibt das Modell nur Überlegungen (oft Englisch) oder beschreibt ein Werkzeug, statt es aufzurufen, fordert ATLAS einmal ausdrücklich den Werkzeugaufruf an.
  - Englische Überlegungen nach getaner Arbeit werden durch eine kurze deutsche Antwort ersetzt.
  - Ein Werkzeug wird nie aus Text „erraten“.
- **Ein schnelles Modell für alles:** `qwen3:4b-instruct` übernimmt Gespräch und Aufgaben. Das spart Speicher und Ladezeit; `qwen3:8b` ist optional (`ATLAS_WITH_8B=1`).
  - `MAC_TESTEN.command` vergleicht alle installierten Modelle an echten Aufgaben und trägt das beste als Standard ein.
- **Einfachere Werkzeuge für kleine Modelle:**
  - `organize_folder` sortiert einen Ordner in einem Schritt.
  - `replace_in_file` ändert gezielt eine Code-Stelle.
  - `run_tests` erkennt den Testbefehl selbst.
  - `recent_files` findet „die Datei von gestern“.
  - Excel versteht Spalten und Zeilen, Objekte oder CSV-Text.
- **Lernen aus Korrekturen:** Auf „Das war falsch“ prüft ATLAS seine Antwort, korrigiert sie und merkt sich dauerhafte Vorlieben.
- **16 statt 12 echte Testaufgaben.**

Neu in 0.4.1, nach Ihrem ersten Mac-Test:

- Antworten dauerten 9–15 Sekunden, weil `qwen3:4b` bei Ollama vor jeder Antwort ein verstecktes Selbstgespräch schreibt (Denk-Variante).
- **ATLAS nutzt jetzt automatisch die schnelle Variante `qwen3:4b-instruct`.** Das Update lädt sie, etwa 2,5 GB.
- Erkennt er trotzdem ein Denk-Modell, verbirgt er dessen Selbstgespräch.
- Das Update macht am Ende selbst einen Kurztest mit dem echten Modell.
- `MAC_TESTEN.command` endet mit einer Zusammenfassung, die auf einen Bildschirm passt.

Neu in 0.4.0:

- **Terminal ohne freie Shell:** nur Programme aus einer festen Liste, ohne Pipes und Umleitungen.
- **Gedächtnis:** erkennt Duplikate und veraltete Einträge.
- **Oberfläche:** zeigt Dienst, Modell und Mikrofon an und listet jede Werkzeugaktion.
- **Rollback:** `ZURUECKSETZEN.command` dreht ein Update zurück.
- **Mehr Tests:** Ollama aus, kaputte Antworten, kein Internet, Migration, Leistung. Neue Echtmodell-Tests für „Ordner sortieren“ und „Fehler im Projekt beheben“.

## Aktualisieren (vorhandene Installation)

1. ATLAS über die Menüleiste beenden.
2. ZIP entpacken, im Ordner **`AKTUALISIEREN.command`** öffnen. Falls macOS sie sperrt: Systemeinstellungen → Datenschutz & Sicherheit → „Trotzdem öffnen“.
3. Das Update arbeitet von allein:
   - Es baut die App und führt alle automatischen Tests aus.
   - Es richtet eine eigene Python-Umgebung für Excel, PDF, PowerPoint und Word ein.
   - Es lädt das schnelle Modell `qwen3:4b-instruct` (ca. 2,5 GB) und `nomic-embed-text`. Mit `ATLAS_SKIP_MODELS=1` lässt sich das überspringen, mit `ATLAS_WITH_8B=1` kommt `qwen3:8b` dazu.
   - Erst dann ersetzt es App und Dienst. Vorher sichert es Backend, App, Datenbank und Autostart.
4. Danach **`MAC_TESTEN.command`** öffnen. Es prüft mit dem echten Qwen 16 Aufgaben, misst die Antwortzeiten, vergleicht die installierten Modelle und endet mit einer Zusammenfassung auf einem Bildschirm.
5. Falls etwas nicht passt: **`ZURUECKSETZEN.command`** stellt App, Backend und Autostart vor dem Update wieder her.
   - Gespräche und Erinnerungen bleiben dabei unverändert.
   - Die Backend-Datenbank wird nur mit `ATLAS_RESTORE_DATA=1` zurückgesetzt, und dann mit Sicherheitskopie.

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
| „Was steht in der Fehlermeldung auf meinem Bildschirm?“ | Bildschirmfoto (sofort wieder gelöscht) + lokales Bildmodell – **nur wenn eines installiert ist** (`ollama pull gemma3:4b`, ca. 3 GB). |
| „Fasse die Seite zusammen, die ich in Safari offen habe.“ | Liest Adresse und Text der vorderen Safari-Seite (macOS fragt einmal nach „Automation“). |
| „Nein, antworte ab jetzt immer kürzer.“ | Korrektur wird sofort übernommen und als Vorliebe gespeichert. |
| „Lerne, wie man PowerPoint-Präsentationen erstellt.“ | Lernauftrag: ATLAS entwickelt und testet die Fähigkeit im Hintergrund und fragt dann nach Ihrer Freigabe. Bis dahin sagt er ehrlich, dass er es noch nicht kann. |
| „Lerne alles über Unternehmensbewertung.“ | Lernauftrag: Quellen lesen, Aussagen prüfen und mit Quelle speichern. Spätere Fragen dazu beantwortet ATLAS mit Quellenangabe. |
| „What's on my calendar tomorrow?“ | Englische Frage → englische Antwort. |
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
  - Lesende Terminalbefehle aus der Liste (`ls`, `cat`, `grep`, `find`, `git status`, `git diff`, `git log` …)
- **Nur mit Ihrer Bestätigung:**
  - Überschreiben, verschieben, löschen. Löschen heißt immer: in den Papierkorb, also wiederherstellbar.
  - Bauen und Testen: `python3 -m pytest` bzw. `unittest`, Projektskripte, `swift build`/`test`, `xcodebuild`, `npm test`/`run`/`install`, `cargo`, `go`, `make`
  - Git-Änderungen: `add`, `commit`, `push` …
  - Senden von Nachrichten und E-Mails, Anrufe
- **Gesperrt** (keine freie Shell):
  - Alles, was nicht auf der Liste steht, zum Beispiel `rm`, `sudo`, `python -c`, `pip`, `osascript`, `curl`
  - Pipes `|`, Umleitungen `>`, Befehlsketten `;` `&&`, Variablen `$`
  - `git push --force`, `git reset --hard`
  - Pfade außerhalb der freigegebenen Ordner
  - Befehle laufen ohne Shell, die Argumente werden einzeln übergeben.
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
- Bildschirm „sehen“ geht nur mit einem lokalen Bildmodell (Update mit `ATLAS_WITH_VISION=1` oder `ollama pull gemma3:4b`). Ohne Bildmodell sagt ATLAS das und speichert höchstens ein Bildschirmfoto.
- Spracherkennung: Die App hört in der eingestellten Sprache (Deutsch oder Englisch), nicht beides gleichzeitig. Antworten folgen der Sprache Ihrer Frage.
- Stimme: Es spricht die beste installierte Apple-Stimme. Bitte eine **Premium**-Stimme laden, siehe `docs/MODELLE-UND-STIMME.md`. Eine neuronale lokale Stimme ist geplant, aber noch nicht eingebaut.
- Die Swift-App konnte in dieser Entwicklungsumgebung nicht kompiliert werden (kein Mac). Der Build läuft im Update auf Ihrem Mac. Bei einem Fehler stoppt das Update, bevor etwas ersetzt wird; das Protokoll steht in `build/BUILD-LOG.txt`.

## Oberfläche

- **Statuszeile oben:**
  - Dienst: „Lokal bereit“, „Ollama fehlt“ oder „Dienst aus“
  - Aktives Modell, etwa „qwen3:4b · Aufgaben 8b“
  - Mikrofon: „Wartet auf ‚Atlas‘“, „Hört zu“ oder „Mikrofon aus“
- **Aufgabenfeld unten:** jede Werkzeugaktion mit Status (läuft, erledigt, fehlgeschlagen)
- **Nicht geändert:** Gesprächsverlauf und Einstellungen über die Knöpfe oben rechts; der blaue Kern in der Mitte (Darstellung „Schlicht“, Hologramm optional)

## Dokumente

- `TESTBERICHT.md`: was getestet wurde, was simuliert war und was nur auf dem Mac geprüft werden kann.
- `OFFENE-PUNKTE.md`: bekannte Grenzen und nächste Schritte.
- `docs/ARCHITEKTUR.md`: Aufbau, Agenten-Ablauf, Protokoll.
- `docs/MODELLE-UND-STIMME.md`: Modellvergleich für M4/16 GB, Laufzeiten, Stimmen.
- `docs/LEARNING-UND-EVOLUTION.md`: Lernen, Fähigkeiten, Wissen, Verbesserungen, Freigaben, feste Regeln.
- `docs/FINE-TUNING-STUDIE.md`: LoRA/QLoRA auf dem M4 – möglich, aber noch nicht sinnvoll, mit Begründung.

## Daten

- Gesprächsverlauf und Gedächtnis der App bleiben in der App (SwiftData). Die Bundle-ID ist unverändert.
- Backend-Daten liegen unter `~/.atlas-ai`: Zwischenspeicher der Gedächtnissuche, Erfahrungen, Regeln, Wissen und Freigaben (`atlas.db`), selbst entwickelte Fähigkeiten (`skills/`) und Sicherungen der Code-Werkstatt (`werkstatt/`).
- Protokolle: `~/Library/Logs/AtlasLocal`.
- Sicherungen jedes Updates: `~/Library/Application Support/AtlasLocal/*-backup-*`. Zurück zur alten Version: den Backup-Ordner wieder umbenennen.
