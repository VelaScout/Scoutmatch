import Foundation

/// Ein Bestandteil einer Nachricht: Text, Bild oder PDF-Dokument.
enum ContentPart: Sendable, Equatable {
    case text(String)
    /// JPEG- oder PNG-Daten
    case image(data: Data, mediaType: String)
    case pdf(data: Data, name: String)
}

/// Ein Gesprächsbeitrag, wie er an das KI-Modell geschickt wird.
struct ChatTurn: Sendable, Equatable {
    enum Role: String, Sendable {
        case user, assistant
    }

    let role: Role
    let parts: [ContentPart]

    init(role: Role, text: String) {
        self.role = role
        self.parts = [.text(text)]
    }

    init(role: Role, parts: [ContentPart]) {
        self.role = role
        self.parts = parts
    }

    var plainText: String {
        parts.compactMap { part -> String? in
            if case .text(let text) = part { return text }
            return nil
        }
            .joined(separator: "\n")
    }
}

/// Einstellungen für eine einzelne Anfrage.
struct AIRequestOptions: Sendable {
    var model: String
    var effort: String
    var systemPrompt: String
    var webSearch: Bool
    /// Werkzeug-Definitionen als JSON (siehe `ToolCatalog`), leer = keine Werkzeuge.
    var toolDefinitionsJSON: Data? = nil
    var maxTokens: Int = 8192
    /// Alle Erinnerungen; das lokale Backend wählt daraus die zur Frage passenden aus.
    var memories: [String] = []
}

/// Was während einer Antwort passiert.
enum AssistantEvent: Sendable {
    /// Ein Stück gesprochener Antworttext.
    case text(String)
    /// ATLAS benutzt gerade ein Werkzeug (z. B. Kalender).
    case toolStarted(name: String)
    case toolFinished(name: String, succeeded: Bool)
    /// ATLAS durchsucht das Internet.
    case searching
}

/// Ergebnis einer Werkzeug-Ausführung, das an das Modell zurückgeht.
struct ToolResult: Sendable {
    var content: String
    var isError: Bool = false
}

/// Führt Werkzeuge aus, die das Modell anfordert (Kalender, Erinnerungen …).
@MainActor
protocol ToolExecuting: AnyObject {
    func execute(name: String, inputJSON: Data) async -> ToolResult
}

enum AIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case http(status: Int, message: String)
    case stream(String)
    case refusal
    case tooManyToolRounds

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Das lokale Backend ist nicht bereit. Bitte prüfen Sie die Verbindung in den Einstellungen."
        case .invalidResponse:
            return "Die Antwort des KI-Dienstes war unverständlich."
        case .http(let status, let message):
            switch status {
            case 401: return "Die lokale Sitzung ist abgelaufen. Bitte erneut versuchen."
            case 402, 403: return "Der Zugriff wurde verweigert. Bitte prüfen Sie den lokalen Backend-Dienst. (\(message))"
            case 413: return "Die Anfrage ist zu groß – vermutlich ist das Bild oder die PDF zu umfangreich."
            case 429: return "Zu viele Anfragen in kurzer Zeit. Bitte versuchen Sie es gleich noch einmal."
            case 500...599: return "Der KI-Dienst ist gerade überlastet oder nicht erreichbar. Bitte versuchen Sie es später erneut."
            default: return "Fehler \(status): \(message)"
            }
        case .stream(let message):
            return "Die Verbindung wurde unterbrochen: \(message)"
        case .refusal:
            return "Bei dieser Anfrage kann ich leider nicht behilflich sein."
        case .tooManyToolRounds:
            return "Diese Aufgabe war zu umfangreich, ich habe sie abgebrochen."
        }
    }
}

/// Austauschbare Schnittstelle zum „Gehirn“ von ATLAS.
/// Claude ist die erste Implementierung; OpenAI oder ein lokales Modell
/// können später als weitere Implementierung ergänzt werden.
protocol AIProvider: Sendable {
    /// Führt einen kompletten Gesprächszug aus – inklusive Werkzeugnutzung – und
    /// liefert die Antwort Stück für Stück (Streaming), damit ATLAS sofort sprechen kann.
    func runTurn(history: [ChatTurn], options: AIRequestOptions,
                 tools: (any ToolExecuting)?) -> AsyncThrowingStream<AssistantEvent, Error>
}

extension AIProvider {
    /// Einfache Frage ohne Werkzeuge; liefert den vollständigen Antworttext (z. B. für Siri).
    func answer(_ question: String, options: AIRequestOptions) async throws -> String {
        var text = ""
        for try await event in runTurn(history: [ChatTurn(role: .user, text: question)], options: options, tools: nil) {
            if case .text(let piece) = event { text += piece }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
