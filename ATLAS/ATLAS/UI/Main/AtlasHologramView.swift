import SwiftUI

/// ATLAS als Hologramm (Standard-Darstellung): eine glühende, bernsteinfarbene Kugel aus
/// Lichtsplittern und Umlaufbahnen – inspiriert von J.A.R.V.I.S. – mit einem holografischen
/// Gesicht im Zentrum. Das Gesicht blinzelt, hält Blickkontakt und bewegt beim Sprechen den
/// Mund; die Kugel reagiert auf Ihre Stimme (Zuhören), dreht sich schneller beim Nachdenken
/// und pulsiert beim Sprechen.
///
/// Gezeichnet mit SwiftUI `Canvas` und additiver Lichtmischung. Die rund 1.100 Splitter werden
/// nach Helligkeit gebündelt, sodass pro Bild nur wenige Zeichenbefehle anfallen.
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
    @State private var previousExpression = AtlasFaceView.Expression.idle
    @State private var stateChangeDate = Date.distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: scenePhase != .active)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, date: timeline.date)
            }
        }
        .onChange(of: inputLevel) { _, newValue in
            smoothedLevel = smoothedLevel * 0.6 + Double(newValue) * 0.4
        }
        .onChange(of: spokenWordCount) { _, _ in
            lastWordDate = .now
            lastWordDuration = AtlasMotion.wordDuration(length: spokenWordLength, speechRate: speechRate)
        }
        .onChange(of: state) { oldValue, _ in
            previousExpression = AtlasFaceView.Expression.forState(oldValue)
            stateChangeDate = .now
        }
        .accessibilityElement()
        .accessibilityLabel("ATLAS, \(state.label)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Farben

    private static let amberCore = Color(red: 1.0, green: 0.84, blue: 0.55)
    private static let amber = Color(red: 1.0, green: 0.62, blue: 0.2)
    private static let amberDeep = Color(red: 0.84, green: 0.38, blue: 0.09)
    private static let errorRed = Color(red: 1.0, green: 0.35, blue: 0.25)

    private var amber: Color { state.isError ? Self.errorRed : Self.amber }

    // MARK: - Lichtsplitter (einmal berechnet, deterministisch)

    private struct Shard {
        let radius: Double      // relativ zum Kugelradius
        let angle: Double
        let tangential: Bool    // Bogenstück entlang der Kugel oder schräger Strich
        let length: Double
        let speed: Double
        let brightness: Double
        let flicker: Double
        let phase: Double
        let wobble: Double
        let skew: Double
    }

    private struct Orbit {
        let rx: Double, ry: Double, tilt: Double, speed: Double, span: Double
    }

    private static let shards: [Shard] = {
        var seed: UInt64 = 7
        func random() -> Double {
            // SplitMix64 – schneller, reproduzierbarer Zufall
            seed &+= 0x9E37_79B9_7F4A_7C15
            var z = seed
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
        var list: [Shard] = []
        list.reserveCapacity(1100)
        for _ in 0..<1100 {
            let outer = random() < 0.86
            let tangential = random() < 0.72
            list.append(Shard(
                radius: outer ? 0.72 + 0.28 * pow(random(), 0.45) : 0.18 + 0.5 * random(),
                angle: random() * 2 * .pi,
                tangential: tangential,
                length: tangential ? 0.012 + 0.07 * random() * random() : 0.012 + 0.05 * random(),
                speed: (outer ? 0.05 : -0.09) + (random() - 0.5) * 0.08,
                brightness: outer ? 0.12 + 0.88 * pow(random(), 1.6) : 0.08 + 0.45 * pow(random(), 2),
                flicker: 0.6 + 2.8 * random(),
                phase: random() * 6.28,
                wobble: random() * 6.28,
                skew: (random() - 0.5) * 1.2))
        }
        return list
    }()

    private static let orbits: [Orbit] = [
        Orbit(rx: 0.66, ry: 0.2, tilt: 0.5, speed: 0.3, span: 2.4),
        Orbit(rx: 0.6, ry: 0.36, tilt: -0.9, speed: -0.22, span: 1.8),
        Orbit(rx: 0.74, ry: 0.1, tilt: 2.6, speed: -0.16, span: 2.0),
    ]

    // MARK: - Zeichnen

    private func energy(t: Double, mouth: Double) -> Double {
        switch state {
        case .listening, .confirming: return 0.45 + smoothedLevel * 0.55
        case .speaking: return 0.5 + mouth * 0.5
        case .thinking: return 0.55 + sin(t * 3.5) * 0.12
        case .standby: return 0.32 + sin(t * 2) * 0.06
        case .idle, .error: return 0.28 + sin(t * 1.2) * 0.04
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000)
        let motion = reduceMotion ? 0.25 : 1.0
        let blend = min(date.timeIntervalSince(stateChangeDate) / 0.45, 1)
        let expr = AtlasFaceView.Expression.mix(previousExpression, AtlasFaceView.Expression.forState(state),
                                                blend * blend * (3 - 2 * blend))
        let mouth = AtlasMotion.mouthOpen(state: state, sinceWord: date.timeIntervalSince(lastWordDate),
                                          wordDuration: lastWordDuration, wordLength: spokenWordLength)
        let en = energy(t: t, mouth: mouth)
        let spin: Double
        switch state {
        case .thinking: spin = 2.6 * motion
        case .listening, .confirming: spin = 1.3 * motion
        default: spin = motion
        }
        let listeningSwell = (state == .listening || state == .confirming) ? smoothedLevel * 0.04 : 0
        let speakingSwell = state == .speaking ? mouth * 0.02 : 0
        let radius = Double(min(size.width, size.height)) * 0.46 * (1 + listeningSwell + speakingSwell)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        var ctx = context
        ctx.blendMode = .plusLighter

        drawSphere(&ctx, center: center, radius: radius, energy: en, t: t, spin: spin)
        drawOrbits(&ctx, center: center, radius: radius, energy: en, t: t, spin: spin)
        drawFace(&ctx, center: center, radius: radius, energy: en, t: t, motion: motion, expr: expr, mouth: mouth)
    }

    /// Glimmende Scheibe, Außenring und die Kugel aus Lichtsplittern.
    private func drawSphere(_ ctx: inout GraphicsContext, center: CGPoint, radius R: Double,
                            energy en: Double, t: Double, spin: Double) {
        let glowR = R * 1.15
        ctx.fill(circle(center, glowR),
                 with: .radialGradient(
                    Gradient(stops: [
                        .init(color: amber.opacity(0.2 + 0.25 * en), location: 0),
                        .init(color: Self.amberDeep.opacity(0.1 + 0.08 * en), location: 0.35),
                        .init(color: Self.amberDeep.opacity(0.05), location: 0.8),
                        .init(color: Self.amberDeep.opacity(0), location: 1),
                    ]),
                    center: center, startRadius: R * 0.05, endRadius: glowR))
        ctx.stroke(circle(center, R * 1.03), with: .color(Self.amberDeep.opacity(0.09)), lineWidth: R * 0.07)
        ctx.stroke(circle(center, R * 0.985), with: .color(amber.opacity(0.22)), lineWidth: 1)

        let bucketCount = 6
        var buckets = [Path](repeating: Path(), count: bucketCount)
        for shard in Self.shards {
            let flick = 0.55 + 0.45 * sin(t * shard.flicker + shard.phase)
            let alpha = shard.brightness * flick * (0.45 + en * 0.8)
            guard alpha >= 0.04 else { continue }
            let angle = shard.angle + shard.speed * t * spin
            let r = shard.radius * R * (1 + sin(t * 2 + shard.wobble) * 0.012 * en)
            let index = min(bucketCount - 1, Int(alpha * Double(bucketCount)))
            if shard.tangential {
                // Kurzes Bogenstück als Kurve (eindeutig, ohne Richtungsfehler)
                let span = shard.length / shard.radius
                let mid = angle + span / 2
                let controlRadius = r / cos(span / 2)
                buckets[index].move(to: point(center, r, angle))
                buckets[index].addQuadCurve(to: point(center, r, angle + span),
                                            control: point(center, controlRadius, mid))
            } else {
                let length = shard.length * R
                let direction = angle + shard.skew
                let p = point(center, r, angle)
                let hx: Double = cos(direction) * length / 2, hy: Double = sin(direction) * length / 2
                buckets[index].move(to: CGPoint(x: Double(p.x) - hx, y: Double(p.y) - hy))
                buckets[index].addLine(to: CGPoint(x: Double(p.x) + hx, y: Double(p.y) + hy))
            }
        }
        for (index, path) in buckets.enumerated() where !path.isEmpty {
            let a = Double(index + 1) / Double(bucketCount)
            let width = 0.7 + Double(index) * 0.32
            let hot = index >= bucketCount - 2
            ctx.stroke(path, with: .color(Self.amberDeep.opacity(a * 0.22)),
                       style: StrokeStyle(lineWidth: width * 2.6, lineCap: .round))
            ctx.stroke(path, with: .color((hot ? Self.amberCore : amber).opacity(a)),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }

    /// Leuchtende, geneigte Umlaufbahnen (Teilbögen von Ellipsen).
    private func drawOrbits(_ ctx: inout GraphicsContext, center: CGPoint, radius R: Double,
                            energy en: Double, t: Double, spin: Double) {
        for orbit in Self.orbits {
            let rotation = orbit.tilt + t * orbit.speed * spin * 0.6
            let start = t * orbit.speed * spin * 1.4
            var path = Path()
            let steps = 40
            for step in 0...steps {
                let a = start + orbit.span * Double(step) / Double(steps)
                let x = cos(a) * orbit.rx * R, y = sin(a) * orbit.ry * R
                let dx: Double = x * cos(rotation) - y * sin(rotation)
                let dy: Double = x * sin(rotation) + y * cos(rotation)
                let p = CGPoint(x: Double(center.x) + dx, y: Double(center.y) + dy)
                if step == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            ctx.stroke(path, with: .color(amber.opacity(0.06 + 0.06 * en)),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round))
            ctx.stroke(path, with: .color(Self.amberCore.opacity(0.22 + 0.3 * en)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
    }

    /// Das holografische Gesicht: Umriss, Raster, Scan-Balken, glühende Augen, Brauen, Mund.
    private func drawFace(_ ctx: inout GraphicsContext, center: CGPoint, radius R: Double, energy en: Double,
                          t: Double, motion: Double, expr: AtlasFaceView.Expression, mouth: Double) {
        let H = R, W = H * 0.7
        let yaw = (sin(t * 0.37) * 0.035 + sin(t * 0.91) * 0.012) * motion
        let pitch = sin(t * 0.29) * 0.02 * motion
        let fx = yaw * W * 0.55, fy = pitch * H * 0.5
        let flickerFace = 0.82 + 0.18 * sin(t * 23) * sin(t * 7.1)
        let faceA = min(1, (0.75 + 0.35 * en) * flickerFace)

        var face = ctx
        let offsetX: Double = Double(center.x) + yaw * W * 0.35
        let offsetY: Double = Double(center.y) + pitch * H * 0.3 + H * 0.02
        face.translateBy(x: offsetX, y: offsetY)
        face.rotate(by: .radians((expr.headTilt + sin(t * 0.23) * 0.012) * motion))

        let head = AtlasMotion.headPath(W: W, H: H)

        // Dunkler Grund, damit das Gesicht aus der Kugel heraustritt
        var shade = face
        shade.blendMode = .normal
        shade.fill(head, with: .color(Color(red: 0.04, green: 0.02, blue: 0.01).opacity(0.55)))

        // Hologramm-Raster und wandernder Scan-Balken
        var inside = face
        inside.clip(to: head)
        var lines = Path()
        let step = H / 30
        let shift = (t * 12).truncatingRemainder(dividingBy: step)
        var y = -H / 2 + shift
        while y < H / 2 {
            lines.move(to: CGPoint(x: -W / 2, y: y))
            lines.addLine(to: CGPoint(x: W / 2, y: y))
            y += step
        }
        inside.stroke(lines, with: .color(amber.opacity(0.07 * faceA)), lineWidth: 1)
        let scanY = ((t * 0.35).truncatingRemainder(dividingBy: 1.4) - 0.2) * H - H / 2
        inside.fill(Path(CGRect(x: -W / 2, y: scanY - H * 0.06, width: W, height: H * 0.12)),
                    with: .linearGradient(
                        Gradient(colors: [amber.opacity(0), amber.opacity(0.16 * faceA), amber.opacity(0)]),
                        startPoint: CGPoint(x: 0, y: scanY - H * 0.06), endPoint: CGPoint(x: 0, y: scanY + H * 0.06)))

        glow(&face, head, alpha: 0.7 * faceA, width: 1.4)

        // Konturlinien wie ein Drahtgitter
        var contour = Path()
        contour.move(to: CGPoint(x: fx * 0.5, y: -0.49 * H))
        contour.addLine(to: CGPoint(x: fx * 0.8, y: -0.17 * H + fy))
        for side in [-1.0, 1.0] {
            contour.move(to: CGPoint(x: side * 0.44 * W + fx * 0.6, y: -0.12 * H))
            contour.addQuadCurve(to: CGPoint(x: side * 0.17 * W + fx, y: 0.37 * H + fy),
                                 control: CGPoint(x: side * 0.36 * W + fx, y: 0.16 * H))
            contour.move(to: CGPoint(x: side * 0.12 * W + fx * 0.7, y: -0.47 * H))
            contour.addQuadCurve(to: CGPoint(x: side * 0.42 * W + fx * 0.6, y: -0.2 * H),
                                 control: CGPoint(x: side * 0.34 * W + fx * 0.6, y: -0.42 * H))
            contour.move(to: CGPoint(x: side * 0.3 * W + fx, y: 0.05 * H + fy))
            contour.addQuadCurve(to: CGPoint(x: side * 0.1 * W + fx, y: 0.06 * H + fy),
                                 control: CGPoint(x: side * 0.2 * W + fx, y: 0.1 * H + fy))
        }
        glow(&face, contour, alpha: 0.28 * faceA, width: 0.9)

        // Augen: glühende Kerne mit Blick und Blinzeln
        let openness = max(0.06, expr.eyeOpen * (1 - AtlasMotion.blink(t)))
        let gaze = AtlasMotion.gaze(t, state: state)
        let eyeGlow = 0.6 + 0.4 * expr.glow
        for side in [-1.0, 1.0] {
            let ex = side * 0.2 * W + fx, ey = -0.05 * H + fy
            let ew = 0.22 * W, eh = max(0.085 * H * openness, 1.2)
            glow(&face, Path(ellipseIn: CGRect(x: ex - ew / 2, y: ey - eh / 2, width: ew, height: eh)),
                 alpha: 0.7 * faceA, width: 1.2)
            let ix = ex + gaze.x * ew * 0.25, iy = ey + gaze.y * eh * 0.3
            let ir = 0.035 * H * min(1, openness * 1.3)
            face.fill(circle(CGPoint(x: ix, y: iy), ir * 3.2),
                      with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Self.amberCore.opacity(eyeGlow), location: 0),
                            .init(color: amber.opacity(0.75 * eyeGlow), location: 0.3),
                            .init(color: amber.opacity(0), location: 1),
                        ]),
                        center: CGPoint(x: ix, y: iy), startRadius: 0, endRadius: ir * 3.2))
            face.fill(circle(CGPoint(x: ix, y: iy), ir * 0.45),
                      with: .color(Color(red: 1, green: 0.96, blue: 0.88).opacity(eyeGlow)))

            let base = -0.135 * H + fy - expr.browRaise * 0.025 * H
            var brow = Path()
            brow.move(to: CGPoint(x: side * 0.08 * W + fx, y: base - expr.browInner * 0.02 * H))
            brow.addQuadCurve(to: CGPoint(x: side * 0.34 * W + fx, y: base + 0.012 * H),
                              control: CGPoint(x: side * 0.22 * W + fx, y: base - 0.03 * H))
            glow(&face, brow, alpha: 0.6 * faceA, width: 1.4)
        }

        // Nase
        var nose = Path()
        nose.move(to: CGPoint(x: 0.015 * W + fx, y: -0.04 * H + fy))
        nose.addQuadCurve(to: CGPoint(x: 0.035 * W + fx * 1.1, y: 0.13 * H + fy),
                          control: CGPoint(x: 0.045 * W + fx, y: 0.05 * H + fy))
        nose.move(to: CGPoint(x: -0.06 * W + fx * 1.1, y: 0.15 * H + fy))
        nose.addQuadCurve(to: CGPoint(x: 0.06 * W + fx * 1.1, y: 0.15 * H + fy),
                          control: CGPoint(x: fx * 1.1, y: 0.175 * H + fy))
        glow(&face, nose, alpha: 0.4 * faceA, width: 1)

        // Mund – öffnet sich im Takt der gesprochenen Wörter
        let mx = fx * 1.05, my = 0.27 * H + fy
        let half = 0.12 * W * (1 - mouth * 0.15)
        let corner = -expr.smile * 0.018 * H
        let gap = mouth * 0.06 * H
        let left = CGPoint(x: mx - half, y: my + corner), right = CGPoint(x: mx + half, y: my + corner)
        var lips = Path()
        lips.move(to: left)
        lips.addQuadCurve(to: right, control: CGPoint(x: mx, y: my - gap * 0.6 - 0.006 * H))
        lips.addQuadCurve(to: left, control: CGPoint(x: mx, y: my + gap * 1.4 + expr.smile * 0.012 * H))
        if mouth > 0.05 {
            face.fill(lips, with: .color(amber.opacity(0.18 + 0.35 * mouth)))
        }
        glow(&face, lips, alpha: 0.7 * faceA, width: 1.4)
    }

    // MARK: - Hilfen

    /// Leuchtende Linie: breiter, schwacher Schein plus heller Kern.
    private func glow(_ ctx: inout GraphicsContext, _ path: Path, alpha: Double, width: Double) {
        ctx.stroke(path, with: .color(amber.opacity(alpha * 0.18)),
                   style: StrokeStyle(lineWidth: width * 5, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(Self.amberCore.opacity(alpha)),
                   style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func circle(_ center: CGPoint, _ radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: Double(center.x) - radius, y: Double(center.y) - radius,
                               width: radius * 2, height: radius * 2))
    }

    private func point(_ center: CGPoint, _ radius: Double, _ angle: Double) -> CGPoint {
        CGPoint(x: Double(center.x) + cos(angle) * radius, y: Double(center.y) + sin(angle) * radius)
    }
}

#Preview {
    AtlasHologramView(state: .speaking, inputLevel: 0.4, spokenWordCount: 0, spokenWordLength: 5, speechRate: 0.5)
        .frame(width: 380, height: 380)
        .background(.black)
}
