import AVFoundation
import Foundation

// Retained for saved-setting compatibility. Cloud voices cannot run in this build.
enum PremiumProvider: String, CaseIterable, Identifiable, Sendable {
    case elevenLabs, openAI, local
    var id: String { rawValue }
    var displayName: String { "Lokale Apple-Stimme" }
}
@MainActor final class PremiumVoice: NSObject {
    struct Config: Equatable, Sendable {
        var apiKey: String
        var voiceID: String
        var model = "local"
        var provider: PremiumProvider = .local
        var instructions = ""
        var baseURL = ""
        var language = "de"
    }
    static let presets: [(name: String, id: String)] = [("Apple lokal", "")]
    static let defaultOpenAIStyle = ""
    static let previousOpenAIStyle = ""
    nonisolated static func stream(text: String, config: Config, previousText: String,
                                   format: AVAudioFormat) -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        AsyncThrowingStream { $0.finish(throwing: AIError.stream("Bitte die lokale Apple-Stimme verwenden.")) }
    }
}
