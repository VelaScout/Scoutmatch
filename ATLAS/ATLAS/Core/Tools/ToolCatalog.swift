import Foundation

/// Beschreibung aller Werkzeuge, die ATLAS dem Sprachmodell anbietet.
/// Die Beschreibungen sagen dem Modell genau, WANN es ein Werkzeug benutzen soll.
enum ToolCatalog {
    /// - Parameter deviceTools: Kalender, Erinnerungen, Kontakte usw. (abschaltbar);
    ///   die App-Steuerung ist immer verfügbar – sie ersetzt die Knöpfe der Oberfläche.
    static func definitionsJSON(memoryEnabled: Bool, deviceTools: Bool) -> Data? {
        var tools = appTools
        if deviceTools { tools += baseTools }
        if memoryEnabled { tools += memoryTools }
        return try? JSONSerialization.data(withJSONObject: tools)
    }

    /// Kurzer, gesprochener Statustext, während ein Werkzeug läuft.
    static func statusText(for name: String) -> String {
        switch name {
        case "get_calendar_events": return "Prüft Ihren Kalender"
        case "create_calendar_event": return "Trägt den Termin ein"
        case "list_reminders": return "Prüft Ihre Erinnerungen"
        case "create_reminder": return "Legt die Erinnerung an"
        case "complete_reminder": return "Hakt die Aufgabe ab"
        case "search_contacts": return "Sucht im Adressbuch"
        case "get_current_location": return "Bestimmt Ihren Standort"
        case "show_route": return "Öffnet die Route"
        case "prepare_message": return "Bereitet die Nachricht vor"
        case "set_timer": return "Stellt den Timer"
        case "manage_timers": return "Prüft Ihre Timer"
        case "run_shortcut": return "Startet den Kurzbefehl"
        case "open_link": return "Öffnet den Link"
        case "call_phone": return "Bereitet den Anruf vor"
        case "copy_to_clipboard": return "Kopiert den Text"
        case "list_emails": return "Prüft Ihr Postfach"
        case "read_email": return "Liest die E-Mail"
        case "send_email": return "Bereitet die E-Mail vor"
        case "spotify_play": return "Startet die Musik"
        case "spotify_control": return "Steuert Spotify"
        case "spotify_now_playing": return "Prüft, was läuft"
        case "remember": return "Merkt sich das"
        case "forget": return "Vergisst das"
        case "list_memories": return "Durchsucht das Gedächtnis"
        case "open_view": return "Öffnet die Ansicht"
        case "change_setting": return "Ändert die Einstellung"
        default: return "Arbeitet"
        }
    }

    private static func object(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required]
    }

    private static func string(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static let dateTimeHint = "Lokale Zeit im Format YYYY-MM-DDTHH:MM, z. B. 2026-10-20T08:00. Nur Datum: YYYY-MM-DD."

    private static let baseTools: [[String: Any]] = [
        [
            "name": "get_calendar_events",
            "description": "Liest Termine aus dem Kalender des Nutzers. Benutze dies, wenn der Nutzer nach seinen Terminen, seinem Tag, seiner Woche, freien Zeiten fragt oder einen Tagesplan bzw. eine Tagesübersicht möchte.",
            "input_schema": object([
                "start_date": string("Erster Tag, Format YYYY-MM-DD."),
                "days": ["type": "integer", "description": "Anzahl Tage ab start_date (1–31).", "minimum": 1, "maximum": 31],
            ], required: ["start_date"]),
        ],
        [
            "name": "create_calendar_event",
            "description": "Trägt einen neuen Termin in den Kalender ein. Benutze dies, wenn der Nutzer ausdrücklich einen Termin eintragen, planen oder blocken möchte. Frage vorher nach, wenn Datum oder Uhrzeit fehlen.",
            "input_schema": object([
                "title": string("Titel des Termins."),
                "start": string("Beginn. " + dateTimeHint),
                "end": string("Ende (optional, Standard: eine Stunde nach Beginn). " + dateTimeHint),
                "all_day": ["type": "boolean", "description": "Ganztägiger Termin."],
                "location": string("Ort (optional)."),
                "notes": string("Notizen (optional)."),
            ], required: ["title", "start"]),
        ],
        [
            "name": "list_reminders",
            "description": "Liest offene Erinnerungen und Aufgaben (Apple Erinnerungen). Benutze dies für Fragen nach offenen Aufgaben, Einkaufslisten, To-dos oder für Tagesplanung.",
            "input_schema": object([
                "list_name": string("Nur diese Liste, z. B. „Einkaufsliste“ (optional)."),
            ]),
        ],
        [
            "name": "create_reminder",
            "description": "Legt eine Erinnerung bzw. Aufgabe an, optional mit Fälligkeit (dann erinnert das iPhone zur Uhrzeit). Benutze dies für „erinnere mich …“, „notiere …“ oder für Einträge auf Listen wie der Einkaufsliste (dann list_name angeben, je Artikel ein Aufruf). Frage nach der Uhrzeit, wenn der Nutzer eine zeitliche Erinnerung möchte, aber keine Uhrzeit nennt.",
            "input_schema": object([
                "title": string("Was erinnert werden soll."),
                "due": string("Fälligkeit (optional). " + dateTimeHint),
                "list_name": string("Name der Liste (optional), z. B. „Einkaufsliste“. Wird angelegt, falls nicht vorhanden."),
                "notes": string("Notizen (optional)."),
            ], required: ["title"]),
        ],
        [
            "name": "complete_reminder",
            "description": "Markiert eine offene Erinnerung als erledigt. Benutze dies, wenn der Nutzer sagt, dass etwas erledigt ist.",
            "input_schema": object([
                "title": string("Titel oder Teil des Titels der Erinnerung."),
            ], required: ["title"]),
        ],
        [
            "name": "search_contacts",
            "description": "Sucht Kontakte im Adressbuch nach Namen und liefert Telefonnummern und E-Mail-Adressen. Benutze dies, bevor du eine Nachricht an eine Person vorbereitest oder wenn nach Kontaktdaten gefragt wird.",
            "input_schema": object([
                "name": string("Vor- und/oder Nachname."),
            ], required: ["name"]),
        ],
        [
            "name": "get_current_location",
            "description": "Ermittelt den aktuellen Standort (Adresse/Ort). Benutze dies, wenn der Standort für die Antwort nötig ist, z. B. Wetter „hier“, Restaurants in der Nähe oder Fahrzeit von hier.",
            "input_schema": object([:]),
        ],
        [
            "name": "show_route",
            "description": "Öffnet Apple Karten mit einer Route zum Ziel. Benutze dies bei „zeig mir den Weg nach …“, „navigiere zu …“.",
            "input_schema": object([
                "destination": string("Ziel als Adresse oder Ort."),
                "mode": ["type": "string", "enum": ["driving", "walking", "transit"], "description": "Verkehrsmittel, Standard driving."],
            ], required: ["destination"]),
        ],
        [
            "name": "prepare_message",
            "description": "Bereitet eine SMS/iMessage, WhatsApp-Nachricht oder E-Mail vor. Der Nutzer sieht den Entwurf, muss ihn bestätigen und sendet ihn dann selbst – A.T.L.A.S. sendet nie selbstständig. Benutze dies bei „schreib …“, „bereite eine Nachricht an … vor“. Ermittle die Nummer oder Adresse vorher mit search_contacts.",
            "input_schema": object([
                "channel": ["type": "string", "enum": ["message", "whatsapp", "email"], "description": "message = SMS/iMessage, whatsapp = WhatsApp, email = E-Mail."],
                "recipient_name": string("Name des Empfängers."),
                "recipient_address": string("Telefonnummer oder E-Mail-Adresse (optional, sonst wählt der Nutzer)."),
                "subject": string("Betreff (nur E-Mail, optional)."),
                "body": string("Text der Nachricht."),
            ], required: ["channel", "body"]),
        ],
        [
            "name": "set_timer",
            "description": "Stellt einen Timer bzw. Kurzzeitwecker, der mit Ton und Mitteilung meldet, wenn die Zeit um ist – auch wenn A.T.L.A.S. nicht geöffnet ist. Benutze dies bei „stell einen Timer auf …“, „weck mich in 20 Minuten“, „sag mir in einer Stunde Bescheid“. Für Erinnerungen zu einer festen Uhrzeit an einem Tag nimm create_reminder.",
            "input_schema": object([
                "seconds": ["type": "integer", "description": "Dauer in Sekunden (mindestens 5, höchstens 86400).", "minimum": 5, "maximum": 86400],
                "label": string("Kurze Bezeichnung, z. B. „Pizza“ oder „Pause vorbei“ (optional)."),
            ], required: ["seconds"]),
        ],
        [
            "name": "manage_timers",
            "description": "Listet laufende Timer auf oder bricht alle ab. Benutze dies bei „wie lange läuft mein Timer noch?“ oder „stopp den Timer“.",
            "input_schema": object([
                "action": ["type": "string", "enum": ["list", "cancel_all"], "description": "list = anzeigen, cancel_all = alle abbrechen."],
            ], required: ["action"]),
        ],
        [
            "name": "run_shortcut",
            "description": "Startet einen Apple-Kurzbefehl (App „Kurzbefehle“) des Nutzers über seinen Namen. Damit kann A.T.L.A.S. fast alles steuern, was Kurzbefehle können: Licht und Smart Home, Musik, Notizen, Fokus-Modi, Apps anderer Anbieter. Benutze dies, wenn der Nutzer einen Kurzbefehl nennt oder eine Aufgabe möchte, für die er einen Kurzbefehl hat (z. B. aus dem Gedächtnis). Der Nutzer bestätigt vor dem Start.",
            "input_schema": object([
                "name": string("Exakter Name des Kurzbefehls, z. B. „Licht aus“."),
                "input": string("Text, der an den Kurzbefehl übergeben wird (optional)."),
            ], required: ["name"]),
        ],
        [
            "name": "open_link",
            "description": "Öffnet eine Webseite oder einen App-Link (https), z. B. eine Suche bei YouTube, einen Song bei Apple Music oder Spotify, eine Seite für Tickets oder Bestellungen. Benutze dies bei „öffne …“, „zeig mir … im Browser“, „spiel … auf YouTube“. Kaufe oder bestelle niemals selbst – der Nutzer erledigt das auf der geöffneten Seite.",
            "input_schema": object([
                "url": string("Vollständige https-Adresse."),
                "title": string("Kurze Beschreibung, was geöffnet wird."),
            ], required: ["url"]),
        ],
        [
            "name": "call_phone",
            "description": "Bereitet einen Anruf vor (iPhone-Telefon, auf dem Mac über FaceTime/iPhone). Der Nutzer bestätigt vorher. Benutze dies bei „ruf … an“. Ermittle die Nummer mit search_contacts, falls nur ein Name genannt wird.",
            "input_schema": object([
                "recipient_name": string("Name der Person (optional)."),
                "number": string("Telefonnummer (optional, sonst aus den Kontakten)."),
            ]),
        ],
        [
            "name": "copy_to_clipboard",
            "description": "Kopiert Text in die Zwischenablage, damit der Nutzer ihn überall einfügen kann. Benutze dies, wenn der Nutzer einen Text, eine E-Mail, einen Beitrag oder eine Zusammenfassung „zum Kopieren“ möchte oder sagt „kopier das“.",
            "input_schema": object([
                "text": string("Der vollständige Text."),
            ], required: ["text"]),
        ],
        [
            "name": "list_emails",
            "description": "Listet E-Mails aus dem Posteingang des verbundenen Postfachs (Absender, Betreff, Datum, gelesen/ungelesen, id). Benutze dies bei „habe ich neue Mails?“, „was ist in meinem Postfach?“, „hat mir X geschrieben?“. Fasse das Ergebnis kurz gesprochen zusammen, statt alles vorzulesen.",
            "input_schema": object([
                "unread_only": ["type": "boolean", "description": "Nur ungelesene (Standard true). false = alle der letzten 14 Tage."],
                "count": ["type": "integer", "description": "Wie viele höchstens (1–25, Standard 10).", "minimum": 1, "maximum": 25],
            ]),
        ],
        [
            "name": "read_email",
            "description": "Liest den vollständigen Inhalt einer E-Mail (id aus list_emails) und markiert sie als gelesen. Benutze dies, wenn der Nutzer wissen will, was in einer Mail steht, oder bevor du sie beantwortest.",
            "input_schema": object([
                "id": ["type": "integer", "description": "Die id der E-Mail aus list_emails."],
            ], required: ["id"]),
        ],
        [
            "name": "send_email",
            "description": "Sendet eine E-Mail aus dem verbundenen Postfach – als neue Mail oder als Antwort (reply_to_id). Der Nutzer sieht vorher Empfänger, Betreff und Text und muss ausdrücklich bestätigen; erst dann wird gesendet. Formuliere den Text im Namen des Nutzers, passend zum Ton der Unterhaltung, mit Gruß und seinem Namen, falls bekannt. Ohne verbundenes Postfach nimm prepare_message.",
            "input_schema": object([
                "to": string("Empfänger-Adresse(n), durch Komma getrennt. Bei Antworten optional (Standard: Absender der Original-Mail)."),
                "subject": string("Betreff. Bei Antworten optional (Standard: „Re: …“)."),
                "body": string("Der vollständige Text der E-Mail."),
                "reply_to_id": ["type": "integer", "description": "id der E-Mail, auf die geantwortet wird (optional)."],
            ], required: ["body"]),
        ],
        [
            "name": "spotify_play",
            "description": "Spielt Musik bei Spotify ab: einen Song, Künstler, ein Album, eine Playlist (zuerst die eigenen Playlists des Nutzers) oder seine Lieblingssongs. Benutze dies bei „spiel …“, „mach Musik an“, „ich will … hören“. Für Stimmungen („etwas zum Entspannen“) wähle selbst eine passende Playlist-Suche.",
            "input_schema": object([
                "query": string("Suchbegriff, z. B. „Blinding Lights The Weeknd“, „Coldplay“, „Lo-Fi Beats“. Bei kind=liked leer lassen."),
                "kind": ["type": "string", "enum": ["track", "artist", "album", "playlist", "liked"], "description": "Art der Musik. liked = Lieblingssongs des Nutzers."],
            ], required: ["kind"]),
        ],
        [
            "name": "spotify_control",
            "description": "Steuert die laufende Spotify-Wiedergabe: Pause, weiter, nächster/vorheriger Titel, lauter/leiser, Lautstärke setzen, Zufallswiedergabe.",
            "input_schema": object([
                "action": ["type": "string", "enum": ["pause", "resume", "next", "previous", "volume_up", "volume_down", "set_volume", "shuffle_on", "shuffle_off"], "description": "Die Aktion."],
                "volume": ["type": "integer", "description": "Lautstärke 0–100 (nur bei set_volume).", "minimum": 0, "maximum": 100],
            ], required: ["action"]),
        ],
        [
            "name": "spotify_now_playing",
            "description": "Sagt, welcher Song gerade bei Spotify läuft. Benutze dies bei „was läuft gerade?“, „wie heißt dieses Lied?“.",
            "input_schema": object([:]),
        ],
    ]

    /// App-Steuerung per Sprache – die App hat bewusst kaum Knöpfe.
    private static let appTools: [[String: Any]] = [
        [
            "name": "open_view",
            "description": "Öffnet eine Ansicht der A.T.L.A.S.-App. Die App hat bewusst keine Knöpfe – benutze dies immer, wenn der Nutzer etwas sehen, öffnen oder einstellen möchte: Einstellungen, Gesprächsverlauf, Termine/Aufgaben, Gedächtnis (auch zum Übertragen auf iPhone/Mac per AirDrop), Berechtigungen, Aktivitätsprotokoll, Stimmen-Studio (eigene Stimme), Verbindungen (E-Mail-Konto und Spotify einrichten), Foto auswählen, Foto aufnehmen (Kamera) oder eine Datei/PDF auswählen.",
            "input_schema": object([
                "view": ["type": "string", "enum": ["settings", "connections", "history", "tasks", "memory", "permissions", "activity", "voiceStudio", "photoPicker", "camera", "fileImporter"],
                         "description": "Die zu öffnende Ansicht."],
            ], required: ["view"]),
        ],
        [
            "name": "change_setting",
            "description": "Ändert eine Einstellung von A.T.L.A.S. direkt per Zuruf, z. B. „schalte das Wake-Word ein“, „sprich schneller“, „nenn mich nicht mehr Sir“, „antworte auf Englisch“, „nimm das schnellste Modell“. Bestätige danach kurz, was geändert wurde.",
            "input_schema": object([
                "setting": ["type": "string",
                            "enum": ["wake_word", "conversation_mode", "address_sir", "formal_address", "web_search", "premium_voice", "device_tools", "memory", "speech_rate", "language", "model", "appearance", "morning_briefing", "evening_review"],
                            "description": "Welche Einstellung."],
                "value": string("Neuer Wert: on/off für Schalter; slower/faster/normal für speech_rate; de/en für language; die gewünschte Anrede (z. B. „Herr Velasco“, leer = keine) für formal_address; opus/sonnet/haiku für model; core/minimal für appearance; für morning_briefing/evening_review on/off oder eine Uhrzeit HH:MM."),
            ], required: ["setting", "value"]),
        ],
    ]

    private static let memoryTools: [[String: Any]] = [
        [
            "name": "remember",
            "description": "Speichert eine Information dauerhaft im Gedächtnis von A.T.L.A.S. Benutze dies, wenn der Nutzer darum bittet („merk dir …“), und – sofern laut Systemanweisung selbstständiges Lernen aktiv ist – auch von selbst, wenn du etwas dauerhaft Nützliches über ihn erfährst (Vorliebe, Gewohnheit, Ziel, wichtige Person). Niemals Passwörter oder Zugangsdaten. Formuliere den Eintrag als kurzen, eigenständigen Satz.",
            "input_schema": object([
                "content": string("Die zu merkende Information als vollständiger Satz, z. B. „Die Frau des Nutzers heißt Anna.“"),
                "category": ["type": "string", "enum": MemoryCategory.allCases.map(\.rawValue), "description": "Kategorie."],
            ], required: ["content", "category"]),
        ],
        [
            "name": "forget",
            "description": "Löscht Einträge aus dem Gedächtnis. Benutze dies, wenn der Nutzer möchte, dass A.T.L.A.S. etwas vergisst. Der Nutzer muss das Löschen bestätigen.",
            "input_schema": object([
                "query": string("Suchbegriff, der die zu löschenden Einträge beschreibt."),
            ], required: ["query"]),
        ],
        [
            "name": "list_memories",
            "description": "Listet die gespeicherten Gedächtniseinträge auf. Benutze dies, wenn der Nutzer fragt, was A.T.L.A.S. über ihn weiß.",
            "input_schema": object([:]),
        ],
    ]
}
