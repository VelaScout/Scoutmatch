# Modelle, Laufzeit und Stimme für ATLAS auf MacBook M4 mit 16 GB

Stand: Oktober 2026.

Die Zahlen unten sind **Richtwerte nach meinem Wissensstand und aus öffentlichen Erfahrungsberichten**. Gemessen wurden sie hier nicht, denn diese Arbeitsumgebung hat keinen Mac und darf keine Modelle laden.

Die echten Werte für Ihren Mac misst `MAC_TESTEN.command`. Ergebnis: `build/MAC-ECHTE-MODELLTESTS.json` mit erster Ausgabe, Gesamtzeit und Ergebnisprüfung je Aufgabe.

## 1. Sprachmodelle (lokal, Open Weights)

| Modell (Ollama) | Datei / RAM im Betrieb* | Tempo M4 (Tokens/s)* | Werkzeuge (Tool-Calling) | Deutsch | Eignung |
|---|---|---|---|---|---|
| **qwen3:4b** | 2,5 GB / ca. 4 GB | ca. 40–60 | einfach: gut, mehrstufig: wackelig | gut | **schnelle Antworten** (Standard für Gespräche) |
| **qwen3:8b** | 5,2 GB / ca. 6–7 GB | ca. 20–30 | zuverlässig auch über mehrere Schritte | gut | **Agent** (Standard für Aufgaben) |
| qwen3:14b | 9,3 GB / ca. 10–11 GB | ca. 12–15 | sehr gut | sehr gut | möglich, aber knapp neben anderen Programmen |
| qwen3:30b-a3b (MoE) | ca. 18 GB | – | sehr gut | sehr gut | passt **nicht** in 16 GB |
| gpt-oss:20b | ca. 13–14 GB | – | gut | gut | zu knapp für 16 GB |
| llama3.1:8b | 4,9 GB / ca. 6 GB | ca. 25–30 | gut | mittel | Alternative, Deutsch schwächer |
| gemma3:12b | 8 GB / ca. 9–10 GB | ca. 15 | in Ollama nicht verlässlich | sehr gut | gut zum Reden, ungeeignet als Agent |
| mistral-nemo (12B) | 7 GB / ca. 8–9 GB | ca. 15–20 | gut | gut | Alternative zu qwen3:8b |

\* Bei 4-Bit-Quantisierung (Q4_K_M) und 8 000 Tokens Kontext. Der Speicher wächst mit der Kontextlänge.

**Entscheidung ab 0.5.0** (nach den ersten Messungen auf Ihrem M4):

- `qwen3:4b` lieferte 35 Tokens/s und das erste Wort nach 0,1 s, brauchte aber 9–15 s für Kurzantworten.
  - Es ist bei Ollama inzwischen die Denk-Variante, die ein Selbstgespräch voranstellt.
- Darum übernimmt jetzt **`qwen3:4b-instruct-2507`** Gespräch **und** Aufgaben.
  - Es ist gleich groß und gleich schnell, hat keinen Denkschritt und ruft Werkzeuge zuverlässig auf.
  - Nur ein Modell im Speicher heißt: weniger RAM, kein Nachladen.
- `qwen3:8b` ist optional. `MAC_TESTEN.command` vergleicht die installierten Modelle an 16 echten Aufgaben und trägt das bessere ein (`~/.atlas-ai/settings.json`, `chat_model`/`agent_model`).

**Frühere Entscheidung (0.3.0):**

- **Gespräch:** `qwen3:4b`, im Stream und ohne Werkzeuge. So erscheinen die ersten Wörter am schnellsten.
- **Aufgaben:** `qwen3:8b`, falls installiert, sonst 4b. Der Router entscheidet pro Anfrage.
  - Bei kleinen Modellen sieht das Modell nur die passenden Werkzeuge. Das macht es schneller und treffsicherer.
- **Gedächtnissuche:** `nomic-embed-text`, ca. 270 MB.
  - Ohne dieses Modell arbeitet die Suche lexikalisch, also über gemeinsame Wörter.
- Der „Denkmodus“ von Qwen3 ist aus. Er verlängert jede Antwort um Sekunden und erzeugte früher hörbare Selbstgespräche.
- **Speicher:** Beide Modelle zusammen belegen ca. 10 GB. Ollama gibt ein Modell nach 30 Minuten ohne Nutzung wieder frei.
  - Wird es eng, `ollama stop qwen3:8b` ausführen oder nur 4b behalten. Dann arbeitet der Agent mit 4b, weniger zuverlässig.
- Cloud-Modelle von Ollama (Namen mit `cloud`) sind im Code gesperrt. Alles bleibt auf dem Mac.

## 2. Laufzeitumgebung

| | Ollama (gewählt) | MLX / mlx-lm | LM Studio |
|---|---|---|---|
| Tempo auf Apple Silicon | gut (llama.cpp mit Metal) | oft 10–30 % schneller | wie MLX bzw. llama.cpp |
| Tool-Calling-Schnittstelle | ausgereift (`/api/chat` mit `tools`) | über OpenAI-kompatiblen Server, weniger erprobt | vorhanden |
| Modellverwaltung, Dienst im Hintergrund | einfach (`ollama pull`, brew service) | manuell | App mit Oberfläche |
| Bereits installiert und getestet | ja | nein | nein |

**Empfehlung:** Ollama behalten.

- Die Modellanbindung steckt komplett in `Backend/atlas/llm.py`. Eine MLX-Variante lässt sich später als zweite Klasse mit denselben Methoden ergänzen: `chat`, `stream`, `embed`, `installed`.
- Das lohnt sich erst, wenn die Messung auf Ihrem Mac zeigt, dass die Rechenzeit des Modells der Engpass ist und nicht der Ablauf.

## 3. Stimme (Text-to-Speech)

| System | Lizenz | Deutsch | Natürlichkeit | Tempo auf M4 | Bewertung |
|---|---|---|---|---|---|
| **Apple Premium-/Erweitert-Stimme** | kostenlos, macOS | ja | gut (Premium), mäßig (Standard) | sofort | **jetzt im Einsatz** |
| Piper | MIT | ja (z. B. „thorsten“) | ordentlich, etwas synthetisch | sehr schnell | schnelle lokale Alternative |
| XTTS v2 (Coqui) | nur nicht-kommerziell (CPML) | ja, Stimmklon | sehr natürlich | etwa Echtzeit, spürbare Startzeit | gut für privat; Server liegt in `VoiceServer/` |
| Chatterbox Multilingual | MIT | ja (nach meinem Kenntnisstand) | sehr natürlich | eher langsam | Kandidat für später |
| Kokoro | Apache 2.0 | **nein** | sehr gut | sehr schnell | scheidet für Deutsch aus |

**Sofort umsetzbar, mit der größten Wirkung:**

1. Systemeinstellungen → Bedienungshilfen → Gesprochene Inhalte → Systemstimme → Stimmen verwalten.
2. Unter Deutsch eine Stimme mit dem Zusatz **„Premium“** oder **„Erweitert“** laden.
3. ATLAS wählt automatisch die beste installierte Stimme.

Das ist der Unterschied zwischen „roboterhaft“ und „angenehm“ bei null Wartezeit.

**Nicht umgesetzt in 0.3.0:** eine neuronale lokale Stimme direkt in der App.

- Dafür müsste der Swift-Audiopfad neu verbunden und mit echten Modellen auf dem Mac gehört werden. Beides ist hier nicht möglich.
- Ungeprüfter Audiocode würde genau die früheren Probleme mit Knacken und Abhacken riskieren.
- Nächster Schritt: Piper oder XTTS als optionaler Dienst. ATLAS nutzt ihn, wenn er läuft, und fällt sonst auf die Apple-Stimme zurück.
