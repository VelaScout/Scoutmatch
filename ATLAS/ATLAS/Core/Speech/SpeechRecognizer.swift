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
                return "Mikrofon oder Spracherkennung sind nicht freigegeben. Bitte erlauben Sie den Zugriff in den iPhone-Einstellungen unter A.T.L.A.S."
            case .unavailable:
                return "Die Spracherkennung ist gerade nicht verfügbar."
            case .noMicrophone:
                return "Es wurde kein Mikrofon gefunden."
            case .onDeviceUnavailable:
                #if os(macOS)
                return "Für das Wake-Word „Atlas“ wird Spracherkennung direkt auf dem Mac benötigt. Bitte schalten Sie unter Systemeinstellungen → Tastatur → Diktieren das Diktieren ein (Sprache Deutsch), warten Sie den Download ab und sagen Sie dann „Schalte das Wake-Word ein“."
                #else
                return "Für das Wake-Word „Atlas“ wird Spracherkennung direkt auf dem iPhone benötigt. Bitte schalten Sie unter Einstellungen → Allgemein → Tastatur das Diktieren ein (Sprache Deutsch) und sagen Sie dann „Schalte das Wake-Word ein“."
                #endif
            }
        }
    }

    /// Wird bei jedem neuen (Zwischen-)Ergebnis aufgerufen.
    var onTranscript: ((String) -> Void)?
    /// Lautstärke des Mikrofons zwischen 0 und 1 – für die Animation.
    var onLevel: ((Float) -> Void)?
    /// Die Erkennung wurde vom System beendet (z. B. Fehler oder Zeitlimit).
    var onStop: ((Error?) -> Void)?

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

        // Gemeinsame Audio-Leitung mit Echo-Unterdrückung (A.T.L.A.S. hört sich nicht selbst).
        try AudioHub.shared.enableInput(voiceProcessing: UserDefaults.standard.bool(forKey: "bargeInEnabled"))

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = requireOnDevice ? .search : .dictation
        if recognizer.supportsOnDeviceRecognition {
            // Datenschutz und geringere Verzögerung: Audio verlässt das iPhone nicht.
            request.requiresOnDeviceRecognition = true
        }

        let id = UUID()
        sessionID = id
        AudioHub.shared.setInputHandler(Self.makeInputHandler(request: request))

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
        guard isRunning else { return }
        isRunning = false
        sessionID = UUID()
        // Das Mikrofon der gemeinsamen Leitung bleibt bereit; nur die Erkennung hört auf.
        AudioHub.shared.setInputHandler(nil)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        onLevel?(0)
    }

    // MARK: - Callbacks außerhalb des Main Threads

    /// Die Audio-Callbacks laufen auf einem Hintergrund-Thread. Deshalb werden sie
    /// bewusst `nonisolated` erzeugt und leiten nur Daten an den Main Thread weiter.
    nonisolated private static func makeInputHandler(
        request: SFSpeechAudioBufferRecognitionRequest
    ) -> (AVAudioPCMBuffer) -> Void {
        // Mit Echo-Unterdrückung liefert der Mac teils mehrere Kanäle – die Erkennung bekommt
        // sicherheitshalber immer Mono.
        let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let converter = PCMStreamConverter(target: mono)
        return { buffer in
            if buffer.format.channelCount == 1 {
                request.append(buffer)
            } else if let converted = converter.convert(buffer) {
                request.append(converted)
            }
        }
    }

    nonisolated private static func makeResultHandler(
        _ handler: @escaping @Sendable (String?, Bool, Error?) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error)
        }
    }
}
