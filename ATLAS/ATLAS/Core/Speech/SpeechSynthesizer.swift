import AVFoundation
import Foundation

/// Sprachausgabe von A.T.L.A.S.: Premium-Stimme (ElevenLabs, als Strom) oder Apple-Stimme.
///
/// Alles läuft über die gemeinsame `AudioHub`-Leitung: Die Abschnitte einer Antwort werden
/// nacheinander erzeugt und lückenlos hintereinander abgespielt – keine Pausen zwischen Sätzen.
/// Die Premium-Stimme wird gestreamt (sie beginnt, bevor der Satz fertig geladen ist), die
/// nächsten Abschnitte laden bereits parallel. Fällt sie aus, übernimmt die Apple-Stimme den
/// Rest der Antwort – nie zwei Stimmen gleichzeitig.
@MainActor
final class SpeechSynthesizer: NSObject {
    /// Alle eingereihten Abschnitte wurden gesprochen.
    var onFinishedAll: (() -> Void)?
    /// Früher für die Mundbewegung genutzt; die Animation liest jetzt direkt die Lautstärke.
    var onWord: ((Int) -> Void)?

    private struct Item {
        let text: String
        let voiceIdentifier: String
        let language: AtlasLanguage
        let rate: Double
        let premium: AsyncThrowingStream<AVAudioPCMBuffer, Error>?
    }

    private let apple = AVSpeechSynthesizer()
    private let hub = AudioHub.shared
    private var items: [Item] = []
    private var worker: Task<Void, Never>?
    private var premiumFailed = false
    private var previousPremiumText = ""
    private var appleWaiter: AppleWaiter?
    /// Was A.T.L.A.S. in der laufenden Antwort gesagt hat – damit er sich beim Zuhören
    /// nicht mit sich selbst verwechselt.
    private(set) var spokenLog = ""

    var isSpeaking: Bool { worker != nil || !items.isEmpty || hub.isPlaying }

    override init() {
        super.init()
        apple.delegate = self
        _ = NotificationCenter.default.addObserver(forName: AudioHub.drainedNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFinished() }
        }
    }

    /// - Parameter premium: Zugangsdaten der Premium-Stimme; `nil` = Apple-Stimme.
    func speak(_ text: String, voiceIdentifier: String, language: AtlasLanguage, rate: Double,
               premium config: PremiumVoice.Config? = nil) {
        // Geschrieben „A.T.L.A.S.“, gesprochen „Atlas“ – nicht buchstabiert
        let cleaned = SpeechTextCleaner.clean(text).replacingOccurrences(of: "A.T.L.A.S.", with: "Atlas")
        guard !cleaned.isEmpty else { return }
        try? hub.startIfNeeded()
        spokenLog += " " + cleaned
        var stream: AsyncThrowingStream<AVAudioPCMBuffer, Error>?
        if let config, !premiumFailed {
            // Laden beginnt sofort – parallel zu den Abschnitten davor.
            stream = PremiumVoice.stream(text: cleaned, config: config, previousText: previousPremiumText,
                                         format: hub.playbackFormat)
            previousPremiumText = cleaned
        }
        items.append(Item(text: cleaned, voiceIdentifier: voiceIdentifier, language: language, rate: rate, premium: stream))
        startWorker()
    }

    /// Verstummt sofort.
    func stop() {
        worker?.cancel()
        worker = nil
        items.removeAll()
        apple.stopSpeaking(at: .immediate)
        appleWaiter?.finish()
        appleWaiter = nil
        hub.stopPlayback()
        premiumFailed = false
        previousPremiumText = ""
        spokenLog = ""
    }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
            guard let self, !Task.isCancelled else { return }
            self.worker = nil
            self.checkFinished()
        }
    }

    private func drain() async {
        while !Task.isCancelled, !items.isEmpty {
            let item = items.removeFirst()
            await render(item)
        }
    }

    private func render(_ item: Item) async {
        if let stream = item.premium, !premiumFailed {
            var played = false
            do {
                for try await buffer in stream {
                    if Task.isCancelled { return }
                    played = true
                    hub.play(buffer)
                }
                if played { return }
            } catch {
                if Task.isCancelled || played { return }
            }
            // Premium-Stimme ausgefallen (z. B. Kontingent aufgebraucht): Rest mit Apple-Stimme.
            premiumFailed = true
        }
        await renderWithApple(item)
    }

    /// Lässt die Apple-Stimme den Text als Audio erzeugen und reiht ihn lückenlos ein.
    private func renderWithApple(_ item: Item) async {
        let utterance = AVSpeechUtterance(string: item.text)
        utterance.voice = Self.voice(for: item.voiceIdentifier, language: item.language)
        // AVSpeechUtterance-Rate: 0 = sehr langsam, 0.5 = normal, 1 = sehr schnell.
        utterance.rate = Float(item.rate) * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate)
            + AVSpeechUtteranceMinimumSpeechRate
        // Tonhöhe unverändert lassen: Verstellen klingt bei hochwertigen Stimmen künstlich.
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0

        let waiter = AppleWaiter()
        appleWaiter = waiter
        let sink = AppleSink(hub: hub)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiter.set(continuation)
            apple.write(utterance, toBufferCallback: Self.makeBufferCallback(sink: sink, waiter: waiter))
        }
        if appleWaiter === waiter { appleWaiter = nil }
    }

    /// Der Rückruf kommt auf einem Hintergrund-Thread – deshalb `nonisolated` erzeugt.
    nonisolated private static func makeBufferCallback(sink: AppleSink, waiter: AppleWaiter) -> AVSpeechSynthesizer.BufferCallback {
        { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                // Ein leerer Puffer markiert das Ende des Abschnitts.
                waiter.finish()
                return
            }
            sink.play(pcm)
        }
    }

    private func checkFinished() {
        guard !isSpeaking else { return }
        premiumFailed = false
        previousPremiumText = ""
        spokenLog = ""
        onFinishedAll?()
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

    /// Wählt die hochwertigste installierte Stimme. Qualität geht vor: innerhalb der besten
    /// Qualitätsstufe wird eine männliche Stimme bevorzugt.
    static func bestVoice(for language: AtlasLanguage) -> AVSpeechSynthesisVoice? {
        let voices = availableVoices(for: language)
        let bestTier = voices.filter { $0.quality == voices.first?.quality }
        return bestTier.first(where: { $0.gender == .male }) ?? voices.first
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
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    // Sicherheitsnetz: Falls kein leerer End-Puffer kommt, beendet das Ende des Abschnitts das Warten.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.appleWaiter?.finish() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.appleWaiter?.finish() }
    }
}

/// Wandelt die Puffer der Apple-Stimme ins Wiedergabeformat und reiht sie ein (Hintergrund-Thread).
private final class AppleSink: @unchecked Sendable {
    private let hub: AudioHub
    private let converter: PCMStreamConverter
    private let lock = NSLock()

    init(hub: AudioHub) {
        self.hub = hub
        converter = PCMStreamConverter(target: hub.playbackFormat)
    }

    func play(_ buffer: AVAudioPCMBuffer) {
        let converted = lock.withLock { converter.convert(buffer) }
        if let converted { hub.play(converted) }
    }
}

/// Wartet genau einmal auf das Ende eines Abschnitts – auch wenn abgebrochen wird.
private final class AppleWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    func set(_ continuation: CheckedContinuation<Void, Never>) {
        let resumeNow: Bool = lock.withLock {
            if finished { return true }
            self.continuation = continuation
            return false
        }
        if resumeNow { continuation.resume() }
    }

    func finish() {
        let pending: CheckedContinuation<Void, Never>? = lock.withLock {
            guard !finished else { return nil }
            finished = true
            let pending = continuation
            continuation = nil
            return pending
        }
        pending?.resume()
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
