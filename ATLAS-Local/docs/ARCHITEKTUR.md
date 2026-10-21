# Architektur ATLAS Local 0.4

```
 ┌──────────────── ATLAS.app (SwiftUI, Sandbox) ────────────────┐
 │ Wake-Word „Atlas“ + Spracherkennung (Apple, auf dem Gerät)    │
 │ ConversationEngine ── Sprachausgabe (beste Apple-Stimme)      │
 │ AtlasToolbox: Kalender, Erinnerungen, Kontakte, Mail, Spotify,│
 │   Timer, Kurzbefehle, Gedächtnis (SwiftData), Bestätigungen   │
 │ LocalAtlasProvider ── NDJSON-Stream ──┐                       │
 └───────────────────────────────────────┼───────────────────────┘
                     127.0.0.1:8765, Token │ ▲ tool_request / result
 ┌──────────────── Backend (Python, LaunchAgent) ───────────────┐
 │ server.py   HTTP, Token/Origin-Schutz, Streaming              │
 │ agent.py    Router → Chat | Agent | Plan                      │
 │             Planner · Executor · Bridge · Validierung · Bericht│
 │ tools.py    Dateien, PDF/Excel, Apps, Web, System, Terminal,  │
 │             Bildschirmfoto, Rechnen  (sicher/bestätigen/gesperrt)│
 │ memory.py   Erinnerungen auswählen (Embeddings | lexikalisch),│
 │             Gesprächszusammenfassungen (SQLite-Cache)          │
 │ llm.py      Ollama: chat+tools, stream, embed, Modellauswahl   │
 └──────────────────────────────────┬───────────────────────────┘
                                    │ 127.0.0.1:11434
                          Ollama: qwen3:4b · qwen3:8b · nomic-embed-text
```

## Bausteine (wie im Projektauftrag gefordert)

| Baustein | Umsetzung |
|---|---|
| Conversation Manager | `Agent.context`: System-Persona, passende Erinnerungen, Gesprächsverlauf im Zeichenbudget, Zusammenfassung älterer Beiträge |
| Model Router | `llm.route`: direkt / chat / agent / plan; `Ollama.pick`: Modell nach Aufgabe und Installation |
| Tool-Calling | Ollama `tools`; zusätzlich Erkennung von `<tool_call>`-Text kleiner Modelle |
| Agent Planner | Planmodus: JSON-Plan mit höchstens 6 Schritten, wird angezeigt und dem Modell vorgegeben |
| Task Executor | `Agent.agent_loop`: Runden, Zeitlimit, Abbruch, höchstens 4 Werkzeuge pro Runde |
| Memory Manager | `memory.MemoryIndex` (Auswahl, Duplikate, veraltete Einträge, Zusammenfassungen) + native Werkzeuge `remember`, `forget`, `list_memories` |
| Ergebnisvalidierung | Jedes Werkzeug prüft sich selbst (`verified`); `Agent.validate` korrigiert unbelegte Erfolgsbehauptungen |
| Fehlerbehandlung | Werkzeugfehler gehen ans Modell zurück; derselbe fehlerhafte Aufruf wird höchstens zweimal versucht |
| Sicherheitskontrollen | Stufen pro Aufruf (`risk_for`), Pfadregeln, Terminal nur mit fester Programmliste ohne Shell (`command_risk`), Bestätigung über die App |

## Protokoll 2 (App ⇄ Backend)

`POST /api/native/agent/stream`, Kopfzeile `X-Atlas-Token`, Inhalt:

```json
{"request_id": "…", "model": "qwen3:4b", "system": "…",
 "history": [{"role": "user", "content": "…"}],
 "memories": ["[Vorliebe] …"], "tools": [{"name": "…", "description": "…", "input_schema": {}}]}
```

Antwort: eine Zeile JSON pro Ereignis.

| Ereignis | Bedeutung |
|---|---|
| `start` | Beginn |
| `status {label}` | Was ATLAS gerade tut |
| `plan {steps}` | Plan einer mehrstufigen Aufgabe |
| `step {tool, label, status: läuft/erledigt/fehlgeschlagen/abgelehnt/gesperrt, verified}` | Fortschritt eines Werkzeugs |
| `tool_request {id, name, input}` | Die App führt ein Werkzeug aus und antwortet mit `POST /api/native/agent/result {id, content, isError}`. `name = "atlas_confirm"` heißt: Bestätigung erfragen, Antwort `approved` oder `denied`. |
| `delta {text}` | Antworttext |
| `report {done, failed, declined, open}` | Abschlussbericht |
| `done {mode, model, metrics}` / `cancelled` / `error {error}` | Ende |

Abbrechen: `POST /api/chat/cancel {request_id}`. Wartet der Agent gerade auf die App, endet er sofort.

## Warum das Backend die Mac-Aktionen ausführt

Die App läuft in der macOS-Sandbox und darf keine beliebigen Dateien öffnen und keine Terminalbefehle ausführen. Der Backend-Dienst läuft als Ihr Benutzer.

macOS schützt trotzdem weiter. Schreibtisch, Dokumente und Bildschirmaufnahme brauchen Ihre Freigabe für „python3“.

## Speicher und Tempo

- Gespräche ohne Aufgabe laufen ohne Werkzeuge im Stream. Das ist am schnellsten.
- Für Aufgaben sieht das Modell nur die passenden Werkzeuggruppen. Weniger Text vor jeder Antwort bedeutet kürzere Rechenzeit.
- Der Denkmodus von Qwen3 ist aus. Es gibt keine hörbaren Rechenschritte.
- Einfache Rechnungen beantwortet ATLAS ganz ohne Modell.

## Lernen und Weiterentwicklung (ab 0.6.0)

Erfahrungsspeicher, Korrekturregeln, Fähigkeiten-Sandbox, Wissensbasis, Verbesserungsmotor, Code-Werkstatt, Freigaben und Lernplaner sind in `docs/LEARNING-UND-EVOLUTION.md` beschrieben.

Die App spricht diese Bausteine über `POST /api/native/learning/<aktion>` an, immer mit dem Sitzungstoken. Aktionen:
- Übersicht: `overview`
- Freigaben und Aufträge: `decide`, `job`, `cancel`, `settings`
- Gelerntes bearbeiten: `rule`, `fact`, `facts`, `delete`, `confirm`
- Rücknahmen: `skill`, `hint/rollback`, `code/rollback`
- Export der Trainingsdaten: `export`

Der Agent bekommt zusätzlich die Werkzeuge `learn_skill` und `learn_topic` sowie alle freigegebenen Fähigkeiten als `skill_<name>`.

