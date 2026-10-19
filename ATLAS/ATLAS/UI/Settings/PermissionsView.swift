import AVFoundation
import Contacts
import CoreLocation
import EventKit
import Speech
import SwiftUI
import UserNotifications

/// Berechtigungsverwaltung: Was darf ATLAS – und warum?
struct PermissionsView: View {
    @State private var notificationsAllowed = false
    @State private var refresh = 0

    var body: some View {
        List {
            Section {
                row("Mikrofon", "mic", "Damit Sie mit ATLAS sprechen können.",
                    granted: AVAudioApplication.shared.recordPermission == .granted,
                    undetermined: AVAudioApplication.shared.recordPermission == .undetermined) {
                    _ = await AVAudioApplication.requestRecordPermission()
                }
                row("Spracherkennung", "waveform", "Wandelt Ihre Stimme – wenn möglich auf dem Gerät – in Text um.",
                    granted: SFSpeechRecognizer.authorizationStatus() == .authorized,
                    undetermined: SFSpeechRecognizer.authorizationStatus() == .notDetermined) {
                    _ = await SpeechRecognizer.requestPermissions()
                }
            } header: {
                Text("Sprache")
            }

            Section {
                row("Kalender", "calendar", "Termine lesen und auf Ihren Wunsch eintragen.",
                    granted: EventKitService.shared.calendarAuthorized,
                    undetermined: EKEventStore.authorizationStatus(for: .event) == .notDetermined) {
                    _ = await EventKitService.shared.requestCalendarAccess()
                }
                row("Erinnerungen", "checklist", "Aufgaben und Listen lesen, anlegen und abhaken.",
                    granted: EventKitService.shared.remindersAuthorized,
                    undetermined: EKEventStore.authorizationStatus(for: .reminder) == .notDetermined) {
                    _ = await EventKitService.shared.requestRemindersAccess()
                }
                row("Kontakte", "person.crop.circle", "Telefonnummern und E-Mail-Adressen für Nachrichtenentwürfe finden.",
                    granted: ContactsService.shared.authorized,
                    undetermined: CNContactStore.authorizationStatus(for: .contacts) == .notDetermined) {
                    _ = await ContactsService.shared.requestAccess()
                }
                row("Standort", "location", "Nur bei Bedarf, z. B. für das Wetter „hier“ oder Routen.",
                    granted: LocationService.shared.authorized,
                    undetermined: LocationService.shared.notDetermined) {
                    _ = await LocationService.shared.requestAccess()
                }
                row("Mitteilungen", "bell", "Für die Tagesübersicht am Morgen und den Rückblick am Abend.",
                    granted: notificationsAllowed, undetermined: !notificationsAllowed) {
                    _ = await ProactiveScheduler.requestAuthorization()
                }
            } header: {
                Text("Geräte-Funktionen")
            } footer: {
                Text("Fotos und Dateien wählen Sie jeweils selbst aus – dafür braucht ATLAS keinen dauerhaften Zugriff. Bereits abgelehnte Berechtigungen können nur in den Systemeinstellungen geändert werden.")
            }

            Section {
                Button("Systemeinstellungen öffnen") { PlatformBridge.openSystemSettings() }
            }
        }
        .id(refresh)
        .navigationTitle("Berechtigungen")
        .atlasInlineTitle()
        .task { await loadNotificationStatus() }
    }

    private func row(_ title: String, _ symbol: String, _ purpose: String, granted: Bool, undetermined: Bool,
                     request: @escaping () async -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .accessibilityLabel("Erlaubt")
            } else if undetermined {
                Button("Erlauben") {
                    Task {
                        await request()
                        await loadNotificationStatus()
                        refresh += 1
                    }
                }
                .buttonStyle(.bordered)
            } else {
                Button("Einstellungen") { PlatformBridge.openSystemSettings() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func loadNotificationStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsAllowed = status == .authorized || status == .provisional
    }
}
