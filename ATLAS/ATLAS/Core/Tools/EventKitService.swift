import EventKit
import Foundation

/// Zugriff auf Kalender und Erinnerungen (Apple EventKit).
@MainActor
final class EventKitService {
    static let shared = EventKitService()

    let store = EKEventStore()

    struct EventSummary: Identifiable, Sendable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let location: String?
        let calendar: String
    }

    struct ReminderSummary: Identifiable, Sendable {
        let id: String
        let title: String
        let due: Date?
        let list: String
        let notes: String?
    }

    // MARK: - Berechtigungen

    var calendarAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var remindersAuthorized: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    func requestCalendarAccess() async -> Bool {
        if calendarAuthorized { return true }
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return false }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    func requestRemindersAccess() async -> Bool {
        if remindersAuthorized { return true }
        guard EKEventStore.authorizationStatus(for: .reminder) == .notDetermined else { return false }
        return (try? await store.requestFullAccessToReminders()) ?? false
    }

    // MARK: - Kalender

    func events(from start: Date, days: Int) -> [EventSummary] {
        let startOfDay = Calendar.current.startOfDay(for: start)
        let end = Calendar.current.date(byAdding: .day, value: max(1, min(days, 31)), to: startOfDay) ?? startOfDay
        let predicate = store.predicateForEvents(withStart: startOfDay, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(80)
            .map {
                // Wiederkehrende Termine teilen sich die Kennung – Beginn macht sie eindeutig.
                EventSummary(id: "\($0.eventIdentifier ?? UUID().uuidString)-\($0.startDate.timeIntervalSince1970)",
                             title: $0.title ?? "(ohne Titel)",
                             start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay,
                             location: ($0.location?.isEmpty ?? true) ? nil : $0.location,
                             calendar: $0.calendar?.title ?? "")
            }
    }

    @discardableResult
    func createEvent(title: String, start: Date, end: Date?, allDay: Bool, location: String?, notes: String?) throws -> EventSummary {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end ?? (allDay ? start : start.addingTimeInterval(3600))
        event.isAllDay = allDay
        event.location = location
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent, commit: true)
        return EventSummary(id: event.eventIdentifier ?? "", title: title, start: event.startDate, end: event.endDate,
                            isAllDay: allDay, location: location, calendar: event.calendar?.title ?? "")
    }

    // MARK: - Erinnerungen

    func openReminders(listName: String? = nil) async -> [ReminderSummary] {
        var calendars: [EKCalendar]? = nil
        if let listName, !listName.isEmpty {
            let matches = store.calendars(for: .reminder).filter { $0.title.localizedCaseInsensitiveContains(listName) }
            if matches.isEmpty { return [] }
            calendars = matches
        }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        let summaries: [ReminderSummary] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let result = (reminders ?? []).map { reminder in
                    ReminderSummary(id: reminder.calendarItemIdentifier,
                                    title: reminder.title ?? "(ohne Titel)",
                                    due: reminder.dueDateComponents?.date
                                        ?? reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                                    list: reminder.calendar?.title ?? "",
                                    notes: reminder.notes)
                }
                continuation.resume(returning: result)
            }
        }
        return summaries.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    @discardableResult
    func createReminder(title: String, due: Date?, listName: String?, notes: String?) throws -> String {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = try reminderList(named: listName)
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        try store.save(reminder, commit: true)
        return reminder.calendar?.title ?? ""
    }

    /// Markiert die erste passende offene Erinnerung als erledigt; liefert ihren Titel.
    func completeReminder(matching text: String) async throws -> String? {
        let open = await openReminders()
        guard let match = open.first(where: { $0.title.localizedCaseInsensitiveCompare(text) == .orderedSame })
                ?? open.first(where: { $0.title.localizedCaseInsensitiveContains(text) }),
              let reminder = store.calendarItem(withIdentifier: match.id) as? EKReminder else { return nil }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
        return match.title
    }

    func completeReminder(id: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }

    private func reminderList(named name: String?) throws -> EKCalendar? {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return store.defaultCalendarForNewReminders()
        }
        if let existing = store.calendars(for: .reminder)
            .first(where: { $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = name
        list.source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local })
        try store.saveCalendar(list, commit: true)
        return list
    }
}
