import Foundation
import SwiftData

/// Ein gespeichertes Gespräch – lokal auf dem iPhone (SwiftData).
@Model
final class ConversationRecord {
    var id: UUID
    var startedAt: Date
    var title: String
    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
    var messages: [MessageRecord] = []

    init(startedAt: Date = .now, title: String = "Neues Gespräch") {
        self.id = UUID()
        self.startedAt = startedAt
        self.title = title
    }

    var sortedMessages: [MessageRecord] {
        messages.sorted { $0.timestamp < $1.timestamp }
    }
}

@Model
final class MessageRecord {
    var id: UUID
    /// "user" oder "assistant"
    var role: String
    var text: String
    var timestamp: Date
    var conversation: ConversationRecord?

    init(role: String, text: String, timestamp: Date = .now) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }

    var isUser: Bool { role == ChatTurn.Role.user.rawValue }
}
