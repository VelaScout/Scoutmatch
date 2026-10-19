import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Startbildschirm: ATLAS steht im Mittelpunkt, möglichst wenig Text.
struct MainView: View {
    @Environment(ConversationEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = IntentRouter.shared
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showTasks = false
    @State private var showKeyboard = false
    @State private var showOnboarding = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var attachmentError: String?
    @State private var typedText = ""
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                atlasVisual
                    .contentShape(Rectangle())
                    .onTapGesture { engine.primaryAction() }
                Spacer(minLength: 0)
                transcriptArea
                attachmentChips
                bottomBar
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
        .sheet(isPresented: $showSettings) { SettingsView().atlasSheetSize() }
        .sheet(isPresented: $showHistory) { HistoryView().atlasSheetSize() }
        .sheet(isPresented: $showTasks) { TasksView().atlasSheetSize() }
        .atlasFullScreenCover(isPresented: $showOnboarding) { OnboardingView() }
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
            showOnboarding = !KeychainStore.has(.anthropicAPIKey)
            processPendingRequest()
        }
        .onChange(of: router.sequence) { _, _ in processPendingRequest() }
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
    }

    // MARK: - Bausteine

    @ViewBuilder
    private var atlasVisual: some View {
        switch settings.appearance {
        case .face:
            AtlasFaceView(state: engine.state,
                          inputLevel: engine.inputLevel,
                          spokenWordCount: engine.spokenWordCount,
                          spokenWordLength: engine.spokenWordLength,
                          speechRate: settings.speechRate)
                .aspectRatio(0.78, contentMode: .fit)
                .padding(.horizontal, 8)
        case .core:
            AtlasCoreView(state: engine.state,
                          inputLevel: engine.inputLevel,
                          spokenWordCount: engine.spokenWordCount)
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 12)
        }
    }

    private var background: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Color(red: 0.05, green: 0.16, blue: 0.28), .black],
                           center: .center, startRadius: 20, endRadius: 560)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .accessibilityLabel("Gesprächsverlauf")

            Button { showTasks = true } label: {
                Image(systemName: "checklist")
            }
            .accessibilityLabel("Aufgaben und Termine")

            Spacer()

            StatusPill(state: engine.state, detail: engine.statusDetail)

            Spacer()

            Button { settings.wakeWordEnabled.toggle() } label: {
                Image(systemName: settings.wakeWordEnabled ? "ear.fill" : "ear")
            }
            .accessibilityLabel(settings.wakeWordEnabled ? "Wake-Word ausschalten" : "Wake-Word „Atlas“ einschalten")

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Einstellungen")
        }
        .buttonStyle(.plain)
        .font(.title3)
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var transcriptArea: some View {
        VStack(spacing: 10) {
            if !engine.liveTranscript.isEmpty {
                Text(engine.liveTranscript)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
            }
            if !engine.responseText.isEmpty {
                ScrollView {
                    Text(engine.responseText)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 130)
                .scrollIndicators(.hidden)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28)
        .animation(.easeInOut(duration: 0.2), value: engine.liveTranscript)
    }

    @ViewBuilder
    private var attachmentChips: some View {
        if !engine.attachments.isEmpty {
            ScrollView(.horizontal) {
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
                        .background(.white.opacity(0.1), in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.top, 8)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if showKeyboard {
                HStack {
                    TextField("Nachricht an ATLAS", text: $typedText)
                        .textFieldStyle(.plain)
                        .focused($textFieldFocused)
                        .submitLabel(.send)
                        .onSubmit(sendTyped)
                    Button(action: sendTyped) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(typedText.trimmingCharacters(in: .whitespaces).isEmpty && engine.attachments.isEmpty)
                }
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
            }

            HStack(spacing: 28) {
                Menu {
                    Button { showPhotoPicker = true } label: { Label("Foto auswählen", systemImage: "photo") }
                    #if os(iOS)
                    Button { showCamera = true } label: { Label("Foto aufnehmen", systemImage: "camera") }
                    #endif
                    Button { showFileImporter = true } label: { Label("PDF oder Datei", systemImage: "doc") }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .menuIndicator(.hidden)
                .accessibilityLabel("Foto oder Dokument anhängen")

                Button {
                    showKeyboard.toggle()
                    textFieldFocused = showKeyboard
                } label: {
                    Image(systemName: showKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Tastatur")

                MicButton(state: engine.state) { engine.primaryAction() }

                Button { engine.stopAll() } label: {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .disabled((engine.state == .idle || engine.state == .standby) && !engine.isInConversation)
                .accessibilityLabel("Gespräch beenden")
                .keyboardShortcut(.escape, modifiers: [])

                Color.clear.frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private func sendTyped() {
        let text = typedText
        typedText = ""
        engine.send(text: text)
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

/// Kleine Statusanzeige oben in der Mitte.
struct StatusPill: View {
    let state: ConversationEngine.State
    var detail: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(detail ?? "ATLAS · \(state.label)")
                .font(.caption.weight(.medium))
                .tracking(1.0)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white.opacity(0.07), in: Capsule())
        .foregroundStyle(.white.opacity(0.8))
    }

    private var color: Color {
        switch state {
        case .idle: return .gray
        case .standby: return Color(red: 0.55, green: 0.86, blue: 1.0)
        case .listening, .confirming: return .red   // Mikrofon aktiv – immer deutlich sichtbar
        case .thinking: return .cyan
        case .speaking: return .blue
        case .error: return .orange
        }
    }
}

/// Großer Mikrofon-Knopf; rot, solange ATLAS zuhört.
struct MicButton: View {
    let state: ConversationEngine.State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isListening ? Color.red.opacity(0.85) : Color.white.opacity(0.12))
                Circle()
                    .stroke(Color(red: 0.55, green: 0.85, blue: 1.0).opacity(0.6), lineWidth: 1)
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 72, height: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isListening ? "Zuhören beenden" : "Mit ATLAS sprechen")
    }

    private var isListening: Bool { state == .listening || state == .confirming }

    private var symbol: String {
        switch state {
        case .listening, .confirming: return "waveform"
        case .thinking, .speaking: return "hand.raised.fill"
        default: return "mic.fill"
        }
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
