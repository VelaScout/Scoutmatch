import Foundation

@MainActor final class RealtimeSession {
    struct Configuration {
        var apiKey: String
        var model: String
        var voice: String
        var instructions: String
        var tools: [[String: Any]]
        /// Leise Begleit-Transkription für Verlauf und Gedächtnis (geringe Zusatzkosten).
        var transcribeInput = true
    }

    enum Event {
        case ready
        case userStartedSpeaking
        case userStoppedSpeaking
        case userTranscript(String)
        case assistantStartedSpeaking
        case assistantTranscript(String)
        case responseFinished(hadToolCalls: Bool)
        case toolCall(callID: String, name: String, arguments: String)
        case error(String)
        case closed
    }

    var onEvent: ((Event) -> Void)?
    var isOpen: Bool { false }
    func open(_ configuration: Configuration, usePreroll: Bool) throws {
        throw AIError.stream("Cloud-Live-Audio ist in Atlas Local deaktiviert.")
    }
    func close(notify: Bool = true) { if notify { onEvent?(.closed) } }
    func sendToolOutput(callID: String, output: String, respond: Bool = true) {}
    func sendNote(_ text: String, respond: Bool = true) {}
    func interrupt() {}
}
