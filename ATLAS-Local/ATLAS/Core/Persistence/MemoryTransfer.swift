import Foundation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    /// Eigenes Dateiformat für das Gedächtnis – so bietet AirDrop „Mit A.T.L.A.S. öffnen“ an.
    static let atlasMemory = UTType(exportedAs: "de.atlas.memory", conformingTo: .json)
}

/// Kostenlose Übertragung des Gedächtnisses zwischen iPhone und Mac (z. B. per AirDrop):
/// Export als Datei, Import führt zusammen – nichts wird doppelt angelegt oder überschrieben,
/// außer ein Eintrag ist auf dem anderen Gerät neuer.
enum MemoryTransfer {
    struct Entry: Codable {
        let content: String
        let category: String
        let learned: Bool?
        let createdAt: Date
        let updatedAt: Date
    }

    struct Package: Codable {
        let version: Int
        let exportedAt: Date
        let device: String
        let entries: [Entry]
    }

    enum TransferError: LocalizedError {
        case unreadable

        var errorDescription: String? { "Die Datei ist kein A.T.L.A.S.-Gedächtnis." }
    }

    /// Schreibt das Gedächtnis in eine Datei und liefert deren Adresse.
    @MainActor
    static func exportFile(context: ModelContext) throws -> URL {
        let items = try context.fetch(FetchDescriptor<MemoryItem>(sortBy: [SortDescriptor(\.createdAt)]))
        let package = Package(version: 1, exportedAt: .now, device: PlatformBridge.isMac ? "Mac" : "iPhone",
                              entries: items.map {
                                  Entry(content: $0.content, category: $0.category, learned: $0.learned,
                                        createdAt: $0.createdAt, updatedAt: $0.updatedAt)
                              })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("A.T.L.A.S. Gedächtnis.atlasmemory")
        try encoder.encode(package).write(to: url, options: .atomic)
        return url
    }

    /// Liest eine übertragene Datei und führt sie mit dem vorhandenen Gedächtnis zusammen.
    /// - Returns: Anzahl neuer bzw. aktualisierter Einträge.
    @MainActor
    @discardableResult
    static func importFile(_ url: URL, context: ModelContext) throws -> (added: Int, updated: Int) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let package = try? decoder.decode(Package.self, from: Data(contentsOf: url)) else {
            throw TransferError.unreadable
        }

        let existing = try context.fetch(FetchDescriptor<MemoryItem>())
        var byContent: [String: MemoryItem] = [:]
        for item in existing { byContent[item.content.lowercased()] = item }

        var added = 0, updated = 0
        for entry in package.entries {
            let content = entry.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            if let item = byContent[content.lowercased()] {
                if entry.updatedAt > item.updatedAt, item.category != entry.category {
                    item.category = entry.category
                    item.updatedAt = entry.updatedAt
                    updated += 1
                }
                continue
            }
            let item = MemoryItem(content: content, category: MemoryCategory(rawValue: entry.category) ?? .other,
                                  learned: entry.learned ?? false)
            item.createdAt = entry.createdAt
            item.updatedAt = entry.updatedAt
            context.insert(item)
            byContent[content.lowercased()] = item
            added += 1
        }
        if added + updated > 0 {
            context.insert(ActivityRecord(title: "Gedächtnis übernommen",
                                          detail: "\(added) neu, \(updated) aktualisiert (von \(package.device))", succeeded: true))
        }
        try context.save()
        return (added, updated)
    }
}
