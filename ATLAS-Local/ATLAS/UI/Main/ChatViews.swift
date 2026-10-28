import SwiftUI

// MARK: - Kugel

/// Die lebendige ATLAS-Kugel: atmet in Ruhe, reagiert beim Zuhören auf Ihre Stimme,
/// wirbelt beim Nachdenken und pulsiert beim Sprechen.
struct OrbView: View {
    var state: ConversationEngine.State
    var inputLevel: Float = 0
    /// false = ruhige, sparsame Darstellung (weniger Bilder pro Sekunde, keine Weichzeichnung).
    var lively = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: lively ? 1.0 / 60 : 1.0 / 15, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(in: &context, size: size, time: time)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("ATLAS – \(state.label)")
    }

    private struct Look {
        let colors: [Color]
        let speed: Double
        let glow: Double
    }

    private var look: Look {
        switch state {
        case .listening:
            return Look(colors: [Color(red: 0.2, green: 0.9, blue: 1.0), Color(red: 0.1, green: 0.55, blue: 1.0), Color(red: 0.35, green: 1.0, blue: 0.85)], speed: 0.8, glow: 0.55)
        case .thinking:
            return Look(colors: [Color(red: 0.55, green: 0.35, blue: 1.0), Color(red: 0.2, green: 0.45, blue: 1.0), Color(red: 0.85, green: 0.4, blue: 1.0)], speed: 1.9, glow: 0.5)
        case .speaking:
            return Look(colors: [Color(red: 0.43, green: 0.82, blue: 1.0), Color(red: 0.3, green: 0.5, blue: 1.0), Color(red: 0.9, green: 0.95, blue: 1.0)], speed: 1.1, glow: 0.6)
        case .confirming:
            return Look(colors: [Color(red: 1.0, green: 0.75, blue: 0.3), Color(red: 1.0, green: 0.5, blue: 0.2), Color(red: 1.0, green: 0.9, blue: 0.6)], speed: 0.6, glow: 0.5)
        case .error:
            return Look(colors: [Color(red: 1.0, green: 0.45, blue: 0.3), Color(red: 0.85, green: 0.25, blue: 0.35), Color(red: 1.0, green: 0.7, blue: 0.4)], speed: 0.4, glow: 0.35)
        case .idle, .standby:
            return Look(colors: [Color(red: 0.3, green: 0.6, blue: 1.0), Color(red: 0.45, green: 0.3, blue: 0.95), Color(red: 0.25, green: 0.85, blue: 1.0)], speed: 0.35, glow: 0.35)
        }
    }

    private func scale(at time: Double) -> Double {
        switch state {
        case .listening: return 1 + 0.14 * Double(min(max(inputLevel, 0), 1)) + 0.02 * sin(time * 2)
        case .speaking: return 1 + 0.05 * abs(sin(time * 5.5)) + 0.02 * sin(time * 1.7)
        case .thinking: return 1 + 0.03 * sin(time * 3)
        default: return 1 + 0.03 * sin(time * 1.2)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let look = look
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = side / 2 * 0.78 * scale(at: time)

        // Leuchten um die Kugel
        let glowRect = CGRect(x: center.x - radius * 1.28, y: center.y - radius * 1.28, width: radius * 2.56, height: radius * 2.56)
        context.fill(Path(ellipseIn: glowRect),
                     with: .radialGradient(Gradient(colors: [look.colors[0].opacity(look.glow), .clear]),
                                           center: center, startRadius: radius * 0.6, endRadius: radius * 1.28))

        let orbRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let orb = Path(ellipseIn: orbRect)

        context.drawLayer { layer in
            layer.clip(to: orb)
            layer.fill(orb, with: .radialGradient(Gradient(colors: [Color(red: 0.06, green: 0.1, blue: 0.25), Color(red: 0.01, green: 0.02, blue: 0.08)]),
                                                  center: center, startRadius: 0, endRadius: radius))
            // Farbwolken, die im Inneren kreisen
            layer.drawLayer { clouds in
                if lively { clouds.addFilter(.blur(radius: radius * 0.22)) }
                for index in 0..<3 {
                    let i = Double(index)
                    let angle = time * look.speed * (1 + 0.35 * i) + i * 2.1
                    let wobble = 0.3 + 0.12 * sin(time * 0.7 + i)
                    let point = CGPoint(x: center.x + cos(angle) * radius * wobble,
                                        y: center.y + sin(angle * 0.9) * radius * wobble)
                    let blob = radius * (0.85 + 0.1 * sin(time + i))
                    let rect = CGRect(x: point.x - blob, y: point.y - blob, width: blob * 2, height: blob * 2)
                    clouds.fill(Path(ellipseIn: rect),
                                with: .radialGradient(Gradient(colors: [look.colors[index].opacity(0.95), look.colors[index].opacity(0)]),
                                                      center: point, startRadius: 0, endRadius: blob))
                }
            }
            // Glanzlicht oben links
            let shine = CGRect(x: center.x - radius * 0.62, y: center.y - radius * 0.78, width: radius * 0.8, height: radius * 0.5)
            layer.fill(Path(ellipseIn: shine),
                       with: .radialGradient(Gradient(colors: [.white.opacity(0.35), .clear]),
                                             center: CGPoint(x: shine.midX, y: shine.midY), startRadius: 0, endRadius: radius * 0.4))
        }
        context.stroke(orb, with: .color(.white.opacity(0.18)), lineWidth: max(0.5, radius * 0.02))
    }
}

/// Kleine, ruhende Kugel als Absender-Zeichen neben älteren Antworten (ohne Animation).
struct MiniOrb: View {
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(red: 0.45, green: 0.8, blue: 1.0), Color(red: 0.35, green: 0.3, blue: 0.95), Color(red: 0.03, green: 0.06, blue: 0.18)],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 16))
            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

// MARK: - Chatverlauf

/// Gesprächsverlauf wie bei ChatGPT oder Claude: Ihre Nachrichten rechts als Blase,
/// die Antworten von ATLAS links als fließender Text mit der Kugel als Absender.
struct ChatTranscriptView: View {
    let bubbles: [ChatBubble]
    let streamingText: String?
    let state: ConversationEngine.State
    let liveTranscript: String
    let statusDetail: String?
    var lively = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(bubbles) { bubble in
                        ChatRow(bubble: bubble)
                            .id(bubble.id)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity))
                    }
                    if state == .listening, !liveTranscript.isEmpty {
                        UserBubble(text: liveTranscript, pending: true)
                            .transition(.opacity)
                    }
                    if let streamingText {
                        AssistantRow(text: ChatText.display(streamingText), statusDetail: statusDetail,
                                     state: state, live: true, lively: lively)
                            .transition(.opacity)
                    }
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .animation(.spring(duration: 0.4), value: bubbles)
            .onChange(of: bubbles.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            }
            .onChange(of: streamingText) { _, _ in proxy.scrollTo(Self.bottom, anchor: .bottom) }
            .onChange(of: liveTranscript) { _, _ in proxy.scrollTo(Self.bottom, anchor: .bottom) }
        }
    }

    private static let bottom = "chat-bottom"
}

private struct ChatRow: View {
    let bubble: ChatBubble

    var body: some View {
        switch bubble.kind {
        case .user:
            UserBubble(text: bubble.text, pending: false)
        case .assistant:
            AssistantRow(text: ChatText.display(bubble.text), statusDetail: nil, state: .idle, live: false)
        case .stopped:
            AssistantRow(text: ChatText.display(bubble.text), statusDetail: nil, state: .idle, live: false, note: "Abgebrochen")
        case .error:
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .frame(width: 28, height: 28)
                Text(bubble.text)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct UserBubble: View {
    let text: String
    let pending: Bool

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(.body)
                .italic(pending)
                .foregroundStyle(.white.opacity(pending ? 0.6 : 0.95))
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(pending ? 0.05 : 0.11), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

private struct AssistantRow: View {
    let text: String
    let statusDetail: String?
    let state: ConversationEngine.State
    let live: Bool
    var lively = true
    var note: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if live {
                    OrbView(state: state == .idle ? .thinking : state, lively: lively)
                } else {
                    MiniOrb()
                }
            }
            .frame(width: 28, height: 28)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                if text.isEmpty {
                    HStack(spacing: 10) {
                        TypingDots()
                        if let statusDetail, !statusDetail.isEmpty {
                            Text(statusDetail).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 28)
                } else {
                    Text(ChatText.attributed(text))
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.92))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .tint(Color(red: 0.43, green: 0.82, blue: 1.0))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 3)
                }
                if let note {
                    Label(note, systemImage: "stop.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Drei Punkte, die nacheinander aufleuchten, solange ATLAS nachdenkt.
private struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    let phase = (sin(time * 5 - Double(index) * 0.8) + 1) / 2
                    Circle()
                        .fill(Color.white.opacity(0.3 + 0.6 * phase))
                        .frame(width: 7, height: 7)
                        .offset(y: -3 * phase)
                }
            }
        }
        .accessibilityLabel("ATLAS denkt nach")
    }
}

// MARK: - Leerer Chat

/// Neuer Chat: große Kugel, eine Frage und ein paar Vorschläge zum Antippen.
struct EmptyChatView: View {
    let state: ConversationEngine.State
    let inputLevel: Float
    let greeting: String
    var lively = true
    let onOrbTap: () -> Void
    let onSuggestion: (String) -> Void

    private struct Suggestion: Hashable {
        let symbol: String
        let text: String
    }

    private static let suggestions = [
        Suggestion(symbol: "lightbulb", text: "Erkläre mir kurz, was ein Cashflow ist."),
        Suggestion(symbol: "magnifyingglass", text: "Recherchiere aktuelle Förderprogramme für Photovoltaik und nenne Quellen."),
        Suggestion(symbol: "tablecells", text: "Erstelle eine Excel-Tabelle für meine Ausgaben mit Miete 1200 und Strom 90."),
        Suggestion(symbol: "sparkles", text: "Was kannst du alles für mich tun?")
    ]

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 12)
            OrbView(state: state, inputLevel: inputLevel, lively: lively)
                .frame(width: 170, height: 170)
                .contentShape(Circle())
                .onTapGesture(perform: onOrbTap)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Tippen zum Sprechen")
            VStack(spacing: 8) {
                Text("Wie kann ich helfen?")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                if !greeting.isEmpty {
                    Text(greeting)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 24)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                ForEach(Self.suggestions, id: \.text) { suggestion in
                    Button { onSuggestion(suggestion.text) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: suggestion.symbol)
                                .foregroundStyle(Color(red: 0.43, green: 0.82, blue: 1.0))
                            Text(suggestion.text)
                                .font(.callout)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 18)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ChatText {
    /// Markdown für den Chat: fett, kursiv, Code und Links werden formatiert,
    /// Überschriften fett, Aufzählungen mit Punkt. Unvollständiges Markdown (beim Streamen) bleibt lesbar.
    static func attributed(_ text: String) -> AttributedString {
        var prepared = text.replacingOccurrences(of: #"(?m)^#{1,6}\s+(.+)$"#, with: "**$1**", options: .regularExpression)
        prepared = prepared.replacingOccurrences(of: #"(?m)^(\s*)[-*]\s+"#, with: "$1• ", options: .regularExpression)
        prepared = prepared.replacingOccurrences(of: #"(?m)^```.*$\n?"#, with: "", options: .regularExpression)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: prepared, options: options)) ?? AttributedString(text)
    }
}
