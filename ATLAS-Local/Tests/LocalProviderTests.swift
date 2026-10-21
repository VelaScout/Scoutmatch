import Foundation

/// Spielt die App: führt native Werkzeuge aus und beantwortet Bestätigungen.
@MainActor final class FixtureTools: ToolExecuting {
    var calls: [String] = []
    var approve = false
    func execute(name: String, inputJSON: Data) async -> ToolResult {
        calls.append(name)
        switch name {
        case "atlas_confirm": return ToolResult(content: approve ? "approved" : "denied")
        case "get_calendar_events": return ToolResult(content: "Morgen 9 Uhr Zahnarzt")
        default: return ToolResult(content: "Unbekannt", isError: true)
        }
    }
}

/// Vertragstest Swift ⇄ echtes Python-Backend (Modell simuliert, siehe Tests/agent_fixture.py).
@main struct LocalProviderTests {
    static func collect(_ provider: LocalAtlasProvider, _ text: String, _ options: AIRequestOptions,
                        tools: (any ToolExecuting)?) async throws -> (text: String, steps: [String]) {
        var answer = ""
        var steps: [String] = []
        for try await event in provider.runTurn(history: [.init(role: .user, text: text)], options: options, tools: tools) {
            switch event {
            case .text(let piece): answer += piece
            case .toolStarted(let name): steps.append("start:" + name)
            case .toolFinished(let name, let ok): steps.append((ok ? "ok:" : "fail:") + name)
            case .searching: break
            }
        }
        return (answer.trimmingCharacters(in: .whitespacesAndNewlines), steps)
    }

    @MainActor static func main() async throws {
        let port = Int(CommandLine.arguments[1])!
        let home = URL(fileURLWithPath: CommandLine.arguments[2])
        let provider = LocalAtlasProvider(port: port)
        var options = AIRequestOptions(model: "qwen3:4b", effort: "low", systemPrompt: "Test", webSearch: false)
        options.toolDefinitionsJSON = try JSONSerialization.data(withJSONObject: [
            ["name": "get_calendar_events", "description": "Termine", "input_schema": ["type": "object", "properties": [String: Any]()] as [String: Any]]] as [[String: Any]])
        let tools = FixtureTools()

        let health = try await provider.health()
        precondition(health.contains("qwen3:4b"), health)

        let chat = try await collect(provider, "Hallo", options, tools: tools)
        precondition(chat.text == "Hallo Robin", chat.text)

        let calculated = try await collect(provider, "Was ist 17 mal 23?", options, tools: tools)
        precondition(calculated.text == "391.", calculated.text)

        let folder = try await collect(provider, "Erstelle auf dem Schreibtisch einen Testordner", options, tools: tools)
        var isDirectory: ObjCBool = false
        precondition(FileManager.default.fileExists(atPath: home.appendingPathComponent("Desktop/Testordner").path,
                                                    isDirectory: &isDirectory) && isDirectory.boolValue, "Ordner fehlt")
        precondition(folder.steps.contains("ok:Legt den Ordner an"), "\(folder.steps)")

        let calendar = try await collect(provider, "Was steht morgen im Kalender?", options, tools: tools)
        precondition(tools.calls.contains("get_calendar_events"))
        precondition(calendar.text.contains("Zahnarzt"), calendar.text)

        tools.approve = false
        _ = try await collect(provider, "Lösche alt.txt in Dokumente", options, tools: tools)
        precondition(tools.calls.contains("atlas_confirm"))
        precondition(FileManager.default.fileExists(atPath: home.appendingPathComponent("Documents/alt.txt").path),
                     "Datei trotz Ablehnung gelöscht")
        tools.approve = true
        _ = try await collect(provider, "Lösche alt.txt in Dokumente", options, tools: tools)
        precondition(!FileManager.default.fileExists(atPath: home.appendingPathComponent("Documents/alt.txt").path),
                     "Datei trotz Zustimmung vorhanden")

        // Bereich „Learning & Evolution“: echte Übersicht vom Backend muss sich dekodieren lassen.
        var overview = try LearningOverview.decode(try await provider.learning("overview"))
        precondition(!overview.settings.enabled, "Lernzyklen müssen anfangs aus sein")
        precondition(overview.metrics.tasks >= 1, "Erfahrung fehlt: \(overview.metrics.tasks)")
        _ = try await provider.learning("settings", ["paused": true])
        overview = try LearningOverview.decode(try await provider.learning("overview"))
        precondition(overview.settings.paused, "Pause nicht gespeichert")

        var failed = false
        do { _ = try await collect(provider, "Erstelle einen Fehler-Test", options, tools: tools) } catch { failed = true }
        precondition(failed, "Modellfehler muss gemeldet werden")

        var remote = options
        remote.model = "remote-model"
        var rejected = false
        do { _ = try await collect(provider, "Hallo", remote, tools: tools) } catch { rejected = true }
        precondition(rejected, "Fremdes Modell muss abgelehnt werden")

        print("PASS Swift ⇄ Backend: Health, Streaming, direkte Rechnung, echter Ordner, App-Werkzeug-Rundreise, Bestätigung Nein/Ja, Fehlermeldung, Modell-Sperre (9 Prüfungen)")
    }
}
