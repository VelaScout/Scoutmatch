# Offene Punkte und bekannte Grenzen – ATLAS Local 0.4.1

## Noch nicht auf echter Hardware bewiesen

| Punkt | Status | So wird es geprüft |
|---|---|---|
| Xcode-Build von 0.4.1 | nur Syntaxprüfung | `AKTUALISIEREN.command` baut und stoppt bei Fehlern, bevor etwas ersetzt wird. Bei Fehlern `build/BUILD-LOG.txt` schicken. |
| Qualität und Tempo mit echtem Qwen | erster Diagnose-Ausschnitt: zu lange Antworten (Denk-Variante) → in 0.4.1 behoben, Wirkung noch nicht gemessen | `MAC_TESTEN.command` → `build/MAC-ECHTE-MODELLTESTS.json` |
| Neue Statuszeile und Aufgabenfeld in der App | ungesehen | nach dem Update ansehen |
| RAM-Verbrauch mit qwen3:4b und qwen3:8b gleichzeitig | geschätzt ca. 10 GB | Aktivitätsanzeige bzw. `ollama ps` während `MAC_TESTEN.command` |

## Bekannte Grenzen

1. **Intelligenz:** Qwen3 8B ist deutlich schwächer als ChatGPT oder Claude. Mehrstufige Aufgaben mit vielen Schritten können scheitern. ATLAS meldet das dann ehrlich (offene Schritte im Bericht).
2. **Stimme:** Es spricht die beste installierte Apple-Stimme, am besten eine Premium-Stimme laden.
   - Eine neuronale lokale Stimme (Piper, XTTS, Chatterbox) ist nicht eingebaut. Ohne Hörtest auf dem Mac wäre das Risiko für Knacken und Abhacken zu hoch.
   - Englische Begriffe in deutschen Sätzen spricht die deutsche Stimme deutsch aus. Nur ausdrücklich markierte Abschnitte wechseln die Stimme.
3. **Spracherkennung:** in der eingestellten Sprache, nicht Deutsch und Englisch gleichzeitig.
4. **Bildschirm verstehen:** nur mit zusätzlichem Bildmodell (`ollama pull gemma3:4b`, ca. 3 GB RAM zusätzlich während der Nutzung).
5. **Fotos und PDF-Anhänge im Chat:** Das Textmodell sieht sie nicht direkt. PDFs in einen Ordner legen und per Namen ansprechen.
6. **Browser:** öffnen, suchen, Seiten und die vordere Safari-Seite lesen. Keine Klick-Automatisierung auf Webseiten, keine Formulare und keine Käufe – bewusst.
7. **Terminal:** nur Programme der festen Liste. Werkzeuge, die dort fehlen (z. B. `docker`), lehnt ATLAS ab. Erweiterbar nur im Code (`tools.py`), nicht durch das Modell.
8. **Proaktive Hilfe:** nur Morgen- und Abendübersicht per Mitteilung (aus 0.2). Keine Hintergrundbeobachtung.
9. **Lernen:** Gedächtnis, Korrekturen und Vorlieben werden gespeichert und genutzt. Die Modellgewichte werden nicht trainiert. Eine lokale Feinabstimmung (z. B. LoRA mit MLX) wäre ein eigenes, späteres Modul.
10. **App-Store-Fähigkeit:** nein. Das Backend läuft als Benutzerdienst außerhalb der Sandbox.

## Nächste sinnvolle Schritte (nach Auswertung der Mac-Tests)

1. Die Ergebnisse von `MAC-ECHTE-MODELLTESTS.json` auswerten. Prompts und Werkzeugbeschreibungen dort nachschärfen, wo Qwen scheitert.
2. Optional: Piper- oder XTTS-Dienst als Stimme, mit Rückfall auf Apple. Erst wenn ein Hörtest möglich ist.
3. Optional: MLX als zweite Laufzeit in `llm.py`, falls die Messung zeigt, dass Ollama der Engpass ist.
4. Englische Aussprache in deutschen Sätzen: automatisch markieren, mit Hörtest.
