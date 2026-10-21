# Studie: Fine-Tuning (LoRA/QLoRA) auf dem MacBook M4 mit 16 GB

Stand: 21.10.2026.

**Ergebnis vorweg:** Jetzt nicht trainieren. Erst Erfahrungen, Regeln, Werkzeuge und Wissensabruf ausschöpfen (das ist umgesetzt). Ein Training lohnt sich erst, wenn genug geprüfte Beispiele und ein fester Bewertungssatz vorliegen. Bis dahin trainiert ATLAS nichts automatisch.

## 1. Technisch möglich?

Ja, für kleine Modelle:

- **Werkzeug:** Apples MLX mit `mlx-lm`. Das Paket trainiert LoRA-Adapter auf Apple Silicon, auch auf quantisierten Modellen (QLoRA).
- **Qwen3-4B (Instruct):**
  - 4-Bit-Gewichte brauchen rund 2,5 GB.
  - Mit kleiner Batchgröße (1–2) und Sequenzen bis etwa 2048 Tokens passt ein LoRA-Training in 16 GB gemeinsamen Speicher.
  - Während des Trainings ist der Mac stark ausgelastet; ATLAS sollte so lange pausieren.
- **Qwen3-8B:** auf 16 GB knapp. Nur mit 4 Bit, kurzen Sequenzen und geschlossenen Programmen; nicht empfohlen.
- **Dauer:** Schätzung (nicht gemessen): einige hundert Beispiele in etwa 30–120 Minuten. Gemessen wird erst auf Ihrem Mac.
- **Einbindung:** Den Adapter mit `mlx_lm.fuse` mit dem Modell verschmelzen, in GGUF umwandeln und als eigenes Ollama-Modell anlegen, z. B. `atlas-qwen3-4b-v1`.
  - Ollama kann Adapter laut Dokumentation auch per `ADAPTER` im Modelfile laden. Ob das für Qwen3-Adapter aus MLX funktioniert, ist ungeprüft.

## 2. Was es bringen würde – und was nicht

| Bringt es | Bringt es nicht |
|---|---|
| Stil und Format (kurz, Deutsch, Anrede) | Neues Faktenwissen (dafür: Wissensbasis mit Quellen) |
| Zuverlässigere Werkzeugaufrufe bei Ihren typischen Aufgaben | Mehr allgemeine Intelligenz |
| Weniger Nachfassen bei bekannten Abläufen | Sicherheit (Regeln bleiben im Code, nicht im Modell) |

Vieles davon leisten schon Regeln, bewährte Abläufe und Werkzeugbeschreibungen. Diese sind sofort wirksam, transparent und rücksetzbar. Ein Training ist nichts davon.

## 3. Daten

- **Quelle:** `Learning & Evolution → Trainingsdaten exportieren`. Der Export enthält nur Aufgaben, die (a) erfolgreich waren, (b) von Werkzeugen bestätigt wurden und (c) nicht korrigiert wurden, dazu Ihre aktiven Regeln.
- **Menge:** Unter einigen hundert geprüften Beispielen ist kein stabiler Nutzen zu erwarten, eher Überanpassung.
- **Qualität:**
  - Duplikate entfernen.
  - Persönliche Daten prüfen: Aufgabentexte werden wörtlich gespeichert und können Persönliches enthalten. Vor einem Training den Export durchsehen und solche Stellen entfernen.
  - Ausgewogen über die Aufgabenarten.
  - 10–20 % zurückhalten für die Bewertung.
- **Werkzeugaufrufe:** Für Werkzeugtraining müssten die tatsächlichen Aufrufe mit Argumenten gespeichert werden. Bisher speichert ATLAS Werkzeugnamen und die Lehre, nicht vollständige Dialoge. Das wäre der erste Ausbauschritt.

## 4. Ablauf, falls Sie es später freigeben

1. **Eignungsprüfung (automatisch, ohne Training):**
   - Genug Beispiele?
   - Genug freier Speicher?
   - Netzteil angeschlossen?
   - Bewertungssatz vorhanden: die 16 Echtaufgaben aus `MAC_TESTEN.command` plus zurückgehaltene Beispiele.
2. **Ihre Freigabe** mit genannter Dauer und Speicherbedarf.
3. **Training:** in einem eigenen Prozess, pausierbar, mit festem Zeitlimit.
4. **Versionierung:** Adapter und Datensatz unter `~/.atlas-ai/adapters/vN` mit Prüfsumme, Datum und Kennzahlen.
5. **Regressionstest:** Echtaufgaben und zurückgehaltene Beispiele, altes gegen neues Modell.
   - Ein neues Modell wird nur vorgeschlagen, wenn es nirgends schlechter ist.
   - Es muss außerdem messbar besser sein.
6. **Ihre zweite Freigabe** zum Umschalten.
7. **Rollback:** Das Basismodell bleibt installiert. Zurück ist ein Eintrag in `~/.atlas-ai/settings.json`, auch in der App.

## 5. Empfehlung und Reihenfolge

1. **Jetzt:** Erfahrungen, Korrekturen, Fähigkeiten und Wissen nutzen (0.6.0).
   - `MAC_TESTEN.command` regelmäßig laufen lassen, damit die Kennzahlen eine verlässliche Grundlage haben.
2. **Danach:** vollständige Werkzeugdialoge bestätigter Aufgaben speichern (Datengrundlage).
3. **Ab etwa 300–500 geprüften Beispielen:**
   - Eignungsprüfung und ein erstes LoRA auf `qwen3:4b-instruct` als Versuch, mit dem Ablauf aus Abschnitt 4.
   - Nur behalten, wenn der Regressionstest es belegt.
