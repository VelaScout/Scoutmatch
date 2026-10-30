import SwiftUI

// MARK: - Kugel

/// Die ATLAS-Kugel als 3D-Teilchenkugel: Hunderte leuchtende Punkte und kleine Quadrate bilden eine
/// drehende Kugel, umkreist von Hologramm-Ringen. In Ruhe atmet sie, beim Zuhören schlagen Wellen
/// mit Ihrer Stimme, beim Nachdenken verdreht sie sich, beim Sprechen laufen Impulse über sie.
struct OrbView: View {
    var state: ConversationEngine.State
    var inputLevel: Float = 0
    /// false = ruhige, sparsame Darstellung (weniger Teilchen, weniger Bilder pro Sekunde).
    var lively = true
    /// false = ein ruhendes Standbild (z. B. als Absender-Zeichen neben älteren Antworten).
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animated {
                TimelineView(.animation(minimumInterval: lively ? 1.0 / 60 : 1.0 / 20, paused: reduceMotion)) { timeline in
                    canvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(time: 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("ATLAS – \(state.label)")
    }

    private func canvas(time: Double) -> some View {
        let renderer = OrbRenderer(look: look, state: state, level: Double(min(max(inputLevel, 0), 1)), lively: lively)
        return Canvas { context, size in
            renderer.draw(in: &context, size: size, time: time)
        }
    }

    private var look: OrbLook {
        switch state {
        case .listening:
            return OrbLook(colors: [Color(red: 0.25, green: 0.92, blue: 1.0), Color(red: 0.1, green: 0.5, blue: 1.0), Color(red: 0.6, green: 1.0, blue: 0.9)], speed: 0.9, glow: 0.45)
        case .thinking:
            return OrbLook(colors: [Color(red: 0.6, green: 0.45, blue: 1.0), Color(red: 0.25, green: 0.4, blue: 1.0), Color(red: 0.95, green: 0.55, blue: 1.0)], speed: 2.2, glow: 0.4)
        case .speaking:
            return OrbLook(colors: [Color(red: 0.43, green: 0.82, blue: 1.0), Color(red: 0.3, green: 0.45, blue: 1.0), Color(red: 0.95, green: 0.98, blue: 1.0)], speed: 1.2, glow: 0.5)
        case .confirming:
            return OrbLook(colors: [Color(red: 1.0, green: 0.75, blue: 0.3), Color(red: 1.0, green: 0.5, blue: 0.2), Color(red: 1.0, green: 0.92, blue: 0.65)], speed: 0.6, glow: 0.4)
        case .error:
            return OrbLook(colors: [Color(red: 1.0, green: 0.45, blue: 0.3), Color(red: 0.85, green: 0.25, blue: 0.35), Color(red: 1.0, green: 0.75, blue: 0.45)], speed: 0.4, glow: 0.3)
        case .idle, .standby:
            return OrbLook(colors: [Color(red: 0.35, green: 0.75, blue: 1.0), Color(red: 0.4, green: 0.35, blue: 1.0), Color(red: 0.75, green: 0.95, blue: 1.0)], speed: 0.45, glow: 0.3)
        }
    }
}

struct OrbLook {
    /// Vorderseite, Rückseite, Akzent.
    let colors: [Color]
    let speed: Double
    let glow: Double
}

/// Zeichnet die Teilchenkugel: Punkte auf einer Fibonacci-Kugel, gedreht, perspektivisch projiziert,
/// hinten blass und klein, vorne hell und groß.
private struct OrbRenderer {
    let look: OrbLook
    let state: ConversationEngine.State
    let level: Double
    let lively: Bool

    private static let dense = sphere(count: 650)
    private static let light = sphere(count: 170)

    private static func sphere(count: Int) -> [SIMD3<Double>] {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0..<count).map { index in
            let y = 1 - 2 * (Double(index) + 0.5) / Double(count)
            let ring = (1 - y * y).squareRoot()
            let phi = Double(index) * golden
            return SIMD3(cos(phi) * ring, y, sin(phi) * ring)
        }
    }

    /// Wie stark die Kugel gerade „lebt“ (0…1).
    private func pulse(_ t: Double) -> Double {
        switch state {
        case .listening: return 0.3 + 0.7 * level
        case .speaking: return 0.4 + 0.6 * abs(sin(t * 5.5))
        case .thinking: return 0.5 + 0.3 * sin(t * 3)
        default: return 0.25 + 0.15 * sin(t * 1.2)
        }
    }

    /// Verformung je Zustand: Wellen beim Zuhören, Impulse beim Sprechen, Verdrehung beim Nachdenken.
    private func displaced(_ point: SIMD3<Double>, index: Int, t: Double) -> SIMD3<Double> {
        var p = point
        var radius = 1.0
        switch state {
        case .listening:
            radius += (0.03 + 0.22 * level) * sin(p.y * 9 + t * 6) * (0.6 + 0.4 * sin(p.x * 7 - t * 3))
        case .speaking:
            radius += 0.1 * max(0, sin(p.y * 6 - t * 9))
        case .thinking:
            let twist = p.y * 1.6 * sin(t * 1.3)
            p = SIMD3(p.x * cos(twist) - p.z * sin(twist), p.y, p.x * sin(twist) + p.z * cos(twist))
            radius += 0.03 * sin(Double(index) + t * 4)
        case .confirming, .error:
            radius += 0.02 * sin(Double(index) + t * 2)
        case .idle, .standby:
            radius += 0.025 * sin(p.y * 4 + t * 1.5)
        }
        return p * radius
    }

    func draw(in context: inout GraphicsContext, size: CGSize, time t: Double) {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = side / 2 * 0.62
        let small = side < 60
        let points = small || !lively ? Self.light : Self.dense
        let strength = pulse(t)

        // Leuchten hinter der Kugel
        let glow = radius * (1.5 + 0.12 * strength)
        context.fill(Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [look.colors[0].opacity(look.glow), look.colors[1].opacity(look.glow * 0.25), .clear]),
                                           center: center, startRadius: 0, endRadius: glow))
        context.blendMode = .plusLighter

        let spin = t * look.speed * 0.5
        let tilt = 0.38 + 0.08 * sin(t * 0.3)
        let sinS = sin(spin), cosS = cos(spin), sinT = sin(tilt), cosT = cos(tilt)

        /// 3D-Punkt → Bildschirm (Drehung um die Hochachse, Neigung, Perspektive).
        func project(_ p: SIMD3<Double>) -> (point: CGPoint, z: Double, scale: Double) {
            let x1 = p.x * cosS + p.z * sinS
            let z1 = -p.x * sinS + p.z * cosS
            let y2 = p.y * cosT - z1 * sinT
            let z2 = p.y * sinT + z1 * cosT
            let f = 3.0 / (3.0 - z2)
            return (CGPoint(x: center.x + x1 * radius * f, y: center.y + y2 * radius * f), z2, f)
        }

        // Hologramm-Ringe
        if !small {
            let rings: [(size: Double, tiltZ: Double, speed: Double)] = [(1.32, 0.0, -0.6), (1.18, 1.15, 0.9)]
            for ring in rings {
                var path = Path()
                for step in 0...72 {
                    let a = Double(step) / 72 * 2 * .pi + t * ring.speed
                    let flat = SIMD3(cos(a) * ring.size, 0, sin(a) * ring.size)
                    let p = SIMD3(flat.x * cos(ring.tiltZ) - flat.y * sin(ring.tiltZ), flat.x * sin(ring.tiltZ) + flat.y * cos(ring.tiltZ), flat.z)
                    let projected = project(p).point
                    if step == 0 { path.move(to: projected) } else { path.addLine(to: projected) }
                }
                context.stroke(path, with: .color(look.colors[0].opacity(0.22 + 0.2 * strength)),
                               style: StrokeStyle(lineWidth: max(0.6, side * 0.004), dash: [side * 0.01, side * 0.025]))
                // Kleine Satelliten auf dem Ring
                for satellite in 0..<3 {
                    let a = Double(satellite) * 2.1 + t * ring.speed * 1.6
                    let flat = SIMD3(cos(a) * ring.size, 0, sin(a) * ring.size)
                    let p = SIMD3(flat.x * cos(ring.tiltZ), flat.x * sin(ring.tiltZ), flat.z)
                    let projected = project(p)
                    let s = side * 0.018 * projected.scale
                    let rect = CGRect(x: projected.point.x - s / 2, y: projected.point.y - s / 2, width: s, height: s)
                    context.fill(Path(rect), with: .color(look.colors[2].opacity(0.35 + 0.5 * (projected.z + 1) / 2)))
                }
            }
        }

        // Teilchen: erst die Rückseite, dann die Vorderseite
        for pass in 0..<2 {
            for (index, base) in points.enumerated() {
                let projected = project(displaced(base, index: index, t: t))
                if (pass == 0) != (projected.z < 0) { continue }
                let depth = (projected.z + 1) / 2
                let dot = side * (small ? 0.05 : 0.0095) * (0.5 + 0.9 * depth) * projected.scale
                let opacity = 0.1 + 0.9 * depth * depth
                let color = index % 7 == 0 ? look.colors[2] : (base.y > 0 ? look.colors[0] : look.colors[1])
                let rect = CGRect(x: projected.point.x - dot / 2, y: projected.point.y - dot / 2, width: dot, height: dot)
                let shape = index % 3 == 0 ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: dot * 0.2)
                context.fill(shape, with: .color(color.opacity(opacity)))
            }
        }

        // Leuchtender Kern
        let core = radius * (0.42 + 0.12 * strength)
        context.fill(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(0.25 + 0.35 * strength), look.colors[0].opacity(0.25), .clear]),
                                           center: center, startRadius: 0, endRadius: core))
    }
}

/// Kleine, ruhende Kugel als Absender-Zeichen neben älteren Antworten.
struct MiniOrb: View {
    var body: some View {
        OrbView(state: .idle, lively: false, animated: false)
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
                .frame(width: 220, height: 220)
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
