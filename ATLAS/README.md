# ATLAS – Advanced Thinking, Learning & Assistance System

Ihr persönlicher KI-Assistent für das iPhone. **Phase 1:** native SwiftUI-App mit Claude als „Gehirn“, Spracheingabe, Sprachausgabe, Gesprächsmodus und Gesprächsverlauf.

> Ausgelegt für: iPhone 15 Pro oder neuer · iOS 26 · Mac mit Apple-Chip · Claude API
> (Die App läuft ab iOS 17.)

---

## Was Phase 1 kann

| Funktion | Stand |
|---|---|
| Auf den ATLAS-Kern oder das Mikrofon tippen und sprechen | ✅ |
| Automatische Pausenerkennung: ATLAS merkt, wann Sie fertig sind | ✅ |
| Antwort von Claude, satzweise gestreamt, damit ATLAS schnell zu sprechen beginnt | ✅ |
| Gesprächsmodus: nach jeder Antwort hört ATLAS automatisch weiter zu | ✅ |
| Unterbrechen: während ATLAS spricht, tippen Sie, und er hört sofort zu | ✅ |
| Gespräch beenden mit „Danke, das ist alles“ oder dem Stopp-Knopf | ✅ |
| Deutsch und britisches Englisch, wählbare Stimme | ✅ |
| Internetrecherche (Wetter, Nachrichten …) über die Websuche von Claude | ✅ |
| Gesprächsverlauf: ansehen, fortsetzen, löschen | ✅ |
| Tastatureingabe für ruhige Umgebungen | ✅ |
| API-Schlüssel verschlüsselt in der iOS-Keychain | ✅ |
| Animierter, auf Ihre Stimme reagierender ATLAS-Kern | ✅ (das Gesicht folgt in Phase 2) |

Noch **nicht** in Phase 1: Wake-Word „Atlas“, Siri und Kurzbefehle (Phase 3), Kalender, Erinnerungen, Fotos, Dateien (Phase 4), dauerhaftes Gedächtnis (Phase 5). ATLAS weiß das und sagt es Ihnen ehrlich, statt etwas vorzutäuschen.

---

## Teil A – Einmalige Vorbereitung (ca. 30–45 Minuten)

### A1. Xcode installieren
1. Öffnen Sie auf dem Mac den **App Store** und suchen Sie nach **Xcode**.
2. Installieren Sie Xcode (ca. 10–15 GB, das dauert eine Weile).
3. Starten Sie Xcode einmal. Wenn gefragt wird, welche Plattformen installiert werden sollen, wählen Sie **iOS** aus und bestätigen.
4. Sie brauchen **Xcode 26** oder neuer (für iOS 26 auf Ihrem iPhone). Prüfen: Menü *Xcode → About Xcode*.

### A2. Apple-ID in Xcode anmelden
1. In Xcode: Menü **Xcode → Settings… → Accounts**.
2. Unten links auf **+** → **Apple ID** → mit Ihrer normalen Apple-ID anmelden.
3. Es erscheint ein „Personal Team“. Das reicht für den Anfang – kostenlos.

> **Kostenlos vs. Apple Developer Program (99 €/Jahr):**
> Mit dem kostenlosen „Personal Team“ läuft die App **7 Tage**, danach müssen Sie sie aus Xcode erneut aufs iPhone spielen (1 Klick). Mit dem bezahlten Programm läuft sie 1 Jahr, und später können wir TestFlight und iCloud-Synchronisierung nutzen. Für Phase 1 genügt kostenlos.

### A3. Den Code auf den Mac holen
**Variante 1 – ohne Kenntnisse (ZIP):**
1. Öffnen Sie das Repository auf GitHub im Browser.
2. Wählen Sie oben links den Branch **`claude/atlas-iphone-app-su9dj1`**.
3. Klicken Sie auf **Code → Download ZIP** und entpacken Sie die Datei, z. B. in den Ordner *Dokumente*.

**Variante 2 – mit Terminal (empfohlen für spätere Updates):**
```bash
cd ~/Documents
git clone https://github.com/velascout/scoutmatch.git
cd scoutmatch
git checkout claude/atlas-iphone-app-su9dj1
```
Spätere Updates holen Sie dann mit `git pull`.

### A4. iPhone vorbereiten
1. iPhone per USB-C-Kabel mit dem Mac verbinden, entsperren und **„Diesem Computer vertrauen“** bestätigen.
2. Auf dem iPhone: **Einstellungen → Datenschutz & Sicherheit → Entwicklermodus** einschalten. Das iPhone startet neu; danach bestätigen Sie mit **Einschalten**.
   *(Der Schalter erscheint erst, nachdem das iPhone einmal mit Xcode verbunden war. Falls er fehlt: erst Schritt B ausführen, dann wiederkommen.)*

---

## Teil B – App bauen und aufs iPhone bringen

1. Öffnen Sie im Finder den Ordner `ATLAS` und doppelklicken Sie auf **`ATLAS.xcodeproj`**.
2. Klicken Sie links in der Seitenleiste ganz oben auf das blaue Projektsymbol **ATLAS**.
3. Wählen Sie in der Mitte unter *TARGETS* **ATLAS** und dann oben den Reiter **Signing & Capabilities**.
4. Häkchen bei **Automatically manage signing** setzen.
5. Bei **Team** Ihr „Personal Team“ (Ihr Name) auswählen.
6. Bei **Bundle Identifier** steht `de.atlas.assistant.BITTE-AENDERN`. Ersetzen Sie das durch etwas Eindeutiges, z. B. `de.IhrNachname.atlas` (nur Buchstaben, Zahlen, Punkte, Bindestriche).
7. Oben in der Mitte der Xcode-Leiste: als Ziel Ihr **iPhone** auswählen (nicht einen Simulator).
8. Auf den **▶︎ Play-Knopf** klicken (oder ⌘R). Der erste Build dauert 1–2 Minuten.
9. Beim ersten Mal meldet das iPhone „Nicht vertrauenswürdiger Entwickler“:
   **Einstellungen → Allgemein → VPN & Geräteverwaltung →** Ihre Apple-ID → **Vertrauen**. Dann in Xcode erneut ▶︎ drücken.

ATLAS startet jetzt auf Ihrem iPhone. 🎉

**Häufige Probleme**
| Meldung | Lösung |
|---|---|
| „Failed to register bundle identifier“ | Bundle Identifier ist schon vergeben → anderen Namen wählen (Schritt B6). |
| „Signing requires a development team“ | Team in Schritt B5 auswählen. |
| „Developer Mode disabled“ | Schritt A4.2 ausführen. |
| iPhone wird nicht angezeigt | Kabel prüfen, iPhone entsperren, „Vertrauen“ bestätigen; Xcode → *Window → Devices and Simulators*. |
| Build-Fehler im Code | Fehlermeldung (rotes Symbol links, Reiter „Issue Navigator“) kopieren und mir schicken. |

---

## Teil C – Claude API einrichten

1. Gehen Sie auf **https://console.anthropic.com** und erstellen Sie ein Konto (bzw. melden Sie sich an).
2. **Guthaben aufladen:** *Settings → Billing* → z. B. 10 $ einzahlen. Die API wird nach Verbrauch abgerechnet, ein Abo ist nicht nötig.
3. **Ausgabenlimit setzen (empfohlen):** *Settings → Limits* → monatliches Limit, z. B. 20 $. So kann nie mehr ausgegeben werden.
4. **Schlüssel erstellen:** *Settings → API Keys → Create Key* → Name „ATLAS iPhone“ → Schlüssel kopieren (beginnt mit `sk-ant-…`). Er wird nur einmal angezeigt.
5. Am bequemsten: Schlüssel z. B. per AirDrop/Notizen aufs iPhone bringen, in ATLAS beim ersten Start einfügen und **„Speichern und beginnen“** tippen. Anschließend die Notiz wieder löschen.

### Was kostet das?
Richtwerte pro gesprochener Frage und Antwort (kurze Antworten, Gesprächsverlauf wächst mit):

| Modell | ca. Kosten pro Frage | Charakter |
|---|---|---|
| Claude Opus 5.5 (Standard) | ~1 Cent | intelligentestes Modell |
| Claude Sonnet 5.5 | ~0,5 Cent | ausgewogen |
| Claude Haiku 5.5 | < 0,1 Cent | am schnellsten, günstigsten |

Mit **Internetrecherche** kommen ca. 1 Cent pro Suche plus die gelesenen Suchergebnisse hinzu (ein paar Cent). Bei 30 Fragen am Tag liegen Sie mit Opus grob bei 5–15 € im Monat. Aktuelle Preise: https://www.anthropic.com/pricing

### Sicherheit des Schlüssels
- Der Schlüssel steht **nicht im Code** und nicht auf GitHub.
- Er liegt verschlüsselt in der **iOS-Keychain**, nur auf diesem iPhone (`WhenUnlockedThisDeviceOnly`), nicht in Backups.
- Er wird ausschließlich per HTTPS direkt an `api.anthropic.com` gesendet.
- Wenn Sie den Verdacht haben, dass er bekannt wurde: in der Anthropic-Konsole löschen und neu erstellen.
- Für eine spätere Veröffentlichung im App Store oder für mehrere Nutzer würden wir einen kleinen eigenen Server dazwischenschalten, damit der Schlüssel das Gerät gar nicht erst erreicht. Für Ihre persönliche App ist die Keychain-Lösung angemessen.

---

## Teil D – Schritt-für-Schritt-Tests

Bitte gehen Sie die Tests der Reihe nach durch und notieren Sie, was nicht wie erwartet funktioniert.

| # | Test | So geht's | Erwartetes Ergebnis |
|---|---|---|---|
| 1 | Start | App öffnen | Dunkler Bildschirm, leuchtender blauer ATLAS-Kern, Statusanzeige „ATLAS · Bereit“. Beim allerersten Start erscheint die Schlüssel-Eingabe. |
| 2 | Schlüssel | Schlüssel einfügen → Speichern | Eingabe verschwindet. In *Einstellungen → Claude API* steht „API-Schlüssel ist sicher gespeichert“. |
| 3 | Berechtigungen | Auf den Mikrofon-Knopf tippen | iOS fragt nach **Spracherkennung** und **Mikrofon** → beide erlauben. |
| 4 | Zuhören | Erneut tippen, sagen: „Wer bist du?“ | Status „Hört zu“, roter Punkt, Mikrofon-Knopf rot, der Kern reagiert auf Ihre Lautstärke, Ihr Text erscheint live. |
| 5 | Pausenerkennung | Nach dem Satz einfach schweigen | Nach ca. 1,4 s: „Denkt nach“ → ATLAS antwortet laut, stellt sich vor und spricht Sie mit „Sir“ an. |
| 6 | Gesprächsmodus | Nach der Antwort nichts tippen | ATLAS hört automatisch wieder zu (roter Punkt). Fragen Sie: „Und was kannst du?“ – er bezieht sich auf das vorherige Gespräch. |
| 7 | Gespräch beenden | Sagen: „Danke, das ist alles.“ | ATLAS: „Sehr wohl, Sir.“ → Status „Bereit“, Mikrofon aus. |
| 8 | Stille | Mikrofon antippen und 8 s nichts sagen | ATLAS hört von selbst wieder auf. |
| 9 | Unterbrechen | Eine lange Frage stellen („Erkläre mir ausführlich die Relativitätstheorie“) und während der Antwort auf den Kern tippen | ATLAS verstummt sofort und hört zu. |
| 10 | Internet | „Wie wird das Wetter morgen in Hamburg?“ | Nach etwas längerer Denkzeit eine aktuelle Wettervorhersage. |
| 11 | Ehrlichkeit | „Erinnere mich morgen um 8 Uhr an mein Training.“ | ATLAS erklärt höflich, dass er Erinnerungen noch nicht anlegen kann (kommt in Phase 4), und behauptet **nicht**, es getan zu haben. |
| 12 | Tastatur | Tastatur-Symbol → „Rechne 15 % von 2.340 €“ → Senden | Antwort wird gesprochen und angezeigt (351 €). |
| 13 | Englisch | *Einstellungen → Sprache: English (UK)* → „What time is it?“ | Antwort auf Englisch mit britischer Stimme. Danach zurück auf Deutsch stellen. |
| 14 | Stimme | *Einstellungen → Stimme* wählen → „Stimme probehören“ | Begrüßung in der gewählten Stimme. |
| 15 | Verlauf | Uhr-Symbol oben links | Liste Ihrer Gespräche; Gespräch öffnen → „Fortsetzen“ funktioniert; Wischen nach links löscht. |
| 16 | Fehlerfall | Flugmodus an → Frage stellen | Verständliche Fehlermeldung, App stürzt nicht ab. Flugmodus wieder aus. |
| 17 | Falscher Schlüssel | *Einstellungen → Schlüssel entfernen* → falschen Schlüssel `sk-ant-test` speichern → Frage stellen | Meldung „Der API-Schlüssel wurde abgelehnt …“. Danach richtigen Schlüssel wieder eintragen. |
| 18 | Datenschutz | App in den Hintergrund schicken, während ATLAS zuhört | Das Mikrofon geht nicht heimlich weiter (kein oranger/roter Punkt in der iOS-Statusleiste). |

**Tipp für eine natürlichere Stimme:** iPhone-Einstellungen → Bedienungshilfen → Gesprochene Inhalte → Stimmen → Deutsch bzw. Englisch → eine Stimme mit **Premium** oder **Erweitert** herunterladen (für den britischen Butler-Klang: Englisch (UK) „Daniel“). Danach in ATLAS unter *Einstellungen → Stimme* auswählen.

---

## Projektstruktur

```
ATLAS/
├── ATLAS.xcodeproj               Xcode-Projekt (Doppelklick zum Öffnen)
├── README.md                     Diese Anleitung
├── docs/ARCHITEKTUR.md           Technische Planung & Fahrplan Phase 1–6
└── ATLAS/                        Quellcode
    ├── App/ATLASApp.swift        Einstiegspunkt der App
    ├── Core/
    │   ├── AI/
    │   │   ├── AIProvider.swift      Austauschbare KI-Schnittstelle
    │   │   ├── ClaudeProvider.swift  Claude API (Streaming, Websuche)
    │   │   └── Persona.swift         Persönlichkeit von ATLAS
    │   ├── Conversation/
    │   │   └── ConversationEngine.swift  Zuhören → Denken → Sprechen
    │   ├── Speech/
    │   │   ├── SpeechRecognizer.swift    Spracherkennung (auf dem Gerät)
    │   │   ├── SpeechSynthesizer.swift   Sprachausgabe, Satz-Streaming
    │   │   └── AudioSessionManager.swift
    │   ├── Persistence/Models.swift      Gesprächsverlauf (SwiftData)
    │   ├── Security/KeychainStore.swift  Sichere Schlüsselablage
    │   └── Settings/AppSettings.swift    Einstellungen
    ├── UI/
    │   ├── Main/MainView.swift           Startbildschirm
    │   ├── Main/AtlasCoreView.swift      Animierter ATLAS-Kern
    │   ├── Settings/SettingsView.swift
    │   ├── History/HistoryView.swift
    │   └── Onboarding/OnboardingView.swift
    └── Assets.xcassets               App-Symbol & Farben
```
