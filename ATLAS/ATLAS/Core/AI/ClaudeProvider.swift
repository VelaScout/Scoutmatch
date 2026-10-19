import Foundation

/// Anbindung an die Claude API von Anthropic (Messages API mit Streaming).
///
/// Es gibt kein offizielles Swift-SDK, daher spricht ATLAS die REST-Schnittstelle
/// direkt an: https://api.anthropic.com/v1/messages
struct ClaudeProvider: AIProvider {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Modelle, die die serverseitige Ausweichlösung bei Ablehnungen unterstützen.
    private static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-sonnet-5-5"]

    func streamReply(history: [ChatTurn], options: AIRequestOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try Self.makeRequest(history: history, options: options)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }

                    if http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                            if data.count > 32_000 { break }
                        }
                        throw AIError.http(status: http.statusCode, message: Self.errorMessage(from: data))
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        switch Self.parse(line: line) {
                        case .text(let text): continuation.yield(text)
                        case .refusal: throw AIError.refusal
                        case .error(let message): throw AIError.stream(message)
                        case .none: break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Anfrage bauen

    private static func makeRequest(history: [ChatTurn], options: AIRequestOptions) throws -> URLRequest {
        guard let apiKey = KeychainStore.read(.anthropicAPIKey), !apiKey.isEmpty else {
            throw AIError.missingAPIKey
        }

        var body: [String: Any] = [
            "model": options.model,
            "max_tokens": options.maxTokens,
            "stream": true,
            "system": options.systemPrompt,
            // Automatisches Prompt-Caching: spart bei längeren Gesprächen Kosten und Zeit.
            "cache_control": ["type": "ephemeral"],
            "output_config": ["effort": options.effort],
            "messages": history.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]

        if options.webSearch {
            let toolType = options.model == "claude-haiku-5-5" ? "web_search_20250305" : "web_search_20260209"
            body["tools"] = [[
                "type": toolType,
                "name": "web_search",
                "max_uses": 3,
                "user_location": [
                    "type": "approximate",
                    "timezone": TimeZone.current.identifier,
                ],
            ]]
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        if fallbackModels.contains(options.model) {
            // Lehnt das Modell eine Anfrage fälschlich ab, übernimmt automatisch ein anderes Modell.
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Server-Sent Events auswerten

    enum StreamEvent: Equatable {
        case text(String)
        case refusal
        case error(String)
    }

    /// Wertet eine Zeile des SSE-Streams aus. Nur Textstücke werden weitergegeben;
    /// Denk- und Websuche-Blöcke werden übersprungen.
    static func parse(line: String) -> StreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return nil }

        switch type {
        case "content_block_delta":
            guard let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return nil }
            return .text(text)
        case "message_delta":
            guard let delta = event["delta"] as? [String: Any],
                  delta["stop_reason"] as? String == "refusal" else { return nil }
            return .refusal
        case "error":
            let error = event["error"] as? [String: Any]
            return .error(error?["message"] as? String ?? "Unbekannter Fehler")
        default:
            return nil
        }
    }

    private static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "Unbekannter Fehler"
    }
}
