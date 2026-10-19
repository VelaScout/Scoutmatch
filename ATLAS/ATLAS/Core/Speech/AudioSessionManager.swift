import AVFoundation

/// Konfiguriert die Audio-Sitzung für gleichzeitiges Zuhören und Sprechen.
enum AudioSessionManager {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord,
                                mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers])
        try session.setActive(true)
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
