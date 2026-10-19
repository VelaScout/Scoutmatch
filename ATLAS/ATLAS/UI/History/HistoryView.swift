import SwiftData
import SwiftUI

/// Gesprächsverlauf: ansehen, fortsetzen, löschen.
struct HistoryView: View {
    @Environment(ConversationEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ConversationRecord.startedAt, order: .reverse) private var conversations: [ConversationRecord]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        engine.startNewConversation()
                        dismiss()
                    } label: {
                        Label("Neues Gespräch beginnen", systemImage: "plus.bubble")
                    }
                }

                Section {
                    if conversations.isEmpty {
                        Text("Noch keine Gespräche.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(conversations) { conversation in
                        NavigationLink {
                            ConversationDetailView(conversation: conversation) {
                                engine.resume(conversation)
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.title).lineLimit(1)
                                Text(conversation.startedAt, format: .dateTime.day().month().year().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("Löschen", role: .destructive) { delete(conversation) }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { delete(conversations[index]) }
                    }
                }
            }
            .navigationTitle("Verlauf")
            .atlasInlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func delete(_ conversation: ConversationRecord) {
        engine.startNewConversation()
        modelContext.delete(conversation)
        try? modelContext.save()
    }
}

struct ConversationDetailView: View {
    let conversation: ConversationRecord
    let onResume: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(conversation.sortedMessages) { message in
                    HStack {
                        if message.isUser { Spacer(minLength: 40) }
                        Text(message.text)
                            .padding(12)
                            .background(message.isUser ? Color.blue.opacity(0.35) : Color.white.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .textSelection(.enabled)
                        if !message.isUser { Spacer(minLength: 40) }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(conversation.startedAt.formatted(date: .abbreviated, time: .shortened))
        .atlasInlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Fortsetzen", action: onResume)
            }
        }
    }
}
