import Foundation

/// Ein Gesprächsbeitrag, wie er an das KI-Modell geschickt wird.
struct ChatTurn: Sendable, Equatable {
    enum Role: String, Sendable {
        case user, assistant
    }

    let role: Role
    let text: String
}

/// Einstellungen für eine einzelne Anfrage.
struct AIRequestOptions: Sendable {
    var model: String
    var effort: String
    var systemPrompt: String
    var webSearch: Bool
    var maxTokens: Int = 4096
}

enum AIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case http(status: Int, message: String)
    case stream(String)
    case refusal

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Es ist noch kein API-Schlüssel hinterlegt. Bitte tragen Sie ihn in den Einstellungen ein."
        case .invalidResponse:
            return "Die Antwort des KI-Dienstes war unverständlich."
        case .http(let status, let message):
            switch status {
            case 401: return "Der API-Schlüssel wurde abgelehnt. Bitte prüfen Sie ihn in den Einstellungen."
            case 402, 403: return "Der Zugriff wurde verweigert. Bitte prüfen Sie Guthaben und Berechtigungen Ihres Anthropic-Kontos. (\(message))"
            case 429: return "Zu viele Anfragen in kurzer Zeit. Bitte versuchen Sie es gleich noch einmal."
            case 500...599: return "Der KI-Dienst ist gerade überlastet oder nicht erreichbar. Bitte versuchen Sie es später erneut."
            default: return "Fehler \(status): \(message)"
            }
        case .stream(let message):
            return "Die Verbindung wurde unterbrochen: \(message)"
        case .refusal:
            return "Bei dieser Anfrage kann ich leider nicht behilflich sein."
        }
    }
}

/// Austauschbare Schnittstelle zum „Gehirn“ von ATLAS.
/// Claude ist die erste Implementierung; OpenAI oder ein lokales Modell
/// können später als weitere Implementierung ergänzt werden.
protocol AIProvider: Sendable {
    /// Liefert die Antwort Stück für Stück (Streaming), damit ATLAS
    /// schon zu sprechen beginnen kann, bevor die Antwort komplett ist.
    func streamReply(history: [ChatTurn], options: AIRequestOptions) -> AsyncThrowingStream<String, Error>
}
