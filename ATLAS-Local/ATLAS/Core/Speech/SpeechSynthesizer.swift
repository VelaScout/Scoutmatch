import AVFoundation
import Foundation

/// Local system playback: no custom PCM conversion, no cloud, no artificial phonetic override.
@MainActor
final class SpeechSynthesizer: NSObject, AVSpeechSynthesizerDelegate {
    var onFinishedAll: (() -> Void)?
    var onWord: ((Int) -> Void)?
    private let apple = AVSpeechSynthesizer()
    private var pending = Set<ObjectIdentifier>()
    private(set) var spokenLog = ""
    var isSpeaking: Bool { !pending.isEmpty }
    override init() { super.init(); apple.delegate = self }

    func speak(_ text: String, voiceIdentifier: String, language: AtlasLanguage, rate: Double,
               premium: PremiumVoice.Config? = nil) {
        let named = text.replacingOccurrences(of: "A.T.L.A.S.", with: "Atlas")
        for segment in LanguageSegments.split(named) {
            let cleaned = SpeechTextCleaner.clean(segment.text)
            guard !cleaned.isEmpty else { continue }
            let utterance = AVSpeechUtterance(string: cleaned)
            if let locale = segment.locale, !locale.hasPrefix(String(language.rawValue.prefix(2))) {
                utterance.voice = Self.bestVoice(locale: locale)
            } else { utterance.voice = Self.voice(for: voiceIdentifier, language: language) }
            utterance.rate = Float(min(0.6, max(0.35, rate)))
            utterance.pitchMultiplier = 1.0
            utterance.postUtteranceDelay = 0.12
            pending.insert(ObjectIdentifier(utterance))
            spokenLog += " " + cleaned
            apple.speak(utterance)
        }
    }
    func stop() {
        pending.removeAll()
        apple.stopSpeaking(at: .immediate)
        spokenLog = ""
    }
    private func finished(_ utterance: AVSpeechUtterance) {
        guard pending.remove(ObjectIdentifier(utterance)) != nil else { return }
        if pending.isEmpty { spokenLog = ""; onFinishedAll?() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished(utterance) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished(utterance) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.pending.contains(ObjectIdentifier(utterance)) else { return }
            self.onWord?(characterRange.length)
        }
    }
    static func voice(for identifier: String, language: AtlasLanguage) -> AVSpeechSynthesisVoice? {
        if !identifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: identifier),
           voice.language.hasPrefix(language.rawValue.prefix(2)), !voice.voiceTraits.contains(.isNoveltyVoice) {
            return voice
        }
        return bestVoice(for: language)
    }

    /// Wählt die hochwertigste installierte Stimme. Qualität geht vor: innerhalb der besten
    /// Qualitätsstufe wird eine männliche Stimme bevorzugt.
    static func bestVoice(for language: AtlasLanguage) -> AVSpeechSynthesisVoice? {
        let voices = availableVoices(for: language)
        let bestTier = voices.filter { $0.quality == voices.first?.quality }
        return bestTier.first(where: { $0.gender == .male }) ?? voices.first
            ?? AVSpeechSynthesisVoice(language: language.rawValue)
    }

    /// Beste Stimme für eine beliebige Sprache (z. B. „en-GB“), notfalls derselben Sprachfamilie.
    static func bestVoice(locale: String) -> AVSpeechSynthesisVoice? {
        let prefix = String(locale.prefix(2))
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) && $0.language.hasPrefix(prefix) }
            .sorted { lhs, rhs in
                let lhsExact = lhs.language == locale, rhsExact = rhs.language == locale
                if lhs.quality.rawValue != rhs.quality.rawValue { return lhs.quality.rawValue > rhs.quality.rawValue }
                if lhsExact != rhsExact { return lhsExact }
                if (lhs.gender == .male) != (rhs.gender == .male) { return lhs.gender == .male }
                return lhs.name < rhs.name
            }
        return candidates.first ?? AVSpeechSynthesisVoice(language: locale)
    }

    /// Alle Stimmen der Sprache, sortiert nach Qualität (Premium > Erweitert > Standard).
    static func availableVoices(for language: AtlasLanguage) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language.rawValue }
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue { return lhs.quality.rawValue > rhs.quality.rawValue }
                return lhs.name < rhs.name
            }
    }

    static func qualityLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Erweitert"
        default: return "Standard"
        }
    }
}

