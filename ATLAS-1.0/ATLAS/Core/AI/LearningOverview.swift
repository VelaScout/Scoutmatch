import Foundation

// MARK: - Daten vom lokalen Backend (/api/native/learning/overview)

struct LearningOverview: Decodable {
    struct Metrics: Decodable {
        struct TopError: Decodable {
            let tool: String; let kind: String; let count: Int
            enum CodingKeys: String, CodingKey { case tool, kind = "class", count }
        }
        let tasks: Int
        let successRate: Double?
        let toolReliability: Double?
        let avgDurationS: Double?
        let repeatedErrors: Int
        let corrections: Int
        let rules: Int
        let memoryCorrectness: Double?
        let topErrors: [TopError]
    }
    struct Snapshot: Decodable, Identifiable {
        let day: String
        let successRate: Double?
        let toolReliability: Double?
        var id: String { day }
    }
    struct Rule: Decodable, Identifiable { let id: Int; let text: String; let kind: String; let scope: String; let active: Int; let uses: Int }
    struct Experience: Decodable, Identifiable {
        let id: Int; let goal: String; let outcome: String; let verified: Int; let corrected: Int; let lesson: String; let createdAt: String
    }
    struct Skill: Decodable, Identifiable { let id: Int; let name: String; let version: Int; let description: String; let status: String; let attempts: Int }
    struct Topic: Decodable, Identifiable { let id: Int; let topic: String; let status: String; let sources: Int; let gaps: [String]; let note: String; let facts: Int }
    struct Hint: Decodable, Identifiable { let id: Int; let signature: String; let text: String; let status: String; let result: String }
    struct CodeChange: Decodable, Identifiable { let id: Int; let title: String; let files: [String]; let status: String; let securityRelevant: Int }
    struct Job: Decodable, Identifiable { let id: Int; let kind: String; let status: String; let origin: String; let createdAt: String }
    struct Settings: Decodable { let enabled: Bool; let paused: Bool; let maxMinutesPerDay: Int; let allowNetwork: Bool; let cycleHours: Int }
    struct Announcement: Decodable, Identifiable { let id: Int; let kind: String; let text: String; let securityRelevant: Bool }

    let metrics: Metrics
    let history: [Snapshot]
    let rules: [Rule]
    let experiences: [Experience]
    let skills: [Skill]
    let topics: [Topic]
    let hints: [Hint]
    let codeChanges: [CodeChange]
    let jobs: [Job]
    let settings: Settings
    let usedMinutesToday: Double
    let announcements: [Announcement]

    static func decode(_ data: Data) throws -> LearningOverview {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(LearningOverview.self, from: data)
    }
}

struct KnowledgeFact: Decodable, Identifiable {
    let id: Int; let statement: String; let kind: String; let status: String
    let sourceUrl: String; let sourceTitle: String; let retrievedAt: String
}
