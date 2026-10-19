import AVFoundation
import Foundation
import Speech

/// Wandelt Sprache über das Mikrofon in Text um (Apple Speech Framework).
/// Wenn das iPhone es unterstützt, läuft die Erkennung komplett auf dem Gerät.
@MainActor
final class SpeechRecognizer {
    enum RecognizerError: LocalizedError {
        case notAuthorized
        case unavailable
        case noMicrophone
        case onDeviceUnavailable

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Mikrofon oder Spracherkennung sind nicht freigegeben. Bitte erlauben Sie den Zugriff in den iPhone-Einstellungen unter ATLAS."
            case .unavailable:
                return "Die Spracherkennung ist gerade nicht verfügbar."
            case .noMicrophone:
                return "Es wurde kein Mikrofon gefunden."
            case .onDeviceUnavailable:
                return "Für das Wake-Word „Atlas“ wird Spracherkennung direkt auf dem Gerät benötigt. Bitte laden Sie in den Systemeinstellungen die Diktiersprache herunter oder schalten Sie das Wake-Word aus."
            }
        }
    }

    /// Wird bei jedem neuen (Zwischen-)Ergebnis aufgerufen.
    var onTranscript: ((String) -> Void)?
    /// Lautstärke des Mikrofons zwischen 0 und 1 – für die Animation.
    var onLevel: ((Float) -> Void)?
    /// Die Erkennung wurde vom System beendet (z. B. Fehler oder Zeitlimit).
    var onStop: ((Error?) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var sessionID = UUID()

    private(set) var isRunning = false

    // MARK: - Berechtigungen

    static func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Start / Stopp

    /// - Parameter requireOnDevice: Für das Wake-Word muss die Erkennung auf dem Gerät laufen,
    ///   damit im Bereitschaftsmodus kein Ton das Gerät verlässt.
    func start(language: AtlasLanguage, requireOnDevice: Bool = false) throws {
        stop()

        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted else {
            throw RecognizerError.notAuthorized
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue)),
              recognizer.isAvailable else {
            throw RecognizerError.unavailable
        }

        if requireOnDevice && !recognizer.supportsOnDeviceRecognition {
            throw RecognizerError.onDeviceUnavailable
        }

        try AudioSessionManager.activate()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = requireOnDevice ? .search : .dictation
        if recognizer.supportsOnDeviceRecognition {
            // Datenschutz und geringere Verzögerung: Audio verlässt das iPhone nicht.
            request.requiresOnDeviceRecognition = true
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecognizerError.noMicrophone }

        let id = UUID()
        sessionID = id

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format,
                             block: Self.makeTapBlock(request: request) { [weak self] level in
                                 Task { @MainActor in self?.onLevel?(level) }
                             })

        audioEngine.prepare()
        try audioEngine.start()

        self.request = request
        task = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler { [weak self] text, isFinal, error in
            Task { @MainActor in
                guard let self, self.sessionID == id, self.isRunning else { return }
                if let text { self.onTranscript?(text) }
                if isFinal || error != nil {
                    self.stop()
                    self.onStop?(error)
                }
            }
        })
        isRunning = true
    }

    func stop() {
        guard isRunning || audioEngine.isRunning else { return }
        isRunning = false
        sessionID = UUID()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        onLevel?(0)
    }

    // MARK: - Callbacks außerhalb des Main Threads

    /// Die Audio-Callbacks laufen auf einem Hintergrund-Thread. Deshalb werden sie
    /// bewusst `nonisolated` erzeugt und leiten nur Daten an den Main Thread weiter.
    nonisolated private static func makeTapBlock(
        request: SFSpeechAudioBufferRecognitionRequest,
        level: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            level(rmsLevel(of: buffer))
        }
    }

    nonisolated private static func makeResultHandler(
        _ handler: @escaping @Sendable (String?, Bool, Error?) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error)
        }
    }

    nonisolated private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frames { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(frames))
        // In Dezibel umrechnen und auf 0...1 abbilden (-50 dB = still, -10 dB = laut).
        let db = 20 * log10(max(rms, 0.000_01))
        return min(max((db + 50) / 40, 0), 1)
    }
}
