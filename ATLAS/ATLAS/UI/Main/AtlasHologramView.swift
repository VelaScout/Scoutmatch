import CoreText
import SwiftUI

/// Der A.T.L.A.S.-Kern (Standard-Darstellung): ein blauer Energiereaktor.
///
/// - Start (ca. 7 s): Lichtpunkte fliegen mit Leuchtspuren in Wirbeln über den ganzen Bildschirm,
///   schießen zu einem riesigen „A.T.L.A.S.“ zusammen (Blitz, Druckwelle, Beben), ein Scan-Strahl
///   fährt darüber, der Untertitel tippt sich ein – dann zerfällt der Schriftzug spiralförmig und
///   der Kern zündet.
/// - Kern: Plasmakern, 3D-Kugel aus rund 1.200 Lichtstreifen, drei Gyroskop-Ringe, Energieblitze,
///   Splitter-Schale, Lichtstrahlen, schwebender Staub, HUD-Skala und Rahmen mit Telemetrie.
/// - Reaktionen: Zuhören → Oberfläche folgt Ihrer Stimme; Nachdenken → schnellere Drehung, mehr
///   Blitze, Analyse-Strahl; Sprechen → Pulsieren im Wortrhythmus und Schallwellen.
/// - Mit Finger oder Maus drehbar. Pausiert, sobald die App nicht sichtbar ist.
struct AtlasHologramView: View {
    let state: ConversationEngine.State
    let inputLevel: Float
    let spokenWordCount: Int
    let spokenWordLength: Int
    let speechRate: Double
    /// Start-Sequenz abspielen (auf dem Startbildschirm).
    var showsIntro = true
    /// Eckrahmen mit Telemetrie zeichnen (nur bei bildschirmfüllender Darstellung sinnvoll).
    var showsFrame = true

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
                // Über Metal (Grafikchip) zeichnen – deutlich flüssiger bei vielen Lichtstreifen.
                .drawingGroup()
            }
            .task(id: geometry.size) {
                guard showsIntro, intro == nil, !reduceMotion, geometry.size.width > 10 else { return }
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

    private static let deep = Color(red: 0.055, green: 0.157, blue: 0.47)
    private static let blue = Color(red: 0.15, green: 0.44, blue: 1.0)
    private static let iceColor = Color(red: 0.43, green: 0.82, blue: 1.0)
    private static let hot = Color(red: 0.89, green: 0.97, blue: 1.0)
    private static let alert = Color(red: 1.0, green: 0.42, blue: 0.35)

    private var ice: Color { state.isError ? Self.alert : Self.iceColor }

    // MARK: - Schrift

    /// Registriert die mitgelieferte Schrift „Orbitron“ (SIL Open Font License) einmalig.
    private static let fontRegistered: Bool = {
        guard let url = Bundle.main.url(forResource: "Orbitron-Black", withExtension: "ttf") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    static func displayFont(size: Double) -> Font {
        _ = fontRegistered
        // Fehlt die Schrift, nimmt SwiftUI automatisch die Systemschrift.
        return .custom("Orbitron-Black", fixedSize: size)
    }

    // MARK: - Geometrie (einmal berechnet)

    fileprivate struct SpherePoint { let x, y, z, seed, trail, jitter: Double }
    private struct Shard {
        let radius, angle, length, speed, brightness, flicker, phase, skew: Double
        let tangential: Bool
    }
    private struct Swirl { let rx, ry, tilt, speed, span: Double }
    private struct Gyro { let tiltX, tiltZ, speed, radius, gaps, width: Double }
    private struct Dust { let x, y, z: Double }
    private struct Ray { let angle, length, width, speed, phase: Double }
    struct Layout { let side, R, cx, cy, unit: Double }

    fileprivate static func seeded(_ seed: UInt64) -> () -> Double {
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
    fileprivate static let sphere: [SpherePoint] = {
        let random = AtlasHologramView.seeded(5)
        let count = 1200
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
        return (0..<800).map { _ in
            let tangential = random() < 0.7
            return Shard(radius: 1.02 + 0.32 * pow(random(), 1.8),
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

    private static let gyros = [
        Gyro(tiltX: 1.25, tiltZ: 0.2, speed: 0.55, radius: 1.48, gaps: 3, width: 2.2),
        Gyro(tiltX: 0.4, tiltZ: -1.0, speed: -0.38, radius: 1.62, gaps: 5, width: 1.4),
        Gyro(tiltX: -0.9, tiltZ: 0.9, speed: 0.27, radius: 1.76, gaps: 2, width: 3.0),
    ]

    private static let dust: [Dust] = {
        let random = AtlasHologramView.seeded(21)
        return (0..<220).map { _ in Dust(x: random(), y: random(), z: 0.2 + random() * 0.8) }
    }()

    private static let rays: [Ray] = {
        let random = AtlasHologramView.seeded(33)
        return (0..<28).map { _ in
            Ray(angle: random() * 2 * .pi, length: 1.8 + random() * 2.2, width: 0.5 + random() * 1.5,
                speed: (random() - 0.5) * 0.05, phase: random() * 6.28)
        }
    }()

    static func layout(for size: CGSize) -> Layout {
        // Hochformat: die äußeren Ringe dürfen über den Rand laufen, damit der Kern groß wirkt.
        let side = min(Double(size.width) * 1.32, Double(size.height) - 24)
        return Layout(side: side, R: side * 0.22, cx: Double(size.width) / 2, cy: Double(size.height) / 2,
                      unit: side / 400)
    }

    // MARK: - Mathematik

    private static func field(_ x: Double, _ y: Double, _ z: Double, _ t: Double) -> Double {
        let a = sin(3.1 * x + t * 1.3) * sin(2.7 * y - t * 1.1) * sin(2.9 * z + t * 0.9)
        let b = 0.5 * sin(5.3 * x - t * 2.1 + 1.7 * y) * sin(4.7 * z + t * 1.7)
        return a + b
    }

    /// Dreht um die y-Achse (ay), dann um die x-Achse (ax).
    fileprivate static func rotate(_ x: Double, _ y: Double, _ z: Double,
                                   ay: Double, ax: Double) -> (x: Double, y: Double, z: Double) {
        let x1 = x * cos(ay) + z * sin(ay)
        let z1 = -x * sin(ay) + z * cos(ay)
        return (x1, y * cos(ax) - z1 * sin(ax), y * sin(ax) + z1 * cos(ax))
    }

    /// Dreht und projiziert perspektivisch auf den Bildschirm.
    fileprivate static func project(_ x: Double, _ y: Double, _ z: Double, ay: Double, ax: Double,
                                    cx: Double, cy: Double, R: Double) -> (x: Double, y: Double, z: Double) {
        let q = rotate(x, y, z, ay: ay, ax: ax)
        let perspective = 3.2 / (3.2 - q.z)
        return (cx + q.x * R * perspective, cy + q.y * R * perspective, q.z)
    }

    fileprivate static func easeInOut(_ u: Double) -> Double {
        u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
    }

    private static func easeOutBack(_ u: Double) -> Double {
        let c = 1.7
        return 1 + (c + 1) * pow(u - 1, 3) + c * pow(u - 1, 2)
    }

    private func energy(t: Double, envelope: Double) -> Double {
        switch state {
        case .listening, .confirming: return 0.35 + smoothedLevel * 0.65
        case .speaking: return 0.3 + envelope * 0.3
        case .thinking: return 0.5 + 0.15 * sin(t * 4)
        case .standby: return 0.2 + 0.05 * sin(t * 2)
        case .idle, .error: return 0.18 + 0.05 * sin(t * 1.1)
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
        let sinceWord = date.timeIntervalSince(lastWordDate)
        // Über ein kurzes Zeitfenster gemittelt: ruhiges Atmen statt hektischem Zucken pro Silbe.
        var envelope = 0.0
        for lag in [0.0, 0.06, 0.12, 0.18] {
            envelope += AtlasMotion.speechEnvelope(isSpeaking: state == .speaking, sinceWord: max(0, sinceWord - lag),
                                                   wordDuration: lastWordDuration, wordLength: spokenWordLength) / 4
        }
        let en = energy(t: t, envelope: envelope)
        let pulse = state == .speaking ? envelope : 0
        let spin = (state == .thinking ? 2.4 : 1.0) * motion
        let base = Self.layout(for: size)
        let ay = t * 0.16 * spin + dragYaw
        let ax = 0.38 + sin(t * 0.11) * 0.12 * motion + dragPitch

        var ctx = context
        ctx.blendMode = .plusLighter

        // Start-Sequenz
        var effects = Intro.Effects(reveal: 1, shake: 0, flash: 0)
        if let intro {
            effects = intro.draw(&ctx, date: date, t: t, ay: ay, ax: ax, layout: base)
        }
        if effects.shake > 0 {
            ctx.translateBy(x: sin(t * 97) * effects.shake * 0.5, y: cos(t * 83) * effects.shake * 0.5)
        }

        if effects.reveal > 0 {
            let reveal = effects.reveal
            let grow = (0.6 + 0.4 * Self.easeOutBack(reveal)) * (1 + 0.02 * pulse)
            let L = Layout(side: base.side, R: base.R * grow, cx: base.cx, cy: base.cy, unit: base.unit)

            var core = ctx
            core.opacity = min(1, reveal * 1.4)
            drawDust(&core, size: size, t: t)
            drawRays(&core, L: L, t: t, en: en)
            drawSpaceGlow(&core, L: L, en: en, pulse: pulse)

            drawGyros(&core, L: L, t: t, en: en, spin: spin, ay: ay, ax: ax, backOnly: false)
            drawPlasma(&core, L: L, t: t, en: en, pulse: pulse)
            drawSphere(&core, L: L, t: t, en: en, spin: spin, ay: ay, ax: ax)
            drawSwirls(&core, L: L, t: t, en: en, spin: spin)
            drawBolts(&core, L: L, t: t)
            drawShell(&core, L: L, t: t, en: en, spin: spin, pulse: pulse)
            if state == .speaking {
                drawSoundWaves(&core, L: L, sinceWord: sinceWord)
            }
            drawHUD(&core, L: L, t: t, en: en, spin: spin)

            if showsFrame {
                var frame = ctx
                frame.opacity = reveal
                drawFrame(&frame, size: size, t: t, en: en, unit: base.unit)
            }
        }

        if effects.flash > 0 {
            var flash = context
            flash.blendMode = .plusLighter
            flash.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.hot.opacity(effects.flash)))
        }
    }

    /// Schwebender Staub im ganzen Raum (Tiefe durch Parallaxe).
    private func drawDust(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = Double(size.width), h = Double(size.height)
        guard w > 1, h > 1 else { return }
        var path = Path()
        for d in Self.dust {
            var x = (d.x * w + t * 6 * d.z + dragYaw * 40 * d.z).truncatingRemainder(dividingBy: w)
            var y = (d.y * h - t * 3 * d.z).truncatingRemainder(dividingBy: h)
            if x < 0 { x += w }
            if y < 0 { y += h }
            let s = 0.4 + d.z * 1.1
            path.addEllipse(in: CGRect(x: x - s, y: y - s, width: s * 2, height: s * 2))
        }
        ctx.fill(path, with: .color(Self.iceColor.opacity(0.18)))
    }

    /// Feine Lichtstrahlen aus dem Zentrum.
    private func drawRays(_ ctx: inout GraphicsContext, L: Layout, t: Double, en: Double) {
        let center = CGPoint(x: L.cx, y: L.cy)
        for ray in Self.rays {
            let a = ray.angle + t * ray.speed
            let alpha = (0.025 + 0.04 * en) * (0.6 + 0.4 * sin(t * 1.3 + ray.phase))
            let end = CGPoint(x: L.cx + cos(a) * L.R * ray.length, y: L.cy + sin(a) * L.R * ray.length)
            var path = Path()
            path.move(to: center)
            path.addLine(to: end)
            ctx.stroke(path, with: .linearGradient(
                Gradient(colors: [ice.opacity(alpha * 2), ice.opacity(0)]), startPoint: center, endPoint: end),
                       lineWidth: ray.width * L.unit * 2)
        }
    }

    private func drawSpaceGlow(_ ctx: inout GraphicsContext, L: Layout, en: Double, pulse: Double) {
        let radius = L.R * 2.6
        ctx.fill(circle(L.cx, L.cy, radius), with: .radialGradient(
            Gradient(stops: [
                .init(color: Self.blue.opacity(0.25 + 0.2 * en + 0.06 * pulse), location: 0),
                .init(color: Self.deep.opacity(0.14 + 0.06 * en), location: 0.4),
                .init(color: Self.deep.opacity(0), location: 1),
            ]), center: CGPoint(x: L.cx, y: L.cy), startRadius: 0, endRadius: radius))
    }

    /// Gleißender Plasmakern in der Mitte.
    private func drawPlasma(_ ctx: inout GraphicsContext, L: Layout, t: Double, en: Double, pulse: Double) {
        let radius = L.R * (0.5 + 0.08 * sin(t * 2.3) + 0.15 * en + 0.04 * pulse)
        ctx.fill(circle(L.cx, L.cy, radius), with: .radialGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity(0.95), location: 0),
                .init(color: Self.hot.opacity(0.8), location: 0.15),
                .init(color: ice.opacity(0.35 + 0.2 * en), location: 0.45),
                .init(color: Self.blue.opacity(0), location: 1),
            ]), center: CGPoint(x: L.cx, y: L.cy), startRadius: 0, endRadius: radius))
    }

    /// Drei Gyroskop-Ringe in 3D mit Lücken; die vordere Hälfte leuchtet heller.
    private func drawGyros(_ ctx: inout GraphicsContext, L: Layout, t: Double, en: Double, spin: Double,
                           ay: Double, ax: Double, backOnly: Bool) {
        let steps = 180
        for gyro in Self.gyros {
            var front = Path(), back = Path()
            let spinAngle = t * gyro.speed * spin
            let cz = cos(gyro.tiltZ + t * 0.05), sz = sin(gyro.tiltZ + t * 0.05)
            func point(_ a: Double) -> (x: Double, y: Double, z: Double) {
                let p = Self.rotate(cos(a) * gyro.radius, 0, sin(a) * gyro.radius, ay: 0, ax: gyro.tiltX)
                let px = p.x * cz - p.y * sz, py = p.x * sz + p.y * cz
                return Self.project(px, py, p.z, ay: ay * 0.35, ax: ax, cx: L.cx, cy: L.cy, R: L.R)
            }
            for i in 0..<steps {
                let u = Double(i) / Double(steps)
                if sin(u * 2 * .pi * gyro.gaps) > 0.72 { continue }
                let p0 = point(u * 2 * .pi + spinAngle)
                let p1 = point((Double(i + 1) / Double(steps)) * 2 * .pi + spinAngle)
                if p0.z > 0 {
                    front.move(to: CGPoint(x: p0.x, y: p0.y)); front.addLine(to: CGPoint(x: p1.x, y: p1.y))
                } else {
                    back.move(to: CGPoint(x: p0.x, y: p0.y)); back.addLine(to: CGPoint(x: p1.x, y: p1.y))
                }
            }
            let width = gyro.width * L.unit
            ctx.stroke(back, with: .color(Self.deep.opacity(0.35)), style: StrokeStyle(lineWidth: width * 3, lineCap: .round))
            ctx.stroke(back, with: .color(Self.blue.opacity(0.35)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            if backOnly { continue }
            ctx.stroke(front, with: .color(Self.blue.opacity(0.07 + 0.05 * en)),
                       style: StrokeStyle(lineWidth: width * 6, lineCap: .round))
            ctx.stroke(front, with: .color(Self.blue.opacity(0.3 + 0.2 * en)),
                       style: StrokeStyle(lineWidth: width * 2.2, lineCap: .round))
            ctx.stroke(front, with: .color(ice.opacity(0.65)), style: StrokeStyle(lineWidth: width * 0.5, lineCap: .round))
        }
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
                let point = CGPoint(x: L.cx + x * cos(rotation) - y * sin(rotation),
                                    y: L.cy + x * sin(rotation) + y * cos(rotation))
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            ctx.stroke(path, with: .color(Self.hot.opacity(0.5 + 0.35 * en)),
                       style: StrokeStyle(lineWidth: 1.4 * L.unit, lineCap: .round))
        }
    }

    /// Zuckende Energieblitze zwischen Kern und Schale. Rein aus der Zeit berechnet:
    /// jedes Zeitfenster bekommt einen Blitz mit eigenem Zufallswert.
    private func drawBolts(_ ctx: inout GraphicsContext, L: Layout, t: Double) {
        let period: Double
        switch state {
        case .thinking: period = 0.06
        case .speaking: period = 0.09
        default: period = 0.28
        }
        let slot = Int(floor(t / period))
        for s in (slot - 8)...slot {
            let random = Self.seeded(UInt64(bitPattern: Int64(s)) &* 0x2545_F491_4F6C_DD1D &+ 77)
            let born = (Double(s) + random()) * period
            let life = 0.18 + random() * 0.2
            let age = t - born
            guard age >= 0, age < life else { continue }
            let k = age / life
            let a1 = random() * 2 * .pi
            let a2 = a1 + (random() - 0.5) * 2.4
            let r1 = 0.9 + random() * 0.5, r2 = 0.9 + random() * 0.6
            let x1 = L.cx + cos(a1) * L.R * r1, y1 = L.cy + sin(a1) * L.R * r1
            let x2 = L.cx + cos(a2) * L.R * r2, y2 = L.cy + sin(a2) * L.R * r2
            let jitter = Self.seeded(UInt64(bitPattern: Int64(s * 131 + Int(t * 30))))
            var path = Path()
            path.move(to: CGPoint(x: x1, y: y1))
            let segments = 9
            for i in 1..<segments {
                let u = Double(i) / Double(segments)
                let offset = (jitter() - 0.5) * L.R * 0.22 * sin(u * .pi)
                path.addLine(to: CGPoint(x: x1 + (x2 - x1) * u - (y2 - y1) / L.R * offset,
                                         y: y1 + (y2 - y1) * u + (x2 - x1) / L.R * offset))
            }
            path.addLine(to: CGPoint(x: x2, y: y2))
            ctx.stroke(path, with: .color(ice.opacity(0.35 * (1 - k))),
                       style: StrokeStyle(lineWidth: 4 * L.unit, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(Color.white.opacity(0.9 * (1 - k))),
                       style: StrokeStyle(lineWidth: L.unit, lineCap: .round, lineJoin: .round))
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
            let r = shard.radius * L.R * (1 + 0.012 * pulse + sin(t * 2 + shard.phase) * 0.01 * en)
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
            ctx.stroke(circle(L.cx, L.cy, L.R * (1.4 + k * 0.9)),
                       with: .color(ice.opacity(0.25 * (1 - k) * (1 - k))), lineWidth: (1.4 - k * 0.6) * L.unit)
        }
    }

    /// Skala, Segmentbögen und Analyse-Strahl rund um den Kern.
    private func drawHUD(_ ctx: inout GraphicsContext, L: Layout, t: Double, en: Double, spin: Double) {
        let scaleR = L.R * 2.0
        var minor = Path(), major = Path()
        let rotation = -t * 0.04 * spin
        for i in 0..<144 {
            let a = rotation + Double(i) / 144 * 2 * .pi
            let isMajor = i % 12 == 0
            let inner = scaleR - (isMajor ? L.R * 0.08 : L.R * 0.03)
            let from = CGPoint(x: L.cx + cos(a) * inner, y: L.cy + sin(a) * inner)
            let to = CGPoint(x: L.cx + cos(a) * scaleR, y: L.cy + sin(a) * scaleR)
            if isMajor {
                major.move(to: from); major.addLine(to: to)
            } else {
                minor.move(to: from); minor.addLine(to: to)
            }
        }
        ctx.stroke(minor, with: .color(ice.opacity(0.22)), lineWidth: 0.7 * L.unit)
        ctx.stroke(major, with: .color(ice.opacity(0.55)), lineWidth: 1.2 * L.unit)

        for i in 0..<4 {
            let start = Double(i) * .pi / 2 + 0.3 - t * 0.18 * spin
            let span = 0.55 + 0.35 * sin(t * 0.7 + Double(i))
            var arc = Path()
            arc.addArc(center: CGPoint(x: L.cx, y: L.cy), radius: scaleR + 9 * L.unit,
                       startAngle: .radians(start), endAngle: .radians(start + span), clockwise: false)
            ctx.stroke(arc, with: .color(ice.opacity(0.5 + 0.3 * en)),
                       style: StrokeStyle(lineWidth: 2.4 * L.unit, lineCap: .round))
        }

        if state == .thinking {
            var band = circle(L.cx, L.cy, scaleR)
            band.addPath(circle(L.cx, L.cy, L.R * 1.4))
            ctx.fill(band,
                     with: .conicGradient(
                        Gradient(stops: [
                            .init(color: ice.opacity(0), location: 0),
                            .init(color: ice.opacity(0.22), location: 0.14),
                            .init(color: ice.opacity(0), location: 0.145),
                            .init(color: ice.opacity(0), location: 1),
                        ]),
                        center: CGPoint(x: L.cx, y: L.cy), angle: .radians(t * 3.2 - 0.9)),
                     style: FillStyle(eoFill: true))
        }
    }

    /// Eckrahmen am Bildschirmrand mit Telemetrie.
    private func drawFrame(_ ctx: inout GraphicsContext, size: CGSize, t: Double, en: Double, unit: Double) {
        let w = Double(size.width), h = Double(size.height)
        let m = 14.0, length = min(w, h) * 0.08
        let corners: [(x: Double, y: Double, sx: Double, sy: Double)] = [
            (m, m, 1, 1), (w - m, m, -1, 1), (m, h - m, 1, -1), (w - m, h - m, -1, -1),
        ]
        var brackets = Path()
        for c in corners {
            brackets.move(to: CGPoint(x: c.x, y: c.y + c.sy * length))
            brackets.addLine(to: CGPoint(x: c.x, y: c.y))
            brackets.addLine(to: CGPoint(x: c.x + c.sx * length, y: c.y))
        }
        ctx.stroke(brackets, with: .color(ice.opacity(0.45)), lineWidth: 1.2)

        var text = ctx
        text.blendMode = .normal
        let fontSize = max(9, min(12, 9 * unit))
        let color = ice.opacity(0.75)
        func label(_ string: String, _ x: Double, _ y: Double, _ anchor: UnitPoint) {
            text.draw(Text(string)
                        .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(color),
                      at: CGPoint(x: x, y: y), anchor: anchor)
        }
        label("A.T.L.A.S.", m + 10, m + 14, .leading)
        label(String(format: "SYNC %.1f%%", 99.2 + sin(t * 0.7) * 0.5), w - m - 10, m + 14, .trailing)
        label("STATUS · \(statusLabel)", m + 10, h - m - 14, .leading)
        label(String(format: "%.1f HZ", 120 + en * 260 + sin(t * 3) * 6), w - m - 10, h - m - 14, .trailing)
    }

    private func circle(_ x: Double, _ y: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
}

// MARK: - Start-Sequenz „A.T.L.A.S.“

extension AtlasHologramView {
    /// Lichtpunkte fliegen lange in Wirbeln über den Bildschirm, rasten zu einem riesigen
    /// „A.T.L.A.S.“ ein und stürzen dann spiralförmig in den Kern. Alles wird aus der
    /// verstrichenen Zeit berechnet – es gibt keinen Zustand pro Bild.
    struct Intro {
        struct Flyer {
            let theta0, omega, radius, phase, phase2, size, delay, tx, ty: Double
            let sphereIndex: Int
            var sx = 0.0, sy = 0.0
        }

        struct Effects {
            var reveal: Double
            var shake: Double
            var flash: Double
        }

        static let fly = 3.0, form = 1.1, hold = 1.9, dissolve = 1.2
        static var holdStart: Double { fly + form }
        static var dissolveStart: Double { fly + form + hold }
        static var end: Double { fly + form + hold + dissolve }
        static let subtitle = "ADVANCED THINKING · LEARNING & ASSISTANCE SYSTEM"

        private(set) var flyers: [Flyer]
        let fontSize: Double
        let wordTop, wordBottom: Double
        let cx, cy, halfW, halfH, width: Double
        let start = Date.now

        @MainActor
        static func make(size: CGSize, layout L: Layout) -> Intro {
            let width = Double(size.width), height = Double(size.height)
            var fontSize = min(height * 0.22, 260)
            if let measured = textPoints(fontSize: fontSize, step: 1000)?.width, measured > width * 0.92 {
                fontSize *= width * 0.92 / measured
            }
            let step = max(2, (fontSize / 34).rounded())
            let sample = textPoints(fontSize: fontSize, step: step)
            let targets = sample?.points ?? []
            let textHeight = sample?.height ?? fontSize * 1.3

            let random = AtlasHologramView.seeded(17)
            let count = min(3200, max(targets.count, 1800))
            var list: [Flyer] = []
            list.reserveCapacity(count)
            for i in 0..<count {
                let target: (Double, Double)
                if targets.isEmpty {
                    target = (0, 0)
                } else if targets.count > count {
                    target = targets[i * targets.count / count]
                } else {
                    target = targets[i % targets.count]
                }
                let radius = 1.25 * sqrt(random())
                let direction = random() < 0.82 ? 1.0 : -1.0
                list.append(Flyer(
                    theta0: random() * 2 * .pi,
                    omega: direction * (0.6 + 0.9 * random()) / (0.3 + radius),
                    radius: radius, phase: random() * 2 * .pi, phase2: random() * 2 * .pi,
                    size: 0.6 + random() * 1.3, delay: random() * 0.25,
                    tx: L.cx + target.0 + (random() - 0.5) * step * 0.5,
                    ty: L.cy + target.1 + (random() - 0.5) * step * 0.5,
                    sphereIndex: (i * 7) % AtlasHologramView.sphere.count))
            }
            var intro = Intro(flyers: list, fontSize: fontSize,
                              wordTop: L.cy - textHeight / 2, wordBottom: L.cy + textHeight / 2,
                              cx: width / 2, cy: height / 2, halfW: width * 0.62, halfH: height * 0.62, width: width)
            for i in intro.flyers.indices {
                let p = intro.flyPosition(intro.flyers[i], fly)
                intro.flyers[i].sx = p.x
                intro.flyers[i].sy = p.y
            }
            return intro
        }

        /// Rastert den Schriftzug und liefert Punktpositionen relativ zur Mitte sowie die Textmaße.
        @MainActor
        private static func textPoints(fontSize: Double, step: Double)
            -> (points: [(Double, Double)], width: Double, height: Double)? {
            let padding = 4.0
            let renderer = ImageRenderer(content:
                Text("A.T.L.A.S.")
                    .font(AtlasHologramView.displayFont(size: fontSize))
                    .foregroundStyle(.white)
                    .padding(padding))
            renderer.scale = 1
            guard let image = renderer.cgImage else { return nil }
            let w = image.width, h = image.height
            let textWidth = Double(w) - padding * 2, textHeight = Double(h) - padding * 2
            if step >= 1000 { return ([], textWidth, textHeight) }
            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
                guard let bitmap = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                             bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                bitmap.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            var points: [(Double, Double)] = []
            let s = max(1, Int(step))
            for y in stride(from: 0, to: h, by: s) {
                for x in stride(from: 0, to: w, by: s) where pixels[(y * w + x) * 4 + 3] > 120 {
                    points.append((Double(x) - Double(w) / 2, Double(y) - Double(h) / 2))
                }
            }
            return (points, textWidth, textHeight)
        }

        /// Flugbahn: weite, schwingende Wirbel über den ganzen Bildschirm, anfangs beschleunigend.
        func flyPosition(_ f: Flyer, _ e: Double) -> (x: Double, y: Double) {
            let tau = e < 0.6 ? 0.5 * e + e * e / 2.4 : e - 0.15
            let theta = f.theta0 + f.omega * tau + 0.45 * sin(0.9 * tau + f.phase)
            let r = f.radius * (1 + 0.14 * sin(1.6 * tau + f.phase2))
            let x0 = cx + cos(theta) * r * halfW
            let y0 = cy + sin(theta) * r * halfH
            let x = x0 + sin(y0 * 0.011 + tau * 1.4 + f.phase) * 0.06 * halfW
            let y = y0 + cos(x0 * 0.009 - tau * 1.1 + f.phase2) * 0.05 * halfH
            return (x, y)
        }

        /// Zusammenschießen zum Schriftzug mit leichter Krümmung.
        private func formPosition(_ f: Flyer, _ u: Double) -> (x: Double, y: Double) {
            let k = AtlasHologramView.easeInOut(min(1, max(0, u)))
            let dx = f.tx - f.sx, dy = f.ty - f.sy
            let curl = sin(min(1, max(0, u)) * .pi) * 0.25
            return (f.sx + dx * k - dy * curl, f.sy + dy * k + dx * curl)
        }

        /// Zeichnet die Sequenz und liefert Einblendung des Kerns, Beben und Blitz.
        func draw(_ ctx: inout GraphicsContext, date: Date, t: Double, ay: Double, ax: Double,
                  layout L: Layout) -> Effects {
            let e = date.timeIntervalSince(start)
            guard e < Self.end + 0.3 else { return Effects(reveal: 1, shake: 0, flash: 0) }

            drawWordmark(&ctx, e: e)

            let bucketCount = 6
            var buckets = [Path](repeating: Path(), count: bucketCount)
            var widths = [Double](repeating: 0, count: bucketCount)
            let formU = min(1, max(0, (e - Self.fly) / Self.form))
            let fadeIn = min(1, e / 0.5)
            for f in flyers {
                var a: Double, size = f.size
                var head: (x: Double, y: Double), tail: (x: Double, y: Double)?
                if e < Self.fly {
                    // Phase 1: lange, schwungvolle Flugbahnen mit Leuchtspuren
                    head = flyPosition(f, e)
                    tail = flyPosition(f, max(0, e - 0.16))
                    a = (0.35 + 0.4 * pow(sin(t * 3 + f.phase), 2)) * fadeIn
                } else if e < Self.holdStart {
                    // Phase 2: zusammenschießen zum Schriftzug
                    let u = min(1, max(0, (formU - f.delay * 0.6) / (1 - f.delay * 0.6)))
                    head = formPosition(f, u)
                    tail = formPosition(f, u - 0.06)
                    a = 0.5 + 0.5 * u
                    size = f.size * (1 + 0.5 * u)
                } else if e < Self.dissolveStart {
                    // Phase 3: Schriftzug steht und flimmert leicht
                    head = (f.tx + sin(t * 13 + f.phase) * 0.5, f.ty)
                    a = 0.85 + 0.15 * sin(t * 7 + f.tx * 0.03)
                    size = f.size * 1.5
                } else {
                    // Phase 4: Zerfall – Spirale in den Kern
                    let u = min(1, (e - Self.dissolveStart) / Self.dissolve - f.delay * 0.4)
                    let k = AtlasHologramView.easeInOut(max(0, u))
                    let point = AtlasHologramView.sphere[f.sphereIndex]
                    let q = AtlasHologramView.project(point.x, point.y, point.z, ay: ay, ax: ax,
                                                      cx: L.cx, cy: L.cy, R: L.R)
                    let rx = f.tx - L.cx, ry = f.ty - L.cy
                    let r0 = hypot(rx, ry), th0 = atan2(ry, rx)
                    let r1 = hypot(q.x - L.cx, q.y - L.cy), th1 = atan2(q.y - L.cy, q.x - L.cx) + 3 * .pi
                    let rr = r0 + (r1 - r0) * k, th = th0 + (th1 - th0) * k
                    head = (L.cx + cos(th) * rr, L.cy + sin(th) * rr)
                    a = 1 - 0.6 * k
                    size = f.size * (1.5 - 0.7 * k)
                }
                let index = min(bucketCount - 1, max(0, Int(a * Double(bucketCount))))
                let from: (x: Double, y: Double) = tail ?? (x: head.x - 0.01, y: head.y)
                buckets[index].move(to: CGPoint(x: from.x, y: from.y))
                buckets[index].addLine(to: CGPoint(x: head.x + 0.01, y: head.y))
                widths[index] = max(widths[index], size * 2)
            }
            for (index, path) in buckets.enumerated() where !path.isEmpty {
                let a = Double(index + 1) / Double(bucketCount)
                let color = index >= bucketCount - 2 ? AtlasHologramView.hot
                    : (index >= bucketCount - 4 ? AtlasHologramView.iceColor : AtlasHologramView.blue)
                ctx.stroke(path, with: .color(AtlasHologramView.blue.opacity(a * 0.3)),
                           style: StrokeStyle(lineWidth: widths[index] * 2.6, lineCap: .round, lineJoin: .round))
                ctx.stroke(path, with: .color(color.opacity(a)),
                           style: StrokeStyle(lineWidth: widths[index], lineCap: .round, lineJoin: .round))
            }

            var effects = Effects(reveal: 0, shake: 0, flash: 0)

            // Einschlag beim Einrasten des Schriftzugs
            let lock = e - Self.holdStart
            if lock >= 0, lock < 1.2 {
                effects.flash = exp(-lock * 6) * 0.55
                effects.shake = exp(-lock * 9) * 7
                let k = lock / 1.2
                let radius = 30 + k * hypot(width, halfH / 0.62) * 0.7
                ctx.stroke(Path(ellipseIn: CGRect(x: L.cx - radius, y: L.cy - radius, width: radius * 2, height: radius * 2)),
                           with: .color(AtlasHologramView.iceColor.opacity(0.6 * (1 - k))), lineWidth: 3 * (1 - k) + 0.5)
            }

            // Scan-Strahl und Untertitel
            if e >= Self.holdStart, e < Self.dissolveStart + 0.4 {
                drawScanAndSubtitle(&ctx, e: e, t: t, L: L)
            }

            // Zündung des Kerns
            if e >= Self.dissolveStart {
                let k = min(1, (e - Self.dissolveStart) / Self.dissolve)
                effects.reveal = max(0, min(1, (k - 0.55) / 0.45))
                let ignition = e - (Self.dissolveStart + Self.dissolve * 0.6)
                if ignition > 0 {
                    effects.flash = max(effects.flash, exp(-ignition * 5) * 0.7)
                    effects.shake = max(effects.shake, exp(-ignition * 10) * 5)
                }
            }
            return effects
        }

        /// Massiver, metallisch leuchtender Schriftzug unter den Partikeln – rastet mit
        /// kurzer Farbverschiebung ein.
        private func drawWordmark(_ ctx: inout GraphicsContext, e: Double) {
            guard e >= Self.holdStart - 0.15, e < Self.dissolveStart + 0.5 else { return }
            let lockIn = min(1, (e - Self.holdStart + 0.15) / 0.3)
            let out = e < Self.dissolveStart ? 1 : max(0, 1 - (e - Self.dissolveStart) / 0.5)
            let alpha = lockIn * out
            let jitter = e < Self.holdStart + 0.5 ? exp(-(e - Self.holdStart) * 6) * 6 : 0
            let word = ctx.resolve(
                Text("A.T.L.A.S.")
                    .font(AtlasHologramView.displayFont(size: fontSize))
                    .foregroundStyle(LinearGradient(stops: [
                        .init(color: .white, location: 0.2),
                        .init(color: AtlasHologramView.iceColor, location: 0.47),
                        .init(color: AtlasHologramView.blue, location: 0.55),
                        .init(color: AtlasHologramView.iceColor, location: 0.8),
                    ], startPoint: .top, endPoint: .bottom)))
            let y = (wordTop + wordBottom) / 2

            var glow = ctx
            glow.addFilter(.shadow(color: AtlasHologramView.blue.opacity(0.9), radius: fontSize * 0.35))
            glow.opacity = 0.55 * alpha
            glow.draw(word, at: CGPoint(x: cx - jitter - 2, y: y), anchor: .center)

            var shifted = ctx
            shifted.opacity = 0.35 * alpha
            shifted.draw(word, at: CGPoint(x: cx + jitter + 2, y: y), anchor: .center)

            var solid = ctx
            solid.opacity = 0.8 * alpha
            solid.draw(word, at: CGPoint(x: cx, y: y), anchor: .center)
        }

        private func drawScanAndSubtitle(_ ctx: inout GraphicsContext, e: Double, t: Double, L: Layout) {
            let k = (e - Self.holdStart) / Self.hold
            let fade = e < Self.dissolveStart ? 1 : max(0, 1 - (e - Self.dissolveStart) / 0.4)
            let sx = -0.1 * width + k * 1.2 * width
            let beam = CGRect(x: sx - 60, y: wordTop, width: 120, height: wordBottom - wordTop)
            ctx.fill(Path(beam), with: .linearGradient(
                Gradient(stops: [
                    .init(color: AtlasHologramView.iceColor.opacity(0), location: 0),
                    .init(color: AtlasHologramView.hot.opacity(0.35 * fade), location: 0.5),
                    .init(color: AtlasHologramView.iceColor.opacity(0), location: 1),
                ]),
                startPoint: CGPoint(x: beam.minX, y: beam.midY), endPoint: CGPoint(x: beam.maxX, y: beam.midY)))

            let characters = Array(Self.subtitle)
            let shownCount = Int(min(1, k * 1.6) * Double(characters.count))
            var shown = String(characters.prefix(shownCount))
            if shownCount < characters.count, Int(t * 4) % 2 == 1 { shown += "▍" }
            // Pro Zeichen etwa 0,6 Schriftgröße plus 0,35 Sperrung – passt auf 90 % der Breite.
            let subSize = min(15, width / 42, width * 0.9 / (0.95 * Double(characters.count)))
            var text = ctx
            text.blendMode = .normal
            text.opacity = 0.85 * fade
            text.draw(Text(shown)
                        .font(.system(size: subSize, weight: .medium, design: .monospaced))
                        .tracking(subSize * 0.35)
                        .foregroundColor(AtlasHologramView.iceColor),
                      at: CGPoint(x: cx, y: wordBottom + 6), anchor: .top)
        }
    }
}

#Preview {
    AtlasHologramView(state: .thinking, inputLevel: 0.4, spokenWordCount: 0, spokenWordLength: 5, speechRate: 0.5)
        .frame(width: 400, height: 700)
        .background(.black)
}
