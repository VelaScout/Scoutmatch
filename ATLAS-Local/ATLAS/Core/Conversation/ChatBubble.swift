import Foundation

/// Eine Nachricht, wie sie im Chat erscheint (nur Anzeige – gespeichert wird weiterhin als MessageRecord).
struct ChatBubble: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case user, assistant, stopped, error }
    let id: UUID
    let kind: Kind
    let text: String
    let date: Date

    init(kind: Kind, text: String, date: Date = .now) {
        self.id = UUID()
        self.kind = kind
        self.text = text
        self.date = date
    }

    var isUser: Bool { kind == .user }
}

/// Bereitet Antworttext für die Anzeige auf: Sprachmarken (`<en>…</en>`) und Denkprotokolle fallen weg,
/// Markdown bleibt erhalten (wird im Chat formatiert dargestellt).
enum ChatText {
    static func display(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: #"(?s)<think>.*?(</think>|$)"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"</?[a-z]{2}>"#, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
