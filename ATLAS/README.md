# A.T.L.A.S. – Advanced Thinking, Learning & Assistance System

Ihr persönlicher KI-Assistent für **iPhone und Mac** – eine native SwiftUI-App mit Claude als „Gehirn“.

> Ausgelegt für: iPhone 15 Pro oder neuer mit iOS 26 · MacBook mit Apple-Chip · Claude API
> Mindestversionen: iOS 17 und macOS 14 (Sonoma)

---

## Was ATLAS kann

| Bereich | Funktionen |
|---|---|
| **Erscheinung** | Filmreifer Start (gut 9 Sekunden): Tausende Lichtpunkte fliegen mit Leuchtspuren in Wirbeln über den Bildschirm, schießen zu einem riesigen **A.T.L.A.S.** zusammen – mit Lichtblitz, Druckwelle und kurzem Beben –, ein Scan-Strahl fährt darüber, der Untertitel tippt sich ein, dann stürzt alles spiralförmig in die Mitte und der Kern zündet. Der Kern: ein blauer Energiereaktor mit gleißendem Plasmakern, 3D-Kugel aus Lichtstreifen, drei Gyroskop-Ringen, Energieblitzen, Lichtstrahlen, schwebendem Staub und weichem Nachleuchten; Eckrahmen mit Telemetrie. Er reagiert auf Ihre Stimme, kreist beim Nachdenken schneller (mehr Blitze), pulsiert beim Sprechen und sendet Schallwellen aus. Mit dem Finger drehbar. |
| **Sprache** | Sprechen statt Tippen, automatische Pausenerkennung, Gesprächsmodus, Unterbrechen per Tippen, Deutsch und britisches Englisch, wählbare Stimme – optional eine menschlich klingende Premium-Stimme (ElevenLabs). |
| **Freihändig sprechen** | Ab Werk eingeschaltet: Bei geöffneter App einfach „Atlas“ sagen → „Ja, Sir?“. Oder direkt: „Atlas, wie wird das Wetter morgen?“. Nach jeder Antwort hört A.T.L.A.S. von selbst weiter zu – kein Knopf nötig. Die Erkennung des Wortes „Atlas“ läuft ausschließlich auf dem Gerät; das Mikrofon-Symbol des Systems bleibt sichtbar. Abschalten: „Schalte das Wake-Word aus“. |
| **Aufgaben erledigen** | Termine, Erinnerungen, Einkaufslisten, Timer („Stell einen Timer auf 10 Minuten“), Nachrichten/WhatsApp/E-Mails als Entwurf, Anrufe, Routen, Webseiten und App-Links („Spiel Lo-Fi auf YouTube“), Texte in die Zwischenablage und **Apple-Kurzbefehle** („Starte meinen Kurzbefehl Licht aus“) – damit lässt sich fast alles steuern, was Kurzbefehle können: Smart Home, Musik, Notizen, Fokus. Senden, Anrufen, Kurzbefehle und Löschen nur nach Ihrer Bestätigung; Käufe nie selbstständig. |
| **Schnelle Antworten** | Standardmodell Claude Sonnet 5.5 (spürbar schneller als Opus), Antwort beginnt nach 1 Sekunde Sprechpause, die Premium-Stimme nutzt das schnelle Modell Turbo v2.5. Für knifflige Aufgaben: „Nimm das stärkste Modell.“ |
| **Siri & Kurzbefehle** | „Siri, starte ATLAS“, „Siri, frag ATLAS“ (Antwort ohne App-Öffnen), „Siri, ATLAS Tagesübersicht“, „Siri, plane morgen mit ATLAS“. Auf den Action-Button legbar. |
| **Intelligenz** | Fragen, Internetrecherche, Texte, Analysen, Studium und Lernen, Finanzrechnungen, Strategien, verständliche Erklärungen. Modell wählbar (Opus, Sonnet, Haiku). |
| **Kalender** | „Was steht heute an?“, „Trag mir Freitag 14 Uhr Zahnarzt ein.“ |
| **Erinnerungen & Listen** | „Erinnere mich morgen um 8 Uhr an mein Training.“, „Setz Milch und Eier auf die Einkaufsliste.“, „Das Training ist erledigt.“ |
| **Kontakte & Nachrichten** | „Bereite eine Nachricht an meine Frau vor …“ → Entwurf mit Bestätigung, **Sie** senden ihn selbst. |
| **Standort & Karten** | „Zeig mir den Weg nach Hamburg.“, „Wie wird das Wetter hier?“ |
| **Fotos & Dokumente** | Foto aufnehmen oder auswählen → „Analysiere dieses Foto.“; PDF auswählen → „Fasse mir diese PDF zusammen.“ |
| **Gedächtnis** | „Merk dir, dass meine Frau Anna heißt.“ – ansehen, bearbeiten, löschen unter *Einstellungen → Gedächtnis*. |
| **Tagesplanung** | „Organisiere meinen morgigen Tag.“ – ATLAS liest Termine und Aufgaben und schlägt einen Plan vor. |
| **Proaktiv** | Morgendliche Tagesübersicht und abendlicher Rückblick per Mitteilung (einschaltbar). |
| **Transparenz** | Berechtigungsübersicht, Aktivitätsprotokoll aller ausgeführten Aktionen, Gesprächsverlauf, Datenschutzhinweise. |
| **Mac** | Dieselbe App läuft nativ auf dem MacBook – mit Menü „ATLAS“ und Tastenkürzeln (⌘L sprechen, ⌘. beenden). |
| **Bedienung** | Keine Knöpfe: Der Kern füllt den Bildschirm, unten nur eine Leiste zum Tippen oder Sprechen. Alles andere per Zuruf – „Öffne die Einstellungen“, „Sprich langsamer“, „Schalte das Wake-Word ein“, „Mach ein Foto“. Notausgang: lange auf den Kern drücken öffnet die Einstellungen. |

### Ehrliche Grenzen (Vorgaben von Apple)
- **Kein „Atlas“-Rufen bei geschlossener App oder gesperrtem Bildschirm.** Apple erlaubt Drittanbieter-Apps kein dauerhaftes Mithören im Hintergrund. Dafür: „Siri, starte ATLAS“ oder der Action-Button.
- **Nachrichten werden nie automatisch gesendet.** ATLAS öffnet einen fertigen Entwurf; Sie tippen auf Senden.
- **Proaktive Übersichten** kommen als Mitteilung zur gewählten Zeit; erstellt werden sie beim Antippen, mit aktuellen Daten. Dauerhafte Hintergrundarbeit ist auf dem iPhone nicht erlaubt.
- **Apple Watch** ist noch nicht enthalten (siehe `docs/ARCHITEKTUR.md`).

---

## Teil A – Einmalige Vorbereitung (ca. 30–45 Minuten)

### A1. Xcode installieren
1. Öffnen Sie auf dem Mac den **App Store** und suchen Sie nach **Xcode**.
2. Installieren Sie Xcode (ca. 10–15 GB, das dauert eine Weile).
3. Starten Sie Xcode einmal. Wählen Sie bei der Frage nach Plattformen **iOS** und **macOS** aus.
4. Sie brauchen **Xcode 26** oder neuer. Prüfen: Menü *Xcode → About Xcode*.

### A2. Apple-ID in Xcode anmelden
1. In Xcode: Menü **Xcode → Settings… → Accounts**.
2. Unten links auf **+** → **Apple ID** → mit Ihrer Apple-ID anmelden.
3. Es erscheint ein „Personal Team“. Das reicht für den Anfang – kostenlos.

> **Kostenlos vs. Apple Developer Program (99 €/Jahr):**
> Kostenlos läuft die App auf dem iPhone **7 Tage**, danach erneut aus Xcode starten (1 Klick). Mit dem bezahlten Programm läuft sie ein Jahr, und Sie können die **iCloud-Synchronisierung** zwischen iPhone und Mac aktivieren (Teil E).

### A3. Den Code auf den Mac holen
**Variante 1 – ZIP:** Entpacken Sie die ZIP-Datei `ATLAS…zip`, z. B. in den Ordner *Dokumente*.

**Variante 2 – GitHub (für spätere Updates):**
```bash
cd ~/Documents
git clone https://github.com/velascout/scoutmatch.git
cd scoutmatch
git checkout claude/atlas-iphone-app-su9dj1
```
Updates später mit `git pull`.

### A4. iPhone vorbereiten
1. iPhone per Kabel mit dem Mac verbinden, entsperren, **„Diesem Computer vertrauen“** bestätigen.
2. Auf dem iPhone: **Einstellungen → Datenschutz & Sicherheit → Entwicklermodus** einschalten und neu starten.
   *(Der Schalter erscheint erst, nachdem das iPhone einmal mit Xcode verbunden war.)*

---

## Teil B – App bauen

### B1. Projekt einrichten (einmalig)
1. Im Finder den Ordner `ATLAS` öffnen und **`ATLAS.xcodeproj`** doppelklicken.
2. Links oben auf das blaue Projektsymbol **ATLAS** klicken → in der Mitte unter *TARGETS* **ATLAS** wählen → Reiter **Signing & Capabilities**.
3. **Automatically manage signing** anhaken.
4. **Team:** Ihr „Personal Team“ wählen.
5. **Bundle Identifier:** `de.atlas.assistant.BITTE-AENDERN` ersetzen durch etwas Eigenes, z. B. `de.IhrNachname.atlas`.

### B2. Auf dem iPhone
1. Oben in der Xcode-Leiste als Ziel Ihr **iPhone** wählen.
2. **▶︎** klicken (⌘R). Erster Build: 1–2 Minuten.
3. Beim ersten Mal: iPhone → **Einstellungen → Allgemein → VPN & Geräteverwaltung →** Ihre Apple-ID → **Vertrauen**, dann erneut ▶︎.

### B3. Auf dem MacBook
1. Oben in der Xcode-Leiste als Ziel **My Mac** wählen.
2. **▶︎** klicken. ATLAS öffnet sich als Fenster.
3. Für dauerhafte Nutzung: Menü **Product → Archive** → **Distribute App → Custom → Copy App** → die App in den Ordner *Programme* ziehen. (Alternativ einfach immer über Xcode starten.)

**Häufige Probleme**
| Meldung | Lösung |
|---|---|
| „Failed to register bundle identifier“ | Bundle Identifier ist vergeben → anderen Namen wählen (B1.5). |
| „Signing requires a development team“ | Team wählen (B1.4). |
| „Developer Mode disabled“ | Schritt A4.2. |
| Mac: Mikrofon-/Kalenderzugriff funktioniert nicht | Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon bzw. Kalender → ATLAS erlauben. |
| Build-Fehler im Code | Fehlermeldung (Issue Navigator, rotes Symbol links) kopieren und mir schicken – ich behebe das sofort. |

---

## Teil C – Claude API einrichten

1. **https://console.anthropic.com** → Konto erstellen bzw. anmelden.
2. **Guthaben:** *Settings → Billing* → z. B. 10 $ einzahlen (Abrechnung nach Verbrauch, kein Abo).
3. **Ausgabenlimit (empfohlen):** *Settings → Limits* → z. B. 20 $ im Monat.
4. **Schlüssel:** *Settings → API Keys → Create Key* → „ATLAS“ → kopieren (beginnt mit `sk-ant-…`, wird nur einmal angezeigt).
5. Beim ersten Start von ATLAS einfügen → **„Speichern und beginnen“**. Auf dem Mac ein zweites Mal eingeben (der Schlüssel verlässt das jeweilige Gerät nie).

### Kosten (Richtwerte)
| Modell | ca. pro einfache Frage | Charakter |
|---|---|---|
| Claude Opus 5.5 (Standard) | ~1 Cent | intelligentestes Modell |
| Claude Sonnet 5.5 | ~0,5 Cent | ausgewogen |
| Claude Haiku 5.5 | < 0,1 Cent | am schnellsten, günstigsten |

Aufgaben mit Kalender/Erinnerungen brauchen 2–3 Anfragen (~2–4 Cent), Internetrecherche ca. 1 Cent pro Suche plus gelesene Inhalte, Fotos ~1–2 Cent, PDFs je nach Länge (10 Seiten ~5–10 Cent). Mit 30 Fragen am Tag liegen Sie mit Opus grob bei **10–25 € im Monat**; mit Sonnet etwa die Hälfte. Aktuelle Preise: https://www.anthropic.com/pricing

### Sicherheit des Schlüssels
- Steht **nicht im Code** und nicht auf GitHub.
- Liegt verschlüsselt im Schlüsselbund des Geräts (iPhone: nur dieses Gerät, nicht in Backups).
- Wird ausschließlich per HTTPS direkt an `api.anthropic.com` gesendet.
- Bei Verdacht: in der Anthropic-Konsole löschen und neu erstellen.

### E-Mail verbinden (iCloud-Mail)
1. Auf **account.apple.com** anmelden → **Anmelden und Sicherheit** → **App-spezifische Passwörter** → **+** → Name „A.T.L.A.S.“ → das Passwort (`xxxx-xxxx-xxxx-xxxx`) kopieren.
2. Zu A.T.L.A.S. sagen: „Öffne die Verbindungen“ → Anbieter **iCloud-Mail**, Ihre Adresse, das App-Passwort → **Passwort speichern** → **Verbindung testen**.
3. Ausprobieren: „Habe ich neue Mails?“, „Was schreibt mir Tom?“, „Antworte ihm, dass ich morgen um 10 Uhr kann.“ – A.T.L.A.S. zeigt den Entwurf und sendet erst nach Ihrem „Ja“.

Das App-Passwort liegt verschlüsselt im Schlüsselbund und kann jederzeit bei Apple widerrufen werden. Mails werden nur gelesen, wenn Sie danach fragen; zum Zusammenfassen geht der Inhalt an Claude (Anthropic).

### Spotify verbinden (Premium)
1. **developer.spotify.com/dashboard** → mit Spotify anmelden → **Create app** → Name „A.T.L.A.S.“.
2. **Redirect URI:** `atlas-assistant://spotify-callback` (genau so) · Haken bei **Web API** · speichern.
3. Die **Client ID** kopieren → in A.T.L.A.S. „Öffne die Verbindungen“ → einfügen → **Mit Spotify verbinden** → bei Spotify zustimmen.
4. Ausprobieren: „Spiel meine Lieblingssongs“, „Spiel Coldplay“, „Mach etwas zum Entspannen an“, „Lauter“, „Nächstes Lied“, „Was läuft gerade?“.

Ist Spotify auf keinem Gerät aktiv, öffnet A.T.L.A.S. die Spotify-App kurz selbst. Ihr Spotify-Passwort sieht A.T.L.A.S. nie.

### Datenschutz
Gespräche, Gedächtnis und Verlauf liegen nur auf Ihren Geräten. Für Antworten wird die jeweilige Frage an Claude (Anthropic) gesendet – laut Anthropic werden API-Daten standardmäßig nicht zum Training verwendet. Die Premium-Stimme schickt nur den vorzulesenden Text an ElevenLabs. A.T.L.A.S. gibt von sich aus nichts über Sie weiter; Nachrichten und E-Mails verlassen das Gerät nur nach Ihrer Bestätigung.

### Optional: Premium-Stimme (klingt nicht nach Siri)
Die eingebauten Apple-Stimmen klingen schnell nach Siri. Für eine wirklich geschmeidige, menschliche Stimme nutzt ATLAS auf Wunsch **ElevenLabs**:
1. Auf **https://elevenlabs.io** ein Konto anlegen. Ein bezahlter Tarif (ab ca. 5 $ im Monat) reicht für den täglichen Gebrauch.
2. Profil → **API Keys** → neuen Schlüssel erstellen und kopieren.
3. In ATLAS: *Einstellungen → Premium-Stimme* einschalten, Schlüssel einfügen, **Verbindung testen**, dann **Stimme probehören**.
4. Stimme wählen: „George“ (warm, britisch) oder „Daniel“ (ruhig, sachlich). Beide sprechen auch fließend Deutsch. Jede andere Stimme aus der ElevenLabs-Bibliothek lässt sich über ihre Stimmen-ID eintragen.
5. **Eigene Stimme erschaffen (empfohlen):** *Einstellungen → Premium-Stimme → Eigene Stimme erschaffen*. Beschreibung anpassen (z. B. tiefer, wärmer, jünger), **Stimmen entwerfen**, die Varianten anhören, eine auswählen, **Als ATLAS-Stimme verwenden**. Der Probetext mischt Deutsch und Englisch – so hören Sie sofort, dass englische Begriffe wie „Advanced Thinking“ ohne deutschen Akzent gesprochen werden. Die Stimme gehört nur Ihnen.

Der Schlüssel liegt wie der Claude-Schlüssel nur im Schlüsselbund des Geräts. Fällt ElevenLabs aus, spricht automatisch die Apple-Stimme weiter.

---

## Teil D – Schritt-für-Schritt-Tests

Bitte der Reihe nach testen und notieren, was nicht wie erwartet funktioniert.

### D1. Grundfunktionen
| # | Test | Erwartet |
|---|---|---|
| 1 | App öffnen | Lichtpunkte fliegen etwa 3 Sekunden über den Bildschirm, formen ein riesiges „A.T.L.A.S.“ (Blitz, Beben, Untertitel), dann zündet der blaue Kern. Er füllt den Bildschirm, unten eine schlanke Leiste. Mit dem Finger lässt sich der Kern drehen. Beim ersten Start Schlüssel-Eingabe. |
| 2 | Schlüssel speichern | Lange auf den Kern drücken → Einstellungen → *Claude API*: „sicher gespeichert“. |
| 3 | Mikrofon in der Leiste antippen (oder auf den Kern) | Fragen nach **Spracherkennung** und **Mikrofon** → erlauben. |
| 4 | „Wer bist du?“ | Status „Hört zu“, das Klangfeld des Kerns folgt Ihrer Stimme, Text erscheint live. Nach der Pause „Denkt nach“ (Kern dreht schneller, Analyse-Strahl), dann spricht ATLAS – der Kern pulsiert und sendet Schallwellen aus. |
| 5 | Gesprächsmodus | Nach der Antwort hört ATLAS automatisch weiter zu. |
| 6 | „Danke, das ist alles.“ | „Sehr wohl, Sir.“ → Bereit. |
| 7 | Unterbrechen | Lange Frage stellen, während der Antwort auf den Kern tippen → ATLAS verstummt und hört zu. |
| 8 | Tippen | In die Leiste „Rechne 15 % von 2.340 €“ → 351 €. |
| 9 | „Öffne die Einstellungen.“ | ATLAS bestätigt und öffnet die Einstellungen. Ebenso: „Zeig mir meinen Verlauf“, „Öffne mein Gedächtnis“, „Öffne das Stimmen-Studio“. |

### D2. Wake-Word & Siri
| # | Test | Erwartet |
|---|---|---|
| 10 | „Schalte das Wake-Word ein.“ | ATLAS bestätigt; der Kern wartet nun auf „Atlas“. |
| 11 | „Atlas.“ | „Ja, Sir?“ → hört zu. |
| 12 | „Atlas, wie spät ist es?“ | Antwortet direkt ohne Zwischenfrage. |
| 13 | App in den Hintergrund | Mikrofon aus (kein oranger Punkt). Beim Zurückkehren wieder Bereitschaft. |
| 14 | „Siri, starte ATLAS“ | ATLAS öffnet sich und hört sofort zu. *(Beim ersten Mal kann Siri bis zu einigen Minuten brauchen, bis sie die neuen Befehle kennt.)* |
| 15 | „Siri, frag ATLAS“ → „Was ist die Hauptstadt von Kanada?“ | Siri liest die Antwort vor, ohne die App zu öffnen. |
| 16 | Kurzbefehle-App → „ATLAS starten“ | Aktion vorhanden; auf dem iPhone 15 Pro: *Einstellungen → Action-Button → Kurzbefehl → ATLAS starten*. |

### D3. iPhone-Funktionen
| # | Test | Erwartet |
|---|---|---|
| 17 | „Was steht heute in meinem Kalender?“ | Frage nach Kalenderzugriff → erlauben; ATLAS nennt Ihre Termine. Status zeigt „Prüft Ihren Kalender“. |
| 18 | „Trag mir morgen um 15 Uhr Kaffee mit Max ein.“ | Termin steht im Kalender; Eintrag in *Einstellungen → Aktivitäten*. |
| 19 | „Erinnere mich morgen an meinen Termin.“ | ATLAS fragt nach der Uhrzeit. „Um 8 Uhr.“ → Erinnerung angelegt. |
| 20 | „Setz Milch, Eier und Brot auf die Einkaufsliste.“ | Liste „Einkaufsliste“ mit drei Einträgen in Apple Erinnerungen. |
| 21 | „Zeig mir den Weg nach Hamburg.“ | Apple Karten öffnet die Route. |
| 22 | „Wie wird das Wetter hier morgen?“ | Standortfrage → erlauben; Wetter für Ihren Ort. |
| 23 | „Bereite eine Nachricht an [Name aus Kontakten] vor, dass ich später komme.“ | Bestätigungskarte mit Entwurf. „Ja“ sagen → Nachrichten-App öffnet sich mit Text; **nichts wird automatisch gesendet**. |
| 24 | „Mach ein Foto.“ → Foto aufnehmen → „Was siehst du?“ | Beschreibung des Fotos. |
| 25 | „Öffne eine Datei.“ → PDF wählen → „Fasse sie zusammen.“ | Kurze Zusammenfassung. |

### D4. Gedächtnis, Aufgaben, Proaktiv
| # | Test | Erwartet |
|---|---|---|
| 26 | „Merk dir, dass ich montags und donnerstags trainiere.“ | Eintrag unter *Einstellungen → Gedächtnis*. |
| 27 | „Zeig mir meinen Verlauf“ → Neues Gespräch → „Wann trainiere ich?“ | ATLAS weiß es. |
| 28 | „Vergiss das mit dem Training.“ | Bestätigungskarte → „Ja“ → Eintrag gelöscht. |
| 29 | „Zeig mir meine Aufgaben.“ | Termine heute/morgen, offene Erinnerungen; antippen hakt ab. |
| 30 | „Organisiere meinen morgigen Tag.“ | Plan mit Uhrzeiten auf Basis Ihrer Termine und Aufgaben. |
| 31 | „Schick mir die Tagesübersicht jeden Morgen um 7:00.“ | ATLAS stellt es ein; zur Uhrzeit kommt eine Mitteilung, Antippen öffnet die Übersicht. |
| 32 | „Öffne die Berechtigungen.“ | Übersicht aller Freigaben mit Erklärung. |

### D5. Mac
| # | Test | Erwartet |
|---|---|---|
| 33 | Ziel „My Mac“ → ▶︎ | ATLAS-Fenster mit dem 3D-Kern. |
| 34 | ⌘L, Frage stellen | Wie auf dem iPhone; Mikrofon-Freigabe beim ersten Mal. |
| 35 | Menü **ATLAS → Tagesübersicht** | Übersicht wird gesprochen. |

**Tipp für eine natürlichere Stimme:** iPhone: Einstellungen → Bedienungshilfen → Gesprochene Inhalte → Stimmen → Deutsch bzw. Englisch → eine **Premium**- oder **Erweitert**-Stimme laden (britischer Butler: Englisch (UK) „Daniel“). Mac: Systemeinstellungen → Bedienungshilfen → Gesprochene Inhalte → Systemstimme → Stimmen verwalten. Danach in ATLAS unter *Einstellungen → Stimme* wählen.

---

## Teil E – Optional: iCloud-Synchronisierung iPhone ⇄ Mac

Gespräche, Gedächtnis und Aktivitäten können automatisch zwischen iPhone und Mac synchronisiert werden. Voraussetzung: **Apple Developer Program** (bezahlt).

1. Xcode → Target **ATLAS** → **Signing & Capabilities** → **+ Capability** → **iCloud**.
2. Unter *Services* **CloudKit** anhaken, bei *Containers* auf **+** → `iCloud.de.IhrNachname.atlas`.
3. **+ Capability** → **Background Modes** → **Remote notifications** anhaken (nur iPhone).
4. App neu auf iPhone **und** Mac installieren. Beide Geräte mit derselben Apple-ID in iCloud angemeldet.

Der Code ist dafür bereits vorbereitet – mehr ist nicht nötig. Der API-Schlüssel wird bewusst **nicht** synchronisiert.

---

## Projektstruktur

```
ATLAS/
├── ATLAS.xcodeproj               Xcode-Projekt (iPhone + Mac)
├── Config/
│   ├── Info.plist                Begründungstexte für Berechtigungen
│   └── ATLAS-macOS.entitlements  Mac-Sandbox-Freigaben
├── README.md                     Diese Anleitung
├── docs/ARCHITEKTUR.md           Technische Planung & Fahrplan
└── ATLAS/                        Quellcode
    ├── App/                      Einstieg, Siri/Kurzbefehle, Anfrage-Router
    ├── Core/
    │   ├── AI/                   Claude-Anbindung, Persönlichkeit, Anhänge
    │   ├── Conversation/         Gesprächssteuerung (Wake-Word, Zuhören, Antworten)
    │   ├── Speech/               Spracherkennung & Sprachausgabe
    │   ├── Tools/                Kalender, Erinnerungen, Kontakte, Standort, Karten, Nachrichten, Gedächtnis
    │   ├── Proactive/            Tagesübersicht per Mitteilung
    │   ├── Persistence/          Verlauf, Gedächtnis, Aktivitäten (SwiftData)
    │   ├── Security/             Schlüsselbund
    │   ├── Settings/             Einstellungen
    │   └── Platform/             Unterschiede iPhone/Mac
    ├── UI/                       ATLAS-Kern, Startbildschirm, Einstellungen, Gedächtnis, Aufgaben …
    └── Assets.xcassets           App-Symbol (iPhone + Mac)
```
