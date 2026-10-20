import SwiftData
import SwiftUI

/// Gedächtnisverwaltung: alles, was sich ATLAS merkt – ansehen, bearbeiten, löschen.
struct MemoryView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var items: [MemoryItem]

    @State private var newContent = ""
    @State private var newCategory = MemoryCategory.other
    @State private var editing: MemoryItem?
    @State private var confirmDeleteAll = false

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                Toggle("Gedächtnis verwenden", isOn: $settings.memoryEnabled)
            } footer: {
                Text("A.T.L.A.S. merkt sich nur, was Sie ausdrücklich sagen („Merk dir, dass …“) oder hier eintragen. Die Einträge liegen auf Ihrem Gerät und werden bei jeder Anfrage an Claude mitgeschickt, damit A.T.L.A.S. Sie kennt.")
            }

            Section("Neuer Eintrag") {
                TextField("z. B. Ich trainiere montags und donnerstags", text: $newContent, axis: .vertical)
                Picker("Kategorie", selection: $newCategory) {
                    ForEach(MemoryCategory.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                Button("Hinzufügen") {
                    let content = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !content.isEmpty else { return }
                    modelContext.insert(MemoryItem(content: content, category: newCategory))
                    try? modelContext.save()
                    newContent = ""
                }
                .disabled(newContent.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("Gespeichert (\(items.count))") {
                if items.isEmpty {
                    Text("Noch nichts gespeichert.").foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    Button { editing = item } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.categoryValue.symbol)
                                .foregroundStyle(.tint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.content).foregroundStyle(.primary)
                                Text("\(item.category) · \(item.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets { modelContext.delete(items[index]) }
                    try? modelContext.save()
                }
            }

            if !items.isEmpty {
                Section {
                    Button("Gesamtes Gedächtnis löschen", role: .destructive) { confirmDeleteAll = true }
                }
            }
        }
        .navigationTitle("Gedächtnis")
        .atlasInlineTitle()
        .sheet(item: $editing) { item in
            MemoryEditView(item: item).atlasSheetSize()
        }
        .confirmationDialog("Wirklich alles vergessen?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Alles löschen", role: .destructive) {
                for item in items { modelContext.delete(item) }
                try? modelContext.save()
            }
        }
    }
}

struct MemoryEditView: View {
    @Bindable var item: MemoryItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var category = MemoryCategory.other

    var body: some View {
        NavigationStack {
            Form {
                TextField("Inhalt", text: $content, axis: .vertical)
                Picker("Kategorie", selection: $category) {
                    ForEach(MemoryCategory.allCases) { Text($0.rawValue).tag($0) }
                }
                Button("Eintrag löschen", role: .destructive) {
                    modelContext.delete(item)
                    try? modelContext.save()
                    dismiss()
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Eintrag bearbeiten")
            .atlasInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        item.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        item.category = category.rawValue
                        item.updatedAt = .now
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                content = item.content
                category = item.categoryValue
            }
        }
    }
}
