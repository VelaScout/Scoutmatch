# ATLAS Local 0.8.1 – persönlicher Arbeitsassistent für den Mac

ATLAS läuft lokal auf Ihrem MacBook: eine SwiftUI-App, ein Python-Dienst auf Ihrem Mac und ein Open-Weight-Sprachmodell (Qwen3) über Ollama. Ohne Cloud und ohne Konto.

Für schwierige Aufgaben gibt es **optional** ein Cloud-Modell (Claude). Es ist standardmäßig aus und hat eine Kostenanzeige. Vor jeder Übertragung fragt ATLAS Sie und zeigt, welche Daten den Mac verlassen.

**Ehrlich vorweg:** Das lokale 4B-Modell ist deutlich schwächer als große Cloud-Modelle. ATLAS gleicht das teilweise aus:
- Werkzeuge, die viel selbst erledigen und ihr Ergebnis nachprüfen
- ein Journal für Folgeaufträge
- Quellenpflicht bei Recherchen
- Prüfungen, die nicht vom Modell abhängen

Gleichwertig wird es dadurch nicht.

## Anleitung

**Aktualisieren** (vorhandene Installation):
1. ATLAS über die Menüleiste beenden.
2. ZIP entpacken und `AKTUALISIEREN.command` öffnen. Falls macOS es sperrt: Systemeinstellungen → Datenschutz & Sicherheit → „Trotzdem öffnen“.
3. Das Update arbeitet von allein:
   - App bauen
   - Python-Umgebung einrichten
   - **alle** automatischen Tests ausführen
   - Modelle laden
   - Sicherungen anlegen
   - erst dann App und Dienst ersetzen

   Schlägt etwas fehl, bleibt die alte Version. Das Protokoll steht in `build/UPDATE-PROTOKOLL.txt`.
4. Danach `MAC_TESTEN.command` öffnen (ca. 10–20 Minuten). Es prüft:
   - App ⇄ Dienst
   - alle Tests
   - **25 echte Arbeitsaufgaben mit Ihrem Modell**
   - die macOS-Sandbox
   - einen Neustart mit Prüfung des Datenerhalts

   Am Ende steht eine Zusammenfassung auf einem Bildschirm. Bitte schicken Sie mir davon einen Screenshot.
5. Falls etwas nicht passt: `ZURUECKSETZEN.command` stellt den Stand vor dem Update wieder her. Gedächtnis, Erfahrungen, Fähigkeiten und Einstellungen bleiben erhalten.

**Erstinstallation:** `INSTALLIEREN.command`. Dafür braucht es Homebrew und das vollständige Xcode.

**Bedienen:** Sprechen Sie „Atlas …“ oder schreiben Sie unten ins Textfeld. Die Statuszeile zeigt Dienst, Modell und Mikrofon. Darunter steht jede Aktion: läuft, erledigt oder fehlgeschlagen.
- **Stoppen:** Antippen des Kerns oder der Stopp-Knopf.
- **Mikrofon** abschalten: in den Einstellungen.
- **Löschen, Überschreiben, Ändern** vorhandener Dateien, ändernde Terminalbefehle, Senden: nur nach Ihrer Bestätigung.

**Was ATLAS konkret kann**, mit Beispielaufträgen: `FUNKTIONEN.md`.
**Was geprüft wurde und was nicht:** `TESTBERICHT.md`.
**Grenzen und bekannte Fehler:** `OFFENE-PUNKTE.md`.

## Neu in 0.8.1 (nach Ihrem ersten Testlauf mit 0.8.0)

- **ATLAS versteht sich als KI.** Auf „Bist du eine KI?“ antwortet er mit Ja. Früher nannte er sich „lokaler Assistent“, und ein alter Text behauptete fälschlich, er habe kein Internet. Neue Arbeitsaufgabe: identitaet.
- **„Schreibtisch“ und „Dokumente“ in Pfaden** landen jetzt in den echten Ordnern Desktop und Documents. Vorher entstand ein neuer Ordner „Schreibtisch“ (vermutliche Ursache für markdown_liste).
- **Teilaufträge nach einem Fehler:** Scheitert ein Schritt, wird das Modell einmal ausdrücklich aufgefordert, die übrigen Teile trotzdem zu erledigen (teilweise_fehler).
- **Recherche:**
  - mehrere Suchdienste mit Ausweichen (DuckDuckGo, DuckDuckGo Lite, Bing, Wikipedia)
  - Zertifikate über certifi
  - genaue Fehlerursache statt pauschal „nicht erreichbar“
  - Ein blockierter Suchdienst zählt im Test jetzt als FEHLGESCHLAGEN, nur echtes Offline als NICHT AUSGEFÜHRT.
- **Rechenfragen mit Formathinweis** („Was ist 17 mal 23? Antworte nur mit der Zahl.“) werden exakt berechnet statt vom Modell geschätzt (Diagnose „rechnung“).
- **Testbericht nennt den Grund jedes fehlgeschlagenen Schritts**, damit ich Fehler aus Ihrem Testlauf genau zuordnen kann.

## Neu in 0.8.0

- **Dokumente wirklich bearbeiten:**
  - Word-Dokumente (.docx) erstellen und ändern.
  - Excel/CSV ändern.
  - PowerPoint lesen.
  - „Speichere es als PDF“ wandelt Word, Text, Markdown, Excel, CSV und PowerPoint um.
  - Jede Datei wird nach dem Speichern wieder geöffnet und auf Inhalt geprüft. Vor jeder Änderung entsteht eine Sicherung in `~/.atlas-ai/sicherungen`.
- **Folgeaufträge und Wiederaufnahme:**
  - „Speichere es als PDF“ oder „Ändere das“ kennt die zuletzt erzeugte Datei, auch nach einem Neustart.
  - „Mach weiter“ setzt eine abgebrochene Aufgabe fort, ohne Erledigtes zu wiederholen.
- **Keine doppelten Aktionen:** Dieselbe E-Mail, Nachricht, derselbe Termin oder dieselbe Erinnerung wird binnen 24 Stunden nie still ein zweites Mal ausgeführt. ATLAS fragt dann ausdrücklich nach.
- **Recherche mit Quellen:**
  - ATLAS liest mehrere Seiten und nummeriert die Quellen mit Abrufdatum.
  - Adressen, die ATLAS nicht wirklich abgerufen hat, werden automatisch aus der Antwort entfernt.
- **Schutz vor fremden Anweisungen:** Inhalte aus Webseiten, Dateien und E-Mails gelten als Daten. Zeilen wie „Ignoriere alle Anweisungen …“ werden entschärft.
- **Zugangsdaten werden nie gespeichert:** Passwörter, PINs, Schlüssel, Karten- und Kontonummern landen weder im Gedächtnis noch in Erfahrungen oder Protokollen.
- **Optionales Cloud-Modell:**
  - Einstellungen → Cloud-Modell, dann „Cloud: …“ sagen oder schreiben.
  - Standard ist aus.
  - Vor jeder Übertragung kommt eine Rückfrage mit Datenübersicht.
  - Kosten werden aus den tatsächlich gemeldeten Token berechnet; dazu ein Monatslimit.
  - Der Schlüssel liegt im macOS-Schlüsselbund.
- **Sandbox repariert:**
  - Behoben ist der Mac-Fehler „No usable temporary directory found“ (über 0.7.0).
  - Die macOS-Sandbox wird jetzt vor der Nutzung geprüft. Funktioniert sie nicht, läuft keine selbst entwickelte Fähigkeit ohne sie.
- **Mac-Testlauf:**
  - 25 Arbeitsaufgaben mit den Zuständen BESTANDEN / FEHLGESCHLAGEN / NICHT AUSGEFÜHRT.
  - Zeiten getrennt nach erster Rückmeldung und vollständigem Ergebnis.
  - Neustart- und Sandbox-Prüfung.

## Daten und Datenschutz

- **Gesprächsverlauf und Gedächtnis** liegen in der App (SwiftData). Ansehen, bearbeiten, exportieren und löschen: unter „Gedächtnis“. Dort steht auch, ob ein Eintrag von Ihnen stammt oder gelernt wurde, und wann er erstellt und geändert wurde.
- **Daten des Dienstes** liegen in `~/.atlas-ai`:
  - Erfahrungen, Regeln, Wissen, Aufgabenjournal, Freigaben, Cloud-Kostenbuch: `atlas.db`
  - Fähigkeiten: `skills/`
  - Sicherungen geänderter Dokumente: `sicherungen/`
- Updates und Rücksetzen verschieben oder löschen dort nichts.
- **Protokolle:** `~/Library/Logs/AtlasLocal`. Sie enthalten Werkzeugnamen, ok/nicht ok und Fehlermeldungen (diese können Dateipfade nennen), keine Dateiinhalte und keine Zugangsdaten.
- **ATLAS umgeht keine macOS-Schutzmechanismen.** Beim ersten Zugriff auf Schreibtisch oder Dokumente fragt macOS, ob „python3“ (der Atlas-Dienst) zugreifen darf.
