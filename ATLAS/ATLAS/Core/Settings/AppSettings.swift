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

/// Darstellung von ATLAS auf dem Startbildschirm.
enum AtlasAppearance: String, CaseIterable, Identifiable {
    case hologram, core

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hologram: return "ATLAS-Kern (3D)"
        case .core: return "Schlicht (besonders sparsam)"
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
    /// Premium-Stimme (ElevenLabs) statt Apple-Stimme verwenden.
    var premiumVoiceEnabled: Bool { didSet { defaults.set(premiumVoiceEnabled, forKey: Keys.premiumVoice) } }
    var premiumVoiceID: String { didSet { defaults.set(premiumVoiceID, forKey: Keys.premiumVoiceID) } }
    var model: AtlasModel { didSet { defaults.set(model.rawValue, forKey: Keys.model) } }
    var effort: AtlasEffort { didSet { defaults.set(effort.rawValue, forKey: Keys.effort) } }
    var webSearchEnabled: Bool { didSet { defaults.set(webSearchEnabled, forKey: Keys.webSearch) } }
    var conversationMode: Bool { didSet { defaults.set(conversationMode, forKey: Keys.conversationMode) } }
    var silenceTimeout: Double { didSet { defaults.set(silenceTimeout, forKey: Keys.silenceTimeout) } }
    var appearance: AtlasAppearance { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    /// „Atlas“ rufen, solange die App geöffnet ist.
    var wakeWordEnabled: Bool { didSet { defaults.set(wakeWordEnabled, forKey: Keys.wakeWord) } }
    /// Zugriff auf Kalender, Erinnerungen, Kontakte, Karten usw.
    var toolsEnabled: Bool { didSet { defaults.set(toolsEnabled, forKey: Keys.tools) } }
    /// Dauerhaftes Gedächtnis verwenden.
    var memoryEnabled: Bool { didSet { defaults.set(memoryEnabled, forKey: Keys.memory) } }
    var morningBriefingEnabled: Bool { didSet { defaults.set(morningBriefingEnabled, forKey: Keys.morningEnabled) } }
    /// Minuten nach Mitternacht
    var morningBriefingMinutes: Int { didSet { defaults.set(morningBriefingMinutes, forKey: Keys.morningMinutes) } }
    var eveningReviewEnabled: Bool { didSet { defaults.set(eveningReviewEnabled, forKey: Keys.eveningEnabled) } }
    var eveningReviewMinutes: Int { didSet { defaults.set(eveningReviewMinutes, forKey: Keys.eveningMinutes) } }

    init() {
        // Lokale Variable, da `self` vor der Initialisierung aller Eigenschaften nicht genutzt werden darf.
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.addressAsSir: true,
            Keys.userName: "",
            Keys.language: AtlasLanguage.german.rawValue,
            Keys.voiceIdentifier: "",
            Keys.speechRate: 0.5,
            Keys.premiumVoice: false,
            Keys.premiumVoiceID: PremiumVoice.presets[0].id,
            Keys.model: AtlasModel.opus.rawValue,
            Keys.effort: AtlasEffort.low.rawValue,
            Keys.webSearch: true,
            Keys.conversationMode: true,
            Keys.silenceTimeout: 1.4,
            Keys.appearance: AtlasAppearance.hologram.rawValue,
            Keys.wakeWord: false,
            Keys.tools: true,
            Keys.memory: true,
            Keys.morningEnabled: false,
            Keys.morningMinutes: 7 * 60,
            Keys.eveningEnabled: false,
            Keys.eveningMinutes: 20 * 60 + 30,
        ])
        addressAsSir = defaults.bool(forKey: Keys.addressAsSir)
        userName = defaults.string(forKey: Keys.userName) ?? ""
        language = AtlasLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .german
        voiceIdentifier = defaults.string(forKey: Keys.voiceIdentifier) ?? ""
        speechRate = defaults.double(forKey: Keys.speechRate)
        premiumVoiceEnabled = defaults.bool(forKey: Keys.premiumVoice)
        premiumVoiceID = defaults.string(forKey: Keys.premiumVoiceID) ?? PremiumVoice.presets[0].id
        model = AtlasModel(rawValue: defaults.string(forKey: Keys.model) ?? "") ?? .opus
        effort = AtlasEffort(rawValue: defaults.string(forKey: Keys.effort) ?? "") ?? .low
        webSearchEnabled = defaults.bool(forKey: Keys.webSearch)
        conversationMode = defaults.bool(forKey: Keys.conversationMode)
        silenceTimeout = defaults.double(forKey: Keys.silenceTimeout)
        appearance = AtlasAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .hologram
        wakeWordEnabled = defaults.bool(forKey: Keys.wakeWord)
        toolsEnabled = defaults.bool(forKey: Keys.tools)
        memoryEnabled = defaults.bool(forKey: Keys.memory)
        morningBriefingEnabled = defaults.bool(forKey: Keys.morningEnabled)
        morningBriefingMinutes = defaults.integer(forKey: Keys.morningMinutes)
        eveningReviewEnabled = defaults.bool(forKey: Keys.eveningEnabled)
        eveningReviewMinutes = defaults.integer(forKey: Keys.eveningMinutes)
    }

    /// Zugangsdaten der Premium-Stimme, falls eingeschaltet und ein Schlüssel hinterlegt ist.
    var premiumVoiceConfig: PremiumVoice.Config? {
        guard premiumVoiceEnabled, let key = KeychainStore.read(.elevenLabsAPIKey), !key.isEmpty else { return nil }
        return PremiumVoice.Config(apiKey: key, voiceID: premiumVoiceID)
    }

    /// Anrede für kurze feste Sätze, z. B. „Ja, Sir?“
    var sirSuffix: String { addressAsSir ? ", Sir" : "" }

    private enum Keys {
        static let addressAsSir = "addressAsSir"
        static let userName = "userName"
        static let language = "language"
        static let voiceIdentifier = "voiceIdentifier"
        static let speechRate = "speechRate"
        static let premiumVoice = "premiumVoiceEnabled"
        static let premiumVoiceID = "premiumVoiceID"
        static let model = "model"
        static let effort = "effort"
        static let webSearch = "webSearchEnabled"
        static let conversationMode = "conversationMode"
        static let silenceTimeout = "silenceTimeout"
        static let appearance = "appearance"
        static let wakeWord = "wakeWordEnabled"
        static let tools = "toolsEnabled"
        static let memory = "memoryEnabled"
        static let morningEnabled = "morningBriefingEnabled"
        static let morningMinutes = "morningBriefingMinutes"
        static let eveningEnabled = "eveningReviewEnabled"
        static let eveningMinutes = "eveningReviewMinutes"
    }
}
