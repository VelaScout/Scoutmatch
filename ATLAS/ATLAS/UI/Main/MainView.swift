import PhotosUI
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
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                atlasVisual
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { engine.primaryAction() }
                    .onLongPressGesture(minimumDuration: 0.6) { sheet = .settings }
                    .overlay(alignment: .bottom) { caption }
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
            showOnboarding = !KeychainStore.has(.anthropicAPIKey)
            processPendingRequest()
        }
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
                              speechRate: settings.speechRate)
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
        case .listening, .confirming: text = engine.liveTranscript
        case .error(let message): text = message
        default: text = engine.statusDetail ?? engine.responseText
        }
        return Text(text)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.82))
            .multilineTextAlignment(.center)
            .lineLimit(3)
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
            captionHideTask = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                captionVisible = false
            }
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
        case .settings: SettingsView()
        case .history: HistoryView()
        case .tasks: TasksView()
        case .memory: SheetContainer { MemoryView() }
        case .permissions: SheetContainer { PermissionsView() }
        case .activity: SheetContainer { ActivityView() }
        case .voiceStudio: SheetContainer { VoiceStudioView() }
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
