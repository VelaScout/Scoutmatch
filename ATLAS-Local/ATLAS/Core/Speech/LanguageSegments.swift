import Foundation

/// Fremdsprachige Stellen in einer Antwort, markiert als `<en>…</en>`, `<fr>…</fr>` usw.
///
/// Apple-Stimmen sprechen nur ihre eigene Sprache sauber – eine deutsche Stimme liest Englisch
/// mit deutschem Akzent. Deshalb spricht A.T.L.A.S. markierte Stellen mit einer Stimme der
/// jeweiligen Sprache. Für die Anzeige und den Verlauf werden die Markierungen entfernt.
enum LanguageSegments {
    struct Segment: Equatable {
        let text: String
        /// Sprache der Stelle, z. B. „en-GB“; `nil` = Hauptsprache.
        let locale: String?
    }

    static let locales: [String: String] = ["en": "en-GB", "fr": "fr-FR", "es": "es-ES", "it": "it-IT"]

    private static let tagPattern = #"<(en|fr|es|it)>(.*?)(</\1>|$)"#

    /// Zerlegt Text in Abschnitte je Sprache. Ein nicht geschlossenes Tag gilt bis zum Ende.
    static func split(_ text: String) -> [Segment] {
        guard let regex = try? NSRegularExpression(pattern: tagPattern, options: [.dotMatchesLineSeparators]) else {
            return [Segment(text: text, locale: nil)]
        }
        var segments: [Segment] = []
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text),
                  let codeRange = Range(match.range(at: 1), in: text),
                  let innerRange = Range(match.range(at: 2), in: text) else { continue }
            append(String(text[last..<whole.lowerBound]), locale: nil, to: &segments)
            append(String(text[innerRange]), locale: locales[String(text[codeRange])], to: &segments)
            last = whole.upperBound
        }
        append(String(text[last...]), locale: nil, to: &segments)
        return segments
    }

    private static func append(_ text: String, locale: String?, to segments: inout [Segment]) {
        let cleaned = strip(text)
        guard cleaned.contains(where: { $0.isLetter || $0.isNumber }) else {
            // Reine Satzzeichen an den vorherigen Abschnitt hängen.
            if let previous = segments.popLast() {
                segments.append(Segment(text: previous.text + cleaned, locale: previous.locale))
            }
            return
        }
        segments.append(Segment(text: cleaned, locale: locale))
    }

    /// Entfernt alle Sprach-Markierungen.
    static func strip(_ text: String) -> String {
        text.replacingOccurrences(of: #"</?(en|fr|es|it)>"#, with: "", options: .regularExpression)
    }

    /// Sind alle Sprach-Markierungen geschlossen? (Ein Satz wird nie mitten in einer Markierung getrennt.)
    static func isBalanced(_ text: Substring) -> Bool {
        var open = 0
        var index = text.startIndex
        while let start = text[index...].firstIndex(of: "<") {
            let rest = text[start...]
            if rest.hasPrefix("</") {
                open = max(0, open - 1)
            } else if locales.keys.contains(where: { rest.hasPrefix("<\($0)>") }) {
                open += 1
            }
            index = text.index(after: start)
        }
        return open == 0
    }
}
