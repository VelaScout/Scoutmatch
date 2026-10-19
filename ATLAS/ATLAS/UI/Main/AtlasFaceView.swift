import SwiftUI

/// Das animierte Gesicht von ATLAS (Phase 2).
///
/// Ein humanoides, weiß-silbernes, leicht transparentes Gesicht mit eisblau
/// leuchtenden Augen. Es blinzelt, hält Blickkontakt, bewegt den Kopf leicht,
/// bewegt beim Sprechen den Mund (synchron zu den gesprochenen Wörtern) und
/// zeigt je nach Zustand einen anderen Ausdruck.
///
/// Gezeichnet wird mit SwiftUI `Canvas` – das läuft auf der GPU, braucht keine
/// 3D-Modelle und schont den Akku. Die Animation pausiert automatisch, wenn die
/// App nicht sichtbar ist.
struct AtlasFaceView: View {
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
    @State private var previousExpression = Expression.idle
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
            // Grobe Schätzung der Wortdauer aus Buchstabenzahl und Sprechtempo.
            let perLetter = 0.075 * (1.15 - speechRate * 0.6)
            lastWordDuration = min(max(Double(spokenWordLength) * perLetter, 0.12), 0.9)
        }
        .onChange(of: state) { oldValue, _ in
            previousExpression = Expression.forState(oldValue)
            stateChangeDate = .now
        }
        .accessibilityElement()
        .accessibilityLabel("ATLAS, \(state.label)")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Ausdruck

    /// Mimik-Parameter für einen Zustand.
    struct Expression: Equatable {
        var eyeOpen: Double        // 0 = geschlossen, 1 = weit offen
        var browRaise: Double      // Augenbrauen gesamt
        var browInner: Double      // innere Brauen (Sorge/Konzentration)
        var smile: Double          // -1 traurig … 1 lächelnd
        var glow: Double           // Leuchtkraft der Augen
        var headTilt: Double       // seitliche Neigung (Aufmerksamkeit)

        static let idle = Expression(eyeOpen: 0.85, browRaise: 0, browInner: 0, smile: 0.25, glow: 0.65, headTilt: 0)
        static let listening = Expression(eyeOpen: 1.0, browRaise: 0.6, browInner: 0.1, smile: 0.15, glow: 0.95, headTilt: 0.05)
        static let thinking = Expression(eyeOpen: 0.7, browRaise: -0.1, browInner: -0.6, smile: 0, glow: 0.8, headTilt: -0.03)
        static let speaking = Expression(eyeOpen: 0.9, browRaise: 0.25, browInner: 0, smile: 0.3, glow: 0.9, headTilt: 0)
        static let concerned = Expression(eyeOpen: 0.85, browRaise: 0.2, browInner: 0.8, smile: -0.35, glow: 0.6, headTilt: 0.02)

        static func forState(_ state: ConversationEngine.State) -> Expression {
            switch state {
            case .idle, .standby: return .idle
            case .listening, .confirming: return .listening
            case .thinking: return .thinking
            case .speaking: return .speaking
            case .error: return .concerned
            }
        }

        static func mix(_ a: Expression, _ b: Expression, _ t: Double) -> Expression {
            func l(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
            return Expression(eyeOpen: l(a.eyeOpen, b.eyeOpen), browRaise: l(a.browRaise, b.browRaise),
                              browInner: l(a.browInner, b.browInner), smile: l(a.smile, b.smile),
                              glow: l(a.glow, b.glow), headTilt: l(a.headTilt, b.headTilt))
        }
    }

    private var tint: Color {
        if case .error = state { return Color(red: 1.0, green: 0.75, blue: 0.4) }
        return Color(red: 0.55, green: 0.86, blue: 1.0)
    }

    // MARK: - Zufall ohne Zustand (deterministisch aus der Zeit)

    private func hash(_ n: Int) -> Double {
        let x = sin(Double(n) * 12.9898 + 78.233) * 43758.5453
        return x - floor(x)
    }

    /// 0 = Augen offen, 1 = geschlossen.
    private func blinkAmount(_ t: Double) -> Double {
        let slot = 4.2
        let k = Int(floor(t / slot))
        let start = Double(k) * slot + hash(k) * 2.8
        let duration = 0.16
        var amount = 0.0
        if t >= start, t <= start + duration {
            amount = sin(.pi * (t - start) / duration)
        }
        // Gelegentlich ein Doppelblinzeln
        if hash(k + 991) > 0.75 {
            let second = start + 0.3
            if t >= second, t <= second + duration {
                amount = max(amount, sin(.pi * (t - second) / duration))
            }
        }
        return amount
    }

    /// Blickrichtung (-1…1). Hält Blickkontakt und macht kleine natürliche Blicksprünge.
    private func gaze(_ t: Double) -> CGPoint {
        let slot = 1.9
        let k = Int(floor(t / slot))
        func target(_ i: Int) -> CGPoint {
            switch state {
            case .listening, .confirming:
                return CGPoint(x: (hash(i) - 0.5) * 0.12, y: (hash(i + 7) - 0.5) * 0.08)
            case .thinking:
                // Nachdenklich nach oben zur Seite blicken
                return CGPoint(x: -0.55 + (hash(i) - 0.5) * 0.3, y: -0.45 + (hash(i + 7) - 0.5) * 0.15)
            case .speaking:
                return CGPoint(x: (hash(i) - 0.5) * 0.3, y: (hash(i + 7) - 0.5) * 0.15)
            case .idle, .standby, .error:
                // Meist Blickkontakt, manchmal kurz zur Seite
                return hash(i + 3) > 0.7
                    ? CGPoint(x: (hash(i) - 0.5) * 0.9, y: (hash(i + 7) - 0.5) * 0.4)
                    : CGPoint(x: (hash(i) - 0.5) * 0.1, y: (hash(i + 7) - 0.5) * 0.08)
            }
        }
        let progress = min((t - Double(k) * slot) / 0.12, 1) // schneller Blicksprung
        let eased = progress * progress * (3 - 2 * progress)
        let a = target(k - 1), b = target(k)
        return CGPoint(x: a.x + (b.x - a.x) * eased, y: a.y + (b.y - a.y) * eased)
    }

    /// Mundöffnung 0…1, synchron zu den gesprochenen Wörtern.
    private func mouthOpen(_ date: Date, _ t: Double) -> Double {
        guard state == .speaking else { return 0 }
        let sinceWord = date.timeIntervalSince(lastWordDate)
        guard sinceWord < lastWordDuration + 0.12 else { return 0.04 }
        let progress = min(sinceWord / lastWordDuration, 1)
        // Silben: ca. eine Öffnung pro 3 Buchstaben
        let syllables = max(1, Double(spokenWordLength) / 3)
        let flap = abs(sin(progress * .pi * syllables))
        let envelope = sinceWord > lastWordDuration ? max(0, 1 - (sinceWord - lastWordDuration) / 0.12) : 1
        return (0.15 + 0.85 * flap) * envelope
    }

    // MARK: - Zeichnen

    private func draw(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000)
        let motion = reduceMotion ? 0.2 : 1.0

        // Ausdruck weich überblenden
        let blend = min(date.timeIntervalSince(stateChangeDate) / 0.45, 1)
        let expr = Expression.mix(previousExpression, Expression.forState(state), blend * blend * (3 - 2 * blend))

        let height = min(Double(size.height) * 0.92, Double(size.width) * 1.3)
        let width = height * 0.7
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // Kopfbewegung: Drehen (yaw), Nicken (pitch), Neigen (roll)
        let listeningNod = state == .listening ? smoothedLevel * 0.02 : 0
        let yaw = (sin(t * 0.37) * 0.035 + sin(t * 0.91) * 0.012) * motion
        let pitch = (sin(t * 0.29) * 0.02 + listeningNod) * motion
        let roll = (expr.headTilt + sin(t * 0.23) * 0.012) * motion
        let breathe = 1 + sin(t * 1.3) * 0.004 * motion

        // Lichtschein hinter dem Kopf
        let energy: Double
        switch state {
        case .listening, .confirming: energy = 0.3 + smoothedLevel * 0.7
        case .speaking: energy = 0.35 + mouthOpen(date, t) * 0.4
        case .thinking: energy = 0.35 + sin(t * 3.5) * 0.1
        case .standby: energy = 0.18 + sin(t * 2) * 0.05
        case .idle, .error: energy = 0.15
        }
        let haloR = height * (0.55 + 0.08 * energy)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - haloR, y: center.y - haloR, width: haloR * 2, height: haloR * 2)),
            with: .radialGradient(Gradient(colors: [tint.opacity(0.22 + 0.25 * energy), tint.opacity(0)]),
                                  center: center, startRadius: height * 0.2, endRadius: haloR))

        var head = context
        head.translateBy(x: center.x + yaw * width * 0.35, y: center.y + pitch * height * 0.3)
        head.rotate(by: .radians(roll))
        head.scaleBy(x: breathe, y: breathe)

        let W = width, H = height
        // Gesichtsmerkmale verschieben sich stärker als der Umriss → räumlicher Eindruck.
        let fx = yaw * W * 0.55
        let fy = pitch * H * 0.5

        drawHead(&head, W: W, H: H, fx: fx, t: t)
        drawSeams(&head, W: W, H: H, fx: fx, fy: fy)

        let blink = blinkAmount(t)
        let openness = max(0.04, expr.eyeOpen * (1 - blink))
        let g = gaze(t)
        for side in [-1.0, 1.0] {
            drawEye(&head, side: side, W: W, H: H, fx: fx, fy: fy, openness: openness, gaze: g,
                    glow: expr.glow * (0.85 + 0.15 * energy), t: t)
            drawBrow(&head, side: side, W: W, H: H, fx: fx, fy: fy, expr: expr)
        }
        drawNose(&head, W: W, H: H, fx: fx, fy: fy)
        drawMouth(&head, W: W, H: H, fx: fx, fy: fy, open: mouthOpen(date, t), smile: expr.smile)
    }

    private func headPath(W: Double, H: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -0.5 * H))
        p.addCurve(to: CGPoint(x: 0.5 * W, y: -0.16 * H),
                   control1: CGPoint(x: 0.3 * W, y: -0.5 * H), control2: CGPoint(x: 0.5 * W, y: -0.38 * H))
        p.addCurve(to: CGPoint(x: 0.31 * W, y: 0.31 * H),
                   control1: CGPoint(x: 0.5 * W, y: 0.04 * H), control2: CGPoint(x: 0.44 * W, y: 0.17 * H))
        p.addCurve(to: CGPoint(x: 0, y: 0.5 * H),
                   control1: CGPoint(x: 0.24 * W, y: 0.44 * H), control2: CGPoint(x: 0.13 * W, y: 0.5 * H))
        p.addCurve(to: CGPoint(x: -0.31 * W, y: 0.31 * H),
                   control1: CGPoint(x: -0.13 * W, y: 0.5 * H), control2: CGPoint(x: -0.24 * W, y: 0.44 * H))
        p.addCurve(to: CGPoint(x: -0.5 * W, y: -0.16 * H),
                   control1: CGPoint(x: -0.44 * W, y: 0.17 * H), control2: CGPoint(x: -0.5 * W, y: 0.04 * H))
        p.addCurve(to: CGPoint(x: 0, y: -0.5 * H),
                   control1: CGPoint(x: -0.5 * W, y: -0.38 * H), control2: CGPoint(x: -0.3 * W, y: -0.5 * H))
        p.closeSubpath()
        return p
    }

    private func drawHead(_ ctx: inout GraphicsContext, W: Double, H: Double, fx: Double, t: Double) {
        let path = headPath(W: W, H: H)
        // Weiß-silberne, leicht transparente Oberfläche
        ctx.fill(path, with: .linearGradient(
            Gradient(colors: [Color(white: 0.97).opacity(0.92), Color(white: 0.78).opacity(0.85),
                              Color(red: 0.55, green: 0.62, blue: 0.7).opacity(0.75)]),
            startPoint: CGPoint(x: -0.4 * W + fx, y: -0.5 * H), endPoint: CGPoint(x: 0.35 * W, y: 0.5 * H)))
        // Glanzlicht, das der Kopfdrehung folgt
        ctx.fill(path, with: .radialGradient(
            Gradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)]),
            center: CGPoint(x: -0.12 * W + fx * 0.6, y: -0.3 * H), startRadius: 0, endRadius: 0.45 * W))
        // Kühler Schatten an den Wangen
        ctx.fill(path, with: .radialGradient(
            Gradient(colors: [Color.clear, Color(red: 0.2, green: 0.32, blue: 0.45).opacity(0.35)]),
            center: CGPoint(x: fx * 0.4, y: -0.05 * H), startRadius: 0.25 * W, endRadius: 0.62 * W))
        // Leuchtende Kante
        ctx.stroke(path, with: .color(tint.opacity(0.45)), lineWidth: 1.4)
    }

    /// Feine Nahtlinien – die künstliche Herkunft bleibt sichtbar.
    private func drawSeams(_ ctx: inout GraphicsContext, W: Double, H: Double, fx: Double, fy: Double) {
        let seam = Color(red: 0.35, green: 0.45, blue: 0.55).opacity(0.35)
        var forehead = Path()
        forehead.move(to: CGPoint(x: fx * 0.5, y: -0.49 * H))
        forehead.addLine(to: CGPoint(x: fx * 0.8, y: -0.17 * H + fy))
        ctx.stroke(forehead, with: .color(seam), lineWidth: 1)

        for side in [-1.0, 1.0] {
            var cheek = Path()
            cheek.move(to: CGPoint(x: side * 0.44 * W + fx * 0.6, y: -0.12 * H))
            cheek.addQuadCurve(to: CGPoint(x: side * 0.17 * W + fx, y: 0.37 * H + fy),
                               control: CGPoint(x: side * 0.36 * W + fx, y: 0.16 * H))
            ctx.stroke(cheek, with: .color(seam), lineWidth: 1)

            var temple = Path()
            temple.move(to: CGPoint(x: side * 0.12 * W + fx * 0.7, y: -0.47 * H))
            temple.addQuadCurve(to: CGPoint(x: side * 0.42 * W + fx * 0.6, y: -0.2 * H),
                                control: CGPoint(x: side * 0.34 * W + fx * 0.6, y: -0.42 * H))
            ctx.stroke(temple, with: .color(seam.opacity(0.7)), lineWidth: 0.8)
        }
    }

    private func drawEye(_ ctx: inout GraphicsContext, side: Double, W: Double, H: Double, fx: Double, fy: Double,
                         openness: Double, gaze: CGPoint, glow: Double, t: Double) {
        let cx = side * 0.2 * W + fx
        let cy = -0.05 * H + fy
        let ew = 0.24 * W, eh = 0.1 * H

        // Augenhöhle (Schatten)
        let socket = CGRect(x: cx - ew * 0.62, y: cy - eh * 0.85, width: ew * 1.24, height: eh * 1.7)
        ctx.fill(Path(ellipseIn: socket), with: .radialGradient(
            Gradient(colors: [Color(red: 0.25, green: 0.33, blue: 0.42).opacity(0.55), Color.clear]),
            center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: ew * 0.65))

        // Lid (Hautfarbe) und geöffneter Bereich
        let lidRect = CGRect(x: cx - ew / 2, y: cy - eh / 2, width: ew, height: eh)
        ctx.fill(Path(ellipseIn: lidRect), with: .color(Color(white: 0.8).opacity(0.9)))

        let openH = eh * openness
        let openRect = CGRect(x: cx - ew / 2, y: cy - eh / 2 + (eh - openH) * 0.65, width: ew, height: openH)
        let openPath = Path(ellipseIn: openRect)
        ctx.fill(openPath, with: .color(Color(red: 0.03, green: 0.06, blue: 0.1)))

        // Iris mit Leuchten, innerhalb des geöffneten Auges
        var eye = ctx
        eye.clip(to: openPath)
        let ir = eh * 0.46
        let ix = cx + gaze.x * ew * 0.22
        let iy = cy + gaze.y * eh * 0.25
        eye.drawLayer { layer in
            layer.addFilter(.blur(radius: ir * 0.7))
            layer.fill(Path(ellipseIn: CGRect(x: ix - ir * 1.6, y: iy - ir * 1.6, width: ir * 3.2, height: ir * 3.2)),
                       with: .color(tint.opacity(0.55 * glow)))
        }
        eye.fill(Path(ellipseIn: CGRect(x: ix - ir, y: iy - ir, width: ir * 2, height: ir * 2)),
                 with: .radialGradient(Gradient(colors: [Color.white, tint.opacity(0.95), tint.opacity(0.35)]),
                                       center: CGPoint(x: ix, y: iy), startRadius: 0, endRadius: ir))
        // Feine Iris-Ringstruktur
        eye.stroke(Path(ellipseIn: CGRect(x: ix - ir * 0.62, y: iy - ir * 0.62, width: ir * 1.24, height: ir * 1.24)),
                   with: .color(Color.white.opacity(0.35 * glow)), lineWidth: 0.8)
        // Pupille
        let pr = ir * (0.32 + 0.04 * sin(t * 0.8))
        eye.fill(Path(ellipseIn: CGRect(x: ix - pr, y: iy - pr, width: pr * 2, height: pr * 2)),
                 with: .color(Color(red: 0.05, green: 0.2, blue: 0.32).opacity(0.85)))
        // Lichtreflex
        eye.fill(Path(ellipseIn: CGRect(x: ix - ir * 0.45, y: iy - ir * 0.55, width: ir * 0.32, height: ir * 0.32)),
                 with: .color(.white.opacity(0.85)))

        // Oberlid-Linie
        var lid = Path()
        lid.move(to: CGPoint(x: openRect.minX, y: openRect.midY))
        lid.addQuadCurve(to: CGPoint(x: openRect.maxX, y: openRect.midY),
                         control: CGPoint(x: openRect.midX, y: openRect.minY - openH * 0.45))
        ctx.stroke(lid, with: .color(Color(red: 0.2, green: 0.28, blue: 0.36).opacity(0.7)), lineWidth: 1.4)
    }

    private func drawBrow(_ ctx: inout GraphicsContext, side: Double, W: Double, H: Double, fx: Double, fy: Double,
                          expr: Expression) {
        let base = -0.135 * H + fy - expr.browRaise * 0.025 * H
        let inner = CGPoint(x: side * 0.08 * W + fx, y: base - expr.browInner * 0.02 * H)
        let outer = CGPoint(x: side * 0.34 * W + fx, y: base + 0.012 * H)
        var brow = Path()
        brow.move(to: inner)
        brow.addQuadCurve(to: outer, control: CGPoint(x: side * 0.22 * W + fx, y: base - 0.03 * H))
        ctx.stroke(brow, with: .color(Color(red: 0.32, green: 0.4, blue: 0.5).opacity(0.75)),
                   style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
    }

    private func drawNose(_ ctx: inout GraphicsContext, W: Double, H: Double, fx: Double, fy: Double) {
        let shade = Color(red: 0.32, green: 0.4, blue: 0.5).opacity(0.45)
        var bridge = Path()
        bridge.move(to: CGPoint(x: 0.015 * W + fx, y: -0.04 * H + fy))
        bridge.addQuadCurve(to: CGPoint(x: 0.035 * W + fx * 1.1, y: 0.13 * H + fy),
                            control: CGPoint(x: 0.045 * W + fx, y: 0.05 * H + fy))
        ctx.stroke(bridge, with: .color(shade), lineWidth: 1.2)

        var base = Path()
        base.move(to: CGPoint(x: -0.06 * W + fx * 1.1, y: 0.15 * H + fy))
        base.addQuadCurve(to: CGPoint(x: 0.06 * W + fx * 1.1, y: 0.15 * H + fy),
                          control: CGPoint(x: fx * 1.1, y: 0.175 * H + fy))
        ctx.stroke(base, with: .color(shade), lineWidth: 1.2)
    }

    private func drawMouth(_ ctx: inout GraphicsContext, W: Double, H: Double, fx: Double, fy: Double,
                           open: Double, smile: Double) {
        let cx = fx * 1.05
        let cy = 0.27 * H + fy
        let half = 0.12 * W * (1 - open * 0.15)
        let corner = -smile * 0.018 * H
        let gap = open * 0.055 * H

        let left = CGPoint(x: cx - half, y: cy + corner)
        let right = CGPoint(x: cx + half, y: cy + corner)

        var upper = Path()
        upper.move(to: left)
        upper.addQuadCurve(to: right, control: CGPoint(x: cx, y: cy - gap * 0.6 - 0.006 * H))

        var lower = Path()
        lower.move(to: left)
        lower.addQuadCurve(to: right, control: CGPoint(x: cx, y: cy + gap * 1.4 + smile * 0.012 * H))

        if open > 0.05 {
            var inside = upper
            inside.addQuadCurve(to: left, control: CGPoint(x: cx, y: cy + gap * 1.4 + smile * 0.012 * H))
            ctx.fill(inside, with: .linearGradient(
                Gradient(colors: [Color(red: 0.03, green: 0.06, blue: 0.1), tint.opacity(0.35 * open)]),
                startPoint: CGPoint(x: cx, y: cy - gap), endPoint: CGPoint(x: cx, y: cy + gap * 1.4)))
        }
        let lip = Color(red: 0.3, green: 0.38, blue: 0.48).opacity(0.85)
        ctx.stroke(upper, with: .color(lip), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        ctx.stroke(lower, with: .color(lip.opacity(0.6)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }
}

#Preview {
    AtlasFaceView(state: .listening, inputLevel: 0.4, spokenWordCount: 0, spokenWordLength: 0, speechRate: 0.5)
        .frame(width: 360, height: 480)
        .background(.black)
}
