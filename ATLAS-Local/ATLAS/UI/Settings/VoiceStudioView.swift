import SwiftUI
struct VoiceStudioView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform").font(.largeTitle)
            Text("Lokale Stimme").font(.title)
            Text("Atlas verwendet installierte Apple-Stimmen. Sprache, Stimme und Tempo wählen Sie in den Einstellungen. Cloud-Stimmen sind deaktiviert.")
        }.padding(24).navigationTitle("Stimme")
    }
}
