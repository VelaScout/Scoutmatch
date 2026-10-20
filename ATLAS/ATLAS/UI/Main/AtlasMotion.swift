import SwiftUI

/// Gemeinsame Bewegungslogik für alle Darstellungen von ATLAS (Hologramm und Gesicht):
/// Blinzeln, Blickrichtung, Mundbewegung und Kopfform. Alles ist rein rechnerisch aus der
/// Zeit abgeleitet – so braucht die Animation keinen eigenen Zustand und kostet kaum Akku.
enum AtlasMotion {
    /// Deterministischer „Zufall“ aus einer Zahl (0…1).
    static func hash(_ n: Int) -> Double {
        let x = sin(Double(n) * 12.9898 + 78.233) * 43758.5453
        return x - floor(x)
    }

    /// 0 = Augen offen, 1 = geschlossen.
    static func blink(_ t: Double) -> Double {
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
    static func gaze(_ t: Double, state: ConversationEngine.State) -> CGPoint {
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

    /// Geschätzte Dauer eines Wortes aus Buchstabenzahl und Sprechtempo.
    static func wordDuration(length: Int, speechRate: Double) -> Double {
        let perLetter = 0.075 * (1.15 - speechRate * 0.6)
        return min(max(Double(length) * perLetter, 0.12), 0.9)
    }

    /// Mundöffnung 0…1, synchron zu den gesprochenen Wörtern.
    static func mouthOpen(state: ConversationEngine.State, sinceWord: Double,
                          wordDuration: Double, wordLength: Int) -> Double {
        guard state == .speaking else { return 0 }
        guard sinceWord < wordDuration + 0.12 else { return 0.04 }
        let progress = min(sinceWord / wordDuration, 1)
        // Silben: ca. eine Öffnung pro 3 Buchstaben
        let syllables = max(1, Double(wordLength) / 3)
        let flap = abs(sin(progress * .pi * syllables))
        let envelope = sinceWord > wordDuration ? max(0, 1 - (sinceWord - wordDuration) / 0.12) : 1
        return (0.15 + 0.85 * flap) * envelope
    }

    /// Umriss des humanoiden Kopfes, zentriert um (0, 0).
    static func headPath(W: Double, H: Double) -> Path {
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
}
