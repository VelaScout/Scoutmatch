import AVFoundation

/// Konfiguriert die Audio-Sitzung für gleichzeitiges Zuhören und Sprechen.
/// Auf dem Mac gibt es keine Audio-Sitzung – dort ist nichts zu tun.
enum AudioSessionManager {
    static func activate() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // Hören und Sprechen laufen dauerhaft parallel (Echo-Unterdrückung über die Audio-Leitung).
        // Andere Apps wie Spotify laufen weiter.
        try session.setCategory(.playAndRecord,
                                mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
        try session.setActive(true)
        #endif
    }

    static func deactivate() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
