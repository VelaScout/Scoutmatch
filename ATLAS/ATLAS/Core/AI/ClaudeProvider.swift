import Foundation

/// Anbindung an die Claude API von Anthropic (Messages API mit Streaming und Werkzeugen).
///
/// Es gibt kein offizielles Swift-SDK, daher spricht ATLAS die REST-Schnittstelle
/// direkt an: https://api.anthropic.com/v1/messages
struct ClaudeProvider: AIProvider {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Modelle, die die serverseitige Ausweichlösung bei Ablehnungen unterstützen.
    private static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-sonnet-5-5"]

    /// Höchstzahl an Werkzeug-Runden pro Gesprächszug (Schutz vor Endlosschleifen).
    private static let maxRounds = 10

    func runTurn(history: [ChatTurn], options: AIRequestOptions,
                 tools: (any ToolExecuting)?) -> AsyncThrowingStream<AssistantEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Self.agentLoop(history: history, options: options, tools: tools,
                                             emit: { continuation.yield($0) })
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Werkzeug-Schleife

    /// Fragt das Modell; fordert es Werkzeuge an, werden sie ausgeführt und die Ergebnisse
    /// zurückgeschickt, bis die Antwort vollständig ist.
    private static func agentLoop(history: [ChatTurn], options: AIRequestOptions, tools: (any ToolExecuting)?,
                                  emit: @escaping @Sendable (AssistantEvent) -> Void) async throws {
        var messages: [[String: Any]] = history.map(apiMessage)
        let toolDefinitions = decodeToolDefinitions(options.toolDefinitionsJSON)

        for _ in 0..<maxRounds {
            try Task.checkCancellation()
            let response = try await streamOnce(messages: messages, options: options,
                                                clientTools: tools == nil ? [] : toolDefinitions, emit: emit)
            let content = echoableContent(response.blocks)

            switch response.stopReason {
            case "tool_use":
                guard let tools else { return }
                messages.append(["role": "assistant", "content": content])
                var results: [[String: Any]] = []
                for block in content where block["type"] as? String == "tool_use" {
                    guard let id = block["id"] as? String, let name = block["name"] as? String else { continue }
                    emit(.toolStarted(name: name))
                    let result: ToolResult
                    if response.invalidToolInputIDs.contains(id) {
                        result = ToolResult(content: "INVALID_JSON: Die Werkzeug-Eingabe war unvollständig. Bitte erneut versuchen.", isError: true)
                    } else {
                        let input = block["input"] ?? [String: Any]()
                        let data = (try? JSONSerialization.data(withJSONObject: input)) ?? Data("{}".utf8)
                        result = await tools.execute(name: name, inputJSON: data)
                    }
                    emit(.toolFinished(name: name, succeeded: !result.isError))
                    results.append([
                        "type": "tool_result",
                        "tool_use_id": id,
                        "content": result.content,
                        "is_error": result.isError,
                    ])
                }
                guard !results.isEmpty else { return }
                messages.append(["role": "user", "content": results])
            case "pause_turn":
                // Eine lange Websuche wurde pausiert: einfach fortsetzen lassen.
                messages.append(["role": "assistant", "content": content])
            case "refusal":
                throw AIError.refusal
            default:
                // end_turn, max_tokens, stop_sequence …
                return
            }
        }
        throw AIError.tooManyToolRounds
    }

    // MARK: - Eine Anfrage streamen

    private struct StreamResponse {
        var blocks: [[String: Any]]
        var stopReason: String?
        var invalidToolInputIDs: Set<String>
    }

    private static func streamOnce(messages: [[String: Any]], options: AIRequestOptions,
                                   clientTools: [[String: Any]],
                                   emit: @escaping @Sendable (AssistantEvent) -> Void) async throws -> StreamResponse {
        let request = try makeRequest(messages: messages, options: options, clientTools: clientTools)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }

        if http.statusCode != 200 {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 32_000 { break }
            }
            throw AIError.http(status: http.statusCode, message: errorMessage(from: data))
        }

        var blocks: [Int: [String: Any]] = [:]
        var partialJSON: [Int: String] = [:]
        var invalidIDs: Set<String> = []
        var stopReason: String?

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }

            switch type {
            case "content_block_start":
                guard let index = event["index"] as? Int,
                      var block = event["content_block"] as? [String: Any] else { continue }
                let blockType = block["type"] as? String
                if blockType == "tool_use" || blockType == "server_tool_use" {
                    partialJSON[index] = ""
                    block["input"] = [String: Any]()
                }
                if blockType == "server_tool_use" { emit(.searching) }
                blocks[index] = block

            case "content_block_delta":
                guard let index = event["index"] as? Int,
                      let delta = event["delta"] as? [String: Any],
                      var block = blocks[index] else { continue }
                switch delta["type"] as? String {
                case "text_delta":
                    let text = delta["text"] as? String ?? ""
                    block["text"] = (block["text"] as? String ?? "") + text
                    if !text.isEmpty { emit(.text(text)) }
                case "thinking_delta":
                    block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
                case "signature_delta":
                    block["signature"] = delta["signature"]
                case "input_json_delta":
                    partialJSON[index, default: ""] += delta["partial_json"] as? String ?? ""
                case "citations_delta":
                    var citations = block["citations"] as? [Any] ?? []
                    if let citation = delta["citation"] { citations.append(citation) }
                    block["citations"] = citations
                default:
                    break
                }
                blocks[index] = block

            case "content_block_stop":
                guard let index = event["index"] as? Int, var block = blocks[index],
                      let json = partialJSON[index] else { continue }
                if json.trimmingCharacters(in: .whitespaces).isEmpty {
                    block["input"] = [String: Any]()
                } else if let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
                    block["input"] = parsed
                } else {
                    block["input"] = [String: Any]()
                    if let id = block["id"] as? String { invalidIDs.insert(id) }
                }
                blocks[index] = block
                partialJSON[index] = nil

            case "message_delta":
                if let delta = event["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                    stopReason = reason
                }

            case "error":
                let error = event["error"] as? [String: Any]
                throw AIError.stream(error?["message"] as? String ?? "Unbekannter Fehler")

            default:
                break
            }
        }

        // Unvollständige Werkzeug-Eingaben (z. B. bei Abbruch durch max_tokens) markieren.
        for (index, _) in partialJSON {
            if var block = blocks[index] {
                block["input"] = [String: Any]()
                if let id = block["id"] as? String { invalidIDs.insert(id) }
                blocks[index] = block
            }
        }
        if stopReason == "max_tokens" { invalidIDs.formUnion(blocks.values.compactMap { $0["id"] as? String }) }

        let ordered = blocks.keys.sorted().compactMap { blocks[$0] }
        return StreamResponse(blocks: ordered, stopReason: stopReason, invalidToolInputIDs: invalidIDs)
    }

    /// Bereitet die Antwortblöcke für die Rückgabe an das Modell vor.
    /// Nach einem Modellwechsel (Ausweichmodell) werden Blöcke vor der Wechselmarke,
    /// die das neue Modell nicht verarbeiten kann, weggelassen.
    private static func echoableContent(_ blocks: [[String: Any]]) -> [[String: Any]] {
        let cleaned = blocks.map { block in block.filter { !($0.value is NSNull) } }
        guard let boundary = cleaned.lastIndex(where: { $0["type"] as? String == "fallback" }) else {
            return cleaned
        }
        let resultIDs = Set(cleaned.compactMap { block -> String? in
            guard let type = block["type"] as? String, type.hasSuffix("_tool_result") else { return nil }
            return block["tool_use_id"] as? String
        })
        var output: [[String: Any]] = []
        for (index, block) in cleaned.enumerated() {
            let type = block["type"] as? String ?? ""
            if index < boundary {
                switch type {
                case "text":
                    output.append(block)
                case "server_tool_use":
                    if let id = block["id"] as? String, resultIDs.contains(id) { output.append(block) }
                case _ where type.hasSuffix("_tool_result"):
                    output.append(block)
                default:
                    continue // thinking, tool_use und Unbekanntes vor dem Wechsel weglassen
                }
            } else if index > boundary {
                output.append(block)
            }
        }
        return output
    }

    // MARK: - Anfrage bauen

    private static func apiMessage(_ turn: ChatTurn) -> [String: Any] {
        var content: [[String: Any]] = []
        // Bilder und Dokumente stehen vor dem Text (empfohlene Reihenfolge).
        for part in turn.parts {
            switch part {
            case .image(let data, let mediaType):
                content.append(["type": "image",
                                "source": ["type": "base64", "media_type": mediaType,
                                           "data": data.base64EncodedString()]])
            case .pdf(let data, let name):
                content.append(["type": "document",
                                "title": name,
                                "source": ["type": "base64", "media_type": "application/pdf",
                                           "data": data.base64EncodedString()]])
            case .text:
                break
            }
        }
        for part in turn.parts {
            if case .text(let text) = part, !text.isEmpty {
                content.append(["type": "text", "text": text])
            }
        }
        if content.isEmpty { content.append(["type": "text", "text": "…"]) }
        return ["role": turn.role.rawValue, "content": content]
    }

    private static func decodeToolDefinitions(_ data: Data?) -> [[String: Any]] {
        guard let data, let tools = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return tools
    }

    private static func makeRequest(messages: [[String: Any]], options: AIRequestOptions,
                                    clientTools: [[String: Any]]) throws -> URLRequest {
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
            "messages": messages,
        ]

        var tools: [[String: Any]] = clientTools.map { tool in
            var tool = tool
            // Werkzeug-Eingaben sofort streamen; die Prüfung übernimmt ATLAS selbst.
            tool["eager_input_streaming"] = true
            return tool
        }
        if options.webSearch {
            let toolType = options.model == "claude-haiku-5-5" ? "web_search_20250305" : "web_search_20260209"
            tools.append([
                "type": toolType,
                "name": "web_search",
                "max_uses": 3,
                "user_location": [
                    "type": "approximate",
                    "timezone": TimeZone.current.identifier,
                ],
            ])
        }
        if !tools.isEmpty { body["tools"] = tools }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
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

    private static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "Unbekannter Fehler"
    }
}
