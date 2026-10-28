import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Gedächtnisverwaltung: alles, was sich ATLAS merkt – ansehen, bearbeiten, löschen.
struct MemoryView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var items: [MemoryItem]

    @State private var newContent = ""
    @State private var newCategory = MemoryCategory.other
    @State private var editing: MemoryItem?
    @State private var confirmDeleteAll = false
    @State private var exportURL: URL?
    @State private var secretWarning = false
    @State private var showImporter = false
    @State private var transferStatus: String?

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                Toggle("Gedächtnis verwenden", isOn: $settings.memoryEnabled)
            } footer: {
                Text("Einträge werden auf diesem Mac gespeichert und als begrenzter Kontext an Qwen3 in Ollama übergeben. Neue Erinnerungen bitte hier anlegen. Automatisches Lernen ist in dieser Ausgabe deaktiviert.")
            }

            Section("Neuer Eintrag") {
                TextField("z. B. Ich trainiere montags und donnerstags", text: $newContent, axis: .vertical)
                Picker("Kategorie", selection: $newCategory) {
                    ForEach(MemoryCategory.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                Button("Hinzufügen") {
                    let content = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !content.isEmpty else { return }
                    guard !SecretFilter.containsSecret(content) else { secretWarning = true; return }
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
                                Text("\(item.learned ? "✦ gelernt · " : "")\(item.category) · \(item.updatedAt.formatted(date: .abbreviated, time: .omitted))")
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

            Section {
                if let exportURL, !items.isEmpty {
                    ShareLink(item: exportURL, preview: SharePreview("A.T.L.A.S.-Gedächtnis")) {
                        Label("Gedächtnis senden (z. B. per AirDrop)", systemImage: "square.and.arrow.up")
                    }
                }
                Button { showImporter = true } label: {
                    Label("Gedächtnis aus Datei übernehmen", systemImage: "square.and.arrow.down")
                }
                if let transferStatus {
                    Text(transferStatus).font(.footnote)
                }
            } header: {
                Text("Auf iPhone oder Mac übertragen")
            } footer: {
                Text("Kostenlos und ohne iCloud: Auf diesem Gerät „Gedächtnis senden“ → AirDrop → das andere Gerät wählen. Dort die Datei mit A.T.L.A.S. öffnen (oder hier „aus Datei übernehmen“). Beide Gedächtnisse werden zusammengeführt – nichts wird doppelt angelegt oder gelöscht.")
            }

            if !items.isEmpty {
                Section {
                    Button("Gesamtes Gedächtnis löschen", role: .destructive) { confirmDeleteAll = true }
                }
            }
        }
        .navigationTitle("Gedächtnis")
        .atlasInlineTitle()
        .task(id: items.count) {
            exportURL = try? MemoryTransfer.exportFile(context: modelContext)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.atlasMemory, .json]) { picked in
            do {
                let result = try MemoryTransfer.importFile(try picked.get(), context: modelContext)
                transferStatus = "✓ Übernommen: \(result.added) neue, \(result.updated) aktualisierte Einträge."
            } catch {
                transferStatus = "Fehler: " + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
        .alert("Nicht gespeichert", isPresented: $secretWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(SecretFilter.refusal)
        }
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
                if SecretFilter.containsSecret(content) {
                    Text(SecretFilter.refusal).font(.caption).foregroundStyle(.orange)
                }
                Text("Herkunft: \(item.learned ? "von Atlas aus Gesprächen gelernt" : "von Ihnen mitgeteilt") · erstellt \(item.createdAt.formatted(date: .abbreviated, time: .shortened)) · geändert \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
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
                    .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty || SecretFilter.containsSecret(content))
                }
            }
            .onAppear {
                content = item.content
                category = item.categoryValue
            }
        }
    }
}
