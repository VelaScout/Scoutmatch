import SwiftUI
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Verbindung wird geprüft …"
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("A.T.L.A.S. Local").font(.largeTitle.bold())
            Text("Ihre Oberfläche, Ihr Gedächtnis und Qwen3 auf Ihrem Mac. Keine API-Schlüssel erforderlich.")
            Text(status).font(.callout).textSelection(.enabled)
            Text("Starten Sie mit einer geschriebenen Frage. Für Spracheingabe benötigt macOS Mikrofon- und Spracherkennungsfreigabe sowie das lokale Sprachpaket. Atlas lädt kein Audio zu einem KI-Anbieter hoch.")
            Button("Verbindung erneut prüfen") { Task { await check() } }
            Button("Beginnen") {
                UserDefaults.standard.set(true, forKey: "localAtlasOnboarded")
                dismiss()
            }.buttonStyle(.borderedProminent)
        }.padding(28).task { await check() }
    }
    private func check() async {
        do { status = try await LocalAtlasProvider().health() }
        catch { status = error.localizedDescription }
    }
}
