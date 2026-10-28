import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Startbildschirm: nur ATLAS. Der Kern füllt den ganzen Bildschirm, unten liegt eine
/// schlanke Leiste zum Tippen oder Sprechen. Alles andere – Einstellungen, Verlauf,
/// Aufgaben, Fotos – öffnet ATLAS auf Zuruf („Öffne die Einstellungen“).
/// Notausgang: langes Drücken auf den Kern öffnet die Einstellungen.
struct MainView: View {
    @Environment(ConversationEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var router = IntentRouter.shared
    @State private var sheet: AppScreen?
    @State private var showOnboarding = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var attachmentError: String?
    @State private var typedText = ""
    @State private var captionVisible = false
    @State private var captionHideTask: Task<Void, Never>?
    @State private var systemStatus = SystemStatus()
    @State private var learningNotice: String?
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                HStack {
                    Text("ATLAS Local").font(.headline)
                    Spacer()
                    Button { sheet = .learning } label: { Image(systemName: "brain") }
                        .accessibilityLabel("Learning & Evolution")
                    Button { sheet = .history } label: { Image(systemName: "clock") }
                        .accessibilityLabel("Verlauf")
                    Button { sheet = .settings } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Einstellungen")
                }.padding().foregroundStyle(.white)
                StatusBar(status: systemStatus)
                if let learningNotice {
                    Button { sheet = .learning; self.learningNotice = nil } label: {
                        Label(learningNotice, systemImage: "sparkles").font(.caption).lineLimit(2)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color.cyan.opacity(0.15)))
                    }
                    .buttonStyle(.plain).foregroundStyle(.cyan).padding(.top, 6).padding(.horizontal)
                }
                Text(engine.state.label).font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                atlasVisual
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { engine.primaryAction() }
                    .onLongPressGesture(minimumDuration: 0.6) { sheet = .settings }
                    .overlay(alignment: .bottom) { caption }
                if !engine.activity.isEmpty {
                    ActivityPanel(items: engine.activity)
                        .padding(.bottom, 6)
                        .transition(.opacity)
                }
                attachmentChips
                inputBar
            }

            if let request = engine.pendingConfirmation {
                ConfirmationCard(request: request) { approved in
                    engine.resolveConfirmation(approved)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: engine.pendingConfirmation)
        .preferredColorScheme(.dark)
        .sheet(item: $sheet) { screen in
            sheetContent(for: screen).atlasSheetSize()
        }
        .atlasFullScreenCover(isPresented: $showOnboarding) { OnboardingView() }
        .onChange(of: showOnboarding) { _, showing in
            // Nach der Einrichtung sofort auf „Atlas“ hören.
            if !showing { engine.wakeWordSettingChanged() }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .image]) { result in
            handleImportedFile(result)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                if let data, let attachment = Attachment.image(from: data, name: "Kamera") {
                    engine.addAttachment(attachment)
                }
            }
            .ignoresSafeArea()
        }
        #endif
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let attachment = Attachment.image(from: data) {
                    engine.addAttachment(attachment)
                } else {
                    attachmentError = "Das Foto konnte nicht geladen werden."
                }
                photoItem = nil
            }
        }
        .alert("Hinweis", isPresented: Binding(get: { attachmentError != nil }, set: { if !$0 { attachmentError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(attachmentError ?? "")
        }
        .onAppear {
            systemStatus.start()
            showOnboarding = !UserDefaults.standard.bool(forKey: "localAtlasOnboarded")
            processPendingRequest()
        }
        .task {
            // Begrüßung genau dann, wenn der Kern am Ende der Start-Sequenz zündet.
            let withIntro = settings.appearance == .hologram && !reduceMotion
            try? await Task.sleep(for: .seconds(withIntro ? 8.9 : 1.2))
            engine.greetOnLaunch()
            await announceLearning()
        }
        .onOpenURL { url in
            // Per AirDrop empfangenes Gedächtnis eines anderen Geräts übernehmen.
            guard url.pathExtension.lowercased() == "atlasmemory" else { return }
            do {
                let result = try MemoryTransfer.importFile(url, context: modelContext)
                engine.announce("Gedächtnis übernommen: \(result.added) neue Einträge\(result.updated > 0 ? ", \(result.updated) aktualisiert" : ""). Jetzt weiß ich auch hier Bescheid.")
            } catch {
                engine.announce("Die Datei konnte ich leider nicht lesen.")
            }
        }
        // Geöffnete Dateien im vorhandenen Fenster empfangen statt ein neues zu öffnen (Mac).
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onChange(of: router.sequence) { _, _ in processPendingRequest() }
        .onChange(of: engine.screenRequestSequence) { _, _ in
            if let screen = engine.screenRequest { open(screen) }
        }
        .onChange(of: engine.state) { _, newState in updateCaption(for: newState) }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                engine.setSceneActive(true)
                processPendingRequest()
            case .background:
                engine.setSceneActive(false)
            default:
                break
            }
        }
        .onChange(of: settings.wakeWordEnabled) { _, _ in engine.wakeWordSettingChanged() }
        .onChange(of: settings.liveModeEnabled) { _, _ in engine.liveSettingChanged() }
        // Mac: Fenster geschlossen – ohne „Im Hintergrund hören“ geht das Mikrofon aus.
        .onDisappear { if PlatformBridge.isMac { engine.setSceneActive(false) } }
    }

    // MARK: - ATLAS

    @ViewBuilder
    private var atlasVisual: some View {
        switch settings.appearance {
        case .hologram:
            AtlasHologramView(state: engine.state,
                              inputLevel: engine.inputLevel,
                              spokenWordCount: engine.spokenWordCount,
                              spokenWordLength: engine.spokenWordLength,
                              speechRate: settings.speechRate, showsIntro: false)
        case .core:
            AtlasCoreView(state: engine.state,
                          inputLevel: engine.inputLevel,
                          spokenWordCount: engine.spokenWordCount)
                .aspectRatio(1, contentMode: .fit)
                .padding(24)
        }
    }

    private var background: some View {
        RadialGradient(colors: [Color(red: 0.02, green: 0.1, blue: 0.25), Color(red: 0.008, green: 0.03, blue: 0.09), .black],
                       center: UnitPoint(x: 0.5, y: 0.42), startRadius: 10, endRadius: 700)
            .ignoresSafeArea()
    }

    /// Dezenter Untertitel: was Sie sagen bzw. was ATLAS antwortet – blendet sich von selbst aus.
    private var caption: some View {
        let text: String
        switch engine.state {
        case .listening, .confirming:
            text = engine.liveTranscript.isEmpty ? (engine.listeningHint ?? "") : engine.liveTranscript
        case .error(let message): text = message
        // Beim Nachdenken keine Statusanzeige – Ihre Frage bleibt einfach stehen.
        case .thinking: text = engine.liveTranscript
        // Wenn A.T.L.A.S. spricht (und danach), kein Untertitel – nur die Stimme.
        // Die Antworten stehen weiterhin im Gesprächsverlauf.
        default: text = engine.responseText
        }
        return Text(text)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.82))
            .multilineTextAlignment(.center)
            .lineLimit(8)
            .shadow(color: .black, radius: 8)
            .padding(.horizontal, 28)
            .padding(.bottom, 10)
            .opacity(captionVisible && !text.isEmpty ? 1 : 0)
            .animation(.easeInOut(duration: 0.5), value: captionVisible)
            .allowsHitTesting(false)
    }

    private func updateCaption(for state: ConversationEngine.State) {
        captionHideTask?.cancel()
        switch state {
        case .idle, .standby:
            captionVisible = !engine.responseText.isEmpty
        default:
            captionVisible = true
        }
    }

    // MARK: - Eingabeleiste

    @ViewBuilder
    private var attachmentChips: some View {
        if !engine.attachments.isEmpty {
            HStack {
                ForEach(engine.attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: attachment.symbol)
                        Text(attachment.name).lineLimit(1)
                        Button { engine.removeAttachment(attachment) } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Anhang entfernen")
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.08), in: Capsule())
                }
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.bottom, 8)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Mit A.T.L.A.S. sprechen …", text: $typedText)
                .textFieldStyle(.plain)
                .focused($textFieldFocused)
                .submitLabel(.send)
                .onSubmit(sendTyped)
                .padding(.leading, 18)

            Button { engine.primaryAction() } label: {
                Image(systemName: micSymbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(micActive ? .white : Self.amber)
                    .frame(width: 40, height: 40)
                    .background(micActive ? Color.red.opacity(0.85) : Color.clear, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(micActive ? "Zuhören beenden" : "Sprechen")

            if !typedText.trimmingCharacters(in: .whitespaces).isEmpty || !engine.attachments.isEmpty {
                Button(action: sendTyped) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 40, height: 40)
                        .background(Self.amber, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Senden")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(5)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Self.amber.opacity(0.25), lineWidth: 1))
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .animation(.easeOut(duration: 0.2), value: typedText.isEmpty)
        #if os(macOS)
        .onExitCommand { engine.stopAll() }
        #endif
    }

    private static let amber = Color(red: 0.43, green: 0.82, blue: 1.0) // Eisblau

    private var micActive: Bool { engine.state == .listening || engine.state == .confirming }

    private var micSymbol: String {
        switch engine.state {
        case .listening, .confirming: return "waveform"
        case .thinking, .speaking: return "stop.fill"
        default: return "mic.fill"
        }
    }

    private func sendTyped() {
        let text = typedText
        typedText = ""
        textFieldFocused = false
        engine.send(text: text)
    }

    // MARK: - Ansichten auf Zuruf

    /// Beim Start: Hat ATLAS etwas entwickelt oder gefunden, das auf Freigabe wartet, sagt er es.
    /// Freigegeben wird nur im Bereich „Learning & Evolution“ – nie per Sprachbefehl des Modells.
    private func announceLearning() async {
        try? await Task.sleep(for: .seconds(6))
        guard let data = try? await LocalAtlasProvider().learning("overview"),
              let overview = try? LearningOverview.decode(data), let first = overview.announcements.first else { return }
        let more = overview.announcements.count > 1 ? " (und \(overview.announcements.count - 1) weitere)" : ""
        learningNotice = first.text + more
        engine.announce(first.text + " Sie finden das unter Learning und Evolution.")
    }

    private func open(_ screen: AppScreen) {
        switch screen {
        case .photoPicker: showPhotoPicker = true
        case .fileImporter: showFileImporter = true
        case .camera:
            #if os(iOS)
            showCamera = true
            #else
            showPhotoPicker = true
            #endif
        case .onboarding: showOnboarding = true
        default: sheet = screen
        }
    }

    @ViewBuilder
    private func sheetContent(for screen: AppScreen) -> some View {
        switch screen {
        case .settings: SheetContainer { SettingsView() }
        case .history: HistoryView()
        case .tasks: TasksView()
        case .memory: SheetContainer { MemoryView() }
        case .permissions: SheetContainer { PermissionsView() }
        case .activity: SheetContainer { ActivityView() }
        case .voiceStudio: SheetContainer { VoiceStudioView() }
        case .connections: SheetContainer { ConnectionsView() }
        case .learning: SheetContainer { LearningView() }
        default: EmptyView()
        }
    }

    private func handleImportedFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let type = UTType(filenameExtension: url.pathExtension)
        let attachment = (type?.conforms(to: .pdf) ?? false) ? Attachment.pdf(at: url) : Attachment.image(at: url)
        if let attachment {
            engine.addAttachment(attachment)
        } else {
            attachmentError = "Die Datei konnte nicht gelesen werden oder ist zu groß (maximal 24 MB)."
        }
    }

    private func processPendingRequest() {
        guard scenePhase == .active || PlatformBridge.isMac, let request = router.take() else { return }
        engine.handle(request)
    }
}

/// Rahmen für Ansichten, die ATLAS als eigenes Blatt öffnet (mit „Fertig“-Knopf).
private struct SheetContainer<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

/// Bestätigung sensibler Aktionen – ATLAS führt sie erst nach „Ja“ aus.
struct ConfirmationCard: View {
    let request: ConfirmationRequest
    let onDecision: (Bool) -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Label(request.title, systemImage: "checkmark.shield")
                    .font(.headline)
                ScrollView {
                    Text(request.detail)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
                Text("Sagen Sie „Ja“ oder „Nein“ – oder tippen Sie.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Abbrechen", role: .cancel) { onDecision(false) }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button(request.confirmLabel) { onDecision(true) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            .padding(16)
        }
    }
}
