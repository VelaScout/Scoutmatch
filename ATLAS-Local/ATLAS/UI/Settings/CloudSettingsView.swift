import SwiftUI

/// Optionales Cloud-Modell (Claude). Standard: aus. Vor jeder Übertragung fragt Atlas nach und zeigt,
/// welche Daten den Mac verlassen – außer Sie erlauben es dauerhaft. Kosten werden mitgezählt.
struct CloudSettingsView: View {
    @State private var status: [String: Any] = [:]
    @State private var key = ""
    @State private var message: String?
    @State private var busy = false
    private let provider = LocalAtlasProvider()
    private let models = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]

    var body: some View {
        Form {
            Section {
                Text("Lokal bleibt der Standard. Ein Cloud-Modell ist deutlich leistungsfähiger als das lokale Modell, kostet aber Geld und sendet Daten an Anthropic. Nutzen: Satz mit „Cloud:“ oder „Mit Claude:“ beginnen. Vor jeder Übertragung zeigt Atlas, was den Mac verlässt.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let message { Text(message).font(.footnote).foregroundStyle(.orange) }
            }
            Section("Cloud-Modell") {
                Toggle("Cloud-Modell erlauben", isOn: binding("enabled", false))
                Picker("Modell", selection: Binding(get: { status["model"] as? String ?? models[0] },
                                                   set: { update(["model": $0]) })) {
                    ForEach(models, id: \.self) { model in Text(label(model)).tag(model) }
                }
                Stepper("Monatslimit: \(Int(limit)) US-$", value: Binding(get: { limit }, set: { update(["monthly_limit_usd": $0]) }),
                        in: 0...200, step: 1)
                Text(String(format: "Diesen Monat verbraucht: %.2f US-$", status["spent_usd"] as? Double ?? 0)).font(.caption)
                Toggle("Ohne Rückfrage senden (Dauerfreigabe)", isOn: binding("always_allow", false))
                Text("Nur einschalten, wenn Sie nicht vor jeder Übertragung gefragt werden möchten.").font(.caption2).foregroundStyle(.secondary)
            }
            Section("API-Schlüssel") {
                Text((status["has_key"] as? Bool ?? false) ? "Schlüssel ist im macOS-Schlüsselbund gespeichert." : "Kein Schlüssel hinterlegt.")
                    .font(.callout)
                SecureField("sk-ant-…", text: $key)
                HStack {
                    Button("Im Schlüsselbund speichern") { save() }.disabled(key.isEmpty || busy)
                    if status["has_key"] as? Bool ?? false {
                        Button("Schlüssel löschen", role: .destructive) { call("key/delete", [:]) }
                    }
                }
                Text("Den Schlüssel erhalten Sie in der Anthropic Console. Er wird nur im Schlüsselbund gespeichert, nie in Atlas-Dateien.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Cloud-Modell (optional)")
        .task { call("status", [:]) }
    }

    private var limit: Double { (status["monthly_limit_usd"] as? Double) ?? Double(status["monthly_limit_usd"] as? Int ?? 5) }

    private func label(_ model: String) -> String {
        guard let prices = (status["prices"] as? [String: Any])?[model] as? [Double], prices.count == 2 else { return model }
        return String(format: "%@ (%.2f / %.2f US-$ je 1 Mio. Token)", model, prices[0], prices[1])
    }

    private func binding(_ key: String, _ fallback: Bool) -> Binding<Bool> {
        Binding(get: { status[key] as? Bool ?? fallback }, set: { update([key: $0]) })
    }

    private func update(_ change: [String: Any]) { call("settings", change) }

    private func save() {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        key = ""                       // Schlüssel nicht länger als nötig im Speicher der Ansicht halten
        call("key", ["key": value])
    }

    private func call(_ action: String, _ object: [String: Any]) {
        busy = true
        Task {
            defer { busy = false }
            do {
                status = try await provider.cloud(action, object)
                message = (status["problem"] as? String).flatMap { $0.isEmpty ? nil : "Status: \($0)" }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
