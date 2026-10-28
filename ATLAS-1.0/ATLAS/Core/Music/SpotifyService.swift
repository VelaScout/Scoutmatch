import AuthenticationServices
import CryptoKit
import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Spotify-Steuerung über die offizielle Web-API (Spotify Premium nötig).
///
/// Anmeldung per OAuth mit PKCE – A.T.L.A.S. sieht nie Ihr Spotify-Passwort. Gespeichert wird
/// nur das Erneuerungs-Token, verschlüsselt im Schlüsselbund. Die Client-ID stammt aus einer
/// eigenen, kostenlosen App im Spotify-Entwicklerbereich (Anleitung in den Einstellungen).
@MainActor
final class SpotifyService: NSObject {
    static let shared = SpotifyService()
    static let redirectURI = "atlas-assistant://spotify-callback"
    private static let scopes = [
        "user-read-playback-state", "user-modify-playback-state", "user-read-currently-playing",
        "playlist-read-private", "user-library-read",
    ]

    enum SpotifyError: LocalizedError {
        case noClientID, notConnected, cancelled, authFailed, premiumRequired, noDevice, nothingFound(String), api(String)

        var errorDescription: String? {
            switch self {
            case .noClientID: return "Für Spotify fehlt noch die Client-ID (Einstellungen → Verbindungen)."
            case .notConnected: return "Spotify ist noch nicht verbunden (Einstellungen → Verbindungen)."
            case .cancelled: return "Die Spotify-Anmeldung wurde abgebrochen."
            case .authFailed: return "Die Anmeldung bei Spotify hat nicht geklappt."
            case .premiumRequired: return "Spotify erlaubt die Steuerung nur mit Spotify Premium."
            case .noDevice: return "Kein Spotify-Gerät gefunden. Bitte öffnen Sie Spotify einmal kurz auf diesem Gerät."
            case .nothingFound(let query): return "Bei Spotify wurde nichts zu „\(query)“ gefunden."
            case .api(let message): return "Spotify meldet: \(message)"
            }
        }
    }

    private var accessToken: String?
    private var tokenExpiry = Date.distantPast
    private var authSession: ASWebAuthenticationSession?

    var isConnected: Bool { KeychainStore.has(.spotifyRefreshToken) }

    // MARK: - Anmeldung

    func connect(clientID: String) async throws {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw SpotifyError.noClientID }
        let verifier = Self.randomVerifier()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
        ]
        guard let url = components.url else { throw SpotifyError.authFailed }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "atlas-assistant") { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: SpotifyError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? SpotifyError.authFailed)
                }
            }
            session.presentationContextProvider = self
            authSession = session
            session.start()
        }
        authSession = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else { throw SpotifyError.authFailed }

        try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
    }

    func disconnect() {
        KeychainStore.delete(.spotifyRefreshToken)
        accessToken = nil
        tokenExpiry = .distantPast
    }

    private func requestToken(_ form: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw SpotifyError.authFailed
        }
        accessToken = token
        tokenExpiry = Date.now.addingTimeInterval(Double(json["expires_in"] as? Int ?? 3600) - 60)
        if let refresh = json["refresh_token"] as? String {
            KeychainStore.save(refresh, for: .spotifyRefreshToken)
        }
    }

    private func validToken() async throws -> String {
        if let accessToken, Date.now < tokenExpiry { return accessToken }
        guard let refresh = KeychainStore.read(.spotifyRefreshToken), !refresh.isEmpty else { throw SpotifyError.notConnected }
        let clientID = UserDefaults.standard.string(forKey: "spotifyClientID") ?? ""
        guard !clientID.isEmpty else { throw SpotifyError.noClientID }
        try await requestToken(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID])
        guard let accessToken else { throw SpotifyError.authFailed }
        return accessToken
    }

    // MARK: - Web-API

    @discardableResult
    private func api(_ method: String, _ path: String, query: [String: String] = [:],
                     json: [String: Any]? = nil) async throws -> (Data, Int) {
        var components = URLComponents(string: "https://api.spotify.com/v1" + path)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else if method == "PUT" || method == "POST" {
            request.setValue("0", forHTTPHeaderField: "Content-Length")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            accessToken = nil
            tokenExpiry = .distantPast
        }
        if status >= 400 {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            let reason = error?["reason"] as? String ?? ""
            if reason == "PREMIUM_REQUIRED" { throw SpotifyError.premiumRequired }
            if reason == "NO_ACTIVE_DEVICE" || status == 404 { throw SpotifyError.noDevice }
            throw SpotifyError.api(error?["message"] as? String ?? "Fehler \(status)")
        }
        return (data, status)
    }

    private func object(_ data: Data) -> [String: Any] {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }

    // MARK: - Abspielen

    enum Kind: String { case track, artist, album, playlist, liked }

    /// Sucht und startet Musik. Liefert eine kurze Beschreibung, was jetzt läuft.
    func play(query: String, kind: Kind) async throws -> String {
        var body: [String: Any]
        var description: String
        switch kind {
        case .liked:
            let (data, _) = try await api("GET", "/me/tracks", query: ["limit": "50"])
            let uris = (object(data)["items"] as? [[String: Any]] ?? [])
                .compactMap { ($0["track"] as? [String: Any])?["uri"] as? String }
            guard !uris.isEmpty else { throw SpotifyError.nothingFound("Lieblingssongs") }
            body = ["uris": uris.shuffled()]
            description = "Ihre Lieblingssongs"
        case .playlist:
            if let own = try await ownPlaylist(matching: query) {
                body = ["context_uri": own.uri]
                description = "Ihre Playlist „\(own.name)“"
            } else {
                let found = try await search(query, type: "playlist")
                body = ["context_uri": found.uri]
                description = "die Playlist „\(found.name)“"
            }
        case .track:
            let found = try await search(query, type: "track")
            body = ["uris": [found.uri]]
            description = found.name
        case .artist, .album:
            let found = try await search(query, type: kind.rawValue)
            body = ["context_uri": found.uri]
            description = found.name
        }
        try await startPlayback(body)
        return description
    }

    private func search(_ query: String, type: String) async throws -> (uri: String, name: String) {
        let (data, _) = try await api("GET", "/search", query: ["q": query, "type": type, "limit": "1", "market": "from_token"])
        let items = (object(data)[type + "s"] as? [String: Any])?["items"] as? [Any] ?? []
        guard let item = items.compactMap({ $0 as? [String: Any] }).first,
              let uri = item["uri"] as? String else { throw SpotifyError.nothingFound(query) }
        var name = item["name"] as? String ?? query
        if let artist = (item["artists"] as? [[String: Any]])?.first?["name"] as? String, type != "artist" {
            name += " von \(artist)"
        }
        return (uri, name)
    }

    private func ownPlaylist(matching query: String) async throws -> (uri: String, name: String)? {
        let (data, _) = try await api("GET", "/me/playlists", query: ["limit": "50"])
        let needle = query.lowercased()
        for item in object(data)["items"] as? [[String: Any]] ?? [] {
            guard let name = item["name"] as? String, let uri = item["uri"] as? String else { continue }
            if name.lowercased().contains(needle) || needle.contains(name.lowercased()) { return (uri, name) }
        }
        return nil
    }

    /// Startet die Wiedergabe – auf dem aktiven Gerät oder, falls keins aktiv ist, auf
    /// diesem Gerät bzw. dem ersten verfügbaren. Notfalls wird die Spotify-App geöffnet.
    private func startPlayback(_ body: [String: Any]) async throws {
        var device = try await chooseDevice()
        if device == nil {
            if let url = URL(string: "spotify:") { PlatformBridge.open(url) }
            for _ in 0..<6 where device == nil {
                try await Task.sleep(for: .seconds(1))
                device = try await chooseDevice()
            }
        }
        guard let device else { throw SpotifyError.noDevice }
        try await api("PUT", "/me/player/play", query: ["device_id": device], json: body)
    }

    private func chooseDevice() async throws -> String? {
        let (data, _) = try await api("GET", "/me/player/devices")
        let devices = object(data)["devices"] as? [[String: Any]] ?? []
        if let active = devices.first(where: { $0["is_active"] as? Bool == true }) { return active["id"] as? String }
        let preferred = PlatformBridge.isMac ? "Computer" : "Smartphone"
        if let local = devices.first(where: { $0["type"] as? String == preferred }) { return local["id"] as? String }
        return devices.first?["id"] as? String
    }

    // MARK: - Steuerung

    enum Action: String {
        case pause, resume, next, previous
        case volumeUp = "volume_up", volumeDown = "volume_down", setVolume = "set_volume"
        case shuffleOn = "shuffle_on", shuffleOff = "shuffle_off"
    }

    func control(_ action: Action, volume: Int?) async throws -> String {
        switch action {
        case .pause:
            try await api("PUT", "/me/player/pause")
            return "Pausiert."
        case .resume:
            try await api("PUT", "/me/player/play")
            return "Wiedergabe läuft weiter."
        case .next:
            try await api("POST", "/me/player/next")
            return "Nächster Titel."
        case .previous:
            try await api("POST", "/me/player/previous")
            return "Vorheriger Titel."
        case .shuffleOn, .shuffleOff:
            try await api("PUT", "/me/player/shuffle", query: ["state": action == .shuffleOn ? "true" : "false"])
            return action == .shuffleOn ? "Zufallswiedergabe an." : "Zufallswiedergabe aus."
        case .volumeUp, .volumeDown, .setVolume:
            var target = volume ?? 50
            if action != .setVolume {
                let (data, status) = try await api("GET", "/me/player")
                let current = status == 204 ? 50 : ((object(data)["device"] as? [String: Any])?["volume_percent"] as? Int ?? 50)
                target = current + (action == .volumeUp ? 15 : -15)
            }
            target = min(100, max(0, target))
            try await api("PUT", "/me/player/volume", query: ["volume_percent": String(target)])
            return "Lautstärke \(target) Prozent."
        }
    }

    func nowPlaying() async throws -> String {
        let (data, status) = try await api("GET", "/me/player/currently-playing")
        guard status != 204 else { return "Gerade läuft nichts." }
        let json = object(data)
        guard let item = json["item"] as? [String: Any], let name = item["name"] as? String else {
            return "Gerade läuft nichts."
        }
        let artists = (item["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
        let playing = json["is_playing"] as? Bool ?? false
        return "\(playing ? "Es läuft" : "Pausiert"): „\(name)“\(artists.isEmpty ? "" : " von \(artists)")."
    }

    // MARK: - Hilfen

    private static func randomVerifier() -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in characters.randomElement()! })
    }
}

extension SpotifyService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(iOS)
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor()
            #else
            return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
            #endif
        }
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
