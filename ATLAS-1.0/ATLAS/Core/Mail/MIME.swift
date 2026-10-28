import Foundation

/// Liest E-Mails im Rohformat (RFC 5322 / MIME): Kopfzeilen, kodierte Betreffs,
/// mehrteilige Nachrichten, Base64 und Quoted-Printable, HTML-Text.
enum MIME {
    /// Trennt Kopf und Inhalt. Gearbeitet wird byte-genau über ISO-Latin-1.
    static func split(_ raw: String) -> (header: String, body: String) {
        if let range = raw.range(of: "\r\n\r\n") {
            return (String(raw[..<range.lowerBound]), String(raw[range.upperBound...]))
        }
        if let range = raw.range(of: "\n\n") {
            return (String(raw[..<range.lowerBound]), String(raw[range.upperBound...]))
        }
        return (raw, "")
    }

    /// Kopfzeilen als Wörterbuch (Schlüssel kleingeschrieben, Folgezeilen zusammengefügt).
    static func headers(_ header: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentKey: String?
        for line in header.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = line.first, first == " " || first == "\t", let key = currentKey {
                result[key, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if result[key] == nil { result[key] = value }
                currentKey = key
            }
        }
        return result
    }

    /// Wandelt Latin-1-Rohtext in echten Text des angegebenen Zeichensatzes.
    static func decodeCharset(_ latin1: String, charset: String?) -> String {
        let bytes = Data(latin1.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) })
        return decodeBytes(bytes, charset: charset)
    }

    static func decodeBytes(_ data: Data, charset: String?) -> String {
        let name = (charset ?? "utf-8").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        let encoding: String.Encoding
        switch name {
        case "iso-8859-1", "latin1", "iso8859-1": encoding = .isoLatin1
        case "windows-1252", "cp1252": encoding = .windowsCP1252
        case "us-ascii", "ascii": encoding = .ascii
        case "iso-8859-15": encoding = .isoLatin1
        default: encoding = .utf8
        }
        return String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
    }

    /// Kodierte Wörter in Kopfzeilen, z. B. „=?UTF-8?B?…?=“ oder „=?iso-8859-1?Q?…?=“.
    static func decodeHeader(_ value: String) -> String {
        let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        var result = ""
        var last = value.startIndex
        var previousWasEncoded = false
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
            guard let whole = Range(match.range, in: value),
                  let charsetRange = Range(match.range(at: 1), in: value),
                  let kindRange = Range(match.range(at: 2), in: value),
                  let textRange = Range(match.range(at: 3), in: value) else { continue }
            let between = String(value[last..<whole.lowerBound])
            // Leerraum zwischen zwei kodierten Wörtern entfällt (RFC 2047).
            if !(previousWasEncoded && between.trimmingCharacters(in: .whitespaces).isEmpty) {
                result += between
            }
            let charset = String(value[charsetRange])
            let text = String(value[textRange])
            let data: Data
            if value[kindRange].uppercased() == "B" {
                data = Data(base64Encoded: padded(text)) ?? Data()
            } else {
                data = quotedPrintableBytes(text.replacingOccurrences(of: "_", with: " "))
            }
            result += decodeBytes(data, charset: charset)
            last = whole.upperBound
            previousWasEncoded = true
        }
        result += value[last...]
        return result
    }

    /// Lesbarer Text einer kompletten Nachricht (bevorzugt text/plain, sonst HTML ohne Tags).
    static func bodyText(raw: String) -> String {
        let (header, body) = split(raw)
        return text(headers: headers(header), body: body) ?? ""
    }

    private static func text(headers: [String: String], body: String) -> String? {
        let contentType = headers["content-type"] ?? "text/plain"
        let type = contentType.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? "text/plain"
        let charset = parameter("charset", in: contentType)
        let encoding = headers["content-transfer-encoding"]?.lowercased().trimmingCharacters(in: .whitespaces)

        if type.hasPrefix("multipart/"), let boundary = parameter("boundary", in: contentType) {
            let parts = body.components(separatedBy: "--" + boundary)
                .dropFirst()
                .filter { !$0.hasPrefix("--") }
            var plain: String?
            var html: String?
            for part in parts {
                let (partHeader, partBody) = split(part.droppingPrefix("\r\n").droppingPrefix("\n"))
                let partHeaders = self.headers(partHeader)
                let partType = (partHeaders["content-type"] ?? "text/plain").lowercased()
                if partHeaders["content-disposition"]?.lowercased().hasPrefix("attachment") == true { continue }
                guard let decoded = text(headers: partHeaders, body: partBody) else { continue }
                if partType.hasPrefix("text/html") {
                    html = html ?? decoded
                } else if plain == nil {
                    plain = decoded
                }
            }
            return plain ?? html
        }

        guard type.hasPrefix("text/") else { return nil }
        let bytes: Data
        switch encoding {
        case "base64":
            bytes = Data(base64Encoded: padded(body.filter { !$0.isWhitespace })) ?? Data()
        case "quoted-printable":
            bytes = quotedPrintableBytes(body)
        default:
            bytes = Data(body.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) })
        }
        let decoded = decodeBytes(bytes, charset: charset)
        return type == "text/html" ? stripHTML(decoded) : decoded
    }

    static func parameter(_ name: String, in header: String) -> String? {
        for piece in header.split(separator: ";").dropFirst() {
            let pair = piece.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == name else { continue }
            return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }
        return nil
    }

    private static func padded(_ base64: String) -> String {
        let remainder = base64.count % 4
        return remainder == 0 ? base64 : base64 + String(repeating: "=", count: 4 - remainder)
    }

    static func quotedPrintableBytes(_ text: String) -> Data {
        var bytes: [UInt8] = []
        let scalars = Array(text.replacingOccurrences(of: "=\r\n", with: "").replacingOccurrences(of: "=\n", with: "").unicodeScalars)
        var i = 0
        while i < scalars.count {
            if scalars[i] == "=", i + 2 < scalars.count,
               let value = UInt8(String(scalars[i + 1]) + String(scalars[i + 2]), radix: 16) {
                bytes.append(value)
                i += 3
            } else {
                bytes.append(UInt8(truncatingIfNeeded: scalars[i].value))
                i += 1
            }
        }
        return Data(bytes)
    }

    static func stripHTML(_ html: String) -> String {
        var text = html
        for (pattern, replacement) in [
            (#"(?is)<(style|script|head)[^>]*>.*?</\1>"#, ""),
            (#"(?i)<br\s*/?>"#, "\n"),
            (#"(?i)</(p|div|tr|li|h[1-6])>"#, "\n"),
            (#"<[^>]+>"#, ""),
        ] {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
                        "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü",
                        "&szlig;": "ß", "&euro;": "€"]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        text = text.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n\s*\n\s*\n+"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reine Adresse aus „Name <adresse@beispiel.de>“.
    static func address(from value: String) -> String {
        if let start = value.firstIndex(of: "<"), let end = value[start...].firstIndex(of: ">") {
            return String(value[value.index(after: start)..<end]).trimmingCharacters(in: .whitespaces)
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
    }

    /// Datum aus einer Kopfzeile (RFC 5322).
    static func date(from value: String?) -> Date? {
        guard var text = value?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if let paren = text.firstIndex(of: "(") { text = String(text[..<paren]).trimmingCharacters(in: .whitespaces) }
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

private extension String {
    func droppingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
