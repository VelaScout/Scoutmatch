import AVFoundation
import Foundation

/// Local system playback: no custom PCM conversion, no cloud, no artificial phonetic override.
@MainActor
final class SpeechSynthesizer: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    var onFinishedAll: (() -> Void)?
    var onWord: ((Int) -> Void)?
    private let apple = AVSpeechSynthesizer()
    private var pending = Set<ObjectIdentifier>()
    private var localQueue: [(text: String, language: String, voiceID: String, rate: Double)] = []
    private var localTask: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var generation = 0
    private var localActive = false
    private(set) var spokenLog = ""
    var isSpeaking: Bool { !pending.isEmpty || localActive || !localQueue.isEmpty }
    override init() { super.init(); apple.delegate = self }

    func speak(_ text: String, voiceIdentifier: String, language: AtlasLanguage, rate: Double,
               premium: PremiumVoice.Config? = nil) {
        let named = text.replacingOccurrences(of: "A.T.L.A.S.", with: "Atlas")
        let segments = LanguageSegments.split(named)
        for segment in segments {
            let cleaned = SpeechTextCleaner.clean(segment.text)
            guard !cleaned.isEmpty else { continue }
            spokenLog += " " + cleaned
            localQueue.append((text: cleaned, language: segment.locale.map { String($0.prefix(2)) } ?? String(language.rawValue.prefix(2)), voiceID: voiceIdentifier, rate: rate))
        }
        if !localActive { playNext(voiceIdentifier: voiceIdentifier, language: language, rate: rate) }
    }

    private func playNext(voiceIdentifier: String, language: AtlasLanguage, rate: Double) {
        guard !localActive else { return }
        guard !localQueue.isEmpty else {
            if pending.isEmpty { spokenLog = ""; onFinishedAll?() }
            return
        }
        let segment = localQueue.removeFirst()
        localActive = true
        let currentGeneration = generation
        // Der XTTS-Server sendet PCM 16-bit mono bei 24 kHz.
        // Wenn er nicht erreichbar ist, wird kontrolliert auf die Systemstimme gewechselt.
        localTask = Task { [weak self] in
            guard let self else { return }
            if let wav = await self.fetchLocalAudio(segment.text, language: segment.language),
               currentGeneration == self.generation {
                do {
                    let audio = try AVAudioPlayer(data: wav)
                    audio.delegate = self
                    self.player = audio
                    if audio.play() { return }
                } catch { /* fallback below */ }
            }
            guard currentGeneration == self.generation else { return }
            self.playApple(segment.text, voiceIdentifier: segment.voiceID, language: segment.language == "en" ? .britishEnglish : .german, rate: segment.rate)
        }
    }

    private func fetchLocalAudio(_ text: String, language: String) async -> Data? {
        guard let url = URL(string: "http://127.0.0.1:5002/tts") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text, "language": language, "voice": "Damien Black"
        ])
        do {
            let (pcm, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !pcm.isEmpty else { return nil }
            return Self.wav(from: pcm)
        } catch { return nil }
    }

    private static func wav(from pcm: Data) -> Data {
        var data = Data()
        func word(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func half(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        data.append(contentsOf: "RIFF".utf8); word(UInt32(pcm.count + 36))
        data.append(contentsOf: "WAVEfmt ".utf8); word(16)
        half(1); half(1); word(24000); word(48000); half(2); half(16)
        data.append(contentsOf: "data".utf8); word(UInt32(pcm.count)); data.append(pcm)
        return data
    }

    private func playApple(_ text: String, voiceIdentifier: String, language: AtlasLanguage, rate: Double) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: voiceIdentifier, language: language)
        utterance.rate = Float(min(0.6, max(0.35, rate)))
        pending.insert(ObjectIdentifier(utterance))
        apple.speak(utterance)
    }

    func stop() {
        generation += 1
        localTask?.cancel(); localTask = nil
        localQueue.removeAll()
        player?.stop(); player = nil
        localActive = false
        pending.removeAll()
        apple.stopSpeaking(at: .immediate)
        spokenLog = ""
    }

    private func segmentFinished() {
        localActive = false
        player = nil
        playNext(voiceIdentifier: "", language: .german, rate: 0.46)
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.segmentFinished() }
    }
    private func finished(_ utterance: AVSpeechUtterance) {
        guard pending.remove(ObjectIdentifier(utterance)) != nil else { return }
        segmentFinished()
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

