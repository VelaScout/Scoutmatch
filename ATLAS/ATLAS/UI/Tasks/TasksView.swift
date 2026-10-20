import SwiftUI

/// Aufgabenübersicht: heutige und morgige Termine sowie offene Erinnerungen.
struct TasksView: View {
    @Environment(ConversationEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var events: [EventKitService.EventSummary] = []
    @State private var reminders: [EventKitService.ReminderSummary] = []
    @State private var calendarAllowed = EventKitService.shared.calendarAuthorized
    @State private var remindersAllowed = EventKitService.shared.remindersAuthorized

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        engine.handle(.briefing(.morning))
                        dismiss()
                    } label: {
                        Label("Tagesübersicht von A.T.L.A.S.", systemImage: "sun.horizon")
                    }
                    Button {
                        engine.handle(.briefing(.planTomorrow))
                        dismiss()
                    } label: {
                        Label("Morgen planen lassen", systemImage: "calendar.badge.clock")
                    }
                }

                Section("Termine heute und morgen") {
                    if !calendarAllowed {
                        Button("Zugriff auf Kalender erlauben") { Task { await requestAccess() } }
                    } else if events.isEmpty {
                        Text("Keine Termine.").foregroundStyle(.secondary)
                    }
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title)
                            Text(eventTime(event))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Offene Erinnerungen") {
                    if !remindersAllowed {
                        Button("Zugriff auf Erinnerungen erlauben") { Task { await requestAccess() } }
                    } else if reminders.isEmpty {
                        Text("Alles erledigt.").foregroundStyle(.secondary)
                    }
                    ForEach(reminders) { reminder in
                        HStack {
                            Button {
                                try? EventKitService.shared.completeReminder(id: reminder.id)
                                Task { await load() }
                            } label: {
                                Image(systemName: "circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Als erledigt markieren")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(reminder.title)
                                Text(reminderDetail(reminder))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Aufgaben")
            .atlasInlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private func requestAccess() async {
        calendarAllowed = await EventKitService.shared.requestCalendarAccess()
        remindersAllowed = await EventKitService.shared.requestRemindersAccess()
        await load()
    }

    private func load() async {
        let service = EventKitService.shared
        calendarAllowed = service.calendarAuthorized
        remindersAllowed = service.remindersAuthorized
        if calendarAllowed { events = service.events(from: .now, days: 2) }
        if remindersAllowed { reminders = await service.openReminders() }
    }

    private func eventTime(_ event: EventKitService.EventSummary) -> String {
        let day = Calendar.current.isDateInToday(event.start) ? "Heute" : "Morgen"
        if event.isAllDay { return "\(day), ganztägig" }
        var text = "\(day), \(DateParsing.timeString(event.start))–\(DateParsing.timeString(event.end))"
        if let location = event.location { text += " · \(location)" }
        return text
    }

    private func reminderDetail(_ reminder: EventKitService.ReminderSummary) -> String {
        guard let due = reminder.due else { return reminder.list }
        return "\(reminder.list) · fällig \(DateParsing.dayString(due)), \(DateParsing.timeString(due))"
    }
}
