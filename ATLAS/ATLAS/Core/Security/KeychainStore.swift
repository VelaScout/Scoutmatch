import Foundation
import Security

/// Speichert Geheimnisse (z. B. den API-Schlüssel) verschlüsselt in der iOS-Keychain.
/// iPhone: `WhenUnlockedThisDeviceOnly` – nur lesbar, wenn das iPhone entsperrt ist,
/// und wird weder in Backups noch auf andere Geräte übertragen.
/// Mac: Schlüsselbund des angemeldeten Benutzers.
enum KeychainStore {
    private static let service = "ATLAS.secrets"

    enum Key: String {
        case anthropicAPIKey = "anthropic-api-key"
        case elevenLabsAPIKey = "elevenlabs-api-key"
    }

    @discardableResult
    static func save(_ value: String, for key: Key) -> Bool {
        let data = Data(value.utf8)
        delete(key)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
        ]
        #if os(iOS)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #endif
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func has(_ key: Key) -> Bool {
        guard let value = read(key) else { return false }
        return !value.isEmpty
    }
}
