import AVFoundation
import Foundation

/// Lautstärke von Mikrofon und Sprachausgabe. Wird vom Audio-Thread geschrieben und von der
/// Animation in jedem Bild direkt gelesen – bewusst kein SwiftUI-Zustand, damit nicht jede
/// Änderung die ganze Oberfläche neu aufbaut (das ließ die Animation ruckeln).
final class AudioMeter: @unchecked Sendable {
    static let shared = AudioMeter()

    private let lock = NSLock()
    private var inputValue: Float = 0
    private var outputValue: Float = 0
    private var inputPeak: Float = 0

    var input: Float { lock.withLock { inputValue } }
    var output: Float { lock.withLock { outputValue } }

    func setInput(_ level: Float) {
        lock.withLock {
            inputValue = inputValue * 0.5 + level * 0.5
            inputPeak = max(inputPeak, level)
        }
    }

    /// Lautester Mikrofonwert seit dem letzten Zurücksetzen – zeigt, ob überhaupt Ton ankommt.
    func takeInputPeak() -> Float {
        lock.withLock {
            let peak = inputPeak
            inputPeak = 0
            return peak
        }
    }

    /// Schnell ansteigend, weich abklingend – wirkt wie natürliches Atmen statt Flackern.
    func setOutput(_ level: Float) {
        lock.withLock {
            outputValue = level > outputValue ? outputValue * 0.35 + level * 0.65 : outputValue * 0.8 + level * 0.2
        }
    }

    func reset() {
        lock.withLock {
            inputValue = 0
            outputValue = 0
        }
    }

    /// Lautstärke eines Puffers zwischen 0 (still) und 1 (laut).
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        let rms = rms(of: buffer)
        let db = 20 * log10(max(rms, 0.000_01))
        return min(max((db + 50) / 40, 0), 1)
    }

    /// Rohe Effektivlautstärke (0 = digitale Stille).
    static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        if let channel = buffer.floatChannelData?[0] {
            for i in 0..<frames { sum += channel[i] * channel[i] }
        } else if let channel = buffer.int16ChannelData?[0] {
            for i in 0..<frames {
                let sample = Float(channel[i]) / 32_768
                sum += sample * sample
            }
        } else {
            return 0
        }
        return sqrt(sum / Float(frames))
    }
}

/// Eine einzige, durchgehend laufende Audio-Leitung für Hören und Sprechen.
///
/// - Sprachausgabe (Apple-Stimme und Premium-Stimme) läuft als lückenloser Strom über einen
///   Abspieler – keine Pausen und kein Neuansetzen zwischen Sätzen.
/// - Das Mikrofon läuft über dieselbe Leitung mit Apples Echo-Unterdrückung: A.T.L.A.S. hört
///   sich nicht selbst und kann deshalb mitten im Satz unterbrochen werden.
/// - Thread-sicher: Puffer dürfen von jedem Thread eingereiht werden.
final class AudioHub: @unchecked Sendable {
    static let shared = AudioHub()

    /// Einheitliches Wiedergabeformat: 24 kHz Mono (liefert die Premium-Stimme direkt so).
    let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!

    /// Wird (auf dem Main Thread) gesendet, sobald alle eingereihten Puffer abgespielt sind.
    static let drainedNotification = Notification.Name("ATLASAudioHubDrained")

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let lock = NSLock()
    private var outputReady = false
    private var inputReady = false
    private var voiceProcessingActive = false
    /// Mikrofon-Puffer mit hörbarem Inhalt – zur Kontrolle, ob überhaupt Ton ankommt.
    private var audibleInputBuffers = 0

    /// Gespeichert, wenn die Echo-Unterdrückung auf diesem Gerät keinen Mikrofonton liefert.
    static let voiceProcessingUnavailableKey = "voiceProcessingUnavailable"

    /// Läuft die Echo-Unterdrückung (Voraussetzung, um A.T.L.A.S. per Stimme zu unterbrechen)?
    var echoCancellationActive: Bool { inputReady && voiceProcessingActive }
    private var pendingBuffers = 0
    private var generation = 0
    private var inputHandler: ((AVAudioPCMBuffer) -> Void)?

    var isPlaying: Bool { lock.withLock { pendingBuffers > 0 } }

    // MARK: - Start und Stopp (vom Main Thread)

    private func prepareOutput() throws {
        guard !outputReady else { return }
        try AudioSessionManager.activate()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil, block: Self.makeOutputTap())
        outputReady = true
    }

    /// Startet die Leitung (nur Wiedergabe, falls das Mikrofon noch nicht freigegeben ist).
    func startIfNeeded() throws {
        try prepareOutput()
        if !engine.isRunning {
            try AudioSessionManager.activate()
            engine.prepare()
            try engine.start()
        }
        if !player.isPlaying { player.play() }
    }

    /// Schaltet das Mikrofon mit Echo-Unterdrückung zu. Erst nach erteilter Erlaubnis aufrufen.
    /// - Parameter voiceProcessing: Echo-Unterdrückung (nötig, um A.T.L.A.S. per Stimme zu
    ///   unterbrechen). Ohne sie klingt die Wiedergabe etwas voller, er hört beim Sprechen aber nicht zu.
    func enableInput(voiceProcessing: Bool = true) throws {
        if inputReady, voiceProcessingActive == voiceProcessing {
            try startIfNeeded()
            return
        }
        try prepareOutput()
        if engine.isRunning { engine.stop() }
        let input = engine.inputNode
        if inputReady { input.removeTap(onBus: 0) }
        // Echo-Unterdrückung: Die eigene Stimme wird aus dem Mikrofon herausgerechnet.
        try? input.setVoiceProcessingEnabled(voiceProcessing)
        voiceProcessingActive = voiceProcessing
        if voiceProcessing {
            // Andere Apps (z. B. Spotify) dabei nicht leiser machen.
            input.voiceProcessingOtherAudioDuckingConfiguration =
                AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechRecognizer.RecognizerError.noMicrophone
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: makeInputTap())
        inputReady = true
        try startIfNeeded()

        if voiceProcessing {
            // Absicherung: Liefert die Echo-Unterdrückung auf diesem Mac/iPhone keinen Ton,
            // ohne sie weitermachen – lieber ohne Unterbrechen per Stimme als gar nicht hören.
            let before = lock.withLock { audibleInputBuffers }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.voiceProcessingActive, self.engine.isRunning else { return }
                let now = self.lock.withLock { self.audibleInputBuffers }
                guard now == before else { return }
                UserDefaults.standard.set(true, forKey: Self.voiceProcessingUnavailableKey)
                try? self.enableInput(voiceProcessing: false)
            }
        }
    }

    /// Hält alles an (App im Hintergrund): Mikrofon aus, Wiedergabe aus.
    func shutdown() {
        stopPlayback()
        if engine.isRunning { engine.stop() }
        AudioMeter.shared.reset()
    }

    // MARK: - Mikrofon

    /// Empfänger der Mikrofon-Puffer, z. B. die Spracherkennung (`nil` = niemand).
    func setInputHandler(_ handler: ((AVAudioPCMBuffer) -> Void)?) {
        lock.withLock { inputHandler = handler }
    }

    // MARK: - Vorlauf für das Live-Gespräch

    /// Hält die letzten Sekunden Mikrofon-Ton bereit – nur im Arbeitsspeicher, nichts wird
    /// gespeichert oder gesendet. Wird beim Öffnen eines Live-Gesprächs einmal übergeben, damit
    /// der Satz „Atlas, wie spät ist es?“ vollständig ankommt.
    private var prerollEnabled = false
    private var preroll = Data()
    private let prerollConverter = PCMStreamConverter(target: AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!)
    /// 4 Sekunden bei 24 kHz, 16 Bit.
    private static let prerollBytes = 24_000 * 2 * 4

    func setPrerollEnabled(_ enabled: Bool) {
        lock.withLock {
            prerollEnabled = enabled
            if !enabled { preroll.removeAll() }
        }
    }

    /// Gibt den Vorlauf (16 Bit, 24 kHz, Mono) heraus und leert ihn.
    func takePreroll() -> Data {
        lock.withLock {
            defer { preroll.removeAll() }
            return preroll
        }
    }

    private func recordPreroll(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard prerollEnabled, let converted = prerollConverter.convert(buffer),
                  let samples = converted.int16ChannelData?[0] else { return }
            preroll.append(Data(bytes: samples, count: Int(converted.frameLength) * 2))
            if preroll.count > Self.prerollBytes + 48_000 {
                preroll.removeFirst(preroll.count - Self.prerollBytes)
            }
        }
    }

    private func countAudibleInput() {
        lock.withLock { audibleInputBuffers += 1 }
    }

    private func deliverInput(_ buffer: AVAudioPCMBuffer) {
        let handler = lock.withLock { inputHandler }
        handler?(buffer)
    }

    // MARK: - Wiedergabe (von jedem Thread)

    /// Reiht einen Puffer im Wiedergabeformat lückenlos hinter die bisherigen ein.
    func play(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        if !engine.isRunning || !player.isPlaying {
            if Thread.isMainThread {
                try? startIfNeeded()
            } else {
                DispatchQueue.main.sync { try? self.startIfNeeded() }
            }
        }
        let current: Int = lock.withLock {
            pendingBuffers += 1
            return generation
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.bufferFinished(generation: current)
        }
    }

    private func bufferFinished(generation finished: Int) {
        let drained: Bool = lock.withLock {
            guard finished == generation else { return false }
            pendingBuffers = max(0, pendingBuffers - 1)
            return pendingBuffers == 0
        }
        if drained {
            DispatchQueue.main.async { NotificationCenter.default.post(name: Self.drainedNotification, object: nil) }
        }
    }

    /// Verstummt sofort – z. B. wenn der Nutzer „Stopp“ sagt.
    func stopPlayback() {
        lock.withLock {
            generation += 1
            pendingBuffers = 0
        }
        player.stop()
        if engine.isRunning { player.play() }
    }

    // MARK: - Taps (laufen auf dem Audio-Thread)

    private static func makeOutputTap() -> AVAudioNodeTapBlock {
        { buffer, _ in AudioMeter.shared.setOutput(AudioMeter.level(of: buffer)) }
    }

    private func makeInputTap() -> AVAudioNodeTapBlock {
        { [weak self] buffer, _ in
            AudioMeter.shared.setInput(AudioMeter.level(of: buffer))
            // Schon leises Raumrauschen zählt – nur echte digitale Stille nicht.
            if AudioMeter.rms(of: buffer) > 0.000_001 { self?.countAudibleInput() }
            self?.recordPreroll(buffer)
            self?.deliverInput(buffer)
        }
    }
}

/// Wandelt einen Strom von Audiopuffern fortlaufend ins Wiedergabeformat um
/// (Abtastrate und Zahlenformat), ohne Knacken an den Puffergrenzen.
final class PCMStreamConverter {
    private let target: AVAudioFormat
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    init(target: AVAudioFormat) {
        self.target = target
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0 else { return nil }
        if buffer.format == target { return buffer }
        if sourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            sourceFormat = buffer.format
        }
        guard let converter else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 512
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var provided = false
        var error: NSError?
        _ = converter.convert(to: output, error: &error) { _, status in
            if provided {
                status.pointee = .noDataNow
                return nil
            }
            provided = true
            status.pointee = .haveData
            return buffer
        }
        return output.frameLength > 0 ? output : nil
    }

    /// Gibt am Ende eines Abschnitts die letzten, noch im Umwandler steckenden Millisekunden
    /// heraus – sonst würden Satzenden abgeschnitten.
    func flush() -> AVAudioPCMBuffer? {
        guard let converter else { return nil }
        defer { converter.reset() }
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 8_192) else { return nil }
        var error: NSError?
        _ = converter.convert(to: output, error: &error) { _, status in
            status.pointee = .endOfStream
            return nil
        }
        return output.frameLength > 0 ? output : nil
    }
}
