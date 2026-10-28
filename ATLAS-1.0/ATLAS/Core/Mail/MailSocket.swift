import Foundation

/// Einfache, blockierende Verbindung für IMAP und SMTP – verschlüsselt per TLS
/// (direkt oder nachträglich per STARTTLS). Wird ausschließlich im Hintergrund benutzt.
final class MailSocket {
    enum SocketError: LocalizedError {
        case connectFailed(String)
        case closed
        case timeout

        var errorDescription: String? {
            switch self {
            case .connectFailed(let host): return "Keine Verbindung zum Mailserver \(host)."
            case .closed: return "Der Mailserver hat die Verbindung beendet."
            case .timeout: return "Der Mailserver antwortet nicht."
            }
        }
    }

    private let input: InputStream
    private let output: OutputStream
    private var buffer = Data()
    private let timeout: TimeInterval

    init(host: String, port: Int, tls: Bool, timeout: TimeInterval = 30) throws {
        var inStream: InputStream?
        var outStream: OutputStream?
        Stream.getStreamsToHost(withName: host, port: port, inputStream: &inStream, outputStream: &outStream)
        guard let inStream, let outStream else { throw SocketError.connectFailed(host) }
        input = inStream
        output = outStream
        self.timeout = timeout
        if tls { startTLS() }
        input.open()
        output.open()
        let deadline = Date().addingTimeInterval(timeout)
        while input.streamStatus == .opening || output.streamStatus == .opening {
            guard Date() < deadline else { close(); throw SocketError.timeout }
            usleep(10_000)
        }
        if input.streamStatus == .error || output.streamStatus == .error {
            close()
            throw SocketError.connectFailed(host)
        }
    }

    deinit { close() }

    /// Schaltet die Verschlüsselung ein (vor dem Öffnen oder nach STARTTLS).
    func startTLS() {
        let level = StreamSocketSecurityLevel.negotiatedSSL.rawValue as NSString
        input.setProperty(level, forKey: .socketSecurityLevelKey)
        output.setProperty(level, forKey: .socketSecurityLevelKey)
    }

    func close() {
        input.close()
        output.close()
    }

    // MARK: - Schreiben

    func write(_ text: String) throws {
        try write(Data(text.utf8))
    }

    func write(_ data: Data) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var offset = 0
        while offset < data.count {
            if output.streamStatus == .error || output.streamStatus == .closed { throw SocketError.closed }
            guard output.hasSpaceAvailable else {
                guard Date() < deadline else { throw SocketError.timeout }
                usleep(5_000)
                continue
            }
            let written = data.withUnsafeBytes { raw -> Int in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return output.write(base + offset, maxLength: data.count - offset)
            }
            if written < 0 { throw SocketError.closed }
            offset += written
        }
    }

    // MARK: - Lesen

    /// Liest eine Zeile (ohne CRLF) als Rohdaten.
    func readLine() throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let range = buffer.range(of: Data([13, 10])) {
                let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return line
            }
            try fill(until: deadline)
        }
    }

    /// Liest eine Zeile als Text (UTF-8, fehlerhafte Zeichen werden ersetzt).
    func readLineString() throws -> String {
        String(decoding: try readLine(), as: UTF8.self)
    }

    /// Liest genau `count` Bytes.
    func readBytes(_ count: Int) throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while buffer.count < count {
            try fill(until: deadline)
        }
        let data = buffer.prefix(count)
        buffer.removeFirst(count)
        return Data(data)
    }

    private func fill(until deadline: Date) throws {
        if input.hasBytesAvailable {
            var chunk = [UInt8](repeating: 0, count: 16_384)
            let read = input.read(&chunk, maxLength: chunk.count)
            if read < 0 { throw SocketError.closed }
            if read == 0 { throw SocketError.closed }
            buffer.append(contentsOf: chunk[0..<read])
            return
        }
        if input.streamStatus == .atEnd || input.streamStatus == .error || input.streamStatus == .closed {
            throw SocketError.closed
        }
        guard Date() < deadline else { throw SocketError.timeout }
        usleep(5_000)
    }
}
