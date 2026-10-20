import SwiftData
import SwiftUI
import UserNotifications

@main
struct ATLASApp: App {
    private let container: ModelContainer
    @State private var settings: AppSettings
    @State private var engine: ConversationEngine

    init() {
        let container = AtlasStore.makeContainer()
        let settings = AppSettings()
        self.container = container
        _settings = State(initialValue: settings)
        _engine = State(initialValue: ConversationEngine(settings: settings,
                                                         provider: ClaudeProvider(),
                                                         modelContext: container.mainContext))
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(settings)
                .environment(engine)
                .task { await ProactiveScheduler.reschedule(settings: settings) }
        }
        .modelContainer(container)
        .atlasWindowDefaults()
        #if os(macOS)
        .commands {
            CommandMenu("A.T.L.A.S.") {
                Button("Mit A.T.L.A.S. sprechen") { engine.primaryAction() }
                    .keyboardShortcut("l", modifiers: .command)
                Button("Gespräch beenden") { engine.stopAll() }
                    .keyboardShortcut(".", modifiers: .command)
                Divider()
                Button("Tagesübersicht") { engine.handle(.briefing(.morning)) }
                Button("Morgen planen") { engine.handle(.briefing(.planTomorrow)) }
                Divider()
                Button("Neues Gespräch") { engine.startNewConversation() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
        #endif
    }
}

extension Scene {
    /// Auf dem Mac ein schmales, hohes Fenster – wie ein iPhone-Bildschirm.
    func atlasWindowDefaults() -> some Scene {
        #if os(macOS)
        return self.defaultSize(width: 480, height: 860)
        #else
        return self
        #endif
    }
}
