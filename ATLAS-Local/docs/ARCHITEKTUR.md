# Architektur ATLAS 0.9.0

ATLAS ist ein **KI-System mit einem generativen Sprachmodell als Kern**:
- lokal Qwen3 über Ollama
- optional Claude in der Cloud

Um den Kern herum liegen Werkzeuge, Gedächtnis, Lernen und Sicherheitsregeln. Feste Regeln gibt es nur dort, wo Exaktheit oder Sicherheit es verlangen: Rechnen, Passwortschutz, Bestätigungen, Quellenprüfung. Alles andere formuliert das Modell selbst.

```
 ┌─────────────── ATLAS.app (SwiftUI) ────────────────────────────────┐
 │ Wake Word „Atlas“ · Spracherkennung (Apple, auf dem Gerät)          │
 │ ConversationEngine · Sprachausgabe (Apple-Stimmen, Englisch-Segmente)│
 │ AtlasToolbox: Kalender, Erinnerungen, Kontakte, Mail, Kurzbefehle,  │
 │   Gedächtnis (SwiftData), Bestätigungen · Learning & Evolution · Cloud│
 └──────────── LocalAtlasProvider ── NDJSON, 127.0.0.1:8765, Token ────┘
 ┌─────────────── Dienst (Python, LaunchAgent) ───────────────────────┐
 │ server.py ─ agent.py (Router · Planer · Ausführung · Prüfung · Bericht)│
 │ llm.py (Ollama) · cloud.py (Claude, optional)                       │
 │ tools.py · documents.py · research.py · tasks.py · privacy.py       │
 │ memory.py · learning.py · knowledge.py · capabilities.py            │
 │ evolution.py · skills.py · skill_harness.py · sandbox.py ·          │
 │ improvement.py · workshop.py · approvals.py · wissenspakete.py      │
 └──────────────────────────── Ollama 127.0.0.1:11434 ────────────────┘
```

## Die 15 Komponenten aus dem Projektauftrag

| Komponente | Datei(en) | Was sie tut |
|---|---|---|
| **LLM Engine** | `Backend/atlas/llm.py`, `cloud.py`, `models.py` | Lokales Sprachmodell über Ollama, mit Streaming und Werkzeugaufrufen. Erkennt Denk-Modelle und verbirgt deren Selbstgespräch. Optional Claude mit Kostenzählung. `models.py` schlägt passend zum Arbeitsspeicher Modelle vor. |
| **Conversation Manager** | `agent.py` (`context`, `task_context`), App: `ConversationEngine.swift` | Gesprächsverlauf im Zeichenbudget, Zusammenfassung älterer Teile. Folgeaufträge („Mach weiter“, „Speichere es als PDF“) bekommen den Zusammenhang. |
| **Memory Engine** | App: SwiftData `MemoryItem`, `LearningService.swift`; Dienst: `memory.py`, `privacy.py` | **Kurzzeit:** Gesprächsverlauf. **Langzeit:** Erinnerungen mit Herkunft und Zeitpunkt, selbst gelernt oder von Ihnen. Erkennt Duplikate und veraltete Einträge. Speichert nie Zugangsdaten. Sie können alles ansehen, bearbeiten, exportieren und löschen. |
| **Retrieval System** | `memory.py` (Embeddings, sonst Wortvergleich), `knowledge.py`, `learning.py` (`context_for`) | Passende Erinnerungen, Wissensaussagen mit Quelle und bewährte Abläufe kommen in den Kontext. |
| **Tool Manager** | `tools.py`, `documents.py`, App: `AtlasToolbox.swift`, `ToolCatalog.swift` | 33 Werkzeuge im Dienst und 26 in der App, in drei Stufen: sicher / Bestätigung / gesperrt. Der Router wählt passende Gruppen aus. |
| **Planning Engine** | `agent.py` (Planmodus, `PLAN_PROMPT`), `tasks.py` | Zerlegt mehrschrittige Aufträge. Nach einem Fehlschlag fordert ATLAS die übrigen Teile an. Unterbrochene Aufgaben lassen sich fortsetzen. |
| **Task Executor** | `agent.py` (`execute`, `native_call`, `validate`, `report`), `tasks.py` | Führt aus und prüft das Ergebnis jedes Werkzeugs. Grenzen für Zeit, Runden und Wiederholungen. Keine doppelten Außenwirkungen. Ehrlicher Bericht: erledigt / fehlgeschlagen / offen. |
| **Experience Learning Engine** | `learning.py`, `improvement.py` | Speichert Erfahrungen: Ziel, Schritte, Ergebnis, Fehler, Lehre. Aus Korrekturen werden Regeln. Wiederkehrende Fehler werden zu Verbesserungsvorschlägen; was nicht hilft, nimmt ATLAS automatisch zurück. |
| **Speech Recognition** | App: `SpeechRecognizer.swift` | Apple-Spracherkennung auf dem Gerät, in einer eingestellten Sprache. |
| **Text-to-Speech Engine** | App: `SpeechSynthesizer.swift`, `LanguageSegments.swift`, `SpeechText.swift` | Beste installierte Apple-Stimme. Englische Abschnitte spricht eine englische Stimme. Adressen, Markdown und Denktext werden nicht vorgelesen. |
| **Wake Word Engine** | App: `ConversationEngine.swift` (Wake-Word über die Spracherkennung) | Reagiert auf „Atlas“. Optional hört ATLAS nach einer Antwort weiter zu, ohne neue Aktivierung. |
| **Research Module** | `research.py`, `tools.py` (`search_web`) | Mehrere Suchdienste mit Ausweichen. Mehrere Quellen lesen, nach Herkunft einordnen, nummeriert belegen. Erfundene Adressen werden entfernt. Fremde Anweisungen werden entschärft. |
| **Permissions and Security Manager** | `tools.py` (Pfadregeln, Befehlsliste, Stufen), `agent.py` (`confirm`), `privacy.py`, `sandbox.py`, `approvals.py`, `server.py` (Token/Origin) | Nur Ihr Benutzerordner. Keine freie Shell. Bestätigung bei Löschen, Überschreiben und Senden. Zugangsdaten nie speichern. Geprüfte macOS-Sandbox. |
| **Self-Improvement Development Sandbox** | `capabilities.py`, `evolution.py`, `skills.py`, `skill_harness.py`, `workshop.py`, `sandbox.py` | Zuerst prüft ATLAS, ob eine Fähigkeit schon vorhanden ist. Dann: entwickeln und testen in der Sandbox → Freigabe → Versionen → Zurücksetzen. Eigene Codeänderungen nur in einer Kopie, mit Testpflicht, Sicherung und automatischem Rücksetzen. |
| **User Interface** | App: `MainView.swift`, `StatusViews.swift`, `LearningView.swift`, `CloudSettingsView.swift`, `MemoryView.swift`; Web: `Backend/web` | Statuszeile, Aktionsliste, Bestätigungen, Gedächtnis, Learning & Evolution, Cloud-Einstellungen. Texteingabe ist immer möglich. |

## Ablauf einer Anfrage

1. **App:** Sie sprechen oder tippen. Die App schickt den Gesprächsverlauf, passende Erinnerungen und die App-Werkzeuge an den Dienst.
2. **Direkte Wege ohne Modell:** zuerst geprüft.
   - Exakte Rechnung, „Merk dir …“ (mit Passwortschutz), Moduswechsel, Lernaufträge.
   - „Cloud: …“ führt zur Cloud, aber nur wenn eingeschaltet und nach Rückfrage.
3. **Router:** entscheidet zwischen Gespräch (schnelle Antwort im Stream), Agent (Werkzeuge) und Plan (mehrstufig).
4. **Agent:** baut den Kontext aus Persona, gelernten Regeln, bewährten Abläufen, Wissen mit Quellen und dem Zusammenhang der letzten Aufgabe. Dann ruft das Modell Werkzeuge auf, ATLAS führt aus und prüft. Bei Bedarf fragt ATLAS nach Bestätigung oder ruft Werkzeuge der App auf.
5. **Prüfung ohne Modell:** Erfolgsbehauptungen gegen die tatsächlichen Ergebnisse, Quellen gegen das tatsächlich Abgerufene. Danach kommt der Bericht.
6. **Lernen:** Erfahrung und Aufgabenjournal speichern. Bei einer Korrektur wird eine Regel daraus.

## Schnittstellen der App (alle nur mit Sitzungstoken, nur 127.0.0.1)

- `/api/native/agent/stream`, `/api/native/agent/result`: Gespräch und Werkzeuge
- `/api/native/learning/*`: Übersicht, Freigaben, Regeln, Wissen, Wissenspakete, Einstellungen, Rücksetzen, Export
- `/api/native/cloud/*`: Status, Einstellungen, Modus, Schlüssel (der Schlüssel wird nur in den macOS-Schlüsselbund geschrieben)

Das Sprachmodell erreicht diese Schnittstellen nicht. Werkzeuge dürfen keine lokalen Adressen aufrufen.
