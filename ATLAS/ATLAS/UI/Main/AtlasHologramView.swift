import SwiftUI

/// ATLAS als Hologramm (Standard-Darstellung): eine glühende, bernsteinfarbene Kugel aus
/// Lichtsplittern und Umlaufbahnen – inspiriert von J.A.R.V.I.S. – mit einem Gesicht aus
/// rund 1.500 Lichtpunkten im Zentrum. Das Gesicht blinzelt, hält Blickkontakt und bewegt beim Sprechen den
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

    /// Das holografische Gesicht als Punktwolke: Fläche mit Tiefe, Umriss- und Konturpunkte,
    /// bewegliche Brauen, Nase, Mund und Lidränder aus Punkten sowie glühende Augenkerne.
    private func drawFace(_ ctx: inout GraphicsContext, center: CGPoint, radius R: Double, energy en: Double,
                          t: Double, motion: Double, expr: AtlasFaceView.Expression, mouth: Double) {
        let H = R, W = H * 0.7
        let yaw = (sin(t * 0.37) * 0.035 + sin(t * 0.91) * 0.012) * motion
        let pitch = sin(t * 0.29) * 0.02 * motion
        let fx = yaw * W * 0.55, fy = pitch * H * 0.5
        let faceA = min(1, (0.8 + 0.3 * en) * (0.9 + 0.1 * sin(t * 23) * sin(t * 7.1)))

        var face = ctx
        let offsetX: Double = Double(center.x) + yaw * W * 0.35
        let offsetY: Double = Double(center.y) + pitch * H * 0.3 + H * 0.02
        face.translateBy(x: offsetX, y: offsetY)
        face.rotate(by: .radians((expr.headTilt + sin(t * 0.23) * 0.012) * motion))

        // Dunkler Grund, damit das Gesicht vor der Kugel steht
        var shade = face
        shade.blendMode = .normal
        shade.fill(AtlasMotion.headPath(W: W, H: H),
                   with: .color(Color(red: 0.03, green: 0.015, blue: 0.004).opacity(0.62)))

        let unit = R / 190
        let scanY = ((t * 0.32).truncatingRemainder(dividingBy: 1.4) - 0.2) * H - H / 2
        func scanBoost(_ y: Double) -> Double {
            let d = (y - scanY) / (H * 0.035)
            return 1 + 1.6 * exp(-d * d)
        }

        var dots = DotBuckets()

        // Gesichtsfläche: vorne heller, Ränder dunkler; vordere Punkte verschieben sich stärker (3D)
        for d in Self.faceDots {
            let par = 0.3 + 0.9 * d.z
            let x = d.u * W + fx * par
            let y = d.v * H + fy * par + sin(t * 1.3 + d.phase) * 0.0025 * H
            let a = d.brightness * (0.72 + 0.28 * sin(t * d.flicker + d.phase)) * faceA * scanBoost(y)
            dots.add(x: x, y: y, alpha: a, size: unit * (0.55 + 0.55 * d.z))
        }
        for d in Self.lineDots {
            let par = 0.3 + 0.9 * d.z
            let x = d.u * W + fx * par, y = d.v * H + fy * par
            let a = d.brightness * (0.8 + 0.2 * sin(t * 3 + d.phase)) * faceA * scanBoost(y)
            dots.add(x: x, y: y, alpha: a, size: unit * 0.95)
        }

        // Bewegliche Teile, jedes Bild neu abgetastet
        let openness = max(0.06, expr.eyeOpen * (1 - AtlasMotion.blink(t)))
        let gaze = AtlasMotion.gaze(t, state: state)
        let eyeGlow = 0.6 + 0.4 * expr.glow
        var eyeCores: [(CGPoint, Double)] = []
        for side in [-1.0, 1.0] {
            let ex = side * 0.2 * W + fx, ey = -0.05 * H + fy
            let ew = 0.22 * W, eh = 0.085 * H * openness
            for i in 0..<26 {
                let angle = Double(i) / 26 * 2 * .pi
                dots.add(x: ex + cos(angle) * ew / 2, y: ey + sin(angle) * eh / 2, alpha: 0.75 * faceA, size: unit * 0.9)
            }
            let base = -0.135 * H + fy - expr.browRaise * 0.025 * H
            dots.addQuad(from: (side * 0.08 * W + fx, base - expr.browInner * 0.02 * H),
                         control: (side * 0.22 * W + fx, base - 0.03 * H),
                         to: (side * 0.34 * W + fx, base + 0.012 * H),
                         count: 16, alpha: 0.85 * faceA, size: unit * 1.1)
            let ir = 0.035 * H * min(1, openness * 1.3)
            eyeCores.append((CGPoint(x: ex + Double(gaze.x) * ew * 0.25, y: ey + Double(gaze.y) * eh * 0.3), ir))
        }
        dots.addQuad(from: (0.015 * W + fx, -0.04 * H + fy), control: (0.045 * W + fx, 0.05 * H + fy),
                     to: (0.035 * W + fx * 1.1, 0.13 * H + fy), count: 12, alpha: 0.55 * faceA, size: unit * 0.9)
        dots.addQuad(from: (-0.06 * W + fx * 1.1, 0.15 * H + fy), control: (fx * 1.1, 0.175 * H + fy),
                     to: (0.06 * W + fx * 1.1, 0.15 * H + fy), count: 9, alpha: 0.6 * faceA, size: unit * 0.9)

        // Mund – öffnet sich im Takt der gesprochenen Wörter
        let mx = fx * 1.05, my = 0.27 * H + fy
        let half = 0.12 * W * (1 - mouth * 0.15)
        let corner = -expr.smile * 0.018 * H
        let gap = mouth * 0.06 * H
        let mouthA = (0.85 + 0.15 * mouth) * faceA
        dots.addQuad(from: (mx - half, my + corner), control: (mx, my - gap * 0.6 - 0.006 * H),
                     to: (mx + half, my + corner), count: 18, alpha: mouthA, size: unit * 1.05)
        dots.addQuad(from: (mx - half, my + corner), control: (mx, my + gap * 1.4 + expr.smile * 0.012 * H),
                     to: (mx + half, my + corner), count: 18, alpha: mouthA * 0.8, size: unit)
        if mouth > 0.05 {
            var inner = Path()
            inner.move(to: CGPoint(x: mx - half, y: my + corner))
            inner.addQuadCurve(to: CGPoint(x: mx + half, y: my + corner), control: CGPoint(x: mx, y: my - gap * 0.6))
            inner.addQuadCurve(to: CGPoint(x: mx - half, y: my + corner), control: CGPoint(x: mx, y: my + gap * 1.4))
            face.fill(inner, with: .color(amber.opacity(0.12 + 0.3 * mouth)))
        }

        // Glühende Augenkerne
        for (core, ir) in eyeCores {
            face.fill(circle(core, ir * 3.2),
                      with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Self.amberCore.opacity(eyeGlow), location: 0),
                            .init(color: amber.opacity(0.75 * eyeGlow), location: 0.3),
                            .init(color: amber.opacity(0), location: 1),
                        ]),
                        center: core, startRadius: 0, endRadius: ir * 3.2))
            face.fill(circle(core, ir * 0.45), with: .color(Color(red: 1, green: 0.96, blue: 0.88).opacity(eyeGlow)))
        }

        // Punkte zeichnen: weicher Schein + heller Kern, nach Helligkeit gebündelt
        for (index, path) in dots.paths.enumerated() where !path.isEmpty {
            let a = Double(index + 1) / Double(DotBuckets.count)
            face.stroke(path, with: .color(amber.opacity(a * 0.22)), lineWidth: unit * 2.2)
            face.fill(path, with: .color((index >= DotBuckets.count - 3 ? Self.amberCore : amber).opacity(a)))
        }
    }

    /// Sammelt Lichtpunkte in wenigen Pfaden – einer pro Helligkeitsstufe.
    private struct DotBuckets {
        static let count = 7
        var paths = [Path](repeating: Path(), count: count)

        mutating func add(x: Double, y: Double, alpha: Double, size: Double) {
            guard alpha >= 0.035 else { return }
            let index = min(Self.count - 1, Int(min(alpha, 0.999) * Double(Self.count)))
            paths[index].addEllipse(in: CGRect(x: x - size, y: y - size, width: size * 2, height: size * 2))
        }

        mutating func addQuad(from a: (Double, Double), control q: (Double, Double), to c: (Double, Double),
                              count n: Int, alpha: Double, size: Double) {
            for i in 0...n {
                let s = Double(i) / Double(n), k = 1 - s
                add(x: k * k * a.0 + 2 * k * s * q.0 + s * s * c.0,
                    y: k * k * a.1 + 2 * k * s * q.1 + s * s * c.1,
                    alpha: alpha, size: size)
            }
        }
    }

    // MARK: - Punktwolke des Gesichts (einmal berechnet)

    /// Ein Lichtpunkt im Gesicht. u relativ zur Kopfbreite, v relativ zur Kopfhöhe, z = Tiefe (1 = vorne).
    private struct FaceDot {
        let u: Double, v: Double, z: Double
        let brightness: Double
        let flicker: Double
        let phase: Double
    }

    private static func seededRandom(_ seed: UInt64) -> () -> Double {
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

    /// Hexagonales Punktraster innerhalb des Kopfes mit plastischer Helligkeit.
    private static let faceDots: [FaceDot] = {
        let random = AtlasHologramView.seededRandom(11)
        let head = AtlasMotion.headPath(W: 700, H: 1000)
        var list: [FaceDot] = []
        let step = 0.021
        let du = step / 0.7
        var row = 0
        var v = -0.49
        while v <= 0.49 {
            var u = -0.5 + Double(row % 2) * du / 2
            while u <= 0.5 {
                let ju = u + (random() - 0.5) * du * 0.35
                let jv = v + (random() - 0.5) * step * 0.35
                u += du
                guard head.contains(CGPoint(x: ju * 700, y: jv * 1000)) else { continue }
                // Augenöffnungen frei lassen – dort sitzen die glühenden Kerne
                let inEye = [-1.0, 1.0].contains { side in
                    pow((ju - side * 0.2) / 0.15, 2) + pow((jv + 0.05) / 0.065, 2) < 1
                }
                if inEye { continue }
                let nu = ju / 0.5, nv = (jv + 0.02) / 0.5
                let z = sqrt(max(0, 1 - 0.8 * nu * nu - 0.35 * nv * nv))
                var b = 0.1 + 0.5 * pow(z, 1.6)
                b += 0.18 * exp(-(pow((abs(ju) - 0.3) / 0.09, 2) + pow((jv - 0.03) / 0.07, 2)))  // Wangenknochen
                b += 0.12 * exp(-(pow(ju / 0.22, 2) + pow((jv + 0.3) / 0.1, 2)))                 // Stirn
                b += 0.1 * exp(-(pow(ju / 0.05, 2) + pow((jv - 0.06) / 0.1, 2)))                 // Nasenrücken
                for side in [-1.0, 1.0] {
                    let d = hypot((ju - side * 0.2) / 0.2, (jv + 0.05) / 0.12)
                    if d < 1 { b *= 0.45 + 0.55 * d }                                           // Augenhöhlen
                }
                if random() < 0.06 { b *= 1.8 }                                                  // einzelne Funken
                list.append(FaceDot(u: ju, v: jv, z: z, brightness: min(b, 0.95),
                                    flicker: 0.8 + 2.5 * random(), phase: random() * 6.28))
            }
            v += step
            row += 1
        }
        return list
    }()

    /// Umriss und Gesichtskonturen als dichte Punktreihen.
    private static let lineDots: [FaceDot] = {
        let random = AtlasHologramView.seededRandom(23)
        var list: [FaceDot] = []
        // Umriss: dieselben Kurven wie AtlasMotion.headPath, in Einheiten von W und H
        let start = (0.0, -0.5)
        let segments: [((Double, Double), (Double, Double), (Double, Double))] = [
            ((0.3, -0.5), (0.5, -0.38), (0.5, -0.16)),
            ((0.5, 0.04), (0.44, 0.17), (0.31, 0.31)),
            ((0.24, 0.44), (0.13, 0.5), (0, 0.5)),
            ((-0.13, 0.5), (-0.24, 0.44), (-0.31, 0.31)),
            ((-0.44, 0.17), (-0.5, 0.04), (-0.5, -0.16)),
            ((-0.5, -0.38), (-0.3, -0.5), (0, -0.5)),
        ]
        var previous = start
        for (c1, c2, end) in segments {
            for i in 0..<30 {
                let s = Double(i) / 30, k = 1 - s
                let u = k * k * k * previous.0 + 3 * k * k * s * c1.0 + 3 * k * s * s * c2.0 + s * s * s * end.0
                let v = k * k * k * previous.1 + 3 * k * k * s * c1.1 + 3 * k * s * s * c2.1 + s * s * s * end.1
                list.append(FaceDot(u: u, v: v, z: 0.1, brightness: 0.8, flicker: 3, phase: random() * 6.28))
            }
            previous = end
        }
        func quad(_ a: (Double, Double), _ q: (Double, Double), _ c: (Double, Double),
                  _ n: Int, _ brightness: Double, _ z: Double) {
            for i in 0...n {
                let s = Double(i) / Double(n), k = 1 - s
                list.append(FaceDot(u: k * k * a.0 + 2 * k * s * q.0 + s * s * c.0,
                                    v: k * k * a.1 + 2 * k * s * q.1 + s * s * c.1,
                                    z: z, brightness: brightness, flicker: 3, phase: random() * 6.28))
            }
        }
        quad((0, -0.49), (0, -0.33), (0, -0.17), 12, 0.35, 0.8)
        for side in [-1.0, 1.0] {
            quad((side * 0.44, -0.12), (side * 0.36, 0.16), (side * 0.17, 0.37), 24, 0.42, 0.4)
            quad((side * 0.12, -0.47), (side * 0.34, -0.42), (side * 0.42, -0.2), 16, 0.32, 0.35)
            quad((side * 0.3, 0.05), (side * 0.2, 0.1), (side * 0.1, 0.06), 9, 0.4, 0.7)
            quad((side * 0.33, -0.05), (side * 0.36, 0.1), (side * 0.3, 0.22), 10, 0.25, 0.5)
        }
        return list
    }()

    // MARK: - Hilfen

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
