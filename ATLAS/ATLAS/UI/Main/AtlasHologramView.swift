import SwiftUI

/// Der A.T.L.A.S.-Kern (Standard-Darstellung): eine blaue Energiekugel aus glühenden Lichtsplittern.
///
/// - Start: Lichtpunkte fliegen in Schwüngen über den Bildschirm, formen das Wort „A.T.L.A.S.“
///   und fliegen dann in den Kern.
/// - Kern: rund 1.700 Punkte auf einer echten 3D-Kugel, jeder als kurzer Lichtstreifen in
///   Drehrichtung; außen eine Schale aus Splittern, innen ein heller Energie-Wirbel.
/// - Reaktionen: Zuhören → Oberfläche folgt Ihrer Stimme; Nachdenken → schnellere Drehung und
///   Analyse-Strahl; Sprechen → Pulsieren im Wortrhythmus und Schallwellen.
/// - Mit Finger oder Maus drehbar. Pausiert, sobald die App nicht sichtbar ist.
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
    @State private var dragYaw: Double = 0
    @State private var dragPitch: Double = 0
    @State private var dragStart: (yaw: Double, pitch: Double)?
    @State private var intro: Intro?

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: scenePhase != .active)) { timeline in
                Canvas { context, size in
                    draw(in: &context, size: size, date: timeline.date)
                }
            }
            .task(id: geometry.size) {
                guard intro == nil, !reduceMotion, geometry.size.width > 10 else { return }
                intro = Intro.make(size: geometry.size, layout: Self.layout(for: geometry.size))
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
        .accessibilityLabel("A.T.L.A.S., \(state.label)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Farben: Tiefblau → Eisblau → fast weiß

    private static let deep = Color(red: 0.07, green: 0.2, blue: 0.55)
    private static let blue = Color(red: 0.16, green: 0.47, blue: 1.0)
    private static let iceColor = Color(red: 0.43, green: 0.82, blue: 1.0)
    private static let hot = Color(red: 0.88, green: 0.96, blue: 1.0)
    private static let alert = Color(red: 1.0, green: 0.42, blue: 0.35)

    private var ice: Color { state.isError ? Self.alert : Self.iceColor }

    // MARK: - Geometrie (einmal berechnet)

    private struct SpherePoint { let x, y, z, seed, trail, jitter: Double }
    private struct Shard {
        let radius, angle, length, speed, brightness, flicker, phase, skew: Double
        let tangential: Bool
    }
    private struct Swirl { let rx, ry, tilt, speed, span: Double }
    struct Layout { let side, R, cx, cy, unit: Double }

    private static func seeded(_ seed: UInt64) -> () -> Double {
        var state = seed
        return {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }

    /// Gleichmäßig verteilte Punkte auf der Einheitskugel (Fibonacci-Gitter).
    private static let sphere: [SpherePoint] = {
        let random = AtlasHologramView.seeded(5)
        let count = 1700
        let golden = Double.pi * (3 - sqrt(5))
        return (0..<count).map { i in
            let y = 1 - 2 * (Double(i) + 0.5) / Double(count)
            let r = sqrt(1 - y * y)
            let phi = Double(i) * golden
            return SpherePoint(x: cos(phi) * r, y: y, z: sin(phi) * r, seed: random(),
                               trail: 0.15 + pow(random(), 2) * 3.2, jitter: (random() - 0.5) * 0.06)
        }
    }()

    /// Splitter-Schale außen: Bogenstücke und schräge Funken.
    private static let shards: [Shard] = {
        let random = AtlasHologramView.seeded(9)
        return (0..<1300).map { _ in
            let tangential = random() < 0.7
            return Shard(radius: 0.98 + 0.34 * pow(random(), 1.8),
                         angle: random() * 2 * .pi,
                         length: tangential ? 0.015 + 0.09 * random() * random() : 0.015 + 0.07 * random(),
                         speed: 0.05 + (random() - 0.5) * 0.09,
                         brightness: 0.1 + 0.9 * pow(random(), 1.7),
                         flicker: 0.6 + 3 * random(), phase: random() * 6.28, skew: (random() - 0.5) * 1.3,
                         tangential: tangential)
        }
    }()

    private static let swirls = [
        Swirl(rx: 0.42, ry: 0.16, tilt: 0.6, speed: 0.9, span: 3.6),
        Swirl(rx: 0.34, ry: 0.22, tilt: -0.8, speed: -0.7, span: 3.0),
        Swirl(rx: 0.26, ry: 0.1, tilt: 2.0, speed: 1.3, span: 3.8),
    ]

    static func layout(for size: CGSize) -> Layout {
        // Hochformat: die äußeren Ringe dürfen über den Rand laufen, damit die Kugel groß ist.
        let side = min(Double(size.width) * 1.32, Double(size.height) - 20)
        return Layout(side: side, R: side * 0.26, cx: Double(size.width) / 2, cy: Double(size.height) / 2,
                      unit: side / 400)
    }

    // MARK: - Mathematik

    private static func field(_ x: Double, _ y: Double, _ z: Double, _ t: Double) -> Double {
        let a = sin(3.1 * x + t * 1.3) * sin(2.7 * y - t * 1.1) * sin(2.9 * z + t * 0.9)
        let b = 0.5 * sin(5.3 * x - t * 2.1 + 1.7 * y) * sin(4.7 * z + t * 1.7)
        return a + b
    }

    /// Dreht um die y-Achse (ay), dann um die x-Achse (ax), und projiziert perspektivisch.
    private static func project(_ x: Double, _ y: Double, _ z: Double, ay: Double, ax: Double,
                                cx: Double, cy: Double, R: Double) -> (x: Double, y: Double, z: Double) {
        let x1 = x * cos(ay) + z * sin(ay)
        let z1 = -x * sin(ay) + z * cos(ay)
        let y2 = y * cos(ax) - z1 * sin(ax)
        let z2 = y * sin(ax) + z1 * cos(ax)
        let perspective = 3.2 / (3.2 - z2)
        return (cx + x1 * R * perspective, cy + y2 * R * perspective, z2)
    }

    private func energy(t: Double, envelope: Double) -> Double {
        switch state {
        case .listening, .confirming: return 0.35 + smoothedLevel * 0.65
        case .speaking: return 0.35 + envelope * 0.65
        case .thinking: return 0.45 + 0.15 * sin(t * 4)
        case .standby: return 0.2 + 0.05 * sin(t * 2)
        case .idle, .error: return 0.16 + 0.05 * sin(t * 1.1)
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

    // MARK: - Zeichnen

    private func draw(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000)
        let motion = reduceMotion ? 0.25 : 1.0
        let envelope = AtlasMotion.speechEnvelope(isSpeaking: state == .speaking,
                                                  sinceWord: date.timeIntervalSince(lastWordDate),
                                                  wordDuration: lastWordDuration, wordLength: spokenWordLength)
        let en = energy(t: t, envelope: envelope)
        let pulse = state == .speaking ? envelope : 0
        let spin = (state == .thinking ? 2.4 : 1.0) * motion
        let base = Self.layout(for: size)
        let speakPulse = state == .speaking ? 0.012 * (0.5 + 0.5 * sin(t * 7)) : 0
        let L = Layout(side: base.side, R: base.R * (1 + 0.065 * pulse + speakPulse),
                       cx: base.cx, cy: base.cy, unit: base.unit)
        let ay = t * 0.16 * spin + dragYaw
        let ax = 0.38 + sin(t * 0.11) * 0.12 * motion + dragPitch

        var ctx = context
        ctx.blendMode = .plusLighter

        // Start-Animation
        var reveal = 1.0
        if let intro {
            reveal = intro.draw(&ctx, date: date, ay: ay, ax: ax, layout: base)
            if reveal <= 0 { return }
        }
        ctx.opacity = reveal

        drawGlow(&ctx, L: L, en: en, pulse: pulse)
        drawSphere(&ctx, L: L, t: t, en: en, spin: spin, ay: ay, ax: ax)
        drawSwirls(&ctx, L: L, t: t, en: en, spin: spin)
        drawShell(&ctx, L: L, t: t, en: en, spin: spin, pulse: pulse)
        if state == .speaking {
            drawSoundWaves(&ctx, L: L, sinceWord: date.timeIntervalSince(lastWordDate))
        }
        drawHUD(&ctx, L: L, t: t, en: en, spin: spin, bounds: size)
    }

    private func drawGlow(_ ctx: inout GraphicsContext, L: Layout, en: Double, pulse: Double) {
        let center = CGPoint(x: L.cx, y: L.cy)
        ctx.fill(circle(L.cx, L.cy, L.R * 1.9), with: .radialGradient(
            Gradient(stops: [
                .init(color: Self.blue.opacity(0.22 + 0.2 * en + 0.15 * pulse), location: 0),
                .init(color: Self.deep.opacity(0.12 + 0.06 * en), location: 0.45),
                .init(color: Self.deep.opacity(0), location: 1),
            ]), center: center, startRadius: 0, endRadius: L.R * 1.9))
        ctx.fill(circle(L.cx, L.cy, L.R * 0.45), with: .radialGradient(
            Gradient(stops: [
                .init(color: Self.hot.opacity(0.5 + 0.3 * en + 0.2 * pulse), location: 0),
                .init(color: ice.opacity(0.25 + 0.2 * en), location: 0.4),
                .init(color: Self.blue.opacity(0), location: 1),
            ]), center: center, startRadius: 0, endRadius: L.R * 0.45))
    }

    /// Jeder Punkt der 3D-Kugel als kurzer Lichtstreifen in Drehrichtung.
    private func drawSphere(_ ctx: inout GraphicsContext, L: Layout, t: Double, en: Double, spin: Double,
                            ay: Double, ax: Double) {
        let amplitude = 0.03 + 0.14 * en
        let fieldTime = t * (state == .thinking ? 1.8 : 1)
        let breathing = sin(t * 1.2) * 0.008
        let trailStep = 0.16 * spin * 0.12
        let bucketCount = 7
        var buckets = [Path](repeating: Path(), count: bucketCount)
        for p in Self.sphere {
            let d = 1 + amplitude * Self.field(p.x, p.y, p.z, fieldTime) + breathing
            let now = Self.project(p.x * d, p.y * d, p.z * d, ay: ay, ax: ax, cx: L.cx, cy: L.cy, R: L.R)
            let before = Self.project(p.x * d, p.y * d, p.z * d, ay: ay - trailStep * p.trail,
                                      ax: ax + p.jitter * p.trail, cx: L.cx, cy: L.cy, R: L.R)
            let depth = (now.z + 1.15) / 2.3
            let twinkle = 0.6 + 0.4 * sin(t * (1.5 + p.seed * 3) + p.seed * 40)
            let alpha = min(0.999, (0.04 + depth * depth) * twinkle * (0.8 + 0.35 * en))
            guard alpha >= 0.05 else { continue }
            let index = Int(alpha * Double(bucketCount))
            buckets[index].move(to: CGPoint(x: before.x, y: before.y))
            buckets[index].addLine(to: CGPoint(x: now.x + 0.01, y: now.y))
        }
        for (index, path) in buckets.enumerated() where !path.isEmpty {
            let a = Double(index + 1) / Double(bucketCount)
            let width = L.unit * (0.6 + Double(index) * 0.22)
            let color: Color = index >= bucketCount - 2 ? Self.hot : (index >= bucketCount - 4 ? ice : Self.blue)
            ctx.stroke(path, with: .color(Self.deep.opacity(a * 0.5)),
                       style: StrokeStyle(lineWidth: width * 3, lineCap: .round))
            ctx.stroke(path, with: .color(color.opacity(a)), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }

    /// Heller Energie-Wirbel im Zentrum.
    private func drawSwirls(_ ctx: inout GraphicsContext, L: Layout, t: Double, en: Double, spin: Double) {
        for swirl in Self.swirls {
            let rotation = swirl.tilt + t * swirl.speed * spin * 0.5
            let start = t * swirl.speed * spin
            var path = Path()
            for step in 0...48 {
                let a = start + swirl.span * Double(step) / 48
                let x = cos(a) * swirl.rx * L.R, y = sin(a) * swirl.ry * L.R
                let px = L.cx + x * cos(rotation) - y * sin(rotation)
                let py = L.cy + x * sin(rotation) + y * cos(rotation)
                if step == 0 { path.move(to: CGPoint(x: px, y: py)) } else { path.addLine(to: CGPoint(x: px, y: py)) }
            }
            ctx.stroke(path, with: .color(ice.opacity(0.12 + 0.1 * en)),
                       style: StrokeStyle(lineWidth: 6 * L.unit, lineCap: .round))
            ctx.stroke(path, with: .color(Self.hot.opacity(0.45 + 0.35 * en)),
                       style: StrokeStyle(lineWidth: 1.3 * L.unit, lineCap: .round))
        }
    }

    /// Äußere Schale aus funkelnden Splittern.
    private func drawShell(_ ctx: inout GraphicsContext, L: Layout, t: Double, en: Double, spin: Double, pulse: Double) {
        let bucketCount = 6
        var buckets = [Path](repeating: Path(), count: bucketCount)
        for shard in Self.shards {
            let flicker = 0.55 + 0.45 * sin(t * shard.flicker + shard.phase)
            let alpha = shard.brightness * flicker * (0.45 + 0.75 * en)
            guard alpha >= 0.05 else { continue }
            let angle = shard.angle + shard.speed * t * spin
            let r = shard.radius * L.R * (1 + 0.04 * pulse + sin(t * 2 + shard.phase) * 0.01 * en)
            let index = min(bucketCount - 1, Int(alpha * Double(bucketCount)))
            if shard.tangential {
                let span = shard.length / shard.radius
                let controlRadius = r / cos(span / 2)
                buckets[index].move(to: CGPoint(x: L.cx + cos(angle) * r, y: L.cy + sin(angle) * r))
                buckets[index].addQuadCurve(
                    to: CGPoint(x: L.cx + cos(angle + span) * r, y: L.cy + sin(angle + span) * r),
                    control: CGPoint(x: L.cx + cos(angle + span / 2) * controlRadius,
                                     y: L.cy + sin(angle + span / 2) * controlRadius))
            } else {
                let length = shard.length * L.R
                let direction = angle + shard.skew
                let px = L.cx + cos(angle) * r, py = L.cy + sin(angle) * r
                let hx = cos(direction) * length / 2, hy = sin(direction) * length / 2
                buckets[index].move(to: CGPoint(x: px - hx, y: py - hy))
                buckets[index].addLine(to: CGPoint(x: px + hx, y: py + hy))
            }
        }
        for (index, path) in buckets.enumerated() where !path.isEmpty {
            let a = Double(index + 1) / Double(bucketCount)
            let width = L.unit * (0.7 + Double(index) * 0.3)
            ctx.stroke(path, with: .color(Self.deep.opacity(a * 0.35)),
                       style: StrokeStyle(lineWidth: width * 2.6, lineCap: .round))
            ctx.stroke(path, with: .color((index >= bucketCount - 2 ? Self.hot : ice).opacity(a)),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }

    /// Jedes gesprochene Wort sendet zwei Lichtringe aus.
    private func drawSoundWaves(_ ctx: inout GraphicsContext, L: Layout, sinceWord: Double) {
        for lag in [0.0, 0.42] {
            let s = sinceWord - lag
            guard s >= 0, s <= 0.9 else { continue }
            let k = s / 0.9
            ctx.stroke(circle(L.cx, L.cy, L.R * (1.35 + k * 0.5)),
                       with: .color(ice.opacity(0.5 * (1 - k) * (1 - k))), lineWidth: (1.6 - k) * L.unit)
        }
    }

    private func drawHUD(_ ctx: inout GraphicsContext, L: Layout, t: Double, en: Double, spin: Double, bounds: CGSize) {
        let scaleR = L.R * 1.62
        var minor = Path(), major = Path()
        let rotation = -t * 0.04 * spin
        for i in 0..<120 {
            let a = rotation + Double(i) / 120 * 2 * .pi
            let isMajor = i % 10 == 0
            let inner = scaleR - (isMajor ? L.R * 0.06 : L.R * 0.025)
            let from = CGPoint(x: L.cx + cos(a) * inner, y: L.cy + sin(a) * inner)
            let to = CGPoint(x: L.cx + cos(a) * scaleR, y: L.cy + sin(a) * scaleR)
            if isMajor {
                major.move(to: from); major.addLine(to: to)
            } else {
                minor.move(to: from); minor.addLine(to: to)
            }
        }
        ctx.stroke(minor, with: .color(ice.opacity(0.22)), lineWidth: 0.7 * L.unit)
        ctx.stroke(major, with: .color(ice.opacity(0.5)), lineWidth: 1.1 * L.unit)

        if state == .thinking {
            var band = circle(L.cx, L.cy, scaleR)
            band.addPath(circle(L.cx, L.cy, L.R * 1.35))
            ctx.fill(band,
                     with: .conicGradient(
                        Gradient(stops: [
                            .init(color: ice.opacity(0), location: 0),
                            .init(color: ice.opacity(0.2), location: 0.14),
                            .init(color: ice.opacity(0), location: 0.145),
                            .init(color: ice.opacity(0), location: 1),
                        ]),
                        center: CGPoint(x: L.cx, y: L.cy), angle: .radians(t * 3.2 - 0.9)),
                     style: FillStyle(eoFill: true))
        }

        var text = ctx
        text.blendMode = .normal
        let width = Double(bounds.width), height = Double(bounds.height)
        let left = max(14, L.cx - scaleR), right = min(width - 14, L.cx + scaleR)
        let top = max(18, L.cy - scaleR - 10 * L.unit), bottom = min(height - 10, L.cy + scaleR + 12 * L.unit)
        let fontSize = max(9, 9 * L.unit)
        let color = ice.opacity(0.7)
        func label(_ string: String, _ x: Double, _ y: Double, _ anchor: UnitPoint) {
            text.draw(Text(string).font(.system(size: fontSize, weight: .medium, design: .monospaced)).foregroundColor(color),
                      at: CGPoint(x: x, y: y), anchor: anchor)
        }
        label("A.T.L.A.S.", left, top, .leading)
        label(String(format: "SYNC %.1f%%", 99.2 + sin(t * 0.7) * 0.5), right, top, .trailing)
        label("STATUS · \(statusLabel)", left, bottom, .leading)
        label(String(format: "%.1f HZ", 120 + en * 260 + sin(t * 3) * 6), right, bottom, .trailing)
    }

    private func circle(_ x: Double, _ y: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    // MARK: - Start-Animation „A.T.L.A.S.“

    /// Lichtpunkte fliegen in Schwüngen herein, formen „A.T.L.A.S.“ und dann den Kern.
    struct Intro {
        struct Particle {
            let sx, sy, tx, ty, swing, waves, delay, size: Double
            let sphereIndex: Int
        }

        let particles: [Particle]
        let start = Date.now
        static let gather = 1.25
        static let hold = 0.85
        static let form = 0.85

        @MainActor
        static func make(size: CGSize, layout: Layout) -> Intro {
            let width = Double(size.width)
            let fontSize = min(width * 0.125, 120)
            let targets = textPoints("A.T.L.A.S.", fontSize: fontSize, step: max(3, (fontSize / 30).rounded()))
            let random = AtlasHologramView.seeded(17)
            let count = min(AtlasHologramView.sphere.count, max(targets.count, 700))
            let diagonal = hypot(width, Double(size.height))
            var list: [Particle] = []
            list.reserveCapacity(count)
            for i in 0..<count {
                let target = targets.isEmpty ? (0.0, 0.0) : targets[i % targets.count]
                let angle = random() * 2 * .pi
                let distance = diagonal * (0.55 + random() * 0.4)
                list.append(Particle(
                    sx: layout.cx + cos(angle) * distance, sy: layout.cy + sin(angle) * distance,
                    tx: layout.cx + target.0 + (random() - 0.5) * 2, ty: layout.cy + target.1 + (random() - 0.5) * 2,
                    swing: (random() - 0.5) * 0.9 * min(width, Double(size.height)),
                    waves: Double(1 + Int(random() * 2)), delay: random() * 0.35,
                    size: 0.8 + random() * 1.4,
                    sphereIndex: (i * 7) % AtlasHologramView.sphere.count))
            }
            return Intro(particles: list)
        }

        /// Rastert das Wort und liefert Punktpositionen relativ zur Mitte.
        @MainActor
        private static func textPoints(_ string: String, fontSize: Double, step: Double) -> [(Double, Double)] {
            let renderer = ImageRenderer(content:
                Text(string)
                    .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(4))
            renderer.scale = 1
            guard let image = renderer.cgImage else { return [] }
            let w = image.width, h = image.height
            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
                guard let bitmap = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                             bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                bitmap.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return [] }
            var points: [(Double, Double)] = []
            let s = max(1, Int(step))
            for y in stride(from: 0, to: h, by: s) {
                for x in stride(from: 0, to: w, by: s) where pixels[(y * w + x) * 4 + 3] > 140 {
                    points.append((Double(x) - Double(w) / 2, Double(y) - Double(h) / 2))
                }
            }
            return points
        }

        private static func ease(_ u: Double) -> Double {
            u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
        }

        /// Zeichnet die Animation; liefert 0…1, wie weit der Kern schon sichtbar sein soll.
        func draw(_ ctx: inout GraphicsContext, date: Date, ay: Double, ax: Double, layout L: Layout) -> Double {
            let e = date.timeIntervalSince(start)
            let holdEnd = Self.gather + Self.hold, formEnd = holdEnd + Self.form
            guard e < formEnd + 0.2 else { return 1 }
            let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000)
            let bucketCount = 6
            var buckets = [Path](repeating: Path(), count: bucketCount)
            for p in particles {
                var x: Double, y: Double, a: Double
                if e < Self.gather {
                    let u = min(1, max(0, (e - p.delay) / (Self.gather - p.delay)))
                    let k = Self.ease(u)
                    let dx = p.tx - p.sx, dy = p.ty - p.sy, length = max(1, hypot(dx, dy))
                    let sway = sin(u * .pi * p.waves) * p.swing * (1 - k)
                    x = p.sx + dx * k - dy / length * sway
                    y = p.sy + dy * k + dx / length * sway
                    a = 0.35 + 0.65 * u
                } else if e < holdEnd {
                    x = p.tx + sin(t * 9 + p.tx * 0.05) * 0.6
                    y = p.ty
                    a = 0.85 + 0.15 * sin(t * 6 + p.ty)
                } else {
                    let u = min(1, (e - holdEnd) / Self.form), k = Self.ease(u)
                    let point = AtlasHologramView.sphere[p.sphereIndex]
                    let q = AtlasHologramView.project(point.x, point.y, point.z, ay: ay, ax: ax,
                                                      cx: L.cx, cy: L.cy, R: L.R)
                    x = p.tx + (q.x - p.tx) * k + sin(u * .pi) * 0.15 * L.R
                    y = p.ty + (q.y - p.ty) * k
                    a = 1 - 0.5 * u
                }
                let index = min(bucketCount - 1, max(0, Int(a * Double(bucketCount))))
                let s = p.size * L.unit * 0.85
                buckets[index].addEllipse(in: CGRect(x: x - s, y: y - s, width: s * 2, height: s * 2))
            }
            var glowing = ctx
            glowing.addFilter(.shadow(color: AtlasHologramView.blue.opacity(0.9), radius: 8 * L.unit))
            for (index, path) in buckets.enumerated() where !path.isEmpty {
                let a = Double(index + 1) / Double(bucketCount)
                let color = index >= bucketCount - 2 ? AtlasHologramView.hot : AtlasHologramView.iceColor
                glowing.fill(path, with: .color(color.opacity(a)))
            }
            return e < holdEnd ? 0 : min(1, (e - holdEnd) / Self.form)
        }
    }
}

#Preview {
    AtlasHologramView(state: .thinking, inputLevel: 0.4, spokenWordCount: 0, spokenWordLength: 5, speechRate: 0.5)
        .frame(width: 400, height: 700)
        .background(.black)
}
