import SwiftUI
struct ConnectionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Lokale Verbindung").font(.title)
            Text("Atlas verwendet Qwen3 über Ollama auf diesem Mac. Den Verbindungsstatus finden Sie in den Einstellungen.")
            Text("Die früheren E-Mail- und Spotify-Anbindungen sind in dieser Ausgabe nicht an das lokale Modell angeschlossen. Vorhandene Zugangsdaten wurden nicht verändert.").foregroundStyle(.secondary)
        }.padding(24).navigationTitle("Verbindungen")
    }
}
