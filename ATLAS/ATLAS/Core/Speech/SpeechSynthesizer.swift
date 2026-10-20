import AVFoundation
import Foundation

/// Sprachausgabe von ATLAS: Apple-Stimme (AVSpeechSynthesizer) oder – falls eingerichtet –
/// die Premium-Stimme von ElevenLabs. Antworten werden satzweise eingereiht, damit ATLAS
/// sofort losspricht.
@MainActor
final class SpeechSynthesizer: NSObject {
    /// Alle eingereihten Sätze wurden gesprochen.
    var onFinishedAll: (() -> Void)?
    /// Wird bei jedem gesprochenen Wort mit dessen Buchstabenzahl ausgelöst –
    /// Grundlage für das Pulsieren des ATLAS-Kerns.
    var onWord: ((Int) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private let premium = PremiumVoice()
    private var queued: Set<ObjectIdentifier> = []
    /// Zuletzt verwendete Apple-Stimme – für den Fall, dass die Premium-Stimme ausfällt.
    private var fallbackVoice: (identifier: String, language: AtlasLanguage, rate: Double) = ("", .german, 0.5)

    var isSpeaking: Bool { !queued.isEmpty || premium.isSpeaking }

    override init() {
        super.init()
        synthesizer.delegate = self
        premium.onWord = { [weak self] length in self?.onWord?(length) }
        premium.onFinishedAll = { [weak self] in self?.checkFinished() }
        premium.onFallback = { [weak self] text in
            guard let self else { return }
            self.speakWithApple(text, voiceIdentifier: self.fallbackVoice.identifier,
                                language: self.fallbackVoice.language, rate: self.fallbackVoice.rate)
        }
    }

    /// - Parameter premium: Zugangsdaten der Premium-Stimme; `nil` = Apple-Stimme.
    func speak(_ text: String, voiceIdentifier: String, language: AtlasLanguage, rate: Double,
               premium config: PremiumVoice.Config? = nil) {
        let cleaned = SpeechTextCleaner.clean(text)
        guard !cleaned.isEmpty else { return }
        fallbackVoice = (voiceIdentifier, language, rate)
        if let config {
            premium.speak(cleaned, config: config)
        } else {
            speakWithApple(cleaned, voiceIdentifier: voiceIdentifier, language: language, rate: rate)
        }
    }

    private func speakWithApple(_ cleaned: String, voiceIdentifier: String, language: AtlasLanguage, rate: Double) {
        try? AudioSessionManager.activate()

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = Self.voice(for: voiceIdentifier, language: language)
        // AVSpeechUtterance-Rate: 0 = sehr langsam, 0.5 = normal, 1 = sehr schnell.
        utterance.rate = Float(rate) * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate)
            + AVSpeechUtteranceMinimumSpeechRate
        utterance.pitchMultiplier = 0.95
        utterance.postUtteranceDelay = 0
        queued.insert(ObjectIdentifier(utterance))
        synthesizer.speak(utterance)
    }

    func stop() {
        queued.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        premium.stop()
    }

    private func checkFinished() {
        if !isSpeaking { onFinishedAll?() }
    }

    // MARK: - Stimmen

    static func voice(for identifier: String, language: AtlasLanguage) -> AVSpeechSynthesisVoice? {
        if !identifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: identifier),
           voice.language.hasPrefix(language.rawValue.prefix(2)) {
            return voice
        }
        return bestVoice(for: language)
    }

    /// Wählt die hochwertigste installierte Stimme; bevorzugt eine männliche Butler-Stimme.
    static func bestVoice(for language: AtlasLanguage) -> AVSpeechSynthesisVoice? {
        let voices = availableVoices(for: language)
        return voices.first(where: { $0.gender == .male }) ?? voices.first
            ?? AVSpeechSynthesisVoice(language: language.rawValue)
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

    // MARK: - Delegate (wird auf einem Hintergrund-Thread aufgerufen)

    fileprivate func utteranceFinished(_ id: ObjectIdentifier) {
        guard queued.remove(id) != nil else { return }
        checkFinished()
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceFinished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let length = characterRange.length
        Task { @MainActor in self.onWord?(length) }
    }
}

/// Entfernt Formatierungen, die beim Vorlesen stören würden.
enum SpeechTextCleaner {
    static func clean(_ text: String) -> String {
        var result = text
        // Markdown-Links [Text](URL) -> Text
        result = result.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        // Nackte URLs entfernen
        result = result.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        // Markdown-Zeichen entfernen
        result = result.replacingOccurrences(of: #"[*_`#>]+"#, with: "", options: .regularExpression)
        // Aufzählungszeichen am Zeilenanfang
        result = result.replacingOccurrences(of: #"(?m)^\s*[-•]\s+"#, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Zerlegt eine gestreamte Antwort in sprechbare Sätze.
struct SentenceChunker {
    private var buffer = ""
    private var emittedFirst = false
    /// Mindestlänge des ersten Abschnitts (kurz = ATLAS beginnt schnell zu sprechen).
    private let firstMinimum: Int
    /// Mindestlänge der folgenden Abschnitte (lang = fließender, weniger „abgehackt“).
    private let minimum: Int

    init(firstMinimum: Int = 30, minimum: Int = 120) {
        self.firstMinimum = firstMinimum
        self.minimum = minimum
    }

    /// Fügt neuen Text hinzu und liefert alle vollständigen Sätze.
    mutating func feed(_ text: String) -> [String] {
        buffer += text
        var sentences: [String] = []
        while let end = nextBoundary() {
            let sentence = String(buffer[..<end])
            buffer = String(buffer[end...])
            if !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sentences.append(sentence)
                emittedFirst = true
            }
        }
        return sentences
    }

    /// Liefert den restlichen Text am Ende der Antwort.
    mutating func flush() -> String? {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? nil : rest
    }

    /// Satzende = . ! ? : ; oder Zeilenumbruch, gefolgt von Leerraum.
    /// Der erste Abschnitt darf kurz sein (schneller Start), danach werden mehrere
    /// Sätze zusammengefasst, damit die Stimme fließend und natürlich klingt.
    private func nextBoundary() -> String.Index? {
        let minimumLength = emittedFirst ? minimum : firstMinimum
        var index = buffer.startIndex
        var length = 0
        while index < buffer.endIndex {
            let char = buffer[index]
            let next = buffer.index(after: index)
            length += 1
            if char == "\n", length >= 2 { return next }
            if ".!?;:".contains(char), next < buffer.endIndex, buffer[next].isWhitespace, length >= minimumLength {
                return next
            }
            index = next
        }
        return nil
    }
}
