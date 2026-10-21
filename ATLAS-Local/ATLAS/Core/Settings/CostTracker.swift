import Foundation

/// Erfasst die geschätzten API-Kosten pro Monat (lokal, auf dem Gerät) und prüft das Budget.
///
/// Grundlage sind die Verbrauchsangaben, die Claude und OpenAI mit jeder Antwort mitliefern,
/// multipliziert mit den Listenpreisen pro Million Tokens. Es ist eine Schätzung – maßgeblich
/// ist die Abrechnung im jeweiligen Konto.
final class CostTracker: @unchecked Sendable {
    static let shared = CostTracker()

    enum Source: String, CaseIterable, Codable {
        case claude, realtime, openAIVoice

        var displayName: String {
            switch self {
            case .claude: return "Claude (Denken)"
            case .realtime: return "OpenAI Live-Gespräch"
            case .openAIVoice: return "OpenAI-Stimme"
            }
        }
    }

    /// Preise in US-Dollar pro 1 Million Tokens.
    struct Price {
        let input: Double
        let output: Double
        let cachedInput: Double
        var audioInput: Double = 0
        var audioOutput: Double = 0
        var cachedAudioInput: Double = 0
    }

    /// Claude-Listenpreise (Anthropic, Stand Oktober 2026).
    static let claudePrices: [String: Price] = [
        "claude-opus-5-5": Price(input: 4.00, output: 20.00, cachedInput: 0.20),
        "claude-sonnet-5-5": Price(input: 2.00, output: 10.00, cachedInput: 0.20),
        "claude-haiku-5-5": Price(input: 0.10, output: 0.50, cachedInput: 0.01),
    ]

    /// OpenAI-Realtime-Preise (Schätzwerte nach den zuletzt veröffentlichten Listenpreisen –
    /// bitte mit openai.com/api/pricing abgleichen).
    static func realtimePrice(model: String) -> Price {
        model.contains("mini")
            ? Price(input: 0.60, output: 2.40, cachedInput: 0.06, audioInput: 10.00, audioOutput: 20.00, cachedAudioInput: 0.30)
            : Price(input: 4.00, output: 16.00, cachedInput: 0.40, audioInput: 32.00, audioOutput: 64.00, cachedAudioInput: 0.40)
    }

    /// OpenAI-Stimme (gpt-4o-mini-tts): Schätzwert pro Minute gesprochener Sprache.
    static let openAIVoicePerMinute = 0.015

    private let lock = NSLock()
    private let defaults = UserDefaults.standard
    private static let storageKey = "costTrackerMonths"

    // MARK: - Erfassen

    func recordClaude(model: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int) {
        let price = Self.claudePrices[model] ?? Self.claudePrices["claude-opus-5-5"]!
        let usd = (Double(input) * price.input + Double(cacheWrite) * price.input * 1.25
            + Double(cacheRead) * price.cachedInput + Double(output) * price.output) / 1_000_000
        add(usd, to: .claude)
    }

    func recordRealtime(model: String, textIn: Int, audioIn: Int, cachedIn: Int, textOut: Int, audioOut: Int) {
        let price = Self.realtimePrice(model: model)
        // Zwischengespeicherte Tokens zum günstigen Preis, den Rest voll.
        let cachedShare = Double(min(cachedIn, textIn + audioIn))
        let usd = (Double(textIn) * price.input + Double(audioIn) * price.audioInput
            - cachedShare * (price.audioInput - price.cachedAudioInput)
            + Double(textOut) * price.output + Double(audioOut) * price.audioOutput) / 1_000_000
        add(max(0, usd), to: .realtime)
    }

    func recordOpenAIVoice(seconds: Double) {
        add(seconds / 60 * Self.openAIVoicePerMinute, to: .openAIVoice)
    }

    // MARK: - Auswerten

    /// Kosten des laufenden Monats je Quelle (US-Dollar).
    func currentMonth() -> [Source: Double] {
        lock.withLock {
            let months = load()
            let month = months[Self.monthKey()] ?? [:]
            var result: [Source: Double] = [:]
            for (key, value) in month {
                if let source = Source(rawValue: key) { result[source] = value }
            }
            return result
        }
    }

    var monthTotal: Double { currentMonth().values.reduce(0, +) }

    /// Ist das Budget für kostenpflichtige Sprachfunktionen (OpenAI) aufgebraucht?
    func isOverBudget(_ budget: Double) -> Bool {
        budget > 0 && monthTotal >= budget
    }

    func resetCurrentMonth() {
        lock.withLock {
            var months = load()
            months[Self.monthKey()] = [:]
            save(months)
        }
    }

    // MARK: - Speicher

    private func add(_ usd: Double, to source: Source) {
        guard usd > 0, usd.isFinite else { return }
        lock.withLock {
            var months = load()
            let key = Self.monthKey()
            var month = months[key] ?? [:]
            month[source.rawValue, default: 0] += usd
            months[key] = month
            // Nur die letzten 12 Monate behalten.
            if months.count > 12 {
                for old in months.keys.sorted().dropLast(12) { months[old] = nil }
            }
            save(months)
        }
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changedNotification, object: nil) }
    }

    static let changedNotification = Notification.Name("ATLASCostsChanged")

    private func load() -> [String: [String: Double]] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let months = try? JSONDecoder().decode([String: [String: Double]].self, from: data) else { return [:] }
        return months
    }

    private func save(_ months: [String: [String: Double]]) {
        if let data = try? JSONEncoder().encode(months) { defaults.set(data, forKey: Self.storageKey) }
    }

    private static func monthKey(_ date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}
