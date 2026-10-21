import Foundation
import SwiftData

// Alle Modelle sind so aufgebaut, dass SwiftData sie später über iCloud (CloudKit)
// zwischen iPhone und Mac synchronisieren kann: jede Eigenschaft hat einen
// Standardwert, Beziehungen sind optional, es gibt keine Eindeutigkeitsregeln.

/// Ein gespeichertes Gespräch.
@Model
final class ConversationRecord {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    var title: String = "Neues Gespräch"
    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
    var messages: [MessageRecord]? = []

    init(startedAt: Date = .now, title: String = "Neues Gespräch") {
        self.id = UUID()
        self.startedAt = startedAt
        self.title = title
    }

    var sortedMessages: [MessageRecord] {
        (messages ?? []).sorted { $0.timestamp < $1.timestamp }
    }
}

@Model
final class MessageRecord {
    var id: UUID = UUID()
    /// "user" oder "assistant"
    var role: String = "user"
    var text: String = ""
    var timestamp: Date = Date.now
    var conversation: ConversationRecord?

    init(role: String, text: String, timestamp: Date = .now) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }

    var isUser: Bool { role == ChatTurn.Role.user.rawValue }
}

/// Eine Information, die sich ATLAS auf Ihren Wunsch dauerhaft merkt.
@Model
final class MemoryItem {
    var id: UUID = UUID()
    var content: String = ""
    /// Ziel, Projekt, Routine, Vorliebe, Person, Sonstiges
    var category: String = MemoryCategory.other.rawValue
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// Von A.T.L.A.S. selbst gelernt (statt vom Nutzer diktiert).
    var learned: Bool = false

    init(content: String, category: MemoryCategory, learned: Bool = false) {
        self.id = UUID()
        self.content = content
        self.category = category.rawValue
        self.createdAt = .now
        self.updatedAt = .now
        self.learned = learned
    }

    var categoryValue: MemoryCategory { MemoryCategory(rawValue: category) ?? .other }
}

enum MemoryCategory: String, CaseIterable, Identifiable {
    case goal = "Ziel"
    case project = "Projekt"
    case routine = "Routine"
    case preference = "Vorliebe"
    case person = "Person"
    case other = "Sonstiges"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .goal: return "target"
        case .project: return "folder"
        case .routine: return "repeat"
        case .preference: return "heart"
        case .person: return "person"
        case .other: return "note.text"
        }
    }
}

/// Protokoll aller Aktionen, die ATLAS ausgeführt hat – nachvollziehbar und löschbar.
@Model
final class ActivityRecord {
    var id: UUID = UUID()
    var date: Date = Date.now
    var title: String = ""
    var detail: String = ""
    var succeeded: Bool = true

    init(title: String, detail: String, succeeded: Bool) {
        self.id = UUID()
        self.date = .now
        self.title = title
        self.detail = detail
        self.succeeded = succeeded
    }
}

enum AtlasStore {
    static let models: [any PersistentModel.Type] = [
        ConversationRecord.self, MessageRecord.self, MemoryItem.self, ActivityRecord.self,
    ]

    /// Öffnet den lokalen Speicher. Ist mit iCloud-Berechtigung signiert, synchronisiert
    /// SwiftData automatisch; sonst bleibt alles nur auf dem Gerät.
    static func makeContainer() -> ModelContainer {
        let schema = Schema(models)
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .none))
        } catch {
            // Never move or silently reset a user's existing database after a migration failure.
            fatalError("Der vorhandene Atlas-Speicher konnte nicht geöffnet werden. Er wurde nicht verändert. Bitte Fehlerbericht und Datensicherung prüfen: \(error)")
        }
    }
}
