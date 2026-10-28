import SwiftData
import SwiftUI

/// Aktivitätsprotokoll: jede Aktion, die ATLAS ausgeführt hat – nachvollziehbar.
struct ActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActivityRecord.date, order: .reverse) private var records: [ActivityRecord]

    var body: some View {
        List {
            if records.isEmpty {
                Text("Noch keine Aktivitäten.").foregroundStyle(.secondary)
            }
            ForEach(records) { record in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: record.succeeded ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(record.succeeded ? .green : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.title)
                        if !record.detail.isEmpty {
                            Text(record.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(record.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle("Aktivitäten")
        .atlasInlineTitle()
        .toolbar {
            if !records.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Leeren", role: .destructive) {
                        try? modelContext.delete(model: ActivityRecord.self)
                        try? modelContext.save()
                    }
                }
            }
        }
    }
}
