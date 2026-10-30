import AVFoundation
import SwiftData
import SwiftUI
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ConversationEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext
    @State private var status = "Verbindung wird geprüft …"
    @State private var busy = false
    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("ATLAS Local · Core 2.0.3") {
                Text(status).font(.callout).textSelection(.enabled)
                Button("Verbindung prüfen") { Task { await check() } }.disabled(busy)
                Picker("Modell", selection: $settings.model) {
                    ForEach(AtlasModel.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Gespräche: das gewählte Modell (4B antwortet am schnellsten). Aufgaben mit Werkzeugen erledigt Atlas automatisch mit 8B, wenn es installiert ist – das Update lädt es.").font(.caption)
            }
            Section("Sprache auf diesem Mac") {
                Picker("Sprache", selection: $settings.language) {
                    ForEach(AtlasLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Stimme", selection: $settings.voiceIdentifier) {
                    Text("Systemstimme").tag("")
                    ForEach(AVSpeechSynthesisVoice.speechVoices().filter {
                        !$0.voiceTraits.contains(.isNoveltyVoice) && $0.language.hasPrefix(String(settings.language.rawValue.prefix(2)))
                    }, id: \.identifier) { voice in Text("\(voice.name) · \(SpeechSynthesizer.qualityLabel(voice))").tag(voice.identifier) }
                }
                Slider(value: $settings.speechRate, in: 0.35...0.6) { Text("Sprechtempo") }
                Toggle("Mikrofon", isOn: Binding(get: { settings.microphoneEnabled }, set: { engine.setMicrophoneEnabled($0) }))
                Toggle("Nach einer Antwort weiter zuhören", isOn: $settings.conversationMode)
                Toggle("Auf das Wort Atlas warten", isOn: $settings.wakeWordEnabled)
                Toggle("Im Hintergrund zuhören", isOn: $settings.backgroundListening)
                Text("Ausgewählte Systemstimme: " + (SpeechSynthesizer.voice(for: settings.voiceIdentifier, language: settings.language)?.name ?? "Nicht verfügbar")).font(.caption)
                Text("Apple-Spracherkennung ausschließlich auf dem Gerät. Fehlt das lokale Sprachpaket, zeigt Atlas einen Fehler; Texteingabe funktioniert weiter. Natürlicher klingt eine Premium-Stimme: Systemeinstellungen → Bedienungshilfen → Gesprochene Inhalte → Systemstimme → Stimmen verwalten → Deutsch → „Premium“ laden.").font(.caption)
            }
            Section("Persönlichkeit und Darstellung") {
                TextField("Ihr Name", text: $settings.userName)
                TextField("Förmliche Anrede", text: $settings.formalAddress)
                Toggle("Gelegentlich Sir sagen", isOn: $settings.addressAsSir)
                Picker("Darstellung", selection: $settings.appearance) {
                    ForEach(AtlasAppearance.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section("Gedächtnis") {
                Toggle("Gespeicherte Erinnerungen verwenden", isOn: $settings.memoryEnabled)
                Button("Erinnerungen aus Atlas 0.2 Web übernehmen") { Task { await importMemory() } }.disabled(busy)
                Text("Führt Erinnerungen zusammen, ohne Web-Daten zu löschen. Gesprächsverläufe bleiben getrennt. Neue Erinnerungen im Bereich Gedächtnis anlegen.").font(.caption)
            }
            Section("Cloud-Modell (optional, standardmäßig aus)") {
                NavigationLink("Cloud-Modell einrichten") { CloudSettingsView() }
                Text("Für schwierige Aufgaben auf ausdrücklichen Wunsch („Cloud: …“). Mit Kostenanzeige, Monatslimit und Rückfrage vor jeder Übertragung.").font(.caption)
            }
            Section("Lernen und Weiterentwicklung") {
                NavigationLink("ATLAS – Learning & Evolution") { LearningView() }
                Text("Was Atlas gelernt hat, selbst entwickelte Fähigkeiten, Wissen mit Quellen, Verbesserungen und alles, was auf Ihre Freigabe wartet.").font(.caption)
            }
            Section("Funktionsumfang") {
                Text("Lokaler Text- und Sprachchat, Aufgaben mit Werkzeugen (Dateien, Ordner, Excel, PDF, Apps, Websuche, Systeminfo, erlaubte Terminalbefehle, Bildschirm), Gedächtnis und Lernen. Löschen, Überschreiben und ändernde Befehle nur nach Ihrer Bestätigung. Keine Cloud-Dienste.").font(.caption)
            }
        }.formStyle(.grouped).navigationTitle("Einstellungen").task { await check() }
    }
    private func check() async {
        busy = true
        defer { busy = false }
        do { status = try await LocalAtlasProvider().health() }
        catch { status = error.localizedDescription }
    }
    private func importMemory() async {
        busy = true
        defer { busy = false }
        do {
            let data = try await LocalAtlasProvider().legacyMemory()
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".atlasmemory")
            defer { try? FileManager.default.removeItem(at: file) }
            try data.write(to: file, options: .atomic)
            let result = try MemoryTransfer.importFile(file, context: modelContext)
            status = "Erinnerungen übernommen: \(result.added) neu, \(result.updated) aktualisiert."
        } catch { status = error.localizedDescription }
    }
}
