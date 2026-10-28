import Foundation

enum SpeechTextCleaner {
    static func clean(_ text: String) -> String {
        var result = LanguageSegments.strip(text)
        // Markdown-Links [Text](URL) -> Text
        result = result.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        // Nackte URLs entfernen
        result = result.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        // Markdown-Zeichen entfernen
        result = result.replacingOccurrences(of: #"[*_`#>]+"#, with: "", options: .regularExpression)
        // Aufzählungszeichen am Zeilenanfang
        result = result.replacingOccurrences(of: #"(?m)^\s*[-•]\s+"#, with: "", options: .regularExpression)
        // Piktogramme und Emoji-Sequenzen werden nicht vorgelesen.
        result = String(result.unicodeScalars.filter { scalar in
            let v = scalar.value
            if scalar.properties.isEmojiPresentation { return false }
            if v == 0xFE0F || v == 0x200D || v == 0x20E3 { return false }
            if (0x1F1E6...0x1F1FF).contains(v) { return false }
            return true
        })
        result = result.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Zerlegt eine gestreamte Antwort in sprechbare Sätze.
struct SentenceChunker {
    private var buffer = ""
    private var emittedFirst = false
    /// Mindestlänge des ersten Abschnitts (kurz = ATLAS beginnt schnell zu sprechen).
    private let firstMinimum: Int
    /// Mindestlänge der folgenden Abschnitte (lang = fließender, weniger „abgehackt“).
    private let minimum: Int

    init(firstMinimum: Int = 30, minimum: Int = 120) {
        self.firstMinimum = firstMinimum
        self.minimum = minimum
    }

    /// Fügt neuen Text hinzu und liefert alle vollständigen Sätze.
    mutating func feed(_ text: String) -> [String] {
        buffer += text
        var sentences: [String] = []
        while let end = nextBoundary() {
            let sentence = String(buffer[..<end])
            buffer = String(buffer[end...])
            if !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sentences.append(sentence)
                emittedFirst = true
            }
        }
        return sentences
    }

    /// Liefert den restlichen Text am Ende der Antwort.
    mutating func flush() -> String? {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? nil : rest
    }

    /// Satzende = . ! ? : ; oder Zeilenumbruch, gefolgt von Leerraum.
    /// Der erste Abschnitt darf kurz sein (schneller Start), danach werden mehrere
    /// Sätze zusammengefasst, damit die Stimme fließend und natürlich klingt.
    private func nextBoundary() -> String.Index? {
        let minimumLength = emittedFirst ? minimum : firstMinimum
        var index = buffer.startIndex
        var length = 0
        while index < buffer.endIndex {
            let char = buffer[index]
            let next = buffer.index(after: index)
            length += 1
            if char == "\n", length >= minimumLength, LanguageSegments.isBalanced(buffer[..<next]) { return next }
            if ".!?".contains(char), next < buffer.endIndex, buffer[next].isWhitespace, length >= minimumLength,
               LanguageSegments.isBalanced(buffer[..<next]) {
                return next
            }
            index = next
        }
        return nil
    }
}
