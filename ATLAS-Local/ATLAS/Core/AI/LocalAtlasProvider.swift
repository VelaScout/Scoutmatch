import Foundation

private final class LocalRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Fixed loopback transport; redirects and proxy settings cannot send chat to a cloud service.
struct LocalAtlasProvider: AIProvider {
    let port: Int
    init(port: Int = 8765) { self.port = port }
    private func url(_ path: String) throws -> URL {
        guard (1...65535).contains(port), let result = URL(string: "http://127.0.0.1:\(port)\(path)") else {
            throw AIError.invalidResponse
        }
        return result
    }
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        // Pause ohne Daten (das Backend sendet bei langen Aufgaben alle 8 s ein Lebenszeichen)
        config.timeoutIntervalForRequest = 75
        // Gesamtdauer einer Agenten-Aufgabe (Zeitlimit im Backend: 4 Minuten plus Bestätigungen)
        config.timeoutIntervalForResource = 900
        config.connectionProxyDictionary = [:]
        config.urlCache = nil
        return URLSession(configuration: config, delegate: LocalRedirectPolicy(), delegateQueue: nil)
    }
    private struct Handshake: Decodable { let token: String; let `protocol`: Int }
    private func token(using session: URLSession) async throws -> String {
        var request = URLRequest(url: try url("/api/native/session"))
        request.timeoutInterval = 5
        let (data, response) = try await session.data(for: request)
        try check(response, data: data)
        let handshake = try JSONDecoder().decode(Handshake.self, from: data)
        guard handshake.protocol == 1, !handshake.token.isEmpty else { throw AIError.invalidResponse }
        return handshake.token
    }
    private func check(_ response: URLResponse, data: Data = Data()) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw AIError.http(status: status, message: object?["error"] as? String ?? "Lokales Backend prüfen.")
        }
    }
    private func post(_ path: String, object: [String: Any], token: String) throws -> URLRequest {
        var request = URLRequest(url: try url(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Atlas-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: object)
        return request
    }
    func actionRequest(kind: String, target: String) async throws -> (token: String, description: String) {
        let data = try await localPost("/api/action/request", object: ["kind": kind, "target": target])
        let result = try JSONSerialization.jsonObject(with: data) as? [String: String]
        guard let token = result?["token"], let description = result?["description"] else { throw AIError.invalidResponse }
        return (token, description)
    }
    func actionConfirm(token: String) async throws {
        _ = try await localPost("/api/action/confirm", object: ["token": token, "approved": true])
    }
    private func localPost(_ path: String, object: [String: Any]) async throws -> Data {
        let connection = session()
        defer { connection.invalidateAndCancel() }
        let key = try await token(using: connection)
        try Task.checkCancellation()
        let request = try post(path, object: object, token: key)
        let (data, response) = try await connection.data(for: request)
        try check(response, data: data)
        return data
    }
    private func cancel(_ id: String) async {
        let connection = session()
        defer { connection.invalidateAndCancel() }
        do {
            let key = try await token(using: connection)
            let request = try post("/api/chat/cancel", object: ["request_id": id], token: key)
            _ = try await connection.data(for: request)
        } catch { }
    }
    /// Native Werkzeugliste (aus `ToolCatalog`) als JSON-Objekte für das Backend.
    private func toolList(_ data: Data?, available: Bool) -> [[String: Any]] {
        guard available, let data, let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list
    }
    /// Ergebnis eines App-Werkzeugs oder einer Bestätigung an den wartenden Agenten zurückgeben.
    private func sendResult(id: String, result: ToolResult, token: String, using connection: URLSession) async throws {
        let request = try post("/api/native/agent/result",
                               object: ["id": id, "content": result.content, "isError": result.isError], token: token)
        let (data, response) = try await connection.data(for: request)
        try check(response, data: data)
    }
    /// Ein Gesprächszug über den lokalen Agenten (Protokoll 2): Das Backend antwortet direkt,
    /// streamt eine Antwort oder arbeitet mit Werkzeugen. Werkzeuge der App (Kalender, Mail …) und
    /// Bestätigungen fordert es als `tool_request` an; die App führt sie aus und meldet das Ergebnis.
    func runTurn(history: [ChatTurn], options: AIRequestOptions,
                 tools: (any ToolExecuting)?) -> AsyncThrowingStream<AssistantEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let id = UUID().uuidString
                let connection = session()
                defer {
                    connection.invalidateAndCancel()
                    if Task.isCancelled { Task.detached { await self.cancel(id) } }
                }
                do {
                    guard ["qwen3:4b", "qwen3:8b"].contains(options.model) else {
                        throw AIError.stream("Bitte Qwen3 4B oder 8B auswählen.")
                    }
                    guard history.allSatisfy({ turn in turn.parts.allSatisfy {
                        if case .text = $0 { return true }; return false
                    } }) else {
                        throw AIError.stream("Fotos und angehängte PDFs kann das lokale Modell nicht direkt sehen. Legen Sie die PDF in Downloads oder Dokumente und sagen Sie z. B. „Fasse die PDF Bericht in Downloads zusammen“.")
                    }
                    let key = try await token(using: connection)
                    try Task.checkCancellation()
                    let request = try post("/api/native/agent/stream", object: [
                        "request_id": id, "model": options.model, "system": options.systemPrompt,
                        "history": history.suffix(60).map { ["role": $0.role.rawValue, "content": String($0.plainText.prefix(12_000))] },
                        "memories": options.memories.prefix(500).map { String($0.prefix(1_000)) },
                        "tools": toolList(options.toolDefinitionsJSON, available: tools != nil)
                    ], token: key)
                    let (bytes, response) = try await connection.bytes(for: request)
                    if (response as? HTTPURLResponse)?.statusCode != 200 {
                        var body = Data()
                        for try await byte in bytes { body.append(byte); if body.count > 4_096 { break } }
                        try check(response, data: body)
                    }
                    var completed = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if line.isEmpty { continue }
                        guard let event = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                              let type = event["type"] as? String else { throw AIError.invalidResponse }
                        switch type {
                        case "start", "plan", "report", "ping":
                            break
                        case "status":
                            if let label = event["label"] as? String { continuation.yield(.toolStarted(name: label)) }
                        case "step":
                            let label = event["label"] as? String ?? "Arbeitet"
                            switch (event["status"] as? String) ?? "" {
                            case "läuft": continuation.yield(.toolStarted(name: label))
                            case "erledigt": continuation.yield(.toolFinished(name: label, succeeded: true))
                            default: continuation.yield(.toolFinished(name: label, succeeded: false))
                            }
                        case "delta":
                            if let text = event["text"] as? String { continuation.yield(.text(text)) }
                        case "tool_request":
                            guard let requestID = event["id"] as? String, let name = event["name"] as? String else {
                                throw AIError.invalidResponse
                            }
                            let input = try JSONSerialization.data(withJSONObject: event["input"] as? [String: Any] ?? [:])
                            let result: ToolResult
                            if let tools {
                                result = await tools.execute(name: name, inputJSON: input)
                            } else {
                                result = ToolResult(content: name == "atlas_confirm" ? "denied" : "Diese Aktion ist nur im Hauptfenster der Atlas-App verfügbar.",
                                                    isError: name != "atlas_confirm")
                            }
                            try Task.checkCancellation()
                            try await sendResult(id: requestID, result: result, token: key, using: connection)
                        case "done":
                            completed = true
                        case "cancelled": throw CancellationError()
                        case "error": throw AIError.stream(event["error"] as? String ?? "Lokale Antwort fehlgeschlagen.")
                        default: break
                        }
                        if completed { break }
                    }
                    guard completed else { throw AIError.stream("Die Antwort wurde unvollständig beendet.") }
                    continuation.finish()
                } catch {
                    if let error = error as? URLError, error.code == .cannotConnectToHost {
                        continuation.finish(throwing: AIError.stream("Atlas-Backend nicht erreichbar. Bitte INSTALLIEREN.command ausführen oder den lokalen Dienst neu starten."))
                    } else { continuation.finish(throwing: error) }
                }
            }
            continuation.onTermination = { reason in if case .cancelled = reason { task.cancel() } }
        }
    }
    func health() async throws -> String {
        let connection = session()
        defer { connection.invalidateAndCancel() }
        _ = try await token(using: connection)
        var request = URLRequest(url: try url("/api/health"))
        request.timeoutInterval = 8
        let (data, response) = try await connection.data(for: request)
        try check(response, data: data)
        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = (result?["installed"] as? [String]) ?? (result?["models"] as? [String] ?? [])
        guard result?["ollama"] as? Bool == true, !models.isEmpty else {
            throw AIError.stream("Ollama oder Qwen3 fehlt. Bitte Ollama starten und INSTALLIEREN.command erneut ausführen.")
        }
        return "Lokal verbunden: " + models.joined(separator: ", ")
    }
    func legacyMemory() async throws -> Data {
        let connection = session()
        defer { connection.invalidateAndCancel() }
        let key = try await token(using: connection)
        let request = try post("/api/native/memory/export", object: [:], token: key)
        let (data, response) = try await connection.data(for: request)
        try check(response, data: data)
        return data
    }
}
