# ATLAS Local 0.7.0 — Prüfbericht, 22.10.2026

## Umfang
Weiterentwicklung des gelieferten 0.6.0-M4-Pakets. Das Modell wurde nicht trainiert oder ausgetauscht. Die Änderungen betreffen Aufgabensteuerung, Dokumentwerkzeuge, Erfahrungsbewertung und den Fähigkeitsprozess.

## Behobener Screenshot-Fehler
Der Screenshot zeigte `FileNotFoundError: No usable temporary directory found`, Python 3.15 auf macOS und 2 failures / 3 errors. Im Code hatte der sandbox-exec-Kindprozess keinen TMPDIR-Eintrag. Die Sandbox erlaubte einen anderen temporären Pfad als die Fallback-Pfade des Kindes.

Jetzt legt der Elternprozess einen privaten Temp-Ordner an, erlaubt exakt diesen Pfad und übergibt TMPDIR/TMP/TEMP. Nach Prozessende wird er entfernt. Eine Regression prüft die tatsächliche Umgebung und das Sandbox-Profil; ein weiterer Test startet den echten Kindprozess. Die echte macOS-Sandbox kann hier nicht ausgeführt werden. Die übrigen abgeschnittenen Fehler aus dem Screenshot lassen sich ohne vollständiges Protokoll nicht eindeutig zuordnen.

## Nachweise
- Ausgangsstand: 210 Tests bestanden unter Linux.
- Neuer Stand: **222 Tests bestanden in 57,813 Sekunden**, mit ResourceWarning als Fehler. Vollständige Testnamen in TESTRESULTS-0.7.0.txt.
- 12 neue Regressionen: PDF-Inhalte/Seitenumbrüche, PPTX-Folieninhalte, Überschreibschutz, Pfadgrenzen/Symlinks, fehlerhafte Eingaben, Folgeauftrag bis zur realen PDF-Datei, Themenwechsel, Werkzeugdialog-Konsistenz, ungültige Modellantworten, korrekte Erfahrungsbewertung, macOS-Temp-Profil, echter isolierter Fähigkeitsprozess.
- 37 Python-Dateien per AST geparst; 15 Shell-Skripte mit bash -n geprüft; Info.plist eingelesen.
- Echte Dateierzeugung, SQLite, HTTP-Testserver und Python-Unterprozesse. Sprachmodellentscheidungen werden in den Integrationstests vorgegeben. Diese Tests beweisen keine allgemeine Qwen-Antwortqualität.

## Nicht ausgeführt / nicht nachgewiesen
- Qwen/Ollama: hier nicht installiert. Der echte Kurztest meldet ausdrücklich NICHT AUSGEFÜHRT (ECHTMODELL-STATUS-0.7.0.json).
- Browserprüfung: gestartet, aber kein Chromium verfügbar. BROWSER-TESTRESULTS-0.7.0.txt enthält den Startfehler; kein bestandener Browser-Test.
- Xcode/Swift-Build, Gatekeeper, Codesign, macOS-Sandbox, Python 3.15, Mikrofon, Wake-Word, Unterbrechen, Stimme, Kalender/Mail-Berechtigungen: benötigen Mac-Hardware bzw. macOS.
- PDF/PPTX strukturell und inhaltlich geprüft, nicht visuell in PowerPoint/Preview gerendert. Sehr lange Wörter oder ungewöhnliche Schriftzeichen können zusätzliche Layoutarbeit erfordern.

## Installieren
ATLAS beenden, ZIP entpacken, AKTUALISIEREN.command öffnen. Es baut die App und führt die gesamte Testsuite vor dem Ersetzen des Backends aus. Bei Fehler bleibt der Austausch aus; das Protokoll liegt unter build/UPDATE-PROTOKOLL.txt. Die Python-Umgebung kann dabei bereits aktualisiert worden sein. Danach läuft ein kurzer Echtmodell-Test; MAC_TESTEN.command bietet 18 echte Aufgaben. Daten und Modelle werden vom Update beibehalten; vorhandene Sicherungs- und Rollback-Skripte bleiben enthalten.

## Grenzen
Keine Universal-KI-Garantie. Lokale Modellgröße, Aufgabenkomplexität und Systemberechtigungen begrenzen die Möglichkeiten. Lernen bedeutet hier gespeicherte Erfahrungen, Regeln und getestete Fähigkeiten, nicht laufende Veränderung der Modellgewichte. Feste neue Werkzeuge erstellen Text-PDFs und einfache Textfolien; keine beliebigen professionellen Layouts. Nicht ausgeführte Werkzeugaufrufe müssen in einer weiteren Runde wiederholt werden.
