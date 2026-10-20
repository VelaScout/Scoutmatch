import AVFoundation
import Foundation

/// Premium-Stimme über ElevenLabs: eine KI-Stimme, die wie ein echter Mensch klingt.
///
/// Jeder Abschnitt wird als Strom geladen (rohes PCM, 24 kHz) und schon abgespielt, während
/// der Rest noch eintrifft – A.T.L.A.S. beginnt dadurch deutlich schneller zu sprechen.
/// Die Wiedergabe übernimmt `SpeechSynthesizer` über die gemeinsame Audio-Leitung.
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

    enum StreamError: Error {
        case http(Int)
        case invalidRequest
    }

    /// Startet sofort das Laden und liefert die Audiopuffer (im angegebenen Format), sobald sie eintreffen.
    nonisolated static func stream(text: String, config: Config, previousText: String,
                                   format: AVAudioFormat) -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    guard let request = streamRequest(text: text, config: config, previousText: previousText) else {
                        throw StreamError.invalidRequest
                    }
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else { throw StreamError.http(status) }
                    // 0,1 Sekunden je Puffer (24.000 Abtastwerte/s × 2 Byte)
                    let chunkSize = 4_800
                    var pending = Data()
                    pending.reserveCapacity(chunkSize * 2)
                    for try await byte in bytes {
                        pending.append(byte)
                        if pending.count >= chunkSize {
                            if let buffer = makeBuffer(pending, format: format) { continuation.yield(buffer) }
                            pending.removeAll(keepingCapacity: true)
                        }
                    }
                    if pending.count >= 2, let buffer = makeBuffer(pending, format: format) {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 16-Bit-PCM (Little Endian) → Float-Puffer im Wiedergabeformat.
    nonisolated private static func makeBuffer(_ data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = data.count / 2
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        data.withUnsafeBytes { raw in
            for i in 0..<frames {
                let low = UInt16(raw[i * 2])
                let high = UInt16(raw[i * 2 + 1])
                channel[i] = Float(Int16(bitPattern: low | (high << 8))) / 32_768
            }
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        return buffer
    }

    nonisolated private static func streamRequest(text: String, config: Config, previousText: String) -> URLRequest? {
        let voice = config.voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !voice.isEmpty,
              let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)/stream?output_format=pcm_24000")
        else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(config.apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body(text: text, config: config, previousText: previousText))
        return request
    }

    nonisolated private static func body(text: String, config: Config, previousText: String) -> [String: Any] {
        var body: [String: Any] = [
            "text": text,
            "model_id": config.model,
            "voice_settings": [
                "stability": 0.45,         // lebendig, aber ruhig
                "similarity_boost": 0.8,
                "style": 0.2,
                "use_speaker_boost": true,
            ],
        ]
        if !previousText.isEmpty { body["previous_text"] = String(previousText.suffix(500)) }
        return body
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
