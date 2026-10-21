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
    @State private var previewSpeaker = SpeechSynthesizer()
    @State private var elevenKeyInput = ""
    @State private var hasElevenKey = KeychainStore.has(.elevenLabsAPIKey)
    @State private var openAIKeyInput = ""
    @State private var hasOpenAIKey = KeychainStore.has(.openAIAPIKey)
    @State private var localVoices: [String] = []
    @State private var premiumTestResult: String?
    @State private var testingPremium = false

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    NavigationLink { ConnectionsView() } label: { Label("Verbindungen (E-Mail, Spotify)", systemImage: "link") }
                    NavigationLink { MemoryView() } label: { Label("Gedächtnis", systemImage: "brain.head.profile") }
                    NavigationLink { PermissionsView() } label: { Label("Berechtigungen", systemImage: "lock.shield") }
                    NavigationLink { ActivityView() } label: { Label("Aktivitäten", systemImage: "list.bullet.rectangle") }
                }

                Section("Anrede") {
                    Toggle("Mit „Sir“ ansprechen", isOn: $settings.addressAsSir)
                    TextField("Förmliche Anrede, z. B. Herr Velasco", text: $settings.formalAddress)
                    TextField("Ihr Vorname (optional)", text: $settings.userName)
                    Toggle("Begrüßung beim Öffnen", isOn: $settings.greetOnLaunch)
                    Toggle("Denkpausen überbrücken („Hm, Moment …“)", isOn: $settings.thinkingFillers)
                    Toggle("Unterbrechen per Stimme („Stopp“, experimentell)", isOn: $settings.bargeIn)
                }

                Section("Darstellung") {
                    Picker("A.T.L.A.S. zeigen als", selection: $settings.appearance) {
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
                    Toggle("Premium-Stimme verwenden", isOn: $settings.premiumVoiceEnabled)
                    if settings.premiumVoiceEnabled {
                        Picker("Anbieter", selection: $settings.premiumProvider) {
                            ForEach(PremiumProvider.allCases) { Text($0.displayName).tag($0) }
                        }
                        if settings.premiumProvider == .openAI {
                            if hasOpenAIKey {
                                Label("OpenAI-Schlüssel gespeichert", systemImage: "lock.fill")
                                    .foregroundStyle(.green)
                            } else {
                                SecureField("OpenAI-API-Schlüssel (sk-…)", text: $openAIKeyInput)
                                    .atlasNoAutocapitalization()
                                Button("Schlüssel speichern") {
                                    KeychainStore.save(openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines),
                                                       for: .openAIAPIKey)
                                    openAIKeyInput = ""
                                    hasOpenAIKey = KeychainStore.has(.openAIAPIKey)
                                }
                                .disabled(openAIKeyInput.isEmpty)
                            }
                            Picker("Stimme", selection: $settings.openAIVoice) {
                                ForEach(PremiumVoice.openAIVoices, id: \.self) { Text($0.capitalized).tag($0) }
                                if !PremiumVoice.openAIVoices.contains(settings.openAIVoice) {
                                    Text("Eigene Stimme").tag(settings.openAIVoice)
                                }
                            }
                            TextField("Eigene Stimmen-ID (voice_…, optional)", text: $settings.openAIVoice)
                                .atlasNoAutocapitalization()
                                .font(.footnote.monospaced())
                            TextField("So soll die Stimme sprechen", text: $settings.openAIVoiceStyle, axis: .vertical)
                                .lineLimit(2...5)
                            Button(testingPremium ? "Teste …" : "Verbindung testen") { testPremium() }
                                .disabled(!hasOpenAIKey || testingPremium)
                            if hasOpenAIKey {
                                Button("OpenAI-Schlüssel entfernen", role: .destructive) {
                                    KeychainStore.delete(.openAIAPIKey)
                                    hasOpenAIKey = false
                                }
                            }
                        } else if settings.premiumProvider == .local {
                            TextField("Adresse der KI-Stimme", text: $settings.localVoiceURL)
                                .atlasNoAutocapitalization()
                                .font(.footnote.monospaced())
                            if localVoices.isEmpty {
                                TextField("Stimme (leer = Standard)", text: $settings.localVoiceName)
                                    .atlasNoAutocapitalization()
                            } else {
                                Picker("Stimme", selection: $settings.localVoiceName) {
                                    Text("Standard").tag("")
                                    ForEach(localVoices, id: \.self) { Text($0 == "eigene" ? "Eigene (stimme.wav)" : $0).tag($0) }
                                }
                            }
                            Button(testingPremium ? "Verbinde …" : "Verbinden & Stimmen laden") {
                                testingPremium = true
                                premiumTestResult = nil
                                Task {
                                    let result = await PremiumVoice.checkLocal(baseURL: settings.localVoiceURL)
                                    localVoices = result.voices
                                    premiumTestResult = result.error ?? "✓ Eigene KI-Stimme ist bereit – \(result.voices.count) Stimmen."
                                    testingPremium = false
                                }
                            }
                            .disabled(testingPremium)
                        } else {
                            if hasElevenKey {
                                Label("ElevenLabs-Schlüssel gespeichert", systemImage: "lock.fill")
                                    .foregroundStyle(.green)
                            } else {
                                SecureField("ElevenLabs-API-Schlüssel", text: $elevenKeyInput)
                                    .atlasNoAutocapitalization()
                                Button("Schlüssel speichern") {
                                    KeychainStore.save(elevenKeyInput.trimmingCharacters(in: .whitespacesAndNewlines),
                                                       for: .elevenLabsAPIKey)
                                    elevenKeyInput = ""
                                    hasElevenKey = KeychainStore.has(.elevenLabsAPIKey)
                                }
                                .disabled(elevenKeyInput.isEmpty)
                            }
                            Picker("Stimme", selection: $settings.premiumVoiceID) {
                                ForEach(PremiumVoice.presets, id: \.id) { Text($0.name).tag($0.id) }
                                if !PremiumVoice.presets.contains(where: { $0.id == settings.premiumVoiceID }) {
                                    Text("Eigene Stimme").tag(settings.premiumVoiceID)
                                }
                            }
                            NavigationLink {
                                VoiceStudioView()
                            } label: {
                                Label("Eigene Stimme erschaffen", systemImage: "waveform.badge.plus")
                            }
                            .disabled(!hasElevenKey)
                            TextField("Eigene Stimmen-ID (optional)", text: $settings.premiumVoiceID)
                                .atlasNoAutocapitalization()
                                .font(.footnote.monospaced())
                            Button(testingPremium ? "Teste …" : "Verbindung testen") { testPremium() }
                                .disabled(!hasElevenKey || testingPremium)
                            if hasElevenKey {
                                Button("ElevenLabs-Schlüssel entfernen", role: .destructive) {
                                    KeychainStore.delete(.elevenLabsAPIKey)
                                    hasElevenKey = false
                                }
                            }
                        }
                        if let premiumTestResult {
                            Text(premiumTestResult)
                                .font(.footnote)
                                .foregroundStyle(premiumTestResult.hasPrefix("✓") ? .green : .orange)
                        }
                    }
                } header: {
                    Text("Premium-Stimme")
                } footer: {
                    Text(settings.premiumProvider == .local
                         ? "Ihre eigene, kostenlose KI-Stimme: Sie läuft auf Ihrem Mac (freie Sprach-KI XTTS, private Nutzung). Einrichtung einmalig im Terminal: Ordner „ATLAS/VoiceServer“ → „bash install.sh“. Danach startet sie automatisch mit dem Mac. Eigene Stimme: eine klare Hörprobe als „stimme.wav“ in diesen Ordner legen. Vom iPhone aus statt 127.0.0.1 den Namen Ihres Macs eintragen, z. B. http://Mein-MacBook.local:5002 (beide im selben WLAN). Läuft sie nicht, spricht automatisch die Apple-Stimme."
                         : settings.premiumProvider == .openAI
                         ? "OpenAI-Stimmen klingen sehr natürlich und sprechen alle Sprachen akzentfrei. Benötigt einen API-Schlüssel von platform.openai.com mit etwas Guthaben (das ChatGPT-Abo zählt nicht; Kosten: etwa 1–2 Cent pro Minute Sprache). Im Feld darunter beschreiben Sie, wie die Stimme sprechen soll. Selbst entworfene Stimmen aus einer Text-Beschreibung lässt OpenAI nur in seinem eigenen Live-Modus zu – hier funktionieren die eingebauten Stimmen und Stimmen aus Hörproben. Die Antworttexte werden dafür an OpenAI gesendet. Ohne Verbindung spricht automatisch die Apple-Stimme."
                         : "Eine KI-Stimme von ElevenLabs, die wie ein echter Mensch klingt – deutlich geschmeidiger als die Systemstimmen. Benötigt ein Konto auf elevenlabs.io und einen API-Schlüssel (kleines kostenloses Kontingent pro Monat). Die Antworttexte werden dafür an ElevenLabs gesendet. Ohne Verbindung spricht automatisch die Apple-Stimme.")
                }

                Section {
                    Toggle("Gesprächsmodus", isOn: $settings.conversationMode)
                    Toggle("Immer zuhören (einfach losreden)", isOn: $settings.alwaysListen)
                        .onChange(of: settings.alwaysListen) { _, _ in engine.wakeWordSettingChanged() }
                    Toggle("Wake-Word „Atlas“", isOn: $settings.wakeWordEnabled)
                    VStack(alignment: .leading) {
                        Text("Pause bis zur Antwort: \(settings.silenceTimeout, specifier: "%.1f") s")
                        Slider(value: $settings.silenceTimeout, in: 0.8...3.0, step: 0.1)
                    }
                } header: {
                    Text("Gespräch")
                } footer: {
                    Text("Immer zuhören: Solange A.T.L.A.S. geöffnet ist, hört er durchgehend zu – einfach losreden, er antwortet nach einer kurzen Pause. Die Spracherkennung läuft auf dem Gerät; erst ein vollständiger Satz wird als Frage an Claude geschickt. Achtung: Er reagiert dann auch auf Gespräche im Raum – bei Besuch einfach „Hör auf zuzuhören“ sagen oder hier ausschalten.\n\nGesprächsmodus: Nach jeder Antwort hört A.T.L.A.S. automatisch weiter zu. Beenden mit „Danke, das ist alles“ oder Stopp.\n\nWake-Word: Solange A.T.L.A.S. geöffnet und im Vordergrund ist, hört er auf „Atlas“. Die Erkennung läuft ausschließlich auf dem Gerät, nichts wird übertragen, bis Sie „Atlas“ sagen. Das Mikrofon-Symbol des Systems bleibt sichtbar. Im Hintergrund oder bei gesperrtem Bildschirm hört A.T.L.A.S. nicht zu – nutzen Sie dafür „Siri, starte A.T.L.A.S.“. Kostet etwas mehr Akku.")
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
                    Text("A.T.L.A.S. schickt Ihnen zur gewählten Zeit eine Mitteilung. Ein Tipp darauf öffnet A.T.L.A.S., und er fasst Termine, Aufgaben und – falls gewünscht – das Wetter zusammen. Eine App darf nicht dauerhaft im Hintergrund arbeiten; deshalb entsteht die Übersicht erst beim Öffnen, dafür mit aktuellen Daten.")
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
            ? "Guten Tag\(settings.sirSuffix). Ich bin A.T.L.A.S. Wie kann ich Ihnen behilflich sein?"
            : "Good day\(settings.sirSuffix). I am A.T.L.A.S. How may I be of assistance?"
        previewSpeaker.stop()
        previewSpeaker.speak(text, voiceIdentifier: settings.voiceIdentifier, language: settings.language,
                             rate: settings.speechRate, premium: settings.premiumVoiceConfig)
    }

    private func testPremium() {
        guard let config = settings.premiumVoiceConfig else { return }
        testingPremium = true
        premiumTestResult = nil
        Task {
            let error = await PremiumVoice.test(config: config)
            premiumTestResult = error ?? "✓ Verbindung steht – tippen Sie auf „Stimme probehören“."
            testingPremium = false
        }
    }

    private func deleteHistory() {
        engine.startNewConversation()
        try? modelContext.delete(model: MessageRecord.self)
        try? modelContext.delete(model: ConversationRecord.self)
        try? modelContext.save()
    }
}
