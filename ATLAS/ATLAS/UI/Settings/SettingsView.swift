import AVFoundation
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ConversationEngine.self) private var engine
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput = ""
    @State private var hasAPIKey = KeychainStore.has(.anthropicAPIKey)
    @State private var confirmDeleteHistory = false
    @State private var previewSynthesizer = AVSpeechSynthesizer()

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    NavigationLink { MemoryView() } label: { Label("Gedächtnis", systemImage: "brain.head.profile") }
                    NavigationLink { PermissionsView() } label: { Label("Berechtigungen", systemImage: "lock.shield") }
                    NavigationLink { ActivityView() } label: { Label("Aktivitäten", systemImage: "list.bullet.rectangle") }
                }

                Section("Anrede") {
                    Toggle("Mit „Sir“ ansprechen", isOn: $settings.addressAsSir)
                    TextField("Ihr Vorname (optional)", text: $settings.userName)
                }

                Section("Darstellung") {
                    Picker("ATLAS zeigen als", selection: $settings.appearance) {
                        ForEach(AtlasAppearance.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                Section {
                    Picker("Sprache", selection: $settings.language) {
                        ForEach(AtlasLanguage.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Stimme", selection: $settings.voiceIdentifier) {
                        Text("Automatisch (beste verfügbare)").tag("")
                        ForEach(SpeechSynthesizer.availableVoices(for: settings.language), id: \.identifier) { voice in
                            Text("\(voice.name) · \(SpeechSynthesizer.qualityLabel(voice))").tag(voice.identifier)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Sprechtempo")
                        Slider(value: $settings.speechRate, in: 0.35...0.65)
                    }
                    Button("Stimme probehören", action: previewVoice)
                } header: {
                    Text("Sprache & Stimme")
                } footer: {
                    Text(PlatformBridge.isMac
                         ? "Tipp: Unter Systemeinstellungen → Bedienungshilfen → Gesprochene Inhalte → Systemstimme → Stimmen verwalten können Sie hochwertige Stimmen laden (z. B. Englisch (UK) „Daniel“)."
                         : "Tipp: Laden Sie unter iPhone-Einstellungen → Bedienungshilfen → Gesprochene Inhalte → Stimmen eine „Premium“- oder „Erweitert“-Stimme herunter (z. B. Englisch (UK) „Daniel“). Diese klingen deutlich natürlicher.")
                }

                Section {
                    Toggle("Gesprächsmodus", isOn: $settings.conversationMode)
                    Toggle("Wake-Word „Atlas“", isOn: $settings.wakeWordEnabled)
                    VStack(alignment: .leading) {
                        Text("Pause bis zur Antwort: \(settings.silenceTimeout, specifier: "%.1f") s")
                        Slider(value: $settings.silenceTimeout, in: 0.8...3.0, step: 0.1)
                    }
                } header: {
                    Text("Gespräch")
                } footer: {
                    Text("Gesprächsmodus: Nach jeder Antwort hört ATLAS automatisch weiter zu. Beenden mit „Danke, das ist alles“ oder Stopp.\n\nWake-Word: Solange ATLAS geöffnet und im Vordergrund ist, hört er auf „Atlas“. Die Erkennung läuft ausschließlich auf dem Gerät, nichts wird übertragen, bis Sie „Atlas“ sagen. Das Mikrofon-Symbol des Systems bleibt sichtbar. Im Hintergrund oder bei gesperrtem Bildschirm hört ATLAS nicht zu – nutzen Sie dafür „Siri, starte ATLAS“. Kostet etwas mehr Akku.")
                }

                Section {
                    Picker("Modell", selection: $settings.model) {
                        ForEach(AtlasModel.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Denktiefe", selection: $settings.effort) {
                        ForEach(AtlasEffort.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Internetrecherche", isOn: $settings.webSearchEnabled)
                    Toggle("Geräte-Funktionen (Kalender, Erinnerungen …)", isOn: $settings.toolsEnabled)
                } header: {
                    Text("Intelligenz")
                } footer: {
                    Text("„Schnell“ liefert die kürzeste Antwortzeit und eignet sich für Gespräche; „Gründlich“ für komplexe Analysen. Die Internetrecherche verursacht pro Suche geringe Zusatzkosten.")
                }

                Section {
                    Toggle("Morgendliche Tagesübersicht", isOn: $settings.morningBriefingEnabled)
                    if settings.morningBriefingEnabled {
                        DatePicker("Uhrzeit", selection: timeBinding($settings.morningBriefingMinutes),
                                   displayedComponents: .hourAndMinute)
                    }
                    Toggle("Abendlicher Rückblick", isOn: $settings.eveningReviewEnabled)
                    if settings.eveningReviewEnabled {
                        DatePicker("Uhrzeit", selection: timeBinding($settings.eveningReviewMinutes),
                                   displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Proaktive Unterstützung")
                } footer: {
                    Text("ATLAS schickt Ihnen zur gewählten Zeit eine Mitteilung. Ein Tipp darauf öffnet ATLAS, und er fasst Termine, Aufgaben und – falls gewünscht – das Wetter zusammen. Eine App darf nicht dauerhaft im Hintergrund arbeiten; deshalb entsteht die Übersicht erst beim Öffnen, dafür mit aktuellen Daten.")
                }

                Section {
                    if hasAPIKey {
                        Label("API-Schlüssel ist sicher gespeichert", systemImage: "lock.fill")
                            .foregroundStyle(.green)
                        Button("API-Schlüssel entfernen", role: .destructive) {
                            KeychainStore.delete(.anthropicAPIKey)
                            hasAPIKey = false
                        }
                    } else {
                        SecureField("sk-ant-…", text: $apiKeyInput)
                            .atlasNoAutocapitalization()
                        Button("Speichern") {
                            KeychainStore.save(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines),
                                               for: .anthropicAPIKey)
                            apiKeyInput = ""
                            hasAPIKey = KeychainStore.has(.anthropicAPIKey)
                        }
                        .disabled(apiKeyInput.isEmpty)
                    }
                } header: {
                    Text("Claude API")
                } footer: {
                    Text("Der Schlüssel liegt verschlüsselt im Schlüsselbund dieses Geräts und ist nicht im App-Code enthalten. Auf jedem Gerät (iPhone, Mac) wird er einmal eingegeben.")
                }

                Section {
                    Text("Ihre gesprochenen Worte werden – wenn möglich – direkt auf dem Gerät in Text umgewandelt. Der Text Ihrer Anfrage, angehängte Fotos/PDFs, Ihre Gedächtniseinträge und benötigte Daten aus Kalender, Erinnerungen oder Kontakten werden zur Beantwortung an Anthropic (Claude API) übertragen. Bei aktivierter Internetrecherche sucht Claude im Web. Gespräche, Gedächtnis und Aktivitäten werden lokal gespeichert – bei eingerichteter iCloud-Synchronisierung zusätzlich verschlüsselt in Ihrem privaten iCloud.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Gesamten Gesprächsverlauf löschen", role: .destructive) {
                        confirmDeleteHistory = true
                    }
                } header: {
                    Text("Datenschutz & Transparenz")
                }

                Section("Info") {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("Gerät", value: PlatformBridge.isMac ? "Mac" : "iPhone")
                }
            }
            .formStyle(.grouped)
            .onChange(of: settings.language) { _, _ in
                // Gewählte Stimme gehört zur alten Sprache – wieder automatisch wählen.
                settings.voiceIdentifier = ""
            }
            .onChange(of: settings.morningBriefingEnabled) { _, _ in reschedule() }
            .onChange(of: settings.morningBriefingMinutes) { _, _ in reschedule() }
            .onChange(of: settings.eveningReviewEnabled) { _, _ in reschedule() }
            .onChange(of: settings.eveningReviewMinutes) { _, _ in reschedule() }
            .navigationTitle("Einstellungen")
            .atlasInlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .confirmationDialog("Wirklich alle Gespräche löschen?", isPresented: $confirmDeleteHistory,
                                titleVisibility: .visible) {
                Button("Alle löschen", role: .destructive, action: deleteHistory)
            } message: {
                Text("Dies kann nicht rückgängig gemacht werden. Das Gedächtnis bleibt erhalten.")
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Minuten nach Mitternacht ⇄ Datum für den DatePicker.
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60,
                                  second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private func reschedule() {
        Task { await ProactiveScheduler.reschedule(settings: settings) }
    }

    private func previewVoice() {
        engine.stopAll()
        try? AudioSessionManager.activate()
        let text = settings.language == .german
            ? "Guten Tag\(settings.sirSuffix). Ich bin ATLAS. Wie kann ich Ihnen behilflich sein?"
            : "Good day\(settings.sirSuffix). I am ATLAS. How may I be of assistance?"
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = SpeechSynthesizer.voice(for: settings.voiceIdentifier, language: settings.language)
        utterance.rate = Float(settings.speechRate)
            * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate)
            + AVSpeechUtteranceMinimumSpeechRate
        utterance.pitchMultiplier = 0.95
        previewSynthesizer.stopSpeaking(at: .immediate)
        previewSynthesizer.speak(utterance)
    }

    private func deleteHistory() {
        engine.startNewConversation()
        try? modelContext.delete(model: MessageRecord.self)
        try? modelContext.delete(model: ConversationRecord.self)
        try? modelContext.save()
    }
}
