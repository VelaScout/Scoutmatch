import SwiftUI

/// Startbildschirm: ATLAS steht im Mittelpunkt, möglichst wenig Text.
struct MainView: View {
    @Environment(ConversationEngine.self) private var engine
    @Environment(AppSettings.self) private var settings

    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showKeyboard = false
    @State private var showOnboarding = false
    @State private var typedText = ""
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                AtlasCoreView(state: engine.state,
                              inputLevel: engine.inputLevel,
                              spokenWordCount: engine.spokenWordCount)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.horizontal, 12)
                    .contentShape(Circle())
                    .onTapGesture { engine.primaryAction() }
                Spacer(minLength: 0)
                transcriptArea
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .fullScreenCover(isPresented: $showOnboarding) { OnboardingView() }
        .onAppear {
            showOnboarding = !KeychainStore.has(.anthropicAPIKey)
        }
    }

    // MARK: - Bausteine

    private var background: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [Color(red: 0.05, green: 0.16, blue: 0.28), .black],
                           center: .center, startRadius: 20, endRadius: 520)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .accessibilityLabel("Gesprächsverlauf")

            Spacer()

            StatusPill(state: engine.state)

            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Einstellungen")
        }
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
                }
                .frame(maxHeight: 120)
                .scrollIndicators(.hidden)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28)
        .animation(.easeInOut(duration: 0.2), value: engine.liveTranscript)
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
                    .disabled(typedText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
            }

            HStack(spacing: 40) {
                Button {
                    showKeyboard.toggle()
                    textFieldFocused = showKeyboard
                } label: {
                    Image(systemName: showKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("Tastatur")

                MicButton(state: engine.state) { engine.primaryAction() }

                Button { engine.stopAll() } label: {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                }
                .disabled(engine.state == .idle && !engine.isInConversation)
                .accessibilityLabel("Gespräch beenden")
            }
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
}

/// Kleine Statusanzeige oben in der Mitte.
struct StatusPill: View {
    let state: ConversationEngine.State

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("ATLAS · \(state.label)")
                .font(.caption.weight(.medium))
                .tracking(1.2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white.opacity(0.07), in: Capsule())
        .foregroundStyle(.white.opacity(0.8))
    }

    private var color: Color {
        switch state {
        case .idle: return .gray
        case .listening: return .red        // Mikrofon aktiv – immer deutlich sichtbar
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
        .accessibilityLabel(isListening ? "Zuhören beenden" : "Mit ATLAS sprechen")
    }

    private var isListening: Bool { state == .listening }

    private var symbol: String {
        switch state {
        case .listening: return "waveform"
        case .thinking, .speaking: return "hand.raised.fill"
        default: return "mic.fill"
        }
    }
}
