import SwiftUI

/// ATLAS-Kern (Standard-Darstellung) im Stil eines J.A.R.V.I.S.-Interfaces:
/// eine echte 3D-Kugel aus rund 1.900 Lichtpunkten, die sich räumlich dreht und deren
/// Oberfläche wie ein Klangfeld wogt, umgeben von einem präzisen HUD – Skala, rotierende
/// Segmentbögen, kreisförmige Audiowelle, Großkreise und Telemetrie-Anzeigen.
///
/// Reaktionen: Beim Zuhören folgt das Klangfeld Ihrer Stimme, beim Nachdenken dreht sich der
/// Kern schneller und ein Analyse-Strahl kreist, beim Sprechen pulsiert er im Wortrhythmus.
/// Gezeichnet mit SwiftUI `Canvas`; die Punkte werden nach Helligkeit gebündelt, sodass pro
/// Bild nur wenige Zeichenbefehle anfallen. Pausiert, sobald die App nicht sichtbar ist.
struct AtlasHologramView: View {
    let state: ConversationEngine.State
    let inputLevel: Float
    let spokenWordCount: Int
    let spokenWordLength: Int
    let speechRate: Double

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var smoothedLevel: Double = 0
    @State private var lastWordDate = Date.distantPast
    @State private var lastWordDuration: Double = 0.3
    /// Drehung per Finger bzw. Maus (zusätzlich zur Eigenrotation).
    @State private var dragYaw: Double = 0
    @State private var dragPitch: Double = 0
    @State private var dragStart: (yaw: Double, pitch: Double)?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: scenePhase != .active)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, date: timeline.date)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    let start = dragStart ?? (yaw: dragYaw, pitch: dragPitch)
                    dragStart = start
                    dragYaw = start.yaw + Double(value.translation.width) * 0.006
                    dragPitch = min(1.2, max(-1.2, start.pitch + Double(value.translation.height) * 0.006))
                }
                .onEnded { _ in dragStart = nil }
        )
        .onChange(of: inputLevel) { _, newValue in
            smoothedLevel = smoothedLevel * 0.6 + Double(newValue) * 0.4
        }
        .onChange(of: spokenWordCount) { _, _ in
            lastWordDate = .now
            lastWordDuration = AtlasMotion.wordDuration(length: spokenWordLength, speechRate: speechRate)
        }
        .accessibilityElement()
        .accessibilityLabel("ATLAS, \(state.label)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Farben

    private static let amberColor = Color(red: 1.0, green: 0.66, blue: 0.26)
    private static let hot = Color(red: 1.0, green: 0.89, blue: 0.71)
    private static let deep = Color(red: 0.75, green: 0.36, blue: 0.09)
    private static let alert = Color(red: 1.0, green: 0.36, blue: 0.24)

    private var amber: Color { state.isError ? Self.alert : Self.amberColor }

    // MARK: - Geometrie (einmal berechnet)

    private struct SpherePoint { let x: Double, y: Double, z: Double, seed: Double }

    /// Gleichmäßig verteilte Punkte auf der Einheitskugel (Fibonacci-Gitter).
    private static let sphere: [SpherePoint] = {
        let count = 1900
        let golden = Double.pi * (3 - sqrt(5))
        return (0..<count).map { i in
            let y = 1 - 2 * (Double(i) + 0.5) / Double(count)
            let r = sqrt(1 - y * y)
            let phi = Double(i) * golden
            return SpherePoint(x: cos(phi) * r, y: y, z: sin(phi) * r, seed: Double((i * 7919) % 97) / 97)
        }
    }()

    private struct GreatCircle { let tiltX: Double, tiltZ: Double, speed: Double }
    private static let greatCircles = [
        GreatCircle(tiltX: 0.55, tiltZ: 0.25, speed: 0.22),
        GreatCircle(tiltX: -0.45, tiltZ: -0.8, speed: -0.16),
    ]

    private struct Segment { let start: Double, length: Double }
    private static let segments = [
        Segment(start: 0.2, length: 0.9), Segment(start: 1.6, length: 0.35),
        Segment(start: 2.4, length: 1.4), Segment(start: 4.3, length: 0.6),
    ]

    // MARK: - Zustand → Ausdruck

    private func energy(t: Double, envelope: Double) -> Double {
        switch state {
        case .listening, .confirming: return 0.35 + smoothedLevel * 0.65
        case .speaking: return 0.35 + envelope * 0.65
        case .thinking: return 0.4 + 0.15 * sin(t * 4)
        case .standby: return 0.18 + 0.05 * sin(t * 2)
        case .idle, .error: return 0.12 + 0.04 * sin(t * 1.1)
        }
    }

    private var statusLabel: String {
        switch state {
        case .idle: return "BEREIT"
        case .standby: return "BEREITSCHAFT"
        case .listening: return "HÖRT ZU"
        case .thinking: return "ANALYSE"
        case .speaking: return "AUSGABE"
        case .confirming: return "BESTÄTIGUNG"
        case .error: return "HINWEIS"
        }
    }

    /// Glatte 3D-Verformung der Oberfläche – das „Klangfeld“.
    private static func field(_ x: Double, _ y: Double, _ z: Double, _ t: Double) -> Double {
        let a = sin(3.1 * x + t * 1.3) * sin(2.7 * y - t * 1.1) * sin(2.9 * z + t * 0.9)
        let b = 0.5 * sin(5.3 * x - t * 2.1 + 1.7 * y) * sin(4.7 * z + t * 1.7)
        return a + b
    }

    /// Dreht einen Punkt um die y-Achse (ay) und danach um die x-Achse (ax).
    private static func rotate(_ x: Double, _ y: Double, _ z: Double,
                               ay: Double, ax: Double) -> (x: Double, y: Double, z: Double) {
        let x1 = x * cos(ay) + z * sin(ay)
        let z1 = -x * sin(ay) + z * cos(ay)
        let y2 = y * cos(ax) - z1 * sin(ax)
        let z2 = y * sin(ax) + z1 * cos(ax)
        return (x1, y2, z2)
    }

    // MARK: - Zeichnen

    private func draw(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000)
        let motion = reduceMotion ? 0.25 : 1.0
        let envelope = AtlasMotion.speechEnvelope(isSpeaking: state == .speaking,
                                                  sinceWord: date.timeIntervalSince(lastWordDate),
                                                  wordDuration: lastWordDuration, wordLength: spokenWordLength)
        let en = energy(t: t, envelope: envelope)
        let spin = (state == .thinking ? 2.4 : 1.0) * motion
        // Hochformat: die äußeren Ringe dürfen über den Rand laufen, damit die Kugel möglichst groß ist.
        let side = min(Double(size.width) * 1.32, Double(size.height) - 20)
        // Pulsieren beim Sprechen: Silbenrhythmus plus sanftes Grundpulsieren
        let pulse = state == .speaking ? envelope : 0
        let speakPulse = state == .speaking ? 0.012 * (0.5 + 0.5 * sin(t * 7)) : 0
        let R = side * 0.29 * (1 + 0.065 * pulse + speakPulse)
        let unit = side / 400
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        var ctx = context
        ctx.blendMode = .plusLighter

        // Weicher Kernschein
        ctx.fill(circle(center, R * 1.6), with: .radialGradient(
            Gradient(stops: [
                .init(color: amber.opacity(0.10 + 0.14 * en + 0.18 * pulse), location: 0),
                .init(color: Self.deep.opacity(0.05 + 0.05 * en), location: 0.5),
                .init(color: Self.deep.opacity(0), location: 1),
            ]),
            center: center, startRadius: 0, endRadius: R * 1.6))

        let ay = t * 0.16 * spin + dragYaw
        let ax = 0.38 + sin(t * 0.11) * 0.12 * motion + dragPitch
        drawSphere(&ctx, center: center, R: R, unit: unit, t: t, en: en, ay: ay, ax: ax)
        drawGreatCircles(&ctx, center: center, R: R, unit: unit, t: t, en: en, spin: spin, ay: ay, ax: ax)
        if state == .speaking {
            drawSoundWaves(&ctx, center: center, R: R, unit: unit, sinceWord: date.timeIntervalSince(lastWordDate))
        }
        drawHUD(&ctx, center: center, R: R, unit: unit, t: t, en: en, spin: spin, bounds: size)
    }

    private func drawSphere(_ ctx: inout GraphicsContext, center: CGPoint, R: Double, unit: Double,
                            t: Double, en: Double, ay: Double, ax: Double) {
        let amplitude = 0.025 + 0.13 * en
        let fieldTime = t * (state == .thinking ? 1.8 : 1)
        let breathing = sin(t * 1.2) * 0.008
        let bucketCount = 8
        var buckets = [Path](repeating: Path(), count: bucketCount)
        let cx = Double(center.x), cy = Double(center.y)

        for p in Self.sphere {
            let d = 1 + amplitude * Self.field(p.x, p.y, p.z, fieldTime) + breathing
            let q = Self.rotate(p.x * d, p.y * d, p.z * d, ay: ay, ax: ax)
            let perspective = 3.2 / (3.2 - q.z)
            let depth = (q.z + 1.15) / 2.3
            let twinkle = 0.85 + 0.15 * sin(t * 2.3 + p.seed * 40)
            let alpha = min(0.999, (0.05 + depth * depth) * twinkle * (0.85 + 0.3 * en))
            guard alpha >= 0.05 else { continue }
            let s = unit * (0.45 + depth * depth) * perspective
            let px = cx + q.x * R * perspective
            let py = cy + q.y * R * perspective
            buckets[Int(alpha * Double(bucketCount))].addRect(CGRect(x: px - s / 2, y: py - s / 2, width: s, height: s))
        }

        var glowing = ctx
        glowing.addFilter(.shadow(color: amber.opacity(0.9), radius: 5 * unit))
        for (index, path) in buckets.enumerated() where !path.isEmpty {
            let alpha = Double(index + 1) / Double(bucketCount)
            let color = (index >= bucketCount - 2 ? Self.hot : amber).opacity(alpha)
            if index >= bucketCount - 3 {
                glowing.fill(path, with: .color(color))
            } else {
                ctx.fill(path, with: .color(color))
            }
        }
    }

    private func drawGreatCircles(_ ctx: inout GraphicsContext, center: CGPoint, R: Double, unit: Double,
                                  t: Double, en: Double, spin: Double, ay: Double, ax: Double) {
        let cx = Double(center.x), cy = Double(center.y)
        let steps = 140
        for spec in Self.greatCircles {
            var front = Path(), back = Path()
            for i in stride(from: 0, to: steps, by: 2) {
                for k in 0..<2 {
                    let angle = Double(i + k) / Double(steps) * 2 * .pi + t * spec.speed * spin
                    // Kreis in der x-z-Ebene, gekippt um x und z, dann wie die Kugel gedreht
                    let p0 = Self.rotate(cos(angle) * 1.08, 0, sin(angle) * 1.08, ay: 0, ax: spec.tiltX)
                    let x1 = p0.x * cos(spec.tiltZ) - p0.y * sin(spec.tiltZ)
                    let y1 = p0.x * sin(spec.tiltZ) + p0.y * cos(spec.tiltZ)
                    let q = Self.rotate(x1, y1, p0.z, ay: ay * 0.6, ax: ax)
                    let perspective = 3.2 / (3.2 - q.z)
                    let point = CGPoint(x: cx + q.x * R * perspective, y: cy + q.y * R * perspective)
                    if k == 0 {
                        if q.z > 0 { front.move(to: point) } else { back.move(to: point) }
                    } else {
                        if q.z > 0 { front.addLine(to: point) } else { back.addLine(to: point) }
                    }
                }
            }
            ctx.stroke(back, with: .color(amber.opacity(0.10)), lineWidth: 0.8 * unit)
            ctx.stroke(front, with: .color(amber.opacity(0.38 + 0.2 * en)), lineWidth: 0.8 * unit)
        }
    }

    /// Jedes gesprochene Wort sendet zwei Lichtringe aus, die nach außen laufen und verblassen.
    private func drawSoundWaves(_ ctx: inout GraphicsContext, center: CGPoint, R: Double, unit: Double,
                                sinceWord: Double) {
        for lag in [0.0, 0.42] {
            let s = sinceWord - lag
            guard s >= 0, s <= 0.9 else { continue }
            let k = s / 0.9
            ctx.stroke(circle(center, R * (1.05 + k * 0.6)),
                       with: .color(amber.opacity(0.45 * (1 - k) * (1 - k))),
                       lineWidth: (1.6 - k) * unit)
        }
    }

    private func drawHUD(_ ctx: inout GraphicsContext, center: CGPoint, R: Double, unit: Double,
                         t: Double, en: Double, spin: Double, bounds: CGSize) {
        let cx = Double(center.x), cy = Double(center.y)
        ctx.stroke(circle(center, R * 1.22), with: .color(amber.opacity(0.16)), lineWidth: 0.7 * unit)

        // Kreisförmige Audiowelle
        var wave = Path()
        let waveR = R * 1.3
        let waveGain = (state == .idle || state == .standby) ? 0.15 : en
        for i in 0...240 {
            let a = Double(i) / 240 * 2 * .pi
            let k = sin(a * 9 + t * 4) * 0.6 + sin(a * 23 - t * 6.5) * 0.4
            let r = waveR + k * R * 0.05 * waveGain
            let p = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
            if i == 0 { wave.move(to: p) } else { wave.addLine(to: p) }
        }
        ctx.stroke(wave, with: .color(amber.opacity(0.28 + 0.4 * en)), lineWidth: 0.9 * unit)

        // Skala mit 120 Teilstrichen
        let scaleR = R * 1.46
        var minor = Path(), major = Path()
        let rotation = -t * 0.04 * spin
        for i in 0..<120 {
            let a = rotation + Double(i) / 120 * 2 * .pi
            let isMajor = i % 10 == 0
            let inner = scaleR - (isMajor ? R * 0.06 : R * 0.025)
            let from = CGPoint(x: cx + cos(a) * inner, y: cy + sin(a) * inner)
            let to = CGPoint(x: cx + cos(a) * scaleR, y: cy + sin(a) * scaleR)
            if isMajor {
                major.move(to: from); major.addLine(to: to)
            } else {
                minor.move(to: from); minor.addLine(to: to)
            }
        }
        ctx.stroke(minor, with: .color(amber.opacity(0.28)), lineWidth: 0.7 * unit)
        ctx.stroke(major, with: .color(amber.opacity(0.6)), lineWidth: 1.1 * unit)
        ctx.stroke(circle(center, scaleR + 2 * unit), with: .color(amber.opacity(0.22)), lineWidth: 0.6 * unit)

        // Rotierende Segmentbögen
        let segmentR = R * 1.62
        for segment in Self.segments {
            let start = segment.start - t * 0.12 * spin * 1.6
            ctx.stroke(arc(center, segmentR, from: start, length: segment.length),
                       with: .color(amber.opacity(0.55 + 0.3 * en)),
                       style: StrokeStyle(lineWidth: 2.2 * unit, lineCap: .butt))
        }
        ctx.stroke(circle(center, segmentR + 6 * unit), with: .color(amber.opacity(0.12)), lineWidth: 0.6 * unit)

        // Analyse-Strahl beim Nachdenken
        if state == .thinking {
            var band = circle(center, segmentR)
            band.addPath(circle(center, R * 1.22))
            ctx.fill(band,
                     with: .conicGradient(
                        Gradient(stops: [
                            .init(color: amber.opacity(0), location: 0),
                            .init(color: amber.opacity(0.22), location: 0.14),
                            .init(color: amber.opacity(0), location: 0.145),
                            .init(color: amber.opacity(0), location: 1),
                        ]),
                        center: center, angle: .radians(t * 3.2 - 0.9)),
                     style: FillStyle(eoFill: true))
        }

        // Fadenkreuz-Markierungen
        var marks = Path()
        let markR = segmentR + 14 * unit, markLength = 7 * unit
        for i in 0..<4 {
            let a = Double(i) * .pi / 2
            marks.move(to: CGPoint(x: cx + cos(a) * markR, y: cy + sin(a) * markR))
            marks.addLine(to: CGPoint(x: cx + cos(a) * (markR + markLength), y: cy + sin(a) * (markR + markLength)))
        }
        ctx.stroke(marks, with: .color(amber.opacity(0.5)), lineWidth: 0.9 * unit)

        // Telemetrie-Beschriftung
        var text = ctx
        text.blendMode = .normal
        let fontSize = max(8, 8.5 * unit)
        // Beschriftungen bleiben immer im sichtbaren Bereich
        let width = Double(bounds.width), height = Double(bounds.height)
        let left = max(14, cx - segmentR - 4 * unit), right = min(width - 14, cx + segmentR + 4 * unit)
        let top = max(18, cy - segmentR - 2 * unit), bottom = min(height - 10, cy + segmentR + 4 * unit)
        let frequency = String(format: "%.1f HZ", 120 + en * 260 + sin(t * 3) * 6)
        let sync = String(format: "SYNC %.1f%%", 99.2 + sin(t * 0.7) * 0.5)
        let labelColor = amber.opacity(0.62)
        func label(_ string: String, _ x: Double, _ y: Double, _ anchor: UnitPoint) {
            text.draw(Text(string)
                        .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                        .foregroundColor(labelColor),
                      at: CGPoint(x: x, y: y), anchor: anchor)
        }
        label("ATLAS // KERN 01", left, top, .leading)
        label(sync, right, top, .trailing)
        label("STATUS · \(statusLabel)", left, bottom, .leading)
        label(frequency, right, bottom, .trailing)
    }

    // MARK: - Hilfen

    private func circle(_ center: CGPoint, _ radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: Double(center.x) - radius, y: Double(center.y) - radius,
                               width: radius * 2, height: radius * 2))
    }

    /// Kreisbogen als Punktfolge – eindeutig in der Richtung, unabhängig vom Koordinatensystem.
    private func arc(_ center: CGPoint, _ radius: Double, from start: Double, length: Double) -> Path {
        var path = Path()
        let steps = max(8, Int(length * 30))
        for i in 0...steps {
            let a = start + length * Double(i) / Double(steps)
            let p = CGPoint(x: Double(center.x) + cos(a) * radius, y: Double(center.y) + sin(a) * radius)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}

#Preview {
    AtlasHologramView(state: .thinking, inputLevel: 0.4, spokenWordCount: 0, spokenWordLength: 5, speechRate: 0.5)
        .frame(width: 400, height: 400)
        .background(.black)
}
