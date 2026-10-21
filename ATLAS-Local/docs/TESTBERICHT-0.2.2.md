# Testbericht – ATLAS Local 0.2.2

Stand: 21. Oktober 2026. Ausführungsumgebung hier: Linux. Kein Zugriff auf das echte MacBook-Mikrofon, Apple-Frameworks, Metal oder Xcode. „Bestanden“ bezieht sich ausschließlich auf die angegebenen Prüfungen.

| Bereich | Ergebnis | Aussage und Grenze |
|---|---|---|
| Python Backend | 66 Tests bestanden | HTTP-Routen, Eingabeprüfung, Rollen-/Modellprüfung, CSRF-Token, Host/Origin, Streaming, Abbruch, Fehler, Sperren, Gedächtnis, Kontextbudget, Diagnose |
| Neue native Schnittstelle | 12 der 66 Tests bestanden | Sitzungsaufbau, authentifizierte Anfragen, begrenzter nativer Kontext, Isolation vom Web-Verlauf, Fehlerende und Gedächtnisexport |
| Audio-Codecs | In 66 Tests enthalten, bestanden | Echtes ffmpeg dekodiert MP4/AAC und WebM/Opus; kein reales Mikrofon/Whisper-Modell in diesen Tests |
| Web-UI | 9 Chromium-Prüfgruppen bestanden | Start, schrittweise Antworten, Zeitmessungsanzeige, Gedächtnis/HTML als Text, Abbruch, Verlauf löschen, Aktionen bestätigen, Aufnahme/Autosenden/Vorlesen, keine JS-Laufzeitfehler; KI, STT und OS-Aktionen simuliert |
| Shell-Syntax | Bestanden | Installations-, Build-, Mac-Test- und Deinstallationsstarter syntaktisch geprüft; nicht als Mac-Installation ausgeführt |
| Native Swift-App | Ausstehend | Kein SwiftUI-/Xcode-Compiler unter Linux. Quellcode geprüft, kein erfolgreicher Mac-Build behauptet |
| Echte Modellqualität/Latenz | Ausstehend | Kein M4-Benchmark für diese Ausgabe; Mock-Antworten beweisen keine Qwen-Qualität |
| Datenübernahme | Teilweise | Backend-Export automatisiert geprüft. SwiftData-Import, Duplikatbehandlung und Sandbox-Migration auf dem Mac noch zu prüfen |

## Automatisch auf dem Mac

`INSTALLIEREN.command` führt vor dem App-Build einen Swift-Schnittstellentest mit eigenem Python-Testserver auf einem freien lokalen Port aus. Sieben Prüfungen: Gesundheitsstatus, gestreamter Text, unvollständige Antwort, Serverfehler, Längenlimit, blockierte Weiterleitung und Modell-Positivliste. **Diese sieben Prüfungen sind vorbereitet, hier noch nicht gelaufen.** Danach kompiliert Xcode die komplette App und codesign prüft die lokale Signatur. Erst bei Erfolg geht die Installation weiter.

`MAC_TESTEN.command` wiederholt die Swift-/Python-Tests und misst mit echten lokal installierten Qwen-Modellen sechs synthetische Fragen pro Modell: Rechnen, genaue Anweisung, Kontext, Erklärung, ehrliche Fähigkeitsgrenzen und Englisch. Die ersten drei erhalten einfache automatische Soll-Prüfungen; die anderen Antworten sind manuell zu bewerten. Zusätzlich läuft macOS-say → Audiodatei → ffmpeg → Whisper. Diese Runde testet weder das Mikrofon noch den nativen Apple-Speech-Eingang.

## Manuelle Abnahme auf dem Mac

1. Installation/Erststart: App erscheint, Hologramm und Menüleiste funktionieren; keine Schlüsselabfrage. Nach Ab-/Anmelden ist das Backend erreichbar.
2. Text: „Was ist 17 mal 23?“ → 391. Danach Namen einer Testperson nennen und nachfragen. Neues Gespräch starten und prüfen, dass alter Gesprächskontext nicht unbeabsichtigt weitergereicht wird.
3. Streaming: erste sichtbare Antwort und vollständige Antwort beobachten; bei einer längeren Frage Stop drücken. Anschließend neue Frage senden. Keine abgeschnittene Antwort als vollständig im Verlauf.
4. Sprache: Mikrofon-/Spracherkennungsfreigabe, deutsche und englische Sprache, ruhige und normale Umgebung. Ohne lokales Apple-Sprachpaket muss eine klare Meldung erscheinen. Kein endloses Zuhören ohne sichtbaren Status.
5. Ausgabe: deutsche/englische Aussprache, verständliches Tempo, Stop während der Ausgabe, kein Selbstecho. Klang bewerten, nicht nur vorhandenen Ton.
6. Mikrofon aus: Menüleiste und Einstellungen müssen Aufnahme beenden. App schließen/öffnen; Hintergrund- und Wake-Word-Schalter separat prüfen.
7. Gedächtnis: Testeintrag anlegen, App neu starten, Eintrag wiederfinden; Web-Erinnerungen zweimal importieren, ohne Duplikate. Bestehende native Inhalte müssen erhalten bleiben. Sicherung vorher prüfen.
8. Fehler: Ollama stoppen, fehlendes 8B-Modell auswählen, Backend stoppen, danach neu starten. Verständliche Fehler und erneute Nutzbarkeit prüfen.
9. Lokalbetrieb: Nach Modell-/Sprachpaket-Downloads Internet trennen. Textchat und unterstützte lokale Spracheingabe/-ausgabe prüfen.
10. Leistung: 4B und 8B vergleichen, Aktivitätsanzeige/Speicherdruck und `ollama ps` kontrollieren. Für 16 GB ist 4B voreingestellt; 8B nur wählen, wenn Qualität den gemessenen Zeit-/Speicheraufwand rechtfertigt.

## Noch nicht fertig umgesetzt

Die lokalen KI-Werkzeuge für Kalender, E-Mail und Spotify sowie Bild/PDF-Analyse, Websuche und automatisches Lernen fehlen. Diese Ausgabe ist deshalb ein integrierter Entwicklungsstand zur Mac-Abnahme, keine vollständig geprüfte Umsetzung aller Funktionen der früheren Cloud-App. Swift-/Berechtigungsfehler sind vor produktivem Einsatz zu beheben.
