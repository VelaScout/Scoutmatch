import Foundation

/// Gleiche Fälle wie Backend/tests/test_privacy.py – läuft auf dem Mac in Tests/test_provider_mac.sh.
@main struct SecretFilterTests {
    static func main() {
        let secrets = ["Mein Passwort ist Sommer2026!", "Das Passwort für Netflix lautet hund123", "PIN: 4711", "Passwort für das Online-Banking: Hund123",
                       "api key = sk-ant-api03-abcdefghijklmnopqrstuv", "ghp_abcdefghijklmnopqrstuvwxyz0123",
                       "Karte 4111 1111 1111 1111", "IBAN DE89 3704 0044 0532 0130 00"]
        let normal = ["Ich trainiere montags", "Mein Passwort-Manager ist 1Password", "Termin um 14:30",
                      "Rufnummer 030 1234567", "Die PIN-Eingabe hat geklappt", "Projekt Atlas läuft bis 2027"]
        for text in secrets { precondition(SecretFilter.containsSecret(text), "nicht erkannt: \(text)") }
        for text in normal { precondition(!SecretFilter.containsSecret(text), "fälschlich erkannt: \(text)") }
        print("SecretFilterTests: \(secrets.count + normal.count) Fälle bestanden")
    }
}
