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
        config.timeoutIntervalForRequest = 75
        config.timeoutIntervalForResource = 180
        config.connectionProxyDictionary = [:]
        config.urlCache = nil
        return URLSession(configuration: config, delegate: LocalRedirectPolicy(), delegateQueue: nil)
    }
    private struct Handshake: Decodable { let token: String; let `protocol`: Int }
    private struct Event: Decodable {
        let type: String
        let text: String?
        let error: String?
        let truncated: Bool?
    }
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
    private struct IntentPlan: Decodable {
        struct Step: Decodable { let name: String; let input: [String: String] }
        let kind: String
        let answer: String?
        let steps: [Step]?
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
                    } }) else { throw AIError.stream("Dieses Modell verarbeitet nur Text, keine Bilder oder PDFs.") }
                    let key = try await token(using: connection)
                    try Task.checkCancellation()
                    let intentRequest = try post("/api/native/intent", object: ["message": history.last?.plainText ?? ""], token: key)
                    let (intentData, intentResponse) = try await connection.data(for: intentRequest)
                    try check(intentResponse, data: intentData)
                    let plan = try JSONDecoder().decode(IntentPlan.self, from: intentData)
                    try Task.checkCancellation()
                    if plan.kind == "answer", let answer = plan.answer {
                        continuation.yield(.text(answer)); continuation.finish(); return
                    }
                    if plan.kind == "tools" {
                        guard let tools, let steps = plan.steps, (1...3).contains(steps.count),
                              steps.allSatisfy({ ["local_open", "remember", "list_memories"].contains($0.name) }) else {
                            throw AIError.stream("Diese Aktion ist nur im Hauptfenster der Atlas-App verfügbar.")
                        }
                        for step in steps {
                            try Task.checkCancellation()
                            continuation.yield(.toolStarted(name: step.name))
                            let input = try JSONEncoder().encode(step.input)
                            let result = await tools.execute(name: step.name, inputJSON: input)
                            try Task.checkCancellation()
                            continuation.yield(.toolFinished(name: step.name, succeeded: !result.isError))
                            continuation.yield(.text(result.content + "\n"))
                            if result.isError { break }
                        }
                        continuation.finish(); return
                    }
                    guard plan.kind == "chat" else { throw AIError.invalidResponse }
                    let request = try post("/api/native/chat/stream", object: [
                        "request_id": id, "model": options.model, "system": options.systemPrompt,
                        "history": history.map { ["role": $0.role.rawValue, "content": $0.plainText] }
                    ], token: key)
                    let (bytes, response) = try await connection.bytes(for: request)
                    try check(response)
                    var completed = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if line.isEmpty { continue }
                        let event = try JSONDecoder().decode(Event.self, from: Data(line.utf8))
                        switch event.type {
                        case "start": break
                        case "delta": if let text = event.text { continuation.yield(.text(text)) }
                        case "done":
                            guard event.truncated != true else {
                                throw AIError.stream("Antwort hat das Längenlimit erreicht. Bitte nach einem kürzeren Abschnitt fragen.")
                            }
                            completed = true
                        case "cancelled": throw CancellationError()
                        case "error": throw AIError.stream(event.error ?? "Lokale Antwort fehlgeschlagen.")
                        default: throw AIError.invalidResponse
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
        let models = result?["models"] as? [String] ?? []
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
