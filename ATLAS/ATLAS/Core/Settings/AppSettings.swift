import Foundation
import Observation

/// Sprache, in der ATLAS zuhört und spricht.
enum AtlasLanguage: String, CaseIterable, Identifiable {
    case german = "de-DE"
    case britishEnglish = "en-GB"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .german: return "Deutsch"
        case .britishEnglish: return "English (UK)"
        }
    }
}

/// Verfügbare Claude-Modelle. Weitere Anbieter kommen über `AIProvider` hinzu.
enum AtlasModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus: return "Claude Opus 5.5 – höchste Intelligenz"
        case .sonnet: return "Claude Sonnet 5.5 – ausgewogen"
        case .haiku: return "Claude Haiku 5.5 – am schnellsten & günstigsten"
        }
    }
}

/// Wie gründlich das Modell nachdenkt. Niedrig = schnellere Sprachantworten.
enum AtlasEffort: String, CaseIterable, Identifiable {
    case low, medium, high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: return "Schnell"
        case .medium: return "Ausgewogen"
        case .high: return "Gründlich"
        }
    }
}

/// Alle Benutzereinstellungen. Werden in UserDefaults gespeichert –
/// der API-Schlüssel liegt NICHT hier, sondern in der Keychain.
@MainActor
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var addressAsSir: Bool { didSet { defaults.set(addressAsSir, forKey: Keys.addressAsSir) } }
    var userName: String { didSet { defaults.set(userName, forKey: Keys.userName) } }
    var language: AtlasLanguage { didSet { defaults.set(language.rawValue, forKey: Keys.language) } }
    var voiceIdentifier: String { didSet { defaults.set(voiceIdentifier, forKey: Keys.voiceIdentifier) } }
    var speechRate: Double { didSet { defaults.set(speechRate, forKey: Keys.speechRate) } }
    var model: AtlasModel { didSet { defaults.set(model.rawValue, forKey: Keys.model) } }
    var effort: AtlasEffort { didSet { defaults.set(effort.rawValue, forKey: Keys.effort) } }
    var webSearchEnabled: Bool { didSet { defaults.set(webSearchEnabled, forKey: Keys.webSearch) } }
    var conversationMode: Bool { didSet { defaults.set(conversationMode, forKey: Keys.conversationMode) } }
    var silenceTimeout: Double { didSet { defaults.set(silenceTimeout, forKey: Keys.silenceTimeout) } }

    init() {
        // Lokale Variable, da `self` vor der Initialisierung aller Eigenschaften nicht genutzt werden darf.
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.addressAsSir: true,
            Keys.userName: "",
            Keys.language: AtlasLanguage.german.rawValue,
            Keys.voiceIdentifier: "",
            Keys.speechRate: 0.5,
            Keys.model: AtlasModel.opus.rawValue,
            Keys.effort: AtlasEffort.low.rawValue,
            Keys.webSearch: true,
            Keys.conversationMode: true,
            Keys.silenceTimeout: 1.4,
        ])
        addressAsSir = defaults.bool(forKey: Keys.addressAsSir)
        userName = defaults.string(forKey: Keys.userName) ?? ""
        language = AtlasLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .german
        voiceIdentifier = defaults.string(forKey: Keys.voiceIdentifier) ?? ""
        speechRate = defaults.double(forKey: Keys.speechRate)
        model = AtlasModel(rawValue: defaults.string(forKey: Keys.model) ?? "") ?? .opus
        effort = AtlasEffort(rawValue: defaults.string(forKey: Keys.effort) ?? "") ?? .low
        webSearchEnabled = defaults.bool(forKey: Keys.webSearch)
        conversationMode = defaults.bool(forKey: Keys.conversationMode)
        silenceTimeout = defaults.double(forKey: Keys.silenceTimeout)
    }

    private enum Keys {
        static let addressAsSir = "addressAsSir"
        static let userName = "userName"
        static let language = "language"
        static let voiceIdentifier = "voiceIdentifier"
        static let speechRate = "speechRate"
        static let model = "model"
        static let effort = "effort"
        static let webSearch = "webSearchEnabled"
        static let conversationMode = "conversationMode"
        static let silenceTimeout = "silenceTimeout"
    }
}
