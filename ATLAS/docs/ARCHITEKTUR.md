# ATLAS – Technische Planung

## Zielsystem
- **Gerät:** iPhone 15 Pro oder neuer, iOS 26 (Mindestversion der App: iOS 17)
- **Entwicklung:** Mac mit Apple-Chip, Xcode 26, Swift/SwiftUI
- **KI:** Claude API (Anthropic), austauschbar über das Protokoll `AIProvider`

## Architektur (Phase 1)

```
 ┌──────────── SwiftUI-Oberfläche ────────────┐
 │ MainView · AtlasCoreView · Settings · Verlauf │
 └───────────────▲──────────────┬──────────────┘
                 │ beobachtet    │ Aktionen
        ┌────────┴──────────────▼────────┐
        │       ConversationEngine        │  Zustand: Bereit → Hört zu → Denkt nach → Spricht
        └──┬──────────┬──────────┬───────┘
           │          │          │
  SpeechRecognizer  AIProvider  SpeechSynthesizer
  (Speech, on-device) │ (Claude)  (AVSpeechSynthesizer, satzweise)
                      │
               KeychainStore (API-Schlüssel) · SwiftData (Verlauf)
```

**Warum so?**
- **Streaming + Satz-Zerlegung:** Claude liefert die Antwort Stück für Stück. Sobald ein Satz vollständig ist, wird er gesprochen – die gefühlte Antwortzeit sinkt deutlich.
- **Spracherkennung auf dem Gerät:** schneller, privater, keine Zusatzkosten.
- **Mikrofon aus, während ATLAS spricht:** verhindert, dass ATLAS sich selbst hört. Unterbrechen erfolgt in Phase 1 per Tippen; „Sprach-Unterbrechung“ (Barge-in mit Echounterdrückung) folgt in Phase 3.
- **`AIProvider`-Protokoll:** OpenAI, ein lokales Modell oder ein eigener Server lassen sich ergänzen, ohne den Rest der App zu ändern.
- **Denkblöcke werden nicht gespeichert:** ATLAS schickt nur den Text des Gesprächs zurück. Das hält Anfragen klein und robust.
- **Modell-Voreinstellung:** Claude Opus 5.5 mit Denktiefe „Schnell“ (`effort: low`) – hohe Intelligenz bei kurzer Antwortzeit. Bei fälschlicher Ablehnung springt serverseitig automatisch ein Ausweichmodell ein (`fallbacks: "default"`).

## Bewertung der KI-Optionen

| Option | Vorteile | Nachteile | Entscheidung |
|---|---|---|---|
| Claude API | Sehr gutes Deutsch, starkes Denken, Bildanalyse, PDF-Verständnis, Websuche, Werkzeugnutzung | Laufende Kosten, Internet nötig | **Hauptmodell** |
| OpenAI API | Ebenfalls stark, eigene Sprach-Modelle | Zweiter Anbieter, zweite Abrechnung | Optional später |
| Lokales Modell (Apple Foundation Models, iOS 26) | Kostenlos, offline, privat | Deutlich weniger leistungsfähig | Später für einfache Aufgaben/Offline |
| Hybrid | Beste Mischung | Mehr Komplexität | Ziel ab Phase 5 |

## Was iOS erlaubt – und was nicht

| Wunsch | Realität | Unser Weg |
|---|---|---|
| „Atlas“ rufen, App geöffnet | ✅ erlaubt | Phase 3: lokale Wake-Word-Erkennung im Vordergrund |
| „Atlas“ rufen, App geschlossen / Bildschirm aus | ❌ Apple erlaubt keinen dauerhaften Mikrofonzugriff im Hintergrund für Drittanbieter-Apps | „Siri, starte Atlas“, Kurzbefehl, Action-Button (iPhone 15 Pro+), Sperrbildschirm-/Kontrollzentrum-Steuerelement |
| Siri-Integration | ✅ über App Intents | Phase 3: „Siri, frag Atlas …“, „Siri, starte Atlas“ |
| Kalender, Erinnerungen | ✅ EventKit, mit Erlaubnis | Phase 4 |
| Kontakte, Fotos, Dateien, Kamera, Standort, Karten | ✅ mit Erlaubnis | Phase 4 |
| Nachrichten selbst senden | ⚠️ nur über den System-Dialog, Nutzer bestätigt | Phase 4: ATLAS bereitet vor, Sie tippen „Senden“ |
| Dauerhaft im Hintergrund arbeiten | ❌ | Lokale Benachrichtigungen, Background Tasks (vom System geplant), optional eigener Server |

## Fahrplan

**Phase 1 – Grundlegende App** ✅ *(dieser Stand)*
SwiftUI-App, Claude-Anbindung mit Streaming und Websuche, Spracheingabe/-ausgabe, Gesprächsmodus, Pausenerkennung, Unterbrechen, Verlauf, Einstellungen, sichere Schlüsselablage.

**Phase 2 – Visuelle Persönlichkeit**
Animiertes 2D-Gesicht (SwiftUI Canvas/Metal-Shader): weiß-silberne, halbtransparente Haut, eisblaue leuchtende Augen, Blinzeln, Blickbewegung, Kopfbewegung, Mundbewegung synchron zu den gesprochenen Wörtern (bereits vorbereitet über `spokenWordCount`), Ausdrücke je Zustand. Danach optional 3D-Kopf mit RealityKit (USDZ-Modell mit Blendshapes).

**Phase 3 – Sprachaktivierung**
Wake-Word „Atlas“ bei geöffneter App (kontinuierliche On-Device-Erkennung, energiesparend), Antwort „Ja, Sir?“, Sprach-Unterbrechung mit Echounterdrückung, App Intents für Siri und Kurzbefehle, Action-Button-Unterstützung.

**Phase 4 – iPhone-Integration**
Werkzeuge (Claude Tool Use) für Kalender, Erinnerungen, Kontakte, Karten/Route, Fotos & Kamera (Bildanalyse), Dateien & PDF-Zusammenfassung, Einkaufslisten, Nachrichtenentwürfe. Jede sensible Aktion mit Bestätigung.

**Phase 5 – Gedächtnis & intelligente Aufgaben**
Kontrollierbares Gedächtnis (SwiftData, verschlüsselt): Ziele, Projekte, Routinen, Vorlieben – ansehen, bearbeiten, löschen. Tagesplanung („Organisiere meinen morgigen Tag“), Morgenübersicht per Benachrichtigung, Aufgabenübersicht, Aktivitätsprotokoll.

**Phase 6 – Erweiterung**
Synchronisierung über iCloud/CloudKit (Ende-zu-Ende-verschlüsselt) zu Mac und Apple Watch, optionaler eigener Server für proaktive Funktionen und Schlüsselschutz.

## Sicherheit & Datenschutz (durchgehend)
- Mikrofon nur sichtbar aktiv (roter Punkt + roter Knopf), nie im Hintergrund.
- Berechtigungen erst bei Bedarf und mit Begründung.
- API-Schlüssel nur in der Keychain.
- Gesprächsverlauf lokal; jederzeit löschbar.
- Transparenz in den Einstellungen, welche Daten an Anthropic gehen.
- Riskante Aktionen (Senden, Löschen, Käufe) nur nach ausdrücklicher Bestätigung.
