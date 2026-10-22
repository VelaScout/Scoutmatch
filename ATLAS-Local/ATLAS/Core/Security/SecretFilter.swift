import Foundation

/// Erkennt Zugangsdaten (Passwörter, PINs, Schlüssel, Karten- und Kontonummern), damit sie nie im
/// Gedächtnis landen. Gleiche Regeln wie im Backend (atlas/privacy.py), bewusst eher vorsichtig.
enum SecretFilter {
    static let refusal = "Passwörter, PINs, Schlüssel sowie Karten- und Kontonummern speichere ich nie im Gedächtnis. Dafür ist der macOS-Schlüsselbund (App „Passwörter“) da."

    private static let labelled = try! NSRegularExpression(
        pattern: #"\b(passwort|kennwort|password|passcode|pin|tan|puk|geheimzahl|zugangsdaten|login|api[ -]?key|api[ -]?schlüssel|access[ -]?token|token|secret|geheimnis|private[ -]?key|sicherheitscode|cvv|cvc)\b(\s+(für|von|zu|des|der|vom|meines|meiner|for|of)\s+[\w.@-]+)?\s*(ist|lautet|heißt|=|:|is)\s*["„“']?[^\s"„“']{3,}"#,
        options: [.caseInsensitive])
    private static let rawKeys = try! NSRegularExpression(
        pattern: #"\b(sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[abpr]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,})|-----BEGIN [A-Z ]*PRIVATE KEY-----"#)
    private static let iban = try! NSRegularExpression(pattern: #"\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){3,7}(?:\s?[A-Z0-9]{1,3})?\b"#)
    private static let card = try! NSRegularExpression(pattern: #"\b(?:\d[ -]?){13,19}\b"#)

    static func containsSecret(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        if labelled.firstMatch(in: text, range: range) != nil || rawKeys.firstMatch(in: text, range: range) != nil
            || iban.firstMatch(in: text, range: range) != nil {
            return true
        }
        return card.matches(in: text, range: range).contains { match in
            guard let r = Range(match.range, in: text) else { return false }
            return luhn(String(text[r]))
        }
    }

    private static func luhn(_ value: String) -> Bool {
        let digits = value.compactMap { $0.wholeNumberValue }
        guard (13...19).contains(digits.count) else { return false }
        var total = 0
        for (index, digit) in digits.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                total += doubled > 9 ? doubled - 9 : doubled
            } else {
                total += digit
            }
        }
        return total % 10 == 0
    }
}
