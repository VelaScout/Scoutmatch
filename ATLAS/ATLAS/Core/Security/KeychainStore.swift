import Foundation
import Security

/// Speichert Geheimnisse (z. B. den API-Schlüssel) verschlüsselt im Schlüsselbund.
/// iPhone: `WhenUnlockedThisDeviceOnly` – nur lesbar, wenn das iPhone entsperrt ist,
/// und wird weder in Backups noch auf andere Geräte übertragen.
/// Mac: moderner Schlüsselbund wie auf dem iPhone („Data Protection Keychain“). Der alte
/// Datei-Schlüsselbund fragt nach jedem neuen Build nach dem Mac-Passwort – das entfällt so.
/// Gelesene Werte werden für die Laufzeit der App zwischengespeichert.
enum KeychainStore {
    private static let service = "ATLAS.secrets"

    enum Key: String {
        case anthropicAPIKey = "anthropic-api-key"
        case elevenLabsAPIKey = "elevenlabs-api-key"
        case mailPassword = "mail-app-password"
        case spotifyRefreshToken = "spotify-refresh-token"
    }

    /// Zwischenspeicher: `nil` = noch nicht gelesen, `""` = nicht vorhanden.
    nonisolated(unsafe) private static var cache: [Key: String] = [:]
    private static let lock = NSLock()

    @discardableResult
    static func save(_ value: String, for key: Key) -> Bool {
        delete(key)
        var query = baseQuery(key, modern: true)
        query[kSecValueData as String] = Data(value.utf8)
        #if os(iOS)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #else
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        #endif
        var status = SecItemAdd(query as CFDictionary, nil)
        #if os(macOS)
        if status == errSecMissingEntitlement {
            // Ohne passende Signatur steht nur der alte Schlüsselbund zur Verfügung.
            var legacy = baseQuery(key, modern: false)
            legacy[kSecValueData as String] = Data(value.utf8)
            status = SecItemAdd(legacy as CFDictionary, nil)
        }
        #endif
        if status == errSecSuccess { setCache(value, for: key) }
        return status == errSecSuccess
    }

    static func read(_ key: Key) -> String? {
        if let cached = cachedValue(for: key) { return cached.isEmpty ? nil : cached }
        var value = copy(key, modern: true)
        #if os(macOS)
        if value == nil, let legacy = copy(key, modern: false) {
            // Einmalig umziehen: aus dem alten in den modernen Schlüsselbund.
            value = legacy
            var query = baseQuery(key, modern: true)
            query[kSecValueData as String] = Data(legacy.utf8)
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            if SecItemAdd(query as CFDictionary, nil) == errSecSuccess {
                SecItemDelete(baseQuery(key, modern: false) as CFDictionary)
            }
        }
        #endif
        setCache(value ?? "", for: key)
        return value
    }

    static func delete(_ key: Key) {
        SecItemDelete(baseQuery(key, modern: true) as CFDictionary)
        #if os(macOS)
        SecItemDelete(baseQuery(key, modern: false) as CFDictionary)
        #endif
        setCache("", for: key)
    }

    static func has(_ key: Key) -> Bool {
        guard let value = read(key) else { return false }
        return !value.isEmpty
    }

    // MARK: - Intern

    private static func baseQuery(_ key: Key, modern: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        #if os(macOS)
        if modern { query[kSecUseDataProtectionKeychain as String] = true }
        #endif
        return query
    }

    private static func copy(_ key: Key, modern: Bool) -> String? {
        var query = baseQuery(key, modern: modern)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func cachedValue(for key: Key) -> String? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }

    private static func setCache(_ value: String, for key: Key) {
        lock.lock(); defer { lock.unlock() }
        cache[key] = value
    }
}
