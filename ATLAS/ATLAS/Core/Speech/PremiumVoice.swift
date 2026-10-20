import AVFoundation
import Foundation

/// Premium-Stimme über ElevenLabs: eine KI-Stimme, die wie ein echter Mensch klingt.
///
/// Sätze werden nacheinander als Audio geladen (der nächste schon während der aktuelle
/// läuft) und abgespielt. Weil ElevenLabs keine Wort-Zeitpunkte liefert, werden die
/// Wort-Ereignisse für die Animation gleichmäßig über die Satzdauer verteilt.
/// Schlägt die Verbindung fehl, übernimmt automatisch die Apple-Stimme.
@MainActor
final class PremiumVoice: NSObject {
    struct Config: Equatable {
        var apiKey: String
        var voiceID: String
        /// Turbo v2.5: mehrsprachig, deutlich kürzere Ladezeit – A.T.L.A.S. beginnt schneller zu sprechen.
        var model = "eleven_turbo_v2_5"
    }

    /// Bekannte Stimmen aus der ElevenLabs-Bibliothek (frei wählbar, eigene ID möglich).
    static let presets: [(name: String, id: String)] = [
        ("George – warm, britisch", "JBFqnCBsd6RMkjVDRZzb"),
        ("Daniel – ruhig, britisch, sachlich", "onwK4e9ZLuTAKqWW03F9"),
    ]

    var onWord: ((Int) -> Void)?
    var onFinishedAll: (() -> Void)?
    /// Wird aufgerufen, wenn ein Satz nicht geladen werden konnte – der Text soll dann
    /// mit der Apple-Stimme gesprochen werden.
    var onFallback: ((String) -> Void)?

    private struct Item {
        let text: String
        var audio: Task<Data?, Never>
    }

    private var queue: [Item] = []
    private var player: AVAudioPlayer?
    private var wordTask: Task<Void, Never>?
    private var isPlaying = false
    /// Zuletzt angeforderter Text – ElevenLabs nutzt ihn für eine fließende Betonung über Abschnitte hinweg.
    private var previousText = ""

    var isSpeaking: Bool { isPlaying || !queue.isEmpty }

    func speak(_ text: String, config: Config) {
        let request = Self.request(text: text, config: config, previousText: previousText)
        previousText = text
        // Laden beginnt sofort – so ist der nächste Satz meist fertig, wenn der vorige endet.
        let audio = Task<Data?, Never> {
            guard let request,
                  let result = try? await URLSession.shared.data(for: request),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200, !result.0.isEmpty else { return nil }
            return result.0
        }
        queue.append(Item(text: text, audio: audio))
        if !isPlaying { playNext() }
    }

    func stop() {
        for item in queue { item.audio.cancel() }
        queue.removeAll()
        previousText = ""
        wordTask?.cancel()
        player?.stop()
        player = nil
        isPlaying = false
    }

    private func playNext() {
        guard !queue.isEmpty else {
            isPlaying = false
            previousText = ""
            onFinishedAll?()
            return
        }
        isPlaying = true
        let item = queue.removeFirst()
        Task {
            let data = await item.audio.value
            guard isPlaying else { return } // inzwischen gestoppt
            guard let data, let player = try? AVAudioPlayer(data: data) else {
                onFallback?(item.text)
                playNext()
                return
            }
            try? AudioSessionManager.activate()
            self.player = player
            player.delegate = self
            player.prepareToPlay()
            player.play()
            animateWords(of: item.text, duration: player.duration)
        }
    }

    /// Verteilt die Wörter gleichmäßig über die Abspieldauer – treibt das Pulsieren des Kerns.
    private func animateWords(of text: String, duration: TimeInterval) {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty, duration > 0 else { return }
        let interval = duration / Double(words.count)
        wordTask?.cancel()
        wordTask = Task { [weak self] in
            for word in words {
                guard !Task.isCancelled else { return }
                self?.onWord?(word.count)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    fileprivate func finishedCurrent() {
        wordTask?.cancel()
        player = nil
        guard isPlaying else { return }
        playNext()
    }

    private static func request(text: String, config: Config, previousText: String = "") -> URLRequest? {
        let voice = config.voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !voice.isEmpty,
              let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)?output_format=mp3_44100_128")
        else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(config.apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        var body: [String: Any] = [
            "text": text,
            "model_id": config.model,
            "voice_settings": [
                "stability": 0.55,         // ruhig und gleichmäßig, wie ein Butler
                "similarity_boost": 0.8,
                "style": 0.15,
                "use_speaker_boost": true,
            ],
        ]
        if !previousText.isEmpty { body["previous_text"] = String(previousText.suffix(500)) }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Prüft den Schlüssel mit einem kurzen Probesatz; liefert eine Fehlermeldung oder nil.
    static func test(config: Config) async -> String? {
        guard let probe = Self.request(text: "Guten Tag, Sir.", config: config) else { return "Bitte eine Stimmen-ID angeben." }
        do {
            let (_, response) = try await URLSession.shared.data(for: probe)
            switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200: return nil
            case 401: return "Der ElevenLabs-Schlüssel wurde abgelehnt."
            case 404: return "Diese Stimmen-ID gibt es nicht."
            case 429: return "Das ElevenLabs-Kontingent ist aufgebraucht oder es kamen zu viele Anfragen."
            case let code: return "ElevenLabs antwortet mit Fehler \(code)."
            }
        } catch {
            return "Keine Verbindung zu ElevenLabs."
        }
    }
}

extension PremiumVoice: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finishedCurrent() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.finishedCurrent() }
    }
}

// MARK: - Stimmen-Studio: eigene Stimme per Beschreibung erschaffen (ElevenLabs Voice Design)

extension PremiumVoice {
    struct DesignedPreview: Identifiable, Equatable {
        let id: String          // generated_voice_id
        let audio: Data         // MP3-Hörprobe
    }

    enum DesignError: LocalizedError {
        case http(Int, String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .http(401, _): return "Der ElevenLabs-Schlüssel wurde abgelehnt."
            case .http(402, _), .http(403, _): return "Ihr ElevenLabs-Tarif erlaubt das Erschaffen von Stimmen nicht oder das Kontingent ist aufgebraucht."
            case .http(422, let message): return "Die Beschreibung wurde nicht akzeptiert: \(message)"
            case .http(let code, let message): return "ElevenLabs-Fehler \(code): \(message)"
            case .invalidResponse: return "Die Antwort von ElevenLabs war unverständlich."
            }
        }
    }

    /// Standard-Beschreibung für ATLAS (Englisch beschreibt Stimmen bei ElevenLabs am zuverlässigsten).
    static let defaultVoiceDescription = """
    A calm, warm and genuinely sympathetic male voice in his late thirties with a refined, softly British tone. \
    Smooth, unhurried and articulate, with a hint of dry humour, like a trusted personal assistant. \
    Speaks German and English equally fluently and switches seamlessly between them without any accent. \
    Studio-quality, close-microphone recording, no background noise.
    """

    /// Probetext auf Deutsch mit englischen Begriffen – so hören Sie sofort, ob beide Sprachen sauber klingen.
    static let designSampleText = """
    Guten Abend, Sir. Ich bin A.T.L.A.S. – das steht für Advanced Thinking, Learning and Assistance System. \
    Ich habe Ihre Termine für morgen geprüft und einen entspannten Plan vorbereitet. \
    Shall we go through it together? Selbstverständlich erinnere ich Sie auch rechtzeitig an Ihr Training.
    """

    /// Entwirft neue Stimmen nach Beschreibung; liefert mehrere Hörproben zur Auswahl.
    static func designVoices(apiKey: String, description: String, sampleText: String) async throws -> [DesignedPreview] {
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-voice/design?output_format=mp3_44100_128")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "voice_description": description,
            "model_id": "eleven_multilingual_ttv_v2",
            "text": sampleText,
        ])
        let json = try await send(request)
        guard let previews = json["previews"] as? [[String: Any]] else { throw DesignError.invalidResponse }
        return previews.compactMap { preview in
            guard let id = preview["generated_voice_id"] as? String,
                  let base64 = preview["audio_base_64"] as? String,
                  let audio = Data(base64Encoded: base64) else { return nil }
            return DesignedPreview(id: id, audio: audio)
        }
    }

    /// Speichert eine gewählte Hörprobe dauerhaft als Stimme im ElevenLabs-Konto; liefert die Stimmen-ID.
    static func saveDesignedVoice(apiKey: String, name: String, description: String, previewID: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-voice")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "voice_name": name,
            "voice_description": description,
            "generated_voice_id": previewID,
        ])
        let json = try await send(request)
        guard let voiceID = json["voice_id"] as? String else { throw DesignError.invalidResponse }
        return voiceID
    }

    private static func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let detail = (json["detail"] as? [String: Any])?["message"] as? String
                ?? (json["detail"] as? String) ?? String(data: data, encoding: .utf8) ?? ""
            throw DesignError.http(status, String(detail.prefix(200)))
        }
        return json
    }
}
