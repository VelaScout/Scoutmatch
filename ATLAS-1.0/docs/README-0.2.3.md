# ATLAS Local 0.2.3

Lokale Weiterentwicklung der vorhandenen nativen SwiftUI-App für MacBook Pro M4 / 16 GB. Ollama + Qwen3, keine OpenAI-/Claude-/ElevenLabs-API für Chat oder Stimme.

## Vorhandene Installation aktualisieren

1. Atlas über die Menüleiste vollständig beenden.
2. ZIP entpacken. Im neuen Ordner `AKTUALISIEREN.command` öffnen. Bei macOS-Sperre nur diese Datei unter Datenschutz & Sicherheit freigeben.
3. Der Starter führt Swift-Schnittstellen-/Sprachtexttests, den Xcode-Build und 82 Python-Tests aus. Erst danach ersetzt er App und Backend, bewahrt Sicherungskopien und prüft den laufenden lokalen Rechner. Bereits geladene Modelle und Gesprächsdaten werden nicht ersetzt.

Kein Terminalcode muss manuell kopiert werden. Vollständiges Xcode wird wie bei der bisherigen Installation benötigt. Die neue App wird nach erfolgreichem Update geöffnet. Bei einem Buildfehler stoppt das Update; `build/BUILD-LOG.txt` enthält die Meldungen. Der macOS-Build dieser Ausgabe konnte hier unter Linux nicht ausgeführt werden.

Für eine Erstinstallation dient weiterhin `INSTALLIEREN.command`; Homebrew und vollständiges Xcode werden vorausgesetzt. Der Erstinstaller lädt benötigte lokale Modelle und Pakete. App: `~/Applications/ATLAS Local.app`. Backend-Autostart bei Anmeldung: `de.atlas.localbackend`. `DEINSTALLIEREN.command` entfernt nur diesen Autostart, bewahrt Daten/Modelle/Apps.

## Was sich geändert hat

- Direkte macOS-Sprachausgabe statt eigener PCM-Puffer-/Umwandlungskette. Keine erzwungene englische Lautschrift für „Atlas“. Natürliches Standardtempo, keine kurzen Sprachstücke an jedem Zeilenumbruch oder Doppelpunkt. Die beste installierte passende Apple-Stimme wird gewählt; vorhandene normale Stimmenauswahl bleibt erhalten. Das Ergebnis ist keine ChatGPT-Stimme. Hörqualität muss auf dem Mac bewertet werden.
- Einfache Rechnungen werden lokal berechnet und direkt als Ergebnis ausgegeben, ohne Modell-Selbstgespräch. Dezimalwerte nutzen Decimal; periodische Ergebnisse werden als ungefähr gekennzeichnet. Unterstützt: +, −, ×, ÷, Klammern sowie einige deutsche/englische Operatorwörter. Grenzen: kurze Ausdrücke, keine Formeln/Funktionen, kein Prozent-/Finanzrechner.
- Kurzer Antwortstil als Modellvorgabe. Kein belastbarer Nachweis, dass Qwen bei jeder frei formulierten Frage darauf folgt.
- „Merk dir: …“ speichert im nativen Gedächtnis, verhindert identische Doppeleinträge und meldet Speicherfehler. „Was weißt du über mich?“ liest die dortigen Erinnerungen.
- „Öffne Rechner und Notizen“ führt eine feste Folge aus maximal drei freigegebenen Zielen aus, mit Bestätigung pro Ziel. Bei Ablehnung/Fehler endet die Folge. Kein beliebiger Shellcode, keine vom Modell erfundenen Pfade. Die Rückmeldung bestätigt den macOS-Öffnungsauftrag, nicht den visuell nachgeprüften Zustand einer fremden App.
- Standardmäßig schlichte Darstellung. Keine aufwendige Hologramm-Startsequenz und kein erzwungener Vollbildwechsel. Hologramm bleibt optional, seine Darstellung ist hier nicht unter macOS überprüft.
- Einstellungen/Verlauf als sichtbare Knöpfe; Antworten bleiben auch als Text sichtbar.

## Beispiele

- „Was ist 17 mal 23?“ → „391.“
- „Berechne (2+3)*4“ → „20.“
- „Merk dir: Ich möchte kurze Antworten.“
- „Was weißt du über mich?“
- „Öffne Rechner und Notizen“
- „Öffne Downloads“

Öffnen-Ziele: Finder, Rechner/Taschenrechner, Notizen, Kalender, Safari, TextEdit, Downloads, Dokumente, Schreibtisch. Der Befehlsparser erkennt bewusst nur eindeutige direkte Aufträge; freie Umschreibungen können in den normalen Chat fallen und lösen keine Mac-Aktion aus. Eine gemerkte Vorliebe ist Kontext für das Modell und kein garantiert befolgter Systembefehl.

## Tests und tatsächlicher Stand

Hier bestanden: 82 Python-Tests und neun Chromium-Prüfgruppen. KI, Mikrofon und macOS-Aktionen sind in diesen Tests simuliert; Audioformat-Konvertierung mit ffmpeg ist real. `TESTRESULTS-0.2.3.txt` enthält das aktuelle Python-Protokoll, `TESTBERICHT.md` die Grenzen.

Die Bestätigung des vorigen Installers auf deinem Mac belegt die erfolgreiche Installation von 0.2.2. Sie bestätigt keinen Build von 0.2.3. Die vorbereiteten Swift-Tests laufen automatisch im Update auf deinem Mac. `MAC_TESTEN.command` führt zusätzlich echte Ollama-/Whisper-Diagnosen aus und schreibt `build/MAC-TESTS.txt` sowie `build/MAC-DIAGNOSE.json`. Diese Diagnose verwendet Testfragen, kein echtes Mikrofon, und prüft nicht den Klang der nativen Apple-Stimme.

Es gibt weiterhin keine freie, selbstplanende Steuerung beliebiger Mac-Programme, keine Websuche, Bild-/PDF-Analyse und keine lokale KI-Anbindung für Mail/Spotify/Kalenderänderungen. Diese Ausgabe ist ein weiterer ausführbarer Schritt, nicht die vollständige Endvorstellung einer KI wie ChatGPT.

## Daten

Native SwiftData-Daten bleiben im ursprünglichen Sandbox-Container; die Bundle-ID bleibt gleich. Web-Daten bleiben unter `~/.atlas-ai`. In den Einstellungen lassen sich Web-Erinnerungen ins native Gedächtnis übernehmen. Historische Web-Chats werden nicht automatisch übernommen. Protokolle des Dienstes: `~/Library/Logs/AtlasLocal`.

Alte Dateien unter `docs/` und frühere Testberichte beschreiben historische Versionen. Maßgeblich sind diese README und der aktuelle Testbericht.
