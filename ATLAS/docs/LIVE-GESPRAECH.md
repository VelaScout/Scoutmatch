# Live-Gespräch – natürlich reden wie mit ChatGPT

Diese Anleitung erklärt in einfachen Worten, wie das Live-Gespräch von A.T.L.A.S. funktioniert,
was es kostet, wie Sie es einrichten und wie Sie es testen.

## 1. Was vorher war (Analyse)

Bisher lief jedes Gespräch in drei getrennten Schritten:

1. Apple wandelt Ihre Sprache in Text um.
2. Claude schreibt eine Antwort.
3. Eine Stimme liest den Text vor.

Jeder Schritt wartet auf den vorherigen. Deshalb fühlte es sich langsam, abgehackt und
„vorgelesen“ an. Pausen, Betonung und Unterbrechen waren kaum möglich.

## 2. Wie es jetzt aufgebaut ist (Architektur)

```
 „Atlas“ (nur auf dem Gerät erkannt)
        │
        ▼
 ┌────────────────────────┐     Ton hin und zurück (WebSocket, verschlüsselt)
 │  Live-Stimme (OpenAI   │ ◄────────────────────────────────────────────── Mikrofon / Lautsprecher
 │  Realtime, gpt-realtime)│
 └───────────┬────────────┘
             │ Werkzeug „ask_atlas“ (Wissen, Recherche, Aktionen)
             ▼
 ┌────────────────────────┐
 │  Claude = das Gehirn    │ ── Kalender, Erinnerungen, E-Mail, Spotify, Timer, Gedächtnis …
 └────────────────────────┘
```

- **Live-Stimme (OpenAI Realtime):** hört und spricht direkt – ohne Umweg über Text.
  - Das gibt eine natürliche Satzmelodie, echte Pausen und schnelle Antworten.
  - Sie erkennt am Sinn, wann Sie fertig sind („semantic VAD“), nicht nur an der Stille.
- **Claude bleibt das Gehirn.** Alles, was Wissen, Recherche, Gedächtnis oder Aktionen braucht, gibt die Live-Stimme im Hintergrund an Claude weiter.
  - Claude nutzt dieselben Werkzeuge, dieselbe Persönlichkeit und dasselbe Gedächtnis wie bisher.
  - Die Live-Stimme gibt das Ergebnis in eigenen Worten wieder.
- **Wake-Word lokal:** „Atlas“ erkennt Apples Spracherkennung direkt auf dem Gerät.
  - Vorher verlässt kein Ton das Gerät.
  - Die letzten 4 Sekunden liegen nur im Arbeitsspeicher, damit „Atlas, wie spät ist es?“ vollständig ankommt.
- **Unterbrechen:** Sie können jederzeit reinreden.
  - A.T.L.A.S. verstummt sofort.
  - Der Server erfährt, welchen Teil der Antwort Sie wirklich gehört haben.
- **Echo- und Geräuschunterdrückung:**
  - Apples Echo-Unterdrückung (Voice Processing): A.T.L.A.S. hört sich nicht selbst.
  - Dazu die Rauschunterdrückung von OpenAI.
  - Liefert die Echo-Unterdrückung auf einem Gerät keinen Ton, schaltet A.T.L.A.S. sie automatisch ab. Dann hört er nicht zu, während er selbst spricht. Unterbrechen geht in dem Fall per Tipp auf den Kern.
- **Gesprächsende:** Nach 45 Sekunden Ruhe endet das Live-Gespräch und die Verbindung wird getrennt. Ebenso bei „Danke, das war's“ oder per Tipp auf den Kern.
- **Sicherheitsabfragen bleiben:** Vor dem Senden einer E-Mail, einem Anruf oder dem Löschen fragt A.T.L.A.S. nach. Erst nach einem klaren „Ja“ wird es ausgeführt.
- **Klassischer Modus bleibt erhalten:** Er ist der Ersatz, wenn das Live-Gespräch aus ist, kein OpenAI-Schlüssel da ist, das Budget erreicht ist oder die Verbindung scheitert.

Wichtige Dateien:

| Datei | Aufgabe |
|---|---|
| `Core/Realtime/RealtimeSession.swift` | WebSocket-Verbindung zu OpenAI, Ton hoch und runter, Unterbrechen, Kostenerfassung |
| `Core/Realtime/RealtimePersona.swift` | Persönlichkeit der Live-Stimme, Werkzeuge `ask_atlas`, `confirm_pending_action`, `end_conversation` |
| `Core/Conversation/ConversationEngine.swift` | Ablauf: Wake-Word → Live-Gespräch → Claude → zurück in die Bereitschaft |
| `Core/Speech/AudioHub.swift` | Eine Audio-Leitung für Mikrofon und Lautsprecher, 4-Sekunden-Vorlauf |
| `Core/Settings/CostTracker.swift` | Geschätzte Kosten pro Monat, Budget |
| `UI/Main/MenuBarContent.swift` | Mac: Symbol in der Menüleiste (Mikrofon an/aus, Live an/aus) |

## 3. Einrichten

1. **OpenAI-Schlüssel holen:**
   1. Melden Sie sich auf https://platform.openai.com an.
   2. Unter *Billing* laden Sie etwas Guthaben auf, z. B. 10 $. Das ChatGPT-Abo zählt hier nicht.
   3. Unter *Limits* setzen Sie am besten ein Monatslimit.
   4. Unter *API keys* wählen Sie *Create new secret key* und kopieren den Schlüssel.
2. **In A.T.L.A.S.:**
   1. Sagen Sie „Öffne die Einstellungen“ und gehen Sie zu **Live-Gespräch**.
   2. Fügen Sie den Schlüssel ein und tippen Sie auf **Speichern**.
   3. Der Schlüssel liegt verschlüsselt im Schlüsselbund des Geräts. Er steht nicht im Code und nicht auf GitHub.
3. **Stimme wählen:** „Cedar“ (ruhig, warm) ist voreingestellt, „Marin“ ist die Alternative.
   - Die ChatGPT-Stimme „Arbor“ bietet OpenAI für Entwickler nicht an.
   - Eine geschützte Stimme wird bewusst nicht nachgebaut.
4. **Monatsbudget** unter *Kosten & Budget* festlegen (voreingestellt: 20 $).
5. **Nur Mac, optional:**
   - *Im Hintergrund auf „Atlas“ hören*
   - *Beim Anmelden automatisch starten*: Dafür muss A.T.L.A.S. im Ordner *Programme* liegen.

## 4. Kosten – was kostet Geld, was ist kostenlos?

| Funktion | Kosten | Wo läuft es? |
|---|---|---|
| Wake-Word „Atlas“ | kostenlos | auf dem Gerät |
| Spracherkennung im klassischen Modus | kostenlos | auf dem Gerät |
| Apple-Stimmen, eigene XTTS-Stimme | kostenlos | auf dem Gerät / Ihrem Mac |
| Gedächtnis, Verlauf, Kalender, Erinnerungen | kostenlos | auf dem Gerät |
| Claude (jede Antwort, auch im Live-Gespräch über `ask_atlas`) | ca. 0,1–1 Cent pro Frage | Anthropic |
| **Live-Gespräch** mit `gpt-realtime-2.1` | ca. 3–15 Cent pro Gesprächsminute | OpenAI |
| Live-Gespräch mit `gpt-realtime-2.1-mini` | ungefähr ein Drittel davon | OpenAI |
| OpenAI-Stimme im klassischen Modus | ca. 1,5 Cent pro Minute | OpenAI |

- A.T.L.A.S. rechnet die Kosten aus den Verbrauchsangaben mit, die Anthropic und OpenAI mit jeder Antwort schicken. Sie sehen sie unter *Einstellungen → Kosten & Budget*.
- Das ist eine Schätzung; maßgeblich ist die Abrechnung in Ihrem Konto.
- Ist das Budget erreicht, schaltet A.T.L.A.S. das Live-Gespräch bis Monatsende ab und arbeitet im klassischen Modus weiter.
- Ton wird nur übertragen, solange ein Live-Gespräch läuft. Nach 45 Sekunden Ruhe wird die Verbindung getrennt.

## 5. Mikrofon und Datenschutz

- **Mikrofon-Hauptschalter:** in den Einstellungen und (Mac) in der Menüleiste. Aus heißt: Das Mikrofon wird überhaupt nicht benutzt.
- **Sichtbar:**
  - Unten rechts im Kern steht „MIK xx %“.
  - Auf dem Mac zeigt die Menüleiste ein Symbol: Wellen bedeutet hört bzw. spricht, durchgestrichen bedeutet aus.
  - macOS und iOS zeigen zusätzlich den orangen Mikrofon-Punkt.
- **Vor „Atlas“** bleibt alles auf dem Gerät. Danach geht der Ton verschlüsselt an OpenAI (Live-Stimme). Der Text Ihrer Aufgaben geht an Anthropic (Claude).
- **iPhone:** Apple erlaubt kein Dauerzuhören im Hintergrund. A.T.L.A.S. hört nur zu, solange die App offen ist; sonst „Siri, starte A.T.L.A.S.“.

## 6. Testplan

| # | Test | Erwartung |
|---|---|---|
| 1 | „Atlas, wie spät ist es?“ in einem Atemzug | Antwortet in ca. 1 Sekunde, der Satzanfang geht nicht verloren |
| 2 | Deutsch: „Atlas, erzähl mir einen kurzen Witz“ | Natürliche Betonung, Pausen, kein Vorlesen |
| 3 | Englisch: „Atlas, what's the weather like in London?“ | Antwortet auf Englisch; Wetter über Claude (Recherche) |
| 4 | Gemischt: „Atlas, spiel Blinding Lights von The Weeknd“ | Titel englisch ausgesprochen, Spotify startet |
| 5 | Unterbrechen: Lange Antwort anfordern, nach 3 Sekunden reinreden | Verstummt sofort und geht auf das Neue ein |
| 6 | Weiterreden ohne „Atlas“ direkt nach einer Antwort | Hört weiter zu |
| 7 | 45 Sekunden schweigen | Gespräch endet, wartet wieder auf „Atlas“ |
| 8 | „Atlas, schreib Max eine Mail, dass ich später komme“ | Fragt vor dem Senden nach, sendet erst nach „Ja“ |
| 9 | Mikrofon in der Menüleiste ausschalten und „Atlas“ sagen | Keine Reaktion; MIK-Anzeige weg |
| 10 | Mac: Fenster schließen (Hintergrund an), „Atlas, was steht heute an?“ | Antwortet ohne Fenster; Menüleisten-Symbol zeigt Aktivität |
| 11 | Mac: Fenster schließen (Hintergrund aus) | Mikrofon geht aus |
| 12 | Budget auf 0,01 $ setzen | Nach der nächsten Antwort Hinweis, danach klassischer Modus |
| 13 | Falscher OpenAI-Schlüssel | Hinweis, dann klassischer Modus |

## 7. Ehrliche Grenzen

- Der Code wurde ohne Mac geschrieben. Er wurde nicht kompiliert und nicht auf einem echten Gerät getestet. Beim ersten Bauen in Xcode können kleine Fehler auftauchen – einfach den Screenshot schicken.
- „Arbor“ aus der ChatGPT-App ist über die Entwickler-Schnittstelle nicht verfügbar. „Cedar“ oder „Marin“ kommen am nächsten.
- Ohne funktionierende Echo-Unterdrückung (manche Macs) hört A.T.L.A.S. nicht zu, während er selbst spricht. Unterbrechen geht dann per Tipp oder per Menüleiste.
