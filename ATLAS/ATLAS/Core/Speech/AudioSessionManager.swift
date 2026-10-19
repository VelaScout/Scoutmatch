import AVFoundation

/// Konfiguriert die Audio-Sitzung für gleichzeitiges Zuhören und Sprechen.
/// Auf dem Mac gibt es keine Audio-Sitzung – dort ist nichts zu tun.
enum AudioSessionManager {
    static func activate() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord,
                                mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers])
        try session.setActive(true)
        #endif
    }

    static func deactivate() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
