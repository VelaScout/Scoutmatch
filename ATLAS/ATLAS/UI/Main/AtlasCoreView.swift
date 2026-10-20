import SwiftUI

/// Der animierte ATLAS-Kern – alternative, besonders sparsame Darstellung
/// (Einstellungen → Darstellung). Standard ist der 3D-Kern (`AtlasHologramView`).
struct AtlasCoreView: View {
    let state: ConversationEngine.State
    let inputLevel: Float
    let spokenWordCount: Int

    @Environment(\.scenePhase) private var scenePhase
    @State private var smoothedLevel: Double = 0
    @State private var lastWordDate = Date.distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: scenePhase != .active)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, time: timeline.date)
            }
        }
        .onChange(of: inputLevel) { _, newValue in
            smoothedLevel = smoothedLevel * 0.6 + Double(newValue) * 0.4
        }
        .onChange(of: spokenWordCount) { _, _ in
            lastWordDate = .now
        }
        .accessibilityElement()
        .accessibilityLabel("ATLAS, \(state.label)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Zeichnen

    private var tint: Color {
        if case .error = state { return Color(red: 1.0, green: 0.72, blue: 0.35) }
        return Color(red: 0.55, green: 0.85, blue: 1.0)
    }

    private func energy(at date: Date, t: Double) -> Double {
        switch state {
        case .listening, .confirming:
            return 0.15 + smoothedLevel * 0.85
        case .speaking:
            let sinceWord = date.timeIntervalSince(lastWordDate)
            let kick = exp(-sinceWord * 7)
            return 0.3 + 0.45 * kick + 0.1 * (sin(t * 11) * 0.5 + 0.5)
        case .thinking:
            return 0.3 + 0.1 * sin(t * 4)
        case .standby:
            return 0.12 + 0.06 * (sin(t * 2) * 0.5 + 0.5)
        case .idle, .error:
            return 0.08 + 0.05 * (sin(t * 1.4) * 0.5 + 0.5)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time date: Date) {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = Double(min(size.width, size.height)) / 2 * 0.92
        let e = energy(at: date, t: t)
        let spin: Double = state == .thinking ? 2.4 : (state == .listening ? 0.9 : 0.35)

        // Äußerer Lichtschein
        let glowRadius = radius * (0.55 + 0.25 * e)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - glowRadius, y: center.y - glowRadius,
                                   width: glowRadius * 2, height: glowRadius * 2)),
            with: .radialGradient(
                Gradient(colors: [tint.opacity(0.35 + 0.3 * e), tint.opacity(0)]),
                center: center, startRadius: 0, endRadius: glowRadius))

        // Äußerer Ring
        strokeCircle(&context, center: center, radius: radius, color: tint.opacity(0.25), width: 1.5)

        // Rotierende Bogensegmente
        for i in 0..<3 {
            let start = t * spin + Double(i) * 2 * .pi / 3
            var arc = Path()
            arc.addArc(center: center, radius: radius * 0.93,
                       startAngle: .radians(start), endAngle: .radians(start + 0.9),
                       clockwise: false)
            context.stroke(arc, with: .color(tint.opacity(0.75)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }

        // Skala mit Teilstrichen (gegenläufig)
        let ticks = 72
        for i in 0..<ticks {
            let angle = Double(i) / Double(ticks) * 2 * .pi - t * spin * 0.3
            let long = i % 6 == 0
            let inner = radius * (long ? 0.78 : 0.81)
            let outer = radius * 0.84
            var tick = Path()
            tick.move(to: point(center, inner, angle))
            tick.addLine(to: point(center, outer, angle))
            context.stroke(tick, with: .color(tint.opacity(long ? 0.6 : 0.25)), lineWidth: long ? 2 : 1)
        }

        // Kreisförmige Audiowelle
        let waveRadius = radius * 0.6
        var wave = Path()
        let steps = 180
        for s in 0...steps {
            let angle = Double(s) / Double(steps) * 2 * .pi
            let ripple = sin(angle * 6 + t * 5) * 0.6 + sin(angle * 11 - t * 7) * 0.4
            let r = waveRadius * (1 + ripple * 0.06 * e)
            let p = point(center, r, angle)
            if s == 0 { wave.move(to: p) } else { wave.addLine(to: p) }
        }
        wave.closeSubpath()
        context.stroke(wave, with: .color(tint.opacity(0.55 + 0.4 * e)), lineWidth: 1.6)

        // Innerer Ring
        strokeCircle(&context, center: center, radius: radius * 0.45, color: tint.opacity(0.35), width: 1)

        // Leuchtender Kern
        let coreRadius = radius * (0.2 + 0.08 * e)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - coreRadius, y: center.y - coreRadius,
                                   width: coreRadius * 2, height: coreRadius * 2)),
            with: .radialGradient(
                Gradient(colors: [.white, tint.opacity(0.9), tint.opacity(0)]),
                center: center, startRadius: 0, endRadius: coreRadius))
    }

    private func point(_ center: CGPoint, _ radius: Double, _ angle: Double) -> CGPoint {
        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
    }

    private func strokeCircle(_ context: inout GraphicsContext, center: CGPoint, radius: Double,
                              color: Color, width: CGFloat) {
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2)),
            with: .color(color), lineWidth: width)
    }
}

#Preview {
    AtlasCoreView(state: .listening, inputLevel: 0.5, spokenWordCount: 0)
        .frame(width: 340, height: 340)
        .background(.black)
}
