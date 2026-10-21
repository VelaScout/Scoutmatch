import Observation
import SwiftUI

/// Eine Werkzeugaktion des Agenten, wie sie in der Oberfläche erscheint.
struct ActivityItem: Identifiable, Equatable {
    enum Status: Equatable { case running, done, failed }
    let id = UUID()
    let label: String
    var status: Status = .running
}

/// Zustand von Backend und Ollama – wird regelmäßig im Hintergrund geprüft.
@MainActor
@Observable
final class SystemStatus {
    enum Backend: Equatable { case checking, online, noModel, offline }

    private(set) var backend: Backend = .checking
    private(set) var installedModels: [String] = []
    private(set) var detail = ""
    private var loop: Task<Void, Never>?

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    func check() async {
        do {
            let text = try await LocalAtlasProvider().health()
            installedModels = text.replacingOccurrences(of: "Lokal verbunden: ", with: "")
                .components(separatedBy: ", ").filter { !$0.isEmpty }
            backend = .online
            detail = ""
        } catch is URLError {
            backend = .offline
            installedModels = []
            detail = "Atlas-Dienst läuft nicht. Er startet bei der Anmeldung; sonst INSTALLIEREN.command erneut ausführen."
        } catch {
            backend = .noModel
            installedModels = []
            detail = error.localizedDescription
        }
    }
}

/// Schmale Statuszeile: Dienst, Modell, Mikrofon.
struct StatusBar: View {
    @Environment(ConversationEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    let status: SystemStatus

    var body: some View {
        HStack(spacing: 8) {
            chip(icon: "server.rack", text: backendText, color: backendColor)
                .help(status.detail)
            chip(icon: "cpu", text: modelText, color: .cyan)
            chip(icon: micIcon, text: micText, color: micColor)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal)
    }

    private func chip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.5))
    }

    private var backendText: String {
        switch status.backend {
        case .checking: return "Prüft …"
        case .online: return "Lokal bereit"
        case .noModel: return "Ollama fehlt"
        case .offline: return "Dienst aus"
        }
    }

    private var backendColor: Color {
        switch status.backend {
        case .online: return .green
        case .checking: return .gray
        case .noModel, .offline: return .orange
        }
    }

    private var modelText: String {
        let chat = settings.model.rawValue
        return status.installedModels.contains("qwen3:8b") && chat != "qwen3:8b" ? "\(chat) · Aufgaben 8b" : chat
    }

    private var micIcon: String {
        guard settings.microphoneEnabled else { return "mic.slash" }
        return engine.state.micActive ? "mic.fill" : "mic"
    }

    private var micText: String {
        guard settings.microphoneEnabled else { return "Mikrofon aus" }
        switch engine.state {
        case .listening: return "Hört zu"
        case .standby: return "Wartet auf „Atlas“"
        case .speaking: return "Spricht"
        default: return "Mikrofon bereit"
        }
    }

    private var micColor: Color {
        guard settings.microphoneEnabled else { return .gray }
        return engine.state.micActive ? .blue : .white.opacity(0.7)
    }
}

/// Transparente Anzeige der Werkzeugaktionen: was ATLAS gerade tut und was erledigt ist.
struct ActivityPanel: View {
    let items: [ActivityItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items.suffix(5)) { item in
                HStack(spacing: 6) {
                    icon(for: item.status)
                    Text(item.label).lineLimit(1)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.85))
        .padding(10)
        .frame(maxWidth: 420, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.blue.opacity(0.25), lineWidth: 0.5))
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.25), value: items)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Laufende Aufgaben")
    }

    @ViewBuilder
    private func icon(for status: ActivityItem.Status) -> some View {
        switch status {
        case .running: ProgressView().controlSize(.mini)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
