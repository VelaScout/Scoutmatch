import Foundation

/// E-Mail-Anbieter mit fertigen Servereinstellungen.
enum MailProvider: String, CaseIterable, Identifiable, Sendable {
    case icloud, gmail, gmx, webde

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .icloud: return "iCloud-Mail"
        case .gmail: return "Gmail"
        case .gmx: return "GMX"
        case .webde: return "WEB.DE"
        }
    }

    var imapHost: String {
        switch self {
        case .icloud: return "imap.mail.me.com"
        case .gmail: return "imap.gmail.com"
        case .gmx: return "imap.gmx.net"
        case .webde: return "imap.web.de"
        }
    }

    var smtpHost: String {
        switch self {
        case .icloud: return "smtp.mail.me.com"
        case .gmail: return "smtp.gmail.com"
        case .gmx: return "mail.gmx.net"
        case .webde: return "smtp.web.de"
        }
    }

    /// Ordner für gesendete Mails (Gmail legt sie selbst ab).
    var sentFolder: String? {
        switch self {
        case .icloud: return "Sent Messages"
        case .gmail: return nil
        case .gmx, .webde: return "Gesendet"
        }
    }

    /// Kurzanleitung für das App-Passwort.
    var passwordHelp: String {
        switch self {
        case .icloud:
            return "Aus Sicherheitsgründen braucht A.T.L.A.S. ein App-spezifisches Passwort – nicht Ihr Apple-Passwort. Erstellen: account.apple.com → Anmelden und Sicherheit → App-spezifische Passwörter → „+“, Name „A.T.L.A.S.“. Das Passwort (xxxx-xxxx-xxxx-xxxx) hier eintragen."
        case .gmail:
            return "Google-Konto → Sicherheit → Bestätigung in zwei Schritten (muss an sein) → App-Passwörter → Name „A.T.L.A.S.“. Das 16-stellige Passwort hier eintragen."
        case .gmx, .webde:
            return "Im Postfach unter Einstellungen → POP3/IMAP Abruf den Zugriff per IMAP erlauben. Dann Ihr Postfach-Passwort (oder ein Anwendungspasswort) hier eintragen."
        }
    }
}

struct MailSummary: Sendable {
    let uid: Int
    let from: String
    let subject: String
    let date: Date?
    let unread: Bool
}

struct MailMessage: Sendable {
    let uid: Int
    let from: String
    let replyTo: String
    let to: String
    let subject: String
    let date: Date?
    let messageID: String
    let references: String
    let text: String
}

enum MailError: LocalizedError {
    case notConfigured
    case server(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Es ist noch kein E-Mail-Konto verbunden."
        case .server(let message): return "Der Mailserver meldet: \(message)"
        case .notFound: return "Diese E-Mail wurde nicht gefunden."
        }
    }
}

/// Lesen (IMAP) und Senden (SMTP) von E-Mails. Alle Netzwerkarbeit läuft im Hintergrund.
/// Zugangsdaten: Adresse in den Einstellungen, Passwort verschlüsselt im Schlüsselbund.
enum MailService {
    struct Account: Sendable {
        let provider: MailProvider
        let address: String
        let password: String
    }

    @MainActor
    static func account(settings: AppSettings) -> Account? {
        let address = settings.mailAddress.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty, let password = KeychainStore.read(.mailPassword), !password.isEmpty else { return nil }
        return Account(provider: settings.mailProvider, address: address, password: password)
    }

    // MARK: - Öffentliche Funktionen

    static func test(_ account: Account) async throws {
        try await background {
            let imap = try IMAPClient.login(account)
            imap.logout()
            try SMTPClient.verify(account)
        }
    }

    static func list(_ account: Account, unreadOnly: Bool, count: Int) async throws -> [MailSummary] {
        try await background {
            let imap = try IMAPClient.login(account)
            defer { imap.logout() }
            try imap.select("INBOX")
            var uids: [Int]
            if unreadOnly {
                uids = try imap.search("UNSEEN")
            } else {
                let since = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
                uids = try imap.search("SINCE \(IMAPClient.dateString(since))")
            }
            uids = Array(uids.sorted(by: >).prefix(max(1, min(count, 25))))
            guard !uids.isEmpty else { return [] }
            return try imap.fetchSummaries(uids).sorted { $0.uid > $1.uid }
        }
    }

    static func read(_ account: Account, uid: Int) async throws -> MailMessage {
        try await background {
            let imap = try IMAPClient.login(account)
            defer { imap.logout() }
            try imap.select("INBOX")
            let message = try imap.fetchMessage(uid)
            try? imap.markSeen(uid)
            return message
        }
    }

    /// Sendet eine E-Mail. Aufrufer müssen vorher die Bestätigung des Nutzers einholen.
    static func send(_ account: Account, to recipients: [String], subject: String, body: String,
                     replyingTo original: MailMessage?) async throws {
        try await background {
            let raw = SMTPClient.buildMessage(from: account.address, to: recipients, subject: subject, body: body,
                                              inReplyTo: original?.messageID, references: original?.references)
            try SMTPClient.send(account, recipients: recipients, raw: raw)
            // Kopie in „Gesendet“ ablegen, damit die Mail auch in der Mail-App erscheint.
            if let folder = account.provider.sentFolder, let imap = try? IMAPClient.login(account) {
                try? imap.append(folder, raw: raw)
                if let original { try? imap.select("INBOX"); try? imap.markAnswered(original.uid) }
                imap.logout()
            }
        }
    }

    private static func background<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try work() }.value
    }
}

// MARK: - IMAP

private final class IMAPClient {
    private let socket: MailSocket
    private var tag = 0

    struct Untagged {
        let line: String
        let literals: [Data]
    }

    private init(host: String) throws {
        socket = try MailSocket(host: host, port: 993, tls: true)
        _ = try socket.readLine()
    }

    /// Anmelden. iCloud erwartet teils nur den Namen vor dem @, teils die volle Adresse.
    static func login(_ account: MailService.Account) throws -> IMAPClient {
        var users = [account.address]
        if account.provider == .icloud, let local = account.address.split(separator: "@").first {
            users.insert(String(local), at: 0)
        }
        var lastError: Error = MailError.notConfigured
        for user in users {
            let client = try IMAPClient(host: account.provider.imapHost)
            do {
                _ = try client.command("LOGIN \(quote(user)) \(quote(account.password))")
                return client
            } catch {
                lastError = error
                client.logout()
            }
        }
        throw lastError
    }

    static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d-MMM-yyyy"
        return formatter.string(from: date)
    }

    @discardableResult
    func command(_ text: String) throws -> [Untagged] {
        tag += 1
        let current = "A\(tag)"
        try socket.write("\(current) \(text)\r\n")
        return try readResponse(tag: current)
    }

    private func readResponse(tag current: String) throws -> [Untagged] {
        var result: [Untagged] = []
        while true {
            var line = try socket.readLineString()
            var full = line
            var literals: [Data] = []
            while let length = Self.literalLength(line) {
                literals.append(try socket.readBytes(length))
                line = try socket.readLineString()
                full += " " + line
            }
            if full.hasPrefix(current + " ") {
                let status = full.dropFirst(current.count + 1)
                guard status.uppercased().hasPrefix("OK") else {
                    throw MailError.server(String(status.drop(while: { $0 != " " })).trimmingCharacters(in: .whitespaces))
                }
                return result
            }
            result.append(Untagged(line: full, literals: literals))
        }
    }

    private static func literalLength(_ line: String) -> Int? {
        guard line.hasSuffix("}"), let open = line.lastIndex(of: "{") else { return nil }
        return Int(line[line.index(after: open)..<line.index(before: line.endIndex)])
    }

    func select(_ folder: String) throws {
        try command("SELECT \(Self.quote(folder))")
    }

    func search(_ criteria: String) throws -> [Int] {
        let lines = try command("UID SEARCH \(criteria)")
        return lines.filter { $0.line.hasPrefix("* SEARCH") }
            .flatMap { $0.line.dropFirst("* SEARCH".count).split(separator: " ").compactMap { Int($0) } }
    }

    func fetchSummaries(_ uids: [Int]) throws -> [MailSummary] {
        let set = uids.map(String.init).joined(separator: ",")
        let items = try command("UID FETCH \(set) (UID FLAGS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])")
        return items.compactMap { item -> MailSummary? in
            guard let uid = Self.uid(in: item.line), let raw = item.literals.first else { return nil }
            let headers = MIME.headers(String(decoding: raw, as: UTF8.self))
            return MailSummary(uid: uid,
                               from: MIME.decodeHeader(headers["from"] ?? "Unbekannt"),
                               subject: MIME.decodeHeader(headers["subject"] ?? "(ohne Betreff)"),
                               date: MIME.date(from: headers["date"]),
                               unread: !item.line.contains("\\Seen"))
        }
    }

    func fetchMessage(_ uid: Int) throws -> MailMessage {
        let items = try command("UID FETCH \(uid) (UID BODY.PEEK[])")
        guard let item = items.first(where: { Self.uid(in: $0.line) == uid }), let raw = item.literals.first else {
            throw MailError.notFound
        }
        // Latin-1 hält jedes Byte unverändert – die Zeichensätze werden erst beim Dekodieren angewandt.
        let text = String(data: raw, encoding: .isoLatin1) ?? String(decoding: raw, as: UTF8.self)
        let headers = MIME.headers(MIME.split(text).header)
        let from = MIME.decodeHeader(MIME.decodeCharset(headers["from"] ?? "", charset: "utf-8"))
        let replyTo = MIME.decodeHeader(headers["reply-to"] ?? "")
        return MailMessage(uid: uid,
                           from: from,
                           replyTo: replyTo.isEmpty ? from : replyTo,
                           to: MIME.decodeHeader(headers["to"] ?? ""),
                           subject: MIME.decodeHeader(MIME.decodeCharset(headers["subject"] ?? "", charset: "utf-8")),
                           date: MIME.date(from: headers["date"]),
                           messageID: headers["message-id"] ?? "",
                           references: headers["references"] ?? "",
                           text: MIME.bodyText(raw: text))
    }

    func markSeen(_ uid: Int) throws {
        try command("UID STORE \(uid) +FLAGS (\\Seen)")
    }

    func markAnswered(_ uid: Int) throws {
        try command("UID STORE \(uid) +FLAGS (\\Answered)")
    }

    /// Legt eine Nachricht in einem Ordner ab (z. B. „Gesendet“).
    func append(_ folder: String, raw: Data) throws {
        tag += 1
        let current = "A\(tag)"
        try socket.write("\(current) APPEND \(Self.quote(folder)) (\\Seen) {\(raw.count)}\r\n")
        let continuation = try socket.readLineString()
        guard continuation.hasPrefix("+") else { throw MailError.server(continuation) }
        try socket.write(raw)
        try socket.write("\r\n")
        _ = try readResponse(tag: current)
    }

    func logout() {
        _ = try? command("LOGOUT")
        socket.close()
    }

    private static func uid(in line: String) -> Int? {
        guard let range = line.range(of: #"UID (\d+)"#, options: .regularExpression) else { return nil }
        return Int(line[range].dropFirst(4))
    }
}

// MARK: - SMTP

private enum SMTPClient {
    /// Baut die Nachricht als UTF-8-Text (Base64), mit Bezug auf die Original-Mail bei Antworten.
    static func buildMessage(from: String, to: [String], subject: String, body: String,
                             inReplyTo: String?, references: String?) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let domain = from.split(separator: "@").last.map(String.init) ?? "atlas.local"
        var lines = [
            "From: \(from)",
            "To: \(to.joined(separator: ", "))",
            "Subject: =?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?=",
            "Date: \(formatter.string(from: .now))",
            "Message-ID: <\(UUID().uuidString)@\(domain)>",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Transfer-Encoding: base64",
        ]
        if let inReplyTo, !inReplyTo.isEmpty {
            lines.append("In-Reply-To: \(inReplyTo)")
            lines.append("References: \([references ?? "", inReplyTo].filter { !$0.isEmpty }.joined(separator: " "))")
        }
        let encoded = Data(body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n").utf8)
            .base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n" + encoded + "\r\n").utf8)
    }

    static func verify(_ account: MailService.Account) throws {
        let socket = try openAuthenticated(account)
        _ = try? command(socket, "QUIT", expect: 221)
        socket.close()
    }

    static func send(_ account: MailService.Account, recipients: [String], raw: Data) throws {
        let socket = try openAuthenticated(account)
        defer { socket.close() }
        try command(socket, "MAIL FROM:<\(account.address)>", expect: 250)
        for recipient in recipients {
            try command(socket, "RCPT TO:<\(recipient)>", expect: 250, 251)
        }
        try command(socket, "DATA", expect: 354)
        try socket.write(raw)
        try command(socket, ".", expect: 250)
        _ = try? command(socket, "QUIT", expect: 221)
    }

    /// Verbindung auf Port 587, dann STARTTLS und Anmeldung.
    private static func openAuthenticated(_ account: MailService.Account) throws -> MailSocket {
        let socket = try MailSocket(host: account.provider.smtpHost, port: 587, tls: false)
        try expectReply(socket, 220)
        try command(socket, "EHLO atlas", expect: 250)
        try command(socket, "STARTTLS", expect: 220)
        socket.startTLS()
        try command(socket, "EHLO atlas", expect: 250)
        let credentials = Data(("\u{0}" + account.address + "\u{0}" + account.password).utf8).base64EncodedString()
        try command(socket, "AUTH PLAIN \(credentials)", expect: 235)
        return socket
    }

    @discardableResult
    private static func command(_ socket: MailSocket, _ text: String, expect codes: Int...) throws -> String {
        try socket.write(text + "\r\n")
        return try readReply(socket, codes)
    }

    @discardableResult
    private static func expectReply(_ socket: MailSocket, _ codes: Int...) throws -> String {
        try readReply(socket, codes)
    }

    /// Liest eine (auch mehrzeilige) Antwort und prüft den Statuscode.
    @discardableResult
    private static func readReply(_ socket: MailSocket, _ codes: [Int]) throws -> String {
        var text = ""
        while true {
            let line = try socket.readLineString()
            text += line + "\n"
            // Mehrzeilig: „250-…“, letzte Zeile „250 …“
            if line.count < 4 || line[line.index(line.startIndex, offsetBy: 3)] != "-" { break }
        }
        let code = Int(text.prefix(3)) ?? 0
        guard codes.contains(code) else {
            throw MailError.server(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return text
    }
}
