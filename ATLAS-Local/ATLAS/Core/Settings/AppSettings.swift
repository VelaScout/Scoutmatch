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

/// Lokale Ollama-Modelle für Apple Silicon mit 16 GB RAM.
enum AtlasModel: String, CaseIterable, Identifiable {
    case qwen4b = "qwen3:4b"
    case qwen8b = "qwen3:8b"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .qwen4b: return "Qwen3 4B – schneller Standard"
        case .qwen8b: return "Qwen3 8B – mehr Qualität, mehr Speicher"
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
        case .hologram: return "A.T.L.A.S.-Kern (3D)"
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
    /// Förmliche Anrede mit Nachnamen, z. B. „Herr Velasco“ – wird abwechselnd mit „Sir“ benutzt.
    var formalAddress: String { didSet { defaults.set(formalAddress, forKey: Keys.formalAddress) } }
    var userName: String { didSet { defaults.set(userName, forKey: Keys.userName) } }
    /// Kurze Begrüßung beim Öffnen (höchstens alle drei Stunden).
    var greetOnLaunch: Bool { didSet { defaults.set(greetOnLaunch, forKey: Keys.greetOnLaunch) } }
    /// Denkpausen mit kurzen Lauten überbrücken („Hm, Moment …“).
    var thinkingFillers: Bool { didSet { defaults.set(thinkingFillers, forKey: Keys.thinkingFillers) } }
    /// Während A.T.L.A.S. spricht weiter zuhören – „Stopp“ oder eine neue Frage unterbricht ihn sofort.
    var bargeIn: Bool { didSet { defaults.set(bargeIn, forKey: Keys.bargeIn) } }
    var language: AtlasLanguage { didSet { defaults.set(language.rawValue, forKey: Keys.language) } }
    var voiceIdentifier: String { didSet { defaults.set(voiceIdentifier, forKey: Keys.voiceIdentifier) } }
    var speechRate: Double { didSet { defaults.set(speechRate, forKey: Keys.speechRate) } }
    /// Premium-Stimme (ElevenLabs) statt Apple-Stimme verwenden.
    var premiumVoiceEnabled: Bool { didSet { defaults.set(premiumVoiceEnabled, forKey: Keys.premiumVoice) } }
    var premiumVoiceID: String { didSet { defaults.set(premiumVoiceID, forKey: Keys.premiumVoiceID) } }
    var premiumProvider: PremiumProvider { didSet { defaults.set(premiumProvider.rawValue, forKey: Keys.premiumProvider) } }
    var openAIVoice: String { didSet { defaults.set(openAIVoice, forKey: Keys.openAIVoice) } }
    /// Wie die OpenAI-Stimme sprechen soll („entspannt, locker …“).
    var openAIVoiceStyle: String { didSet { defaults.set(openAIVoiceStyle, forKey: Keys.openAIVoiceStyle) } }
    /// Eigene KI-Stimme: Adresse des Sprach-Servers (auf dem Mac selbst „http://127.0.0.1:5002“,
    /// vom iPhone aus z. B. „http://Mein-Mac.local:5002“) und gewählte Stimme.
    var localVoiceURL: String { didSet { defaults.set(localVoiceURL, forKey: Keys.localVoiceURL) } }
    var localVoiceName: String { didSet { defaults.set(localVoiceName, forKey: Keys.localVoiceName) } }
    var model: AtlasModel { didSet { defaults.set(model.rawValue, forKey: Keys.model) } }
    var effort: AtlasEffort { didSet { defaults.set(effort.rawValue, forKey: Keys.effort) } }
    var webSearchEnabled: Bool { didSet { defaults.set(webSearchEnabled, forKey: Keys.webSearch) } }
    var conversationMode: Bool { didSet { defaults.set(conversationMode, forKey: Keys.conversationMode) } }
    var silenceTimeout: Double { didSet { defaults.set(silenceTimeout, forKey: Keys.silenceTimeout) } }
    var appearance: AtlasAppearance { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    /// „Atlas“ rufen, solange die App geöffnet ist.
    var wakeWordEnabled: Bool { didSet { defaults.set(wakeWordEnabled, forKey: Keys.wakeWord) } }
    /// Solange die App offen ist, durchgehend zuhören – einfach losreden, ohne „Atlas“.
    var alwaysListen: Bool { didSet { defaults.set(alwaysListen, forKey: Keys.alwaysListen) } }
    /// Zugriff auf Kalender, Erinnerungen, Kontakte, Karten usw.
    var toolsEnabled: Bool { didSet { defaults.set(toolsEnabled, forKey: Keys.tools) } }
    /// Dauerhaftes Gedächtnis verwenden.
    var memoryEnabled: Bool { didSet { defaults.set(memoryEnabled, forKey: Keys.memory) } }
    /// Nach Gesprächen selbstständig dazulernen (Vorlieben, Gewohnheiten, Ziele …).
    var autoLearn: Bool { didSet { defaults.set(autoLearn, forKey: Keys.autoLearn) } }
    var morningBriefingEnabled: Bool { didSet { defaults.set(morningBriefingEnabled, forKey: Keys.morningEnabled) } }
    /// Minuten nach Mitternacht
    var morningBriefingMinutes: Int { didSet { defaults.set(morningBriefingMinutes, forKey: Keys.morningMinutes) } }
    var eveningReviewEnabled: Bool { didSet { defaults.set(eveningReviewEnabled, forKey: Keys.eveningEnabled) } }
    var eveningReviewMinutes: Int { didSet { defaults.set(eveningReviewMinutes, forKey: Keys.eveningMinutes) } }
    /// E-Mail-Konto (das Passwort liegt im Schlüsselbund).
    var mailProvider: MailProvider { didSet { defaults.set(mailProvider.rawValue, forKey: Keys.mailProvider) } }
    var mailAddress: String { didSet { defaults.set(mailAddress, forKey: Keys.mailAddress) } }
    /// Client-ID der eigenen Spotify-App (kein Geheimnis).
    var spotifyClientID: String { didSet { defaults.set(spotifyClientID, forKey: Keys.spotifyClientID) } }

    // MARK: Live-Gespräch (OpenAI Realtime) und Mikrofon

    /// Natürliches Live-Gespräch über OpenAI Realtime (kostenpflichtig). Aus = klassischer Modus.
    var liveModeEnabled: Bool { didSet { defaults.set(liveModeEnabled, forKey: Keys.liveMode) } }
    /// Realtime-Modell: „gpt-realtime-2.1“ (beste Qualität) oder „gpt-realtime-2.1-mini“ (günstiger).
    var realtimeModel: String { didSet { defaults.set(realtimeModel, forKey: Keys.realtimeModel) } }
    /// Stimme im Live-Gespräch (offizielle OpenAI-Stimmen, z. B. „cedar“ oder „marin“).
    var realtimeVoice: String { didSet { defaults.set(realtimeVoice, forKey: Keys.realtimeVoice) } }
    /// Monatsbudget in US-Dollar für kostenpflichtige Sprachfunktionen (0 = ohne Grenze).
    var monthlyBudget: Double { didSet { defaults.set(monthlyBudget, forKey: Keys.monthlyBudget) } }
    /// Hauptschalter: Aus = das Mikrofon wird überhaupt nicht benutzt.
    var microphoneEnabled: Bool { didSet { defaults.set(microphoneEnabled, forKey: Keys.microphone) } }
    /// Mac: auch bei geschlossenem Fenster auf „Atlas“ hören (Symbol in der Menüleiste).
    var backgroundListening: Bool { didSet { defaults.set(backgroundListening, forKey: Keys.backgroundListening) } }

    init() {
        // Lokale Variable, da `self` vor der Initialisierung aller Eigenschaften nicht genutzt werden darf.
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.addressAsSir: true,
            Keys.formalAddress: "Herr Velasco",
            Keys.userName: "",
            Keys.greetOnLaunch: true,
            Keys.thinkingFillers: false,
            Keys.bargeIn: false,
            Keys.language: AtlasLanguage.german.rawValue,
            Keys.voiceIdentifier: "",
            Keys.speechRate: 0.46,
            Keys.premiumVoice: false,
            Keys.premiumVoiceID: PremiumVoice.presets[0].id,
            Keys.premiumProvider: PremiumProvider.elevenLabs.rawValue,
            Keys.openAIVoice: "cedar",
            Keys.openAIVoiceStyle: PremiumVoice.defaultOpenAIStyle,
            Keys.localVoiceURL: "http://127.0.0.1:5002",
            Keys.localVoiceName: "",
            // Sonnet antwortet spürbar schneller – wichtig für ein flüssiges Gespräch.
            Keys.model: AtlasModel.qwen4b.rawValue,
            Keys.effort: AtlasEffort.low.rawValue,
            Keys.webSearch: true,
            Keys.conversationMode: true,
            Keys.silenceTimeout: 0.8,
            Keys.appearance: AtlasAppearance.core.rawValue,
            Keys.wakeWord: true,
            Keys.alwaysListen: true,
            Keys.tools: true,
            Keys.memory: true,
            Keys.autoLearn: true,
            Keys.morningEnabled: false,
            Keys.morningMinutes: 7 * 60,
            Keys.eveningEnabled: false,
            Keys.eveningMinutes: 20 * 60 + 30,
            Keys.mailProvider: MailProvider.icloud.rawValue,
            Keys.mailAddress: "",
            Keys.spotifyClientID: "",
            Keys.liveMode: true,
            Keys.realtimeModel: "gpt-realtime-2.1",
            Keys.realtimeVoice: "cedar",
            Keys.monthlyBudget: 20.0,
            Keys.microphone: true,
            Keys.backgroundListening: false,
        ])
        // Einmalig: vorprogrammierte Denk-Laute aus – sie wirkten unnatürlich.
        if !defaults.bool(forKey: "fillersMigrationV1") {
            defaults.set(false, forKey: Keys.thinkingFillers)
            defaults.set(true, forKey: "fillersMigrationV1")
        }
        // Einmalig: Echo-Unterdrückung (für Unterbrechen per Stimme) aus – sie lieferte auf
        // manchen Macs keinen Mikrofonton. Kann in den Einstellungen wieder eingeschaltet werden.
        if !defaults.bool(forKey: "bargeInMigrationV1") {
            defaults.set(false, forKey: Keys.bargeIn)
            defaults.set(true, forKey: "bargeInMigrationV1")
        }
        // Einmalig: Ein früher automatisch abgeschaltetes Wake-Word wieder einschalten.
        if !defaults.bool(forKey: "wakeWordMigrationV2") {
            defaults.set(true, forKey: Keys.wakeWord)
            defaults.set(true, forKey: "wakeWordMigrationV2")
        }
        for key in [Keys.liveMode, Keys.premiumVoice, Keys.webSearch, Keys.tools, Keys.autoLearn] {
            defaults.set(false, forKey: key)
        }
        if !defaults.bool(forKey: "localAtlasMigrationV1") {
            for key in [Keys.alwaysListen, Keys.wakeWord, Keys.greetOnLaunch, Keys.backgroundListening] {
                defaults.set(false, forKey: key)
            }
            defaults.set(true, forKey: "localAtlasMigrationV1")
        }
        if !defaults.bool(forKey: "localSpeechMigrationV2") {
            defaults.set(AtlasAppearance.core.rawValue, forKey: Keys.appearance)
            defaults.set(0.46, forKey: Keys.speechRate)
            defaults.set(false, forKey: Keys.bargeIn)
            defaults.set(true, forKey: "localSpeechMigrationV2")
        }
        addressAsSir = defaults.bool(forKey: Keys.addressAsSir)
        formalAddress = defaults.string(forKey: Keys.formalAddress) ?? ""
        userName = defaults.string(forKey: Keys.userName) ?? ""
        greetOnLaunch = defaults.bool(forKey: Keys.greetOnLaunch)
        thinkingFillers = defaults.bool(forKey: Keys.thinkingFillers)
        bargeIn = defaults.bool(forKey: Keys.bargeIn)
        language = AtlasLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .german
        voiceIdentifier = defaults.string(forKey: Keys.voiceIdentifier) ?? ""
        speechRate = defaults.double(forKey: Keys.speechRate)
        premiumVoiceEnabled = defaults.bool(forKey: Keys.premiumVoice)
        premiumVoiceID = defaults.string(forKey: Keys.premiumVoiceID) ?? PremiumVoice.presets[0].id
        premiumProvider = PremiumProvider(rawValue: defaults.string(forKey: Keys.premiumProvider) ?? "") ?? .elevenLabs
        openAIVoice = defaults.string(forKey: Keys.openAIVoice) ?? "cedar"
        localVoiceURL = defaults.string(forKey: Keys.localVoiceURL) ?? "http://127.0.0.1:5002"
        localVoiceName = defaults.string(forKey: Keys.localVoiceName) ?? ""
        let style = defaults.string(forKey: Keys.openAIVoiceStyle) ?? PremiumVoice.defaultOpenAIStyle
        openAIVoiceStyle = style == PremiumVoice.previousOpenAIStyle ? PremiumVoice.defaultOpenAIStyle : style
        model = AtlasModel(rawValue: defaults.string(forKey: Keys.model) ?? "") ?? .qwen4b
        effort = AtlasEffort(rawValue: defaults.string(forKey: Keys.effort) ?? "") ?? .low
        webSearchEnabled = defaults.bool(forKey: Keys.webSearch)
        conversationMode = defaults.bool(forKey: Keys.conversationMode)
        silenceTimeout = defaults.double(forKey: Keys.silenceTimeout)
        appearance = AtlasAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .hologram
        wakeWordEnabled = defaults.bool(forKey: Keys.wakeWord)
        alwaysListen = defaults.bool(forKey: Keys.alwaysListen)
        toolsEnabled = defaults.bool(forKey: Keys.tools)
        memoryEnabled = defaults.bool(forKey: Keys.memory)
        autoLearn = defaults.bool(forKey: Keys.autoLearn)
        morningBriefingEnabled = defaults.bool(forKey: Keys.morningEnabled)
        morningBriefingMinutes = defaults.integer(forKey: Keys.morningMinutes)
        eveningReviewEnabled = defaults.bool(forKey: Keys.eveningEnabled)
        eveningReviewMinutes = defaults.integer(forKey: Keys.eveningMinutes)
        mailProvider = MailProvider(rawValue: defaults.string(forKey: Keys.mailProvider) ?? "") ?? .icloud
        mailAddress = defaults.string(forKey: Keys.mailAddress) ?? ""
        spotifyClientID = defaults.string(forKey: Keys.spotifyClientID) ?? ""
        liveModeEnabled = defaults.bool(forKey: Keys.liveMode)
        realtimeModel = defaults.string(forKey: Keys.realtimeModel) ?? "gpt-realtime-2.1"
        realtimeVoice = defaults.string(forKey: Keys.realtimeVoice) ?? "cedar"
        monthlyBudget = defaults.double(forKey: Keys.monthlyBudget)
        microphoneEnabled = defaults.bool(forKey: Keys.microphone)
        backgroundListening = defaults.bool(forKey: Keys.backgroundListening)
    }

    /// In dieser Ausgabe gibt es ausschließlich lokale Sprachausgabe.
    var liveModeAvailable: Bool { false }
    var premiumVoiceConfig: PremiumVoice.Config? { nil }
    var hasPremiumKey: Bool { false }

    /// Anrede für kurze feste Sätze, z. B. „Ja, Sir?“
    /// Wechselt zwischen „Sir“ und der förmlichen Anrede, z. B. „Ja, Herr Velasco?“
    var sirSuffix: String {
        let formal = formalAddress.trimmingCharacters(in: .whitespaces)
        var options: [String] = []
        if addressAsSir { options.append("Sir") }
        if !formal.isEmpty { options.append(formal) }
        guard let pick = options.randomElement() else { return "" }
        return ", " + pick
    }

    private enum Keys {
        static let addressAsSir = "addressAsSir"
        static let formalAddress = "formalAddress"
        static let userName = "userName"
        static let greetOnLaunch = "greetOnLaunch"
        static let thinkingFillers = "thinkingFillers"
        static let bargeIn = "bargeInEnabled"
        static let language = "language"
        static let voiceIdentifier = "voiceIdentifier"
        static let speechRate = "speechRate"
        static let premiumVoice = "premiumVoiceEnabled"
        static let premiumVoiceID = "premiumVoiceID"
        static let premiumProvider = "premiumProvider"
        static let openAIVoice = "openAIVoice"
        static let openAIVoiceStyle = "openAIVoiceStyle"
        static let localVoiceURL = "localVoiceURL"
        static let localVoiceName = "localVoiceName"
        static let model = "model"
        static let effort = "effort"
        static let webSearch = "webSearchEnabled"
        static let conversationMode = "conversationMode"
        static let silenceTimeout = "silenceTimeout"
        static let appearance = "appearance"
        static let wakeWord = "wakeWordEnabled"
        static let alwaysListen = "alwaysListenEnabled"
        static let tools = "toolsEnabled"
        static let memory = "memoryEnabled"
        static let autoLearn = "autoLearnEnabled"
        static let morningEnabled = "morningBriefingEnabled"
        static let morningMinutes = "morningBriefingMinutes"
        static let eveningEnabled = "eveningReviewEnabled"
        static let eveningMinutes = "eveningReviewMinutes"
        static let mailProvider = "mailProvider"
        static let mailAddress = "mailAddress"
        static let spotifyClientID = "spotifyClientID"
        static let liveMode = "liveModeEnabled"
        static let realtimeModel = "realtimeModel"
        static let realtimeVoice = "realtimeVoice"
        static let monthlyBudget = "monthlyBudgetUSD"
        static let microphone = "microphoneEnabled"
        static let backgroundListening = "backgroundListening"
    }
}
