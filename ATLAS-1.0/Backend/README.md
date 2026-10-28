# Atlas 0.2.1 – Streaming, Sprache und Diagnose

Diese Version entwickelt die vorhandenen Atlas-0.2-Dateien weiter. Sie nutzt ausschließlich lokale Qwen3-Modelle über Ollama sowie lokale Spracherkennung mit whisper.cpp. Keine OpenAI-/Claude-API und keine API-Schlüssel. Die bestehende Datenbank `~/.atlas-ai/atlas.db` bleibt kompatibel.

## Update auf deinem Mac

1. Das laufende Atlas im Terminal mit **Ctrl+C** beenden. Vor dem Upgrade bei beendetem Atlas den Ordner `~/.atlas-ai` sichern, wenn der Verlauf wichtig ist.
2. Dieses Paket entpacken. Der enthaltene Projektordner heißt **atlas-0.2.1**.
3. Im Terminal `cd ` mit Leerzeichen tippen, den Ordner atlas-0.2.1 aus dem Finder hineinziehen und Enter drücken.
4. Bei bereits erfolgreicher Installation von Atlas 0.2:

```bash
bash test_atlas.command && bash start_atlas.command
```

Fehlen Werkzeuge, zuerst `bash install_atlas.command` ausführen. Homebrew wird vorausgesetzt. Der Installer installiert fehlende Python-/Ollama-/ffmpeg-/whisper-cpp-Pakete und lädt Modelle aus deren Quellen. Er stellt den Whisper-Pfad jetzt korrekt ein. Die ZIP enthält keine Modellgewichte.

Das Startskript prüft die Chat-Voraussetzungen und öffnet die Oberfläche erst, wenn der Server antwortet. Ein belegter Port wird gemeldet. Sprache ist optional; fehlt sie, bleibt der Textchat nutzbar. Terminal geöffnet lassen. Beenden mit Ctrl+C.

Die alte Version bleibt in ihrem bisherigen Ordner. Zum Zurückwechseln erst die neue Version beenden und die alte starten; nicht beide gleichzeitig auf dieselbe Datenbank zugreifen lassen.

## Was geändert wurde

- Antworten erscheinen Stück für Stück. Das reduziert die Zeit bis zur ersten sichtbaren Ausgabe; es ist keine Garantie, dass die komplette Modellberechnung schneller ist.
- Stopptaste und klare Anzeige unvollständiger Antworten. Abgebrochene Antworten werden nicht im Verlauf gespeichert. Das Backend beendet die laufende Anfrage beim nächsten Modellpaket oder spätestens beim Lese-Timeout; das ist kein sofortiges Stoppen des gesamten Ollama-Prozesses.
- Zeitmessungen: erste sichtbare Wörter, gesamte Antwortdauer, Modellladen und Tokenrate. Kurze Antworten, begrenzter Kontext und 15 Minuten Modellhaltezeit sind voreingestellt.
- Natürlichere, aufgabenbezogene Systemanweisung. Das ist keine nachgewiesene Steigerung der Faktenqualität. Qwen3 4B kann weiterhin falsch antworten.
- Modellmenü für Qwen3 4B/8B; nicht installierte Varianten sind deaktiviert.
- Deutsch, Englisch oder automatische Spracherkennung. Deutsch ist der Standard, um eine zusätzliche Spracherkennung zu vermeiden. Für durchgehend englische Aufnahmen Englisch wählen.
- Audiodateien werden ausdrücklich in 16-kHz-Mono-PCM umgewandelt. Der Text wird aus einer Whisper-Ausgabedatei gelesen, statt Konsolenausgaben als Sprache zu behandeln.
- Sehr kurze/stille Aufnahmen starten keine Whisper-Erkennung. Leise Sprache kann dadurch abgewiesen werden; dann näher am Mikrofon sprechen.
- Mikrofonfreigabe wird nach dem Stoppen beendet, Aufnahme auf 30 Sekunden begrenzt, parallele Transkription blockiert.
- Optional „Aufnahme direkt senden“ und „Antworten automatisch vorlesen“. Standardmäßig bleibt die Kontrolle beim Nutzer.
- Vor einer Aufnahme stoppt Atlas seine eigene Sprachausgabe. Eine neue Sprachausgabe ersetzt die vorherige.
- Sitzungs-/Origin-Schutz bleibt erhalten. Nur bestätigte, vorgegebene Apps/Ordner werden geöffnet.

## Größeres Modell ausprobieren

```bash
bash enable_quality.command
```

Das lädt `qwen3:8b` zusätzlich herunter. Danach „Verbindung prüfen“ in Atlas anklicken und 8B auswählen. Das größere Modell kann andere/bessere Antworten liefern, benötigt aber mehr Arbeitsspeicher und kann langsamer sein. Für M4/16 GB sind 4096 Kontexttokens voreingestellt. Tatsächlicher Speicherverbrauch und Qualität müssen auf deinem Gerät geprüft werden. Zuerst nur Atlas/Ollama und den Browser für den Vergleich geöffnet halten.

## Echte Diagnose für deinen Mac

Atlas zuerst beenden, dann im Projektordner:

```bash
bash diagnose_atlas.command
```

Das Skript führt aus:

1. Automatisierte Programmtests mit temporärer Datenbank.
2. Prüfung der installierten Werkzeuge und Modelle.
3. Sechs echte lokale Testanfragen pro installiertem unterstütztem Modell (4B und optional 8B).
4. Erfassung der Antworten, Zeit bis zur ersten Ausgabe, Ladezeit und Tokenrate.
5. Synthetischer Audiotest: macOS `say` erzeugt eine Audiodatei; ffmpeg und Whisper verarbeiten diese wirklich. Das ist **kein Test deines Mikrofons und keine hörbare Stimmbewertung**.
6. Speichern einer Datei `Atlas-Diagnose-DATUM-UHRZEIT.json` auf dem Schreibtisch.

Die Fragen sind fest vorgegeben; vorhandene Chats und Erinnerungen werden dafür weder gelesen noch verändert. Es gibt drei enge automatische Prüfungen (Rechnen, exakte Anweisung, Testname). Weitere Antworten müssen von einem Menschen beurteilt werden. Der Bericht wird auch bei Modell-/Audiofehlern geschrieben, sofern das Skript bis zur Diagnose gelangt. Fehler in den vorausgehenden Programmtests stoppen das Skript vorher.

Schicke die JSON-Datei zur Auswertung hierher. Ein bestandenes kleines Benchmark-Set garantiert keine allgemein korrekten Antworten.

## Deine bestehende Atlas-App

Sie ist in diesem Paket noch **nicht eingebunden**, da ihre Projektdateien fehlen. Für die Zusammenführung wird ihr Quellcode gebraucht (z.B. der Electron-/JavaScript-/Python-/Xcode-Projektordner). Eine vorhandene `.app` allein enthält nicht unbedingt die bearbeitbaren Quellen. Ein Screenshot kann zunächst bei der Einordnung helfen.

Projektordner als ZIP bereitstellen, ohne `.env`, API-Schlüssel, `node_modules`, `.venv` oder große Modellgewichte. Die Schnittstellen und der geplante gemeinsame lokale Backend-Betrieb sind in APP-INTEGRATION.md beschrieben. Es wurde keine neue Hülle als vermeintliche Integration der unbekannten App ausgegeben.

## Grenzen und noch offene Prüfungen

- Kein Wake-Word und keine dauerhafte Hintergrundaufnahme.
- Kein Zugriff auf Bildschirm oder Dateien, keine freien Terminalbefehle und keine Websuche.
- Die Sprachausgabe nutzt weiterhin macOS `say`. Keine ChatGPT-Stimme und keine verlässliche automatische Aussprache gemischtsprachiger Sätze.
- Keine signierte/notarisierte `.app` oder DMG. Die eigenen Starter können über Terminal ausgeführt werden.
- Safari, physisches Mikrofon/Lautsprecher, echte App-/Ordneröffnung, Sprachqualität und M4-Leistung erfordern Tests auf dem Mac.
- Der Verlauf ist lokal, aber nicht verschlüsselt. Zugriffsschutz verhindert nicht den Zugriff anderer Programme unter demselben Benutzerkonto. Keine Portweiterleitung einrichten.

## Entwicklerprüfungen

```bash
python3 -W error::ResourceWarning -m unittest discover -s tests -v
```

Die Browser-Suite `tests/browser_test.cjs` benötigt Node, Playwright und dessen Chromium. Sie nutzt synthetische Modell-/Audio-/OS-Antworten. Sie ist keine Produktionsanwendung. Status der hier tatsächlich ausgeführten Tests: TESTBERICHT.md.

## Offizielle technische Grundlagen

- Ollama Chat/Streaming: https://docs.ollama.com/api/chat
- Kontext, Modelllaufzeit und GPU-Prüfung: https://docs.ollama.com/faq
- Qwen3: https://ollama.com/library/qwen3
- whisper.cpp CLI: https://github.com/ggml-org/whisper.cpp/tree/master/examples/cli
