import Foundation

/// Gemeinsame Bewegungslogik der ATLAS-Darstellungen: Sprechrhythmus aus den Wort-Ereignissen
/// der Sprachausgabe. Rein rechnerisch aus der Zeit abgeleitet – kein eigener Zustand nötig.
enum AtlasMotion {
    /// Geschätzte Dauer eines Wortes aus Buchstabenzahl und Sprechtempo.
    static func wordDuration(length: Int, speechRate: Double) -> Double {
        let perLetter = 0.075 * (1.15 - speechRate * 0.6)
        return min(max(Double(length) * perLetter, 0.12), 0.9)
    }

    /// Lautstärke-Hüllkurve des Sprechens 0…1, synchron zu den gesprochenen Wörtern
    /// (etwa eine Silbe pro drei Buchstaben).
    static func speechEnvelope(isSpeaking: Bool, sinceWord: Double, wordDuration: Double, wordLength: Int) -> Double {
        guard isSpeaking else { return 0 }
        guard sinceWord < wordDuration + 0.12 else { return 0.04 }
        let progress = min(sinceWord / wordDuration, 1)
        let syllables = max(1, Double(wordLength) / 3)
        let flap = abs(sin(progress * .pi * syllables))
        let fade = sinceWord > wordDuration ? max(0, 1 - (sinceWord - wordDuration) / 0.12) : 1
        return (0.15 + 0.85 * flap) * fade
    }
}
