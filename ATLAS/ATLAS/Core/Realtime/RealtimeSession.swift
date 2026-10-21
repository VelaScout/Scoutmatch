import AVFoundation
import Foundation

/// Echtzeit-Sprachgespräch über die OpenAI Realtime API (WebSocket).
///
/// Das Modell hört und spricht direkt – natürliche Betonung, Pausen und Unterbrechen wie im
/// ChatGPT-Sprachmodus. Mikrofon und Lautsprecher laufen über die gemeinsame `AudioHub`-Leitung:
/// - hoch: Mikrofon → 24 kHz/16 Bit Mono → `input_audio_buffer.append`
/// - runter: `response.output_audio.delta` → lückenlose Wiedergabe
/// - Gesprächsende erkennt der Server (semantische Sprechpausen-Erkennung)
/// - Unterbrechen: Spricht der Nutzer, verstummt die Wiedergabe sofort und der bereits
///   gehörte Teil der Antwort wird dem Server gemeldet (`conversation.item.truncate`).
/// Audio wird nur übertragen, solange eine Sitzung offen ist.
@MainActor
final class RealtimeSession {
    struct Configuration {
        var apiKey: String
        var model: String
        var voice: String
        var instructions: String
        var tools: [[String: Any]]
        /// Leise Begleit-Transkription für Verlauf und Gedächtnis (geringe Zusatzkosten).
        var transcribeInput = true
    }

    enum Event {
        case ready
        case userStartedSpeaking
        case userStoppedSpeaking
        case userTranscript(String)
        case assistantStartedSpeaking
        case assistantTranscript(String)
        case responseFinished(hadToolCalls: Bool)
        case toolCall(callID: String, name: String, arguments: String)
        case error(String)
        case closed
    }

    enum SessionError: LocalizedError {
        case invalidURL

        var errorDescription: String? { "Die Verbindung zu OpenAI konnte nicht aufgebaut werden." }
    }

    var onEvent: ((Event) -> Void)?
    private(set) var isOpen = false

    private let hub = AudioHub.shared
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var uplink: RealtimeUplink?
    private var model = ""

    // Wiedergabe der aktuellen Antwort – für das Abschneiden beim Unterbrechen
    private var currentItemID: String?
    private var receivedSamples = 0
    private var playbackStarted: Date?
    private var responseHadToolCalls = false
    private var usePreroll = false
    /// Es läuft gerade eine Antwort – ein neues `response.create` muss warten.
    private var responseActive = false
    private var responseQueued = false

    // MARK: - Verbinden

    /// - Parameter usePreroll: Die letzten Sekunden Mikrofon-Ton vor der Aktivierung (z. B. „Atlas, …“)
    ///   mitsenden, damit nichts vom ersten Satz verloren geht. Wird erst nach dem Verbinden übergeben.
    func open(_ configuration: Configuration, usePreroll: Bool) throws {
        close(notify: false)
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")
        components?.queryItems = [URLQueryItem(name: "model", value: configuration.model)]
        guard let url = components?.url else { throw SessionError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let socket = URLSession.shared.webSocketTask(with: request)
        socket.maximumMessageSize = 16 * 1024 * 1024
        self.socket = socket
        model = configuration.model
        self.usePreroll = usePreroll
        responseActive = false
        responseQueued = false
        socket.resume()
        isOpen = true

        send(sessionUpdate(configuration))
        let uplink = RealtimeUplink(socket: socket, hub: hub)
        self.uplink = uplink
        hub.setInputHandler(uplink.makeHandler())
        receiveTask = Task { [weak self] in await self?.receiveLoop() }
    }

    func close(notify: Bool = true) {
        guard isOpen || socket != nil else { return }
        isOpen = false
        uplink?.stop()
        uplink = nil
        hub.setInputHandler(nil)
        hub.setPrerollEnabled(false)
        hub.stopPlayback()
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        currentItemID = nil
        if notify { onEvent?(.closed) }
    }

    // MARK: - Senden

    /// Ergebnis eines Werkzeugs zurückgeben und das Modell weitersprechen lassen.
    func sendToolOutput(callID: String, output: String, respond: Bool = true) {
        send(["type": "conversation.item.create",
              "item": ["type": "function_call_output", "call_id": callID, "output": output]])
        if respond { requestResponse() }
    }

    /// Hinweis ins Gespräch legen (z. B. ein nachgereichtes Ergebnis) und darauf antworten lassen.
    func sendNote(_ text: String, respond: Bool = true) {
        send(["type": "conversation.item.create",
              "item": ["type": "message", "role": "system",
                       "content": [["type": "input_text", "text": text]]]])
        if respond { requestResponse() }
    }

    /// Neue Antwort anfordern – wartet, falls gerade noch eine läuft.
    private func requestResponse() {
        if responseActive {
            responseQueued = true
        } else {
            responseActive = true
            send(["type": "response.create"])
        }
    }

    /// Laufende Antwort abbrechen (z. B. Tippen auf den Kern).
    func interrupt() {
        truncatePlayback()
        send(["type": "response.cancel"])
    }

    private func send(_ object: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }
    }

    private func sessionUpdate(_ configuration: Configuration) -> [String: Any] {
        var input: [String: Any] = [
            "format": ["type": "audio/pcm", "rate": 24_000],
            // Raumhall und Hintergrundgeräusche dämpfen (MacBook-Mikrofon mit etwas Abstand)
            "noise_reduction": ["type": PlatformBridge.isMac ? "far_field" : "near_field"],
            // Erkennt am Sinn, ob Sie fertig sind – nicht nur an der Stille.
            "turn_detection": [
                "type": "semantic_vad",
                "eagerness": "auto",
                "create_response": true,
                "interrupt_response": true,
            ],
        ]
        if configuration.transcribeInput {
            input["transcription"] = ["model": "gpt-4o-mini-transcribe"]
        }
        let voice = configuration.voice.hasPrefix("voice_") ? ["id": configuration.voice] as Any : configuration.voice as Any
        return [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "model": configuration.model,
                "instructions": configuration.instructions,
                "output_modalities": ["audio"],
                "audio": [
                    "input": input,
                    "output": ["format": ["type": "audio/pcm", "rate": 24_000], "voice": voice],
                ],
                "tools": configuration.tools,
                "tool_choice": "auto",
            ] as [String: Any],
        ]
    }

    // MARK: - Empfangen

    private func receiveLoop() async {
        while !Task.isCancelled, let socket {
            do {
                let message = try await socket.receive()
                let text: String
                switch message {
                case .string(let string): text = string
                case .data(let data): text = String(decoding: data, as: UTF8.self)
                @unknown default: continue
                }
                guard let data = text.data(using: .utf8),
                      let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
                handle(event)
            } catch {
                if isOpen {
                    onEvent?(.error("Die Live-Verbindung wurde getrennt: \(error.localizedDescription)"))
                    close()
                }
                return
            }
        }
    }

    private func handle(_ event: [String: Any]) {
        switch event["type"] as? String ?? "" {
        case "session.updated":
            if usePreroll, case let preroll = hub.takePreroll(), !preroll.isEmpty {
                // Was kurz vor der Aktivierung gesagt wurde („Atlas, …“), zuerst übertragen.
                for chunk in stride(from: 0, to: preroll.count, by: 9_600) {
                    let part = preroll.subdata(in: chunk..<min(chunk + 9_600, preroll.count))
                    send(["type": "input_audio_buffer.append", "audio": part.base64EncodedString()])
                }
            }
            usePreroll = false
            hub.setPrerollEnabled(false)
            uplink?.start()
            onEvent?(.ready)

        case "input_audio_buffer.speech_started":
            // Unterbrechen: sofort verstummen, gehörten Teil melden.
            if hub.isPlaying { truncatePlayback() }
            onEvent?(.userStartedSpeaking)

        case "input_audio_buffer.speech_stopped":
            onEvent?(.userStoppedSpeaking)

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = (event["transcript"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !transcript.isEmpty {
                onEvent?(.userTranscript(transcript))
            }

        case "response.created":
            responseActive = true
            responseHadToolCalls = false

        case "response.output_audio.delta":
            guard let base64 = event["delta"] as? String, let bytes = Data(base64Encoded: base64) else { return }
            let itemID = event["item_id"] as? String
            if itemID != currentItemID {
                currentItemID = itemID
                receivedSamples = 0
                playbackStarted = nil
                onEvent?(.assistantStartedSpeaking)
            }
            if let buffer = Self.makeBuffer(bytes, format: hub.playbackFormat) {
                if playbackStarted == nil, !hub.isPlaying { playbackStarted = Date() }
                receivedSamples += Int(buffer.frameLength)
                hub.play(buffer)
            }

        case "response.output_audio_transcript.done":
            if let transcript = event["transcript"] as? String, !transcript.isEmpty {
                onEvent?(.assistantTranscript(transcript))
            }

        case "response.function_call_arguments.done":
            responseHadToolCalls = true
            onEvent?(.toolCall(callID: event["call_id"] as? String ?? "",
                               name: event["name"] as? String ?? "",
                               arguments: event["arguments"] as? String ?? "{}"))

        case "response.done":
            if let response = event["response"] as? [String: Any], let usage = response["usage"] as? [String: Any] {
                recordUsage(usage)
            }
            responseActive = false
            onEvent?(.responseFinished(hadToolCalls: responseHadToolCalls))
            if responseQueued {
                responseQueued = false
                requestResponse()
            }

        case "error":
            let error = event["error"] as? [String: Any]
            let code = error?["code"] as? String ?? ""
            // Harmlose Meldungen (z. B. Abbruch ohne laufende Antwort) nicht anzeigen.
            guard !code.contains("cancel"), !code.contains("not_active"), !code.contains("active_response") else { return }
            onEvent?(.error(error?["message"] as? String ?? "Unbekannter Fehler bei OpenAI"))

        default:
            break
        }
    }

    /// Wiedergabe stoppen und dem Server mitteilen, wie viel der Antwort wirklich gehört wurde.
    private func truncatePlayback() {
        guard let itemID = currentItemID else {
            hub.stopPlayback()
            return
        }
        let receivedMs = receivedSamples * 1_000 / 24_000
        let heardMs = playbackStarted.map { Int(Date().timeIntervalSince($0) * 1_000) } ?? 0
        hub.stopPlayback()
        send(["type": "conversation.item.truncate", "item_id": itemID, "content_index": 0,
              "audio_end_ms": max(0, min(receivedMs, heardMs))])
        currentItemID = nil
    }

    private func recordUsage(_ usage: [String: Any]) {
        let inputDetails = usage["input_token_details"] as? [String: Any] ?? [:]
        let outputDetails = usage["output_token_details"] as? [String: Any] ?? [:]
        CostTracker.shared.recordRealtime(
            model: model,
            textIn: inputDetails["text_tokens"] as? Int ?? 0,
            audioIn: inputDetails["audio_tokens"] as? Int ?? 0,
            cachedIn: inputDetails["cached_tokens"] as? Int ?? 0,
            textOut: outputDetails["text_tokens"] as? Int ?? 0,
            audioOut: outputDetails["audio_tokens"] as? Int ?? 0)
    }

    /// 16-Bit-PCM (Little Endian, 24 kHz) → Float-Puffer im Wiedergabeformat.
    private static func makeBuffer(_ data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = data.count / 2
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        data.withUnsafeBytes { raw in
            for i in 0..<frames {
                let value = UInt16(raw[i * 2]) | (UInt16(raw[i * 2 + 1]) << 8)
                channel[i] = Float(Int16(bitPattern: value)) / 32_768
            }
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        return buffer
    }
}

/// Schickt den Mikrofon-Ton (läuft auf dem Audio-Thread) in 100-ms-Paketen an OpenAI.
final class RealtimeUplink: @unchecked Sendable {
    private let socket: URLSessionWebSocketTask
    private let hub: AudioHub
    private let lock = NSLock()
    private let converter: PCMStreamConverter
    private var pending = Data()
    private var running = false

    init(socket: URLSessionWebSocketTask, hub: AudioHub) {
        self.socket = socket
        self.hub = hub
        converter = PCMStreamConverter(target: RealtimeUplink.uplinkFormat)
    }

    static let uplinkFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)!

    func start() { lock.withLock { running = true } }
    func stop() { lock.withLock { running = false } }

    func makeHandler() -> (AVAudioPCMBuffer) -> Void {
        { [weak self] buffer in self?.process(buffer) }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        // Ohne Echo-Unterdrückung nicht senden, während A.T.L.A.S. spricht – sonst würde er
        // sich selbst hören und unterbrechen.
        if !hub.echoCancellationActive && hub.isPlaying { return }
        let chunk: Data? = lock.withLock {
            guard running, let converted = converter.convert(buffer),
                  let samples = converted.int16ChannelData?[0] else { return nil }
            pending.append(Data(bytes: samples, count: Int(converted.frameLength) * 2))
            guard pending.count >= 4_800 else { return nil }   // 100 ms
            defer { pending.removeAll(keepingCapacity: true) }
            return pending
        }
        guard let chunk,
              let json = try? JSONSerialization.data(withJSONObject: [
                  "type": "input_audio_buffer.append", "audio": chunk.base64EncodedString(),
              ]),
              let text = String(data: json, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }
    }
}
