import Foundation
import SwiftData

/// Eine Aktion, die der Nutzer vor der Ausführung bestätigen muss.
struct ConfirmationRequest: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
    let confirmLabel: String
    /// Kurzer Satz, den ATLAS vorliest.
    let spokenPrompt: String
}

/// Führt die Werkzeuge aus, die Claude anfordert – mit Berechtigungsabfrage,
/// Bestätigung bei sensiblen Aktionen und lückenlosem Aktivitätsprotokoll.
@MainActor
final class AtlasToolbox: ToolExecuting {
    private let modelContext: ModelContext
    private let settings: AppSettings
    private let eventKit = EventKitService.shared
    private let contacts = ContactsService.shared
    private let location = LocationService.shared

    /// Wird von der Gesprächssteuerung gesetzt: zeigt die Bestätigung an und liefert die Antwort.
    var confirm: ((ConfirmationRequest) async -> Bool)?
    /// Wird von der Gesprächssteuerung gesetzt: öffnet eine Ansicht der App.
    var openScreen: ((AppScreen) -> Void)?
    /// Geräte-Werkzeuge, die in den Einstellungen abgeschaltet werden können.
    private static let deviceToolNames: Set<String> = [
        "get_calendar_events", "create_calendar_event", "list_reminders", "create_reminder", "complete_reminder",
        "search_contacts", "get_current_location", "show_route", "prepare_message",
    ]

    init(modelContext: ModelContext, settings: AppSettings) {
        self.modelContext = modelContext
        self.settings = settings
    }

    func execute(name: String, inputJSON: Data) async -> ToolResult {
        let input = (try? JSONSerialization.jsonObject(with: inputJSON) as? [String: Any]) ?? [:]
        if Self.deviceToolNames.contains(name), !settings.toolsEnabled {
            return ToolResult(content: "Die Geräte-Funktionen sind ausgeschaltet. Der Nutzer kann sie mit „Schalte die Geräte-Funktionen ein“ aktivieren.", isError: true)
        }
        let result: ToolResult
        switch name {
        case "open_view": result = openView(input)
        case "change_setting": result = await changeSetting(input)
        case "get_calendar_events": result = await getCalendarEvents(input)
        case "create_calendar_event": result = await createCalendarEvent(input)
        case "list_reminders": result = await listReminders(input)
        case "create_reminder": result = await createReminder(input)
        case "complete_reminder": result = await completeReminder(input)
        case "search_contacts": result = await searchContacts(input)
        case "get_current_location": result = await currentLocation()
        case "show_route": result = showRoute(input)
        case "prepare_message": result = await prepareMessage(input)
        case "remember": result = remember(input)
        case "forget": result = await forget(input)
        case "list_memories": result = listMemories()
        default: result = ToolResult(content: "Unbekanntes Werkzeug: \(name)", isError: true)
        }
        return result
    }

    // MARK: - Kalender

    private func getCalendarEvents(_ input: [String: Any]) async -> ToolResult {
        guard await eventKit.requestCalendarAccess() else { return denied("Kalender") }
        let start = DateParsing.date(from: input["start_date"] as? String) ?? .now
        let days = (input["days"] as? Int) ?? 1
        let events = eventKit.events(from: start, days: days)
        log("Kalender gelesen", "\(events.count) Termine ab \(DateParsing.dayString(start))")
        guard !events.isEmpty else {
            return ToolResult(content: "Keine Termine im Zeitraum \(DateParsing.dayString(start)) für \(days) Tag(e).")
        }
        let lines = events.map { event -> String in
            let time = event.isAllDay ? "ganztägig"
                : "\(DateParsing.timeString(event.start))–\(DateParsing.timeString(event.end))"
            var line = "\(DateParsing.dayString(event.start)) \(time): \(event.title)"
            if let location = event.location { line += " (Ort: \(location))" }
            return line
        }
        return ToolResult(content: lines.joined(separator: "\n"))
    }

    private func createCalendarEvent(_ input: [String: Any]) async -> ToolResult {
        guard let title = input["title"] as? String, let startText = input["start"] as? String,
              let start = DateParsing.date(from: startText) else {
            return ToolResult(content: "Titel oder Beginn fehlt bzw. ist ungültig.", isError: true)
        }
        guard await eventKit.requestCalendarAccess() else { return denied("Kalender") }
        let allDay = (input["all_day"] as? Bool) ?? !startText.contains("T")
        let end = DateParsing.date(from: input["end"] as? String)
        do {
            let event = try eventKit.createEvent(title: title, start: start, end: end, allDay: allDay,
                                                 location: input["location"] as? String,
                                                 notes: input["notes"] as? String)
            let when = allDay ? DateParsing.dayString(event.start)
                : "\(DateParsing.dayString(event.start)) um \(DateParsing.timeString(event.start)) Uhr"
            log("Termin eingetragen", "\(title) – \(when)")
            return ToolResult(content: "Termin „\(title)“ am \(when) im Kalender „\(event.calendar)“ eingetragen.")
        } catch {
            log("Termin fehlgeschlagen", error.localizedDescription, succeeded: false)
            return ToolResult(content: "Fehler beim Eintragen: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Erinnerungen

    private func listReminders(_ input: [String: Any]) async -> ToolResult {
        guard await eventKit.requestRemindersAccess() else { return denied("Erinnerungen") }
        let reminders = await eventKit.openReminders(listName: input["list_name"] as? String)
        log("Erinnerungen gelesen", "\(reminders.count) offene Einträge")
        guard !reminders.isEmpty else { return ToolResult(content: "Keine offenen Erinnerungen.") }
        let lines = reminders.prefix(60).map { reminder -> String in
            var line = "[\(reminder.list)] \(reminder.title)"
            if let due = reminder.due { line += " – fällig \(DateParsing.dayString(due)) \(DateParsing.timeString(due))" }
            return line
        }
        return ToolResult(content: lines.joined(separator: "\n"))
    }

    private func createReminder(_ input: [String: Any]) async -> ToolResult {
        guard let title = input["title"] as? String, !title.isEmpty else {
            return ToolResult(content: "Titel fehlt.", isError: true)
        }
        guard await eventKit.requestRemindersAccess() else { return denied("Erinnerungen") }
        let due = DateParsing.date(from: input["due"] as? String)
        do {
            let list = try eventKit.createReminder(title: title, due: due, listName: input["list_name"] as? String,
                                                   notes: input["notes"] as? String)
            let when = due.map { " für \(DateParsing.dayString($0)) um \(DateParsing.timeString($0)) Uhr" } ?? ""
            log("Erinnerung angelegt", "\(title)\(when) – Liste \(list)")
            return ToolResult(content: "Erinnerung „\(title)“\(when) in der Liste „\(list)“ angelegt.")
        } catch {
            log("Erinnerung fehlgeschlagen", error.localizedDescription, succeeded: false)
            return ToolResult(content: "Fehler: \(error.localizedDescription)", isError: true)
        }
    }

    private func completeReminder(_ input: [String: Any]) async -> ToolResult {
        guard let title = input["title"] as? String else { return ToolResult(content: "Titel fehlt.", isError: true) }
        guard await eventKit.requestRemindersAccess() else { return denied("Erinnerungen") }
        do {
            guard let done = try await eventKit.completeReminder(matching: title) else {
                return ToolResult(content: "Keine offene Erinnerung passend zu „\(title)“ gefunden.", isError: true)
            }
            log("Erinnerung erledigt", done)
            return ToolResult(content: "„\(done)“ als erledigt markiert.")
        } catch {
            return ToolResult(content: "Fehler: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Kontakte, Standort, Karten

    private func searchContacts(_ input: [String: Any]) async -> ToolResult {
        guard let name = input["name"] as? String, !name.isEmpty else {
            return ToolResult(content: "Name fehlt.", isError: true)
        }
        guard await contacts.requestAccess() else { return denied("Kontakte") }
        let found = await contacts.search(name: name)
        log("Kontakte durchsucht", name)
        guard !found.isEmpty else { return ToolResult(content: "Kein Kontakt namens „\(name)“ gefunden.") }
        let lines = found.map { contact in
            var line = contact.name
            if !contact.organization.isEmpty { line += " (\(contact.organization))" }
            if !contact.phones.isEmpty { line += " – Telefon: " + contact.phones.joined(separator: ", ") }
            if !contact.emails.isEmpty { line += " – E-Mail: " + contact.emails.joined(separator: ", ") }
            return line
        }
        return ToolResult(content: lines.joined(separator: "\n"))
    }

    private func currentLocation() async -> ToolResult {
        guard let place = await location.currentPlaceDescription() else {
            return location.authorized
                ? ToolResult(content: "Der Standort konnte gerade nicht bestimmt werden.", isError: true)
                : denied("Standort")
        }
        log("Standort bestimmt", place)
        return ToolResult(content: "Aktueller Standort: \(place)")
    }

    private func showRoute(_ input: [String: Any]) -> ToolResult {
        guard let destination = input["destination"] as? String, !destination.isEmpty else {
            return ToolResult(content: "Ziel fehlt.", isError: true)
        }
        let flag: String
        switch input["mode"] as? String {
        case "walking": flag = "w"
        case "transit": flag = "r"
        default: flag = "d"
        }
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [URLQueryItem(name: "daddr", value: destination), URLQueryItem(name: "dirflg", value: flag)]
        guard let url = components.url else { return ToolResult(content: "Ungültiges Ziel.", isError: true) }
        PlatformBridge.open(url)
        log("Route geöffnet", destination)
        return ToolResult(content: "Apple Karten wurde mit der Route nach \(destination) geöffnet.")
    }

    // MARK: - Nachrichten (immer mit Bestätigung, gesendet wird vom Nutzer)

    private func prepareMessage(_ input: [String: Any]) async -> ToolResult {
        guard let body = input["body"] as? String, !body.isEmpty else {
            return ToolResult(content: "Nachrichtentext fehlt.", isError: true)
        }
        let isEmail = (input["channel"] as? String) == "email"
        let name = input["recipient_name"] as? String ?? ""
        var address = (input["recipient_address"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        if address.isEmpty, !name.isEmpty {
            address = await contacts.firstAddress(for: name, email: isEmail) ?? ""
        }

        let recipient = [name, address.isEmpty ? nil : "(\(address))"].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " ")
        let request = ConfirmationRequest(
            title: isEmail ? "E-Mail vorbereiten" : "Nachricht vorbereiten",
            detail: "An: \(recipient.isEmpty ? "– bitte in der App wählen –" : recipient)\n\n\(body)",
            confirmLabel: isEmail ? "In Mail öffnen" : "In Nachrichten öffnen",
            spokenPrompt: "Soll ich den Entwurf öffnen? Bitte bestätigen Sie.")

        guard await askConfirmation(request) else {
            log("Nachricht verworfen", recipient, succeeded: false)
            return ToolResult(content: "Der Nutzer hat den Entwurf abgelehnt. Nichts wurde geöffnet oder gesendet.")
        }

        let url: URL?
        if isEmail {
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = address
            components.queryItems = [URLQueryItem(name: "subject", value: input["subject"] as? String ?? ""),
                                     URLQueryItem(name: "body", value: body)]
            url = components.url
        } else {
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
            let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            let number = address.filter { "+0123456789".contains($0) }
            url = URL(string: "sms:\(number)&body=\(encoded)")
        }
        guard let url else { return ToolResult(content: "Der Entwurf konnte nicht geöffnet werden.", isError: true) }
        PlatformBridge.open(url)
        log(isEmail ? "E-Mail-Entwurf geöffnet" : "Nachrichtenentwurf geöffnet", recipient)
        return ToolResult(content: "Der Entwurf wurde geöffnet. Der Nutzer prüft und sendet ihn selbst – er ist noch NICHT gesendet.")
    }

    // MARK: - Gedächtnis

    private func remember(_ input: [String: Any]) -> ToolResult {
        guard settings.memoryEnabled else { return ToolResult(content: "Das Gedächtnis ist in den Einstellungen ausgeschaltet.", isError: true) }
        guard let content = (input["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            return ToolResult(content: "Inhalt fehlt.", isError: true)
        }
        let category = MemoryCategory(rawValue: input["category"] as? String ?? "") ?? .other
        modelContext.insert(MemoryItem(content: content, category: category))
        try? modelContext.save()
        log("Gemerkt", content)
        return ToolResult(content: "Gespeichert: \(content)")
    }

    private func forget(_ input: [String: Any]) async -> ToolResult {
        guard let query = (input["query"] as? String)?.trimmingCharacters(in: .whitespaces), !query.isEmpty else {
            return ToolResult(content: "Suchbegriff fehlt.", isError: true)
        }
        let items = (try? modelContext.fetch(FetchDescriptor<MemoryItem>())) ?? []
        let words = query.lowercased().split(separator: " ").map(String.init).filter { $0.count > 2 }
        let matches = items.filter { item in
            let text = item.content.lowercased()
            return text.contains(query.lowercased()) || (!words.isEmpty && words.allSatisfy { text.contains($0) })
        }
        guard !matches.isEmpty else { return ToolResult(content: "Kein passender Gedächtniseintrag gefunden.") }

        let request = ConfirmationRequest(
            title: "Aus dem Gedächtnis löschen",
            detail: matches.map { "• \($0.content)" }.joined(separator: "\n"),
            confirmLabel: "Löschen",
            spokenPrompt: matches.count == 1 ? "Soll ich diesen Eintrag löschen?" : "Soll ich diese \(matches.count) Einträge löschen?")
        guard await askConfirmation(request) else {
            return ToolResult(content: "Der Nutzer hat das Löschen abgelehnt. Nichts wurde gelöscht.")
        }
        for item in matches { modelContext.delete(item) }
        try? modelContext.save()
        log("Vergessen", "\(matches.count) Einträge gelöscht")
        return ToolResult(content: "\(matches.count) Eintrag/Einträge gelöscht.")
    }

    private func listMemories() -> ToolResult {
        let items = (try? modelContext.fetch(FetchDescriptor<MemoryItem>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        guard !items.isEmpty else { return ToolResult(content: "Das Gedächtnis ist leer.") }
        return ToolResult(content: items.map { "[\($0.category)] \($0.content)" }.joined(separator: "\n"))
    }

    // MARK: - App-Steuerung

    private func openView(_ input: [String: Any]) -> ToolResult {
        guard let raw = input["view"] as? String, let screen = AppScreen(rawValue: raw), screen != .onboarding else {
            return ToolResult(content: "Unbekannte Ansicht.", isError: true)
        }
        openScreen?(screen)
        return ToolResult(content: "Geöffnet: \(raw). Sag dazu nur einen sehr kurzen Satz.")
    }

    private func changeSetting(_ input: [String: Any]) async -> ToolResult {
        guard let setting = input["setting"] as? String, let rawValue = input["value"] as? String else {
            return ToolResult(content: "Einstellung oder Wert fehlt.", isError: true)
        }
        let value = rawValue.lowercased().trimmingCharacters(in: .whitespaces)
        let on = ["on", "an", "ein", "true", "ja", "yes", "1"].contains(value)
        let off = ["off", "aus", "false", "nein", "no", "0"].contains(value)
        func flag(_ apply: (Bool) -> Void) -> ToolResult? {
            guard on || off else { return ToolResult(content: "Bitte on oder off angeben.", isError: true) }
            apply(on)
            return nil
        }
        var error: ToolResult?
        switch setting {
        case "wake_word": error = flag { settings.wakeWordEnabled = $0 }
        case "conversation_mode": error = flag { settings.conversationMode = $0 }
        case "address_sir": error = flag { settings.addressAsSir = $0 }
        case "web_search": error = flag { settings.webSearchEnabled = $0 }
        case "premium_voice":
            if on && !KeychainStore.has(.elevenLabsAPIKey) {
                openScreen?(.settings)
                return ToolResult(content: "Für die Premium-Stimme fehlt noch der ElevenLabs-Schlüssel. Die Einstellungen wurden geöffnet, damit der Nutzer ihn eintragen kann.", isError: true)
            }
            error = flag { settings.premiumVoiceEnabled = $0 }
        case "device_tools": error = flag { settings.toolsEnabled = $0 }
        case "memory": error = flag { settings.memoryEnabled = $0 }
        case "speech_rate":
            switch value {
            case "slower", "langsamer": settings.speechRate = max(0.35, settings.speechRate - 0.05)
            case "faster", "schneller": settings.speechRate = min(0.65, settings.speechRate + 0.05)
            default: settings.speechRate = 0.5
            }
        case "language":
            settings.language = value.hasPrefix("en") ? .britishEnglish : .german
        case "model":
            if value.contains("haiku") { settings.model = .haiku }
            else if value.contains("sonnet") { settings.model = .sonnet }
            else { settings.model = .opus }
        case "appearance":
            settings.appearance = (value.contains("minimal") || value.contains("schlicht")) ? .core : .hologram
        case "morning_briefing", "evening_review":
            let isMorning = setting == "morning_briefing"
            if let minutes = Self.minutes(from: value) {
                if isMorning { settings.morningBriefingMinutes = minutes; settings.morningBriefingEnabled = true }
                else { settings.eveningReviewMinutes = minutes; settings.eveningReviewEnabled = true }
            } else {
                error = flag { enabled in
                    if isMorning { settings.morningBriefingEnabled = enabled } else { settings.eveningReviewEnabled = enabled }
                }
            }
            await ProactiveScheduler.reschedule(settings: settings)
        default:
            return ToolResult(content: "Unbekannte Einstellung: \(setting)", isError: true)
        }
        if let error { return error }
        log("Einstellung geändert", "\(setting) → \(rawValue)")
        return ToolResult(content: "Erledigt: \(setting) = \(rawValue).")
    }

    private static func minutes(from text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }

    // MARK: - Hilfen

    private func askConfirmation(_ request: ConfirmationRequest) async -> Bool {
        guard let confirm else { return false }
        return await confirm(request)
    }

    private func denied(_ what: String) -> ToolResult {
        ToolResult(content: "Kein Zugriff auf \(what). Der Nutzer muss den Zugriff für A.T.L.A.S. in den Einstellungen erlauben (A.T.L.A.S. → Einstellungen → Berechtigungen).",
                   isError: true)
    }

    private func log(_ title: String, _ detail: String, succeeded: Bool = true) {
        modelContext.insert(ActivityRecord(title: title, detail: detail, succeeded: succeeded))
        try? modelContext.save()
    }
}

/// Datumsangaben zwischen Modell (ISO-Format, lokale Zeit) und Anzeige.
enum DateParsing {
    static func date(from text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let formats = ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return ISO8601DateFormatter().date(from: text)
    }

    static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEEE, d. MMMM yyyy"
        return formatter.string(from: date)
    }

    static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
