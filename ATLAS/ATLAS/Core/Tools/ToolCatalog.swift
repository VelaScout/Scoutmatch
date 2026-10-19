import Foundation

/// Beschreibung aller Werkzeuge, die ATLAS dem Sprachmodell anbietet.
/// Die Beschreibungen sagen dem Modell genau, WANN es ein Werkzeug benutzen soll.
enum ToolCatalog {
    static func definitionsJSON(memoryEnabled: Bool) -> Data? {
        var tools = baseTools
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
        case "remember": return "Merkt sich das"
        case "forget": return "Vergisst das"
        case "list_memories": return "Durchsucht das Gedächtnis"
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
            "description": "Bereitet eine SMS/iMessage oder E-Mail vor. Der Nutzer sieht den Entwurf, muss ihn bestätigen und sendet ihn dann selbst – ATLAS sendet nie selbstständig. Benutze dies bei „schreib …“, „bereite eine Nachricht an … vor“. Ermittle die Nummer oder Adresse vorher mit search_contacts.",
            "input_schema": object([
                "channel": ["type": "string", "enum": ["message", "email"], "description": "message = SMS/iMessage, email = E-Mail."],
                "recipient_name": string("Name des Empfängers."),
                "recipient_address": string("Telefonnummer oder E-Mail-Adresse (optional, sonst wählt der Nutzer)."),
                "subject": string("Betreff (nur E-Mail, optional)."),
                "body": string("Text der Nachricht."),
            ], required: ["channel", "body"]),
        ],
    ]

    private static let memoryTools: [[String: Any]] = [
        [
            "name": "remember",
            "description": "Speichert eine Information dauerhaft im Gedächtnis von ATLAS. Benutze dies NUR, wenn der Nutzer ausdrücklich darum bittet („merk dir …“, „vergiss nicht, dass …“) oder einem Vorschlag zum Merken zugestimmt hat. Formuliere den Eintrag als kurzen, eigenständigen Satz.",
            "input_schema": object([
                "content": string("Die zu merkende Information als vollständiger Satz, z. B. „Die Frau des Nutzers heißt Anna.“"),
                "category": ["type": "string", "enum": MemoryCategory.allCases.map(\.rawValue), "description": "Kategorie."],
            ], required: ["content", "category"]),
        ],
        [
            "name": "forget",
            "description": "Löscht Einträge aus dem Gedächtnis. Benutze dies, wenn der Nutzer möchte, dass ATLAS etwas vergisst. Der Nutzer muss das Löschen bestätigen.",
            "input_schema": object([
                "query": string("Suchbegriff, der die zu löschenden Einträge beschreibt."),
            ], required: ["query"]),
        ],
        [
            "name": "list_memories",
            "description": "Listet die gespeicherten Gedächtniseinträge auf. Benutze dies, wenn der Nutzer fragt, was ATLAS über ihn weiß.",
            "input_schema": object([:]),
        ],
    ]
}
