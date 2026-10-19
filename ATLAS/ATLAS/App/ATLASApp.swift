import SwiftData
import SwiftUI

@main
struct ATLASApp: App {
    private let container: ModelContainer
    @State private var settings: AppSettings
    @State private var engine: ConversationEngine

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: ConversationRecord.self, MessageRecord.self)
        } catch {
            fatalError("Lokaler Speicher konnte nicht geöffnet werden: \(error)")
        }
        let settings = AppSettings()
        self.container = container
        _settings = State(initialValue: settings)
        _engine = State(initialValue: ConversationEngine(settings: settings,
                                                         provider: ClaudeProvider(),
                                                         modelContext: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(settings)
                .environment(engine)
        }
        .modelContainer(container)
    }
}
