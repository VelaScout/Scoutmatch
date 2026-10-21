# Offene Punkte, Grenzen und nächste Entwicklungsstufe – ATLAS Local 0.5.0

## Noch nicht auf echter Hardware bewiesen

| Punkt | Status | Prüfung |
|---|---|---|
| Xcode-Build 0.5.0 | Syntax geprüft, nicht kompiliert | `AKTUALISIEREN.command` stoppt bei Fehlern, bevor es etwas ersetzt |
| 16 echte Aufgaben mit `qwen3:4b-instruct` | vorbereitet; 0.4.0 bestand 6/12 | `MAC_TESTEN.command` → Zusammenfassung |
| Antwortzeit kurzer Fragen | Ziel unter 2 s; gemessen bisher nur mit der Denk-Variante (9–15 s) | dito |
| Mikrofon, Wake-Word, Unterbrechen, Stimme | ungetestet in 0.5.0 | von Hand |
| Gedächtnis nach Neustart | SwiftData, nicht verändert; nicht neu geprüft | App beenden und neu öffnen, „Was weißt du über mich?“ |

## Bekannte Grenzen

1. **Intelligenz:** Ein 4B-Modell ist weit von ChatGPT oder Claude entfernt.
   - Die Werkzeuge sind deshalb so gebaut, dass ein Aufruf möglichst viel erledigt (Sortieren, Tests, Ersetzen).
   - Freie, lange Aufträge können trotzdem scheitern. ATLAS meldet das dann ehrlich.
2. **Stimme:** Apple-Stimmen. Bitte eine deutsche „Premium“-Stimme laden.
   - Englische Namen in deutschen Sätzen klingen deutsch.
   - Keine neuronale lokale Stimme: Ohne Hörtest auf dem Mac ist das Risiko für Knacken und Abhacken zu hoch.
3. **Spracherkennung:** in einer Sprache (Einstellung), nicht Deutsch und Englisch gleichzeitig. Die Antwortsprache folgt aber automatisch der Frage.
4. **Bildschirm verstehen:** nur mit Bildmodell (`ollama pull gemma3:4b`).
5. **iPhone-Zugriff auf den Mac-Agenten:** nicht umgesetzt. Der Dienst lauscht bewusst nur lokal.
6. **Lernen:** Erinnerungen, Vorlieben und Korrekturen werden gespeichert und genutzt. Die Modellgewichte verändern sich nicht.

## Empfehlung für die nächste Entwicklungsstufe

1. **Messen:**
   1. `AKTUALISIEREN.command`
   2. `MAC_TESTEN.command`
   3. Screenshot der Zusammenfassung schicken
   - Erst diese Zahlen zeigen, welche der 16 Aufgaben das echte Modell noch nicht schafft.
2. **Gezielt nachschärfen:** Für jede Aufgabe, die noch scheitert, gibt es drei Möglichkeiten: Werkzeugbeschreibung, ein höherwertiges Werkzeug oder ein Beispiel im Prompt. Danach wird erneut gemessen.
3. **Stimme:** Piper-Dienst (schnell, MIT-Lizenz, deutsche Stimmen) als optionale Ausgabe mit Rückfall auf Apple, mit Hörtest auf dem Mac.
4. **iPhone:** Zugriff auf den Mac-Agenten über eine gesicherte Verbindung im eigenen WLAN, mit Kopplung per Code.
5. **Später:** Feinabstimmung (LoRA mit MLX) auf Ihren Korrekturen, als eigenes, abschaltbares Modul. Erst sinnvoll, wenn genug Korrekturen gesammelt sind.
