# Testbericht ATLAS Local 0.2.3

## Hier tatsächlich ausgeführt

82 Python-Tests erfolgreich, einschließlich 16 zusätzlicher Tests für Befehle/Rechnen. Viele Tests enthalten mehrere Eingabevarianten. Das Python-Rohprotokoll steht in TESTRESULTS-0.2.3.txt.

Geprüft wurden: Dezimalrechnung und Operatorreihenfolge, Negativwerte, Rundungskennzeichnung, begrenzte Ausdrucksgröße/-tiefe, Ablehnung von Codeausführung und Potenzen, Kontextpräfix, einfache Fragen versus Erklärungswunsch, alle erlaubten Öffnen-Ziele, Reihenfolge/Deduplizierung/maximal drei Ziele, Negation und eingeschleuste Befehle, explizite Erinnerungen, Token/Origin, keine Modellanfrage für einfache Rechnungen, keine Aktion beim bloßen Planen und zwei tatsächlich bestätigte Aufrufe des simulierten Betriebssystems. Die bestehenden 66 Tests für Chat, Fehler, Daten, Abbruch, Audio-Codecs und Diagnose wurden ebenfalls wiederholt.

Neun Chromium-Prüfgruppen: Start/Health, Streaming/Timing, Gedächtnis/HTML als Text, Abbruch, Verlaufs-/Sprachzustand, bestätigte Aktionen, simuliertes Mikrofon, Autosenden/Vorlesen, keine JavaScript-Laufzeitfehler. Das ist die Weboberfläche, kein SwiftUI-Test. Modell, STT und Mac-Aktionen sind simuliert; MP4/AAC und WebM/Opus wurden mit echtem ffmpeg dekodiert.

Python-Kompilierung und Bash-Syntax werden geprüft. Keine gemessene M4-Latenz und kein echter Hörtest hier.

## Automatisch im Mac-Update vorbereitet, hier nicht ausgeführt

- Swift-Provider: Health, echte URLSession-Streamingverarbeitung gegen isolierten lokalen Testserver, unvollständige Antwort, Serverfehler, Längenlimit, Weiterleitungsblockade, Modellliste, direkter Rechnerpfad.
- Neu: Bestätigungspayload mit approved=true; zwei Werkzeuge nacheinander; Stopp nach Ablehnung; Werkzeugliste; keine Werkzeuge in einem Aufruf ohne Ausführer.
- Sprachtext: kurze Zeilen werden zusammengehalten; Doppelpunkt zerlegt keinen Satz; vollständige Satzgrenze; Resttext; Markdownbereinigung; Englischsegment.
- Vollständiger Xcode-Build und Prüfung der lokalen Signatur.
- Nach Austausch des Backends: Anfrage an den echten Dienst ergibt 391 für 17*23.

## Was auf dem Mac offen bleibt

Die native Ausgabe, Spracheingabe und die neuen SwiftData-Schreibwege lassen sich hier unter Linux nicht ausführen. Hörqualität, Unterbrechen während der Ausgabe, deutsches/englisches Sprachpaket, Mikrofonfreigaben, Stop/Neustart, Erinnerungen über App-Neustarts, echtes Öffnen der Apps/Ordner sowie Hologramm müssen auf macOS geprüft werden. Ein bestandener Build beweist diese Laufzeiteigenschaften nicht.

Der mitgelieferte MAC_TESTEN.command misst echte Qwen-Antworten und eine say→Whisper-Dateirunde. Er ersetzt keine inhaltliche Bewertung, keinen nativen Hörtest und keinen Mikrofontest. Einfache Soll-Prüfungen sind bei Rechnen/Anweisung/Kontext enthalten; freie Antworten bleiben manuell zu bewerten.

## Fehler während der Entwicklung

Der Test der zweistufigen Aktion hat zunächst einen fehlenden approved=true-Wert aufgedeckt. Der Swift-Aufruf wurde korrigiert und ein Mac-Vertragstest ergänzt. Alle 82 Python-Tests sind danach bestanden. Die tatsächliche Swift-Ausführung dieses neuen Tests bleibt bis zum Mac-Update offen.

## Grenzen der Autonomie

Die Aufgabenfolge ist ein begrenzter Parser für ausdrückliche Befehle, kein frei planender Agent. Öffnen muss bestätigt werden, und bei Fehler/Abbruch wird die Folge beendet. Keine beliebige Dateiveränderung, kein Shellzugriff des Sprachmodells, keine Mail-/Kalenderänderungen. Das Modell wird nicht durch diese Tests auf ChatGPT-Niveau validiert.
