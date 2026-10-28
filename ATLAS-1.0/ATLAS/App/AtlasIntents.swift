import AppIntents
import Foundation

// Siri- und Kurzbefehle-Integration (App Intents).
// Beispiele: „Siri, starte ATLAS“, „Siri, frag ATLAS“, „Siri, ATLAS Tagesübersicht“.
// Auf dem iPhone 15 Pro und neuer lassen sich diese Aktionen auch auf den Action-Button legen.

/// Öffnet ATLAS und beginnt sofort zuzuhören.
struct StartAtlasIntent: AppIntent {
    static let title: LocalizedStringResource = "A.T.L.A.S. starten"
    static let description = IntentDescription("Öffnet A.T.L.A.S. und beginnt sofort zuzuhören.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.request(.listen)
        return .result()
    }
}

/// Stellt ATLAS eine Frage, ohne die App zu öffnen – Siri liest die Antwort vor.
struct AskAtlasIntent: AppIntent {
    static let title: LocalizedStringResource = "A.T.L.A.S. fragen"
    static let description = IntentDescription("Stellt A.T.L.A.S. eine Frage. Siri liest die Antwort vor.")

    @Parameter(title: "Frage", requestValueDialog: IntentDialog("Was möchten Sie A.T.L.A.S. fragen?"))
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let settings = AppSettings()
        let context = Persona.context(settings: settings, memories: [])
        let options = AIRequestOptions(
            model: settings.model.rawValue,
            effort: settings.effort.rawValue,
            systemPrompt: Persona.systemPrompt(context)
                + "\n\nDiese Frage kommt über Siri. Antworte besonders kurz (höchstens drei Sätze). Du hast hier keinen Zugriff auf Kalender und andere Werkzeuge.",
            webSearch: settings.webSearchEnabled
        )
        let prompt = Persona.contextLine(language: settings.language) + "\n" + question
        let answer: String
        do {
            answer = try await LocalAtlasProvider().answer(prompt, options: options)
        } catch {
            answer = (error as? LocalizedError)?.errorDescription ?? "Das hat leider nicht funktioniert."
        }
        let spoken = SpeechTextCleaner.clean(answer)
        return .result(value: spoken, dialog: IntentDialog(stringLiteral: spoken))
    }
}

/// Öffnet ATLAS mit der morgendlichen Tagesübersicht.
struct MorningBriefingIntent: AppIntent {
    static let title: LocalizedStringResource = "A.T.L.A.S. Tagesübersicht"
    static let description = IntentDescription("A.T.L.A.S. fasst Ihre Termine und Aufgaben für heute zusammen.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.request(.briefing(.morning))
        return .result()
    }
}

/// Öffnet ATLAS und plant den morgigen Tag.
struct PlanTomorrowIntent: AppIntent {
    static let title: LocalizedStringResource = "Morgen mit A.T.L.A.S. planen"
    static let description = IntentDescription("A.T.L.A.S. organisiert Ihren morgigen Tag anhand von Kalender und Aufgaben.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.request(.briefing(.planTomorrow))
        return .result()
    }
}

/// Sätze, mit denen Siri die Aktionen ohne Einrichtung erkennt.
struct AtlasShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartAtlasIntent(),
                    phrases: ["Starte \(.applicationName)",
                              "\(.applicationName) starten",
                              "Öffne \(.applicationName)",
                              "Start \(.applicationName)"],
                    shortTitle: "A.T.L.A.S. starten",
                    systemImageName: "waveform.circle")
        AppShortcut(intent: AskAtlasIntent(),
                    phrases: ["Frag \(.applicationName)",
                              "Frage \(.applicationName)",
                              "Ask \(.applicationName)"],
                    shortTitle: "A.T.L.A.S. fragen",
                    systemImageName: "questionmark.bubble")
        AppShortcut(intent: MorningBriefingIntent(),
                    phrases: ["\(.applicationName) Tagesübersicht",
                              "Tagesübersicht von \(.applicationName)"],
                    shortTitle: "Tagesübersicht",
                    systemImageName: "sun.horizon")
        AppShortcut(intent: PlanTomorrowIntent(),
                    phrases: ["Plane morgen mit \(.applicationName)",
                              "\(.applicationName) plane meinen Tag"],
                    shortTitle: "Morgen planen",
                    systemImageName: "calendar")
    }
}
