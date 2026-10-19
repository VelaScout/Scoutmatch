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
                Section("Anrede") {
                    Toggle("Mit „Sir“ ansprechen", isOn: $settings.addressAsSir)
                    TextField("Ihr Vorname (optional)", text: $settings.userName)
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
                    Text("Tipp: Laden Sie unter iPhone-Einstellungen → Bedienungshilfen → Gesprochene Inhalte → Stimmen eine „Premium“- oder „Erweitert“-Stimme herunter (z. B. Deutsch oder Englisch (UK) „Daniel“). Diese klingen deutlich natürlicher.")
                }

                Section {
                    Picker("Modell", selection: $settings.model) {
                        ForEach(AtlasModel.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Denktiefe", selection: $settings.effort) {
                        ForEach(AtlasEffort.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Internetrecherche", isOn: $settings.webSearchEnabled)
                } header: {
                    Text("Intelligenz")
                } footer: {
                    Text("„Schnell“ liefert die kürzeste Antwortzeit und eignet sich für Gespräche. Die Internetrecherche verursacht pro Suche geringe Zusatzkosten.")
                }

                Section {
                    Toggle("Gesprächsmodus", isOn: $settings.conversationMode)
                    VStack(alignment: .leading) {
                        Text("Pause bis zur Antwort: \(settings.silenceTimeout, specifier: "%.1f") s")
                        Slider(value: $settings.silenceTimeout, in: 0.8...3.0, step: 0.1)
                    }
                } header: {
                    Text("Gespräch")
                } footer: {
                    Text("Im Gesprächsmodus hört ATLAS nach jeder Antwort automatisch weiter zu. Sagen Sie „Danke, das ist alles“ oder tippen Sie auf Stopp, um das Gespräch zu beenden.")
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
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
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
                    Text("Der Schlüssel liegt verschlüsselt in der iOS-Keychain, nur auf diesem Gerät, und ist nicht im App-Code enthalten.")
                }

                Section {
                    Text("Ihre gesprochenen Worte werden – wenn möglich – direkt auf dem iPhone in Text umgewandelt. Der Text Ihrer Anfrage und der bisherige Gesprächsverlauf werden zur Beantwortung an Anthropic (Claude API) übertragen. Bei aktivierter Internetrecherche sucht Claude im Web. Gespräche werden lokal auf diesem iPhone gespeichert.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Gesamten Gesprächsverlauf löschen", role: .destructive) {
                        confirmDeleteHistory = true
                    }
                } header: {
                    Text("Datenschutz & Transparenz")
                }

                Section("Info") {
                    LabeledContent("Version", value: "0.1 · Phase 1")
                    LabeledContent("Mikrofon", value: AVAudioApplication.shared.recordPermission == .granted ? "Erlaubt" : "Nicht erlaubt")
                    Button("iPhone-Einstellungen für ATLAS öffnen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            .onChange(of: settings.language) { _, _ in
                // Gewählte Stimme gehört zur alten Sprache – wieder automatisch wählen.
                settings.voiceIdentifier = ""
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .confirmationDialog("Wirklich alle Gespräche löschen?", isPresented: $confirmDeleteHistory,
                                titleVisibility: .visible) {
                Button("Alle löschen", role: .destructive, action: deleteHistory)
            } message: {
                Text("Dies kann nicht rückgängig gemacht werden.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func previewVoice() {
        engine.stopAll()
        try? AudioSessionManager.activate()
        let text = settings.language == .german
            ? "Guten Tag\(settings.addressAsSir ? ", Sir" : ""). Ich bin ATLAS. Wie kann ich Ihnen behilflich sein?"
            : "Good day\(settings.addressAsSir ? ", Sir" : ""). I am ATLAS. How may I be of assistance?"
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
        try? modelContext.delete(model: ConversationRecord.self)
        try? modelContext.delete(model: MessageRecord.self)
        try? modelContext.save()
    }
}
