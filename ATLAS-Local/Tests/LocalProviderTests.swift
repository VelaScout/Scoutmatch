import Foundation
@MainActor final class FixtureTools: ToolExecuting {
    var targets: [String] = []
    var failFirst = false
    func execute(name: String, inputJSON: Data) async -> ToolResult {
        let input = try! JSONDecoder().decode([String: String].self, from: inputJSON)
        targets.append(input["target"] ?? "")
        return ToolResult(content: failFirst ? "Abgebrochen" : "Übergeben", isError: failFirst)
    }
}
@main struct LocalProviderTests {
    @MainActor static func main() async throws {
        let port = Int(CommandLine.arguments[1])!
        let provider = LocalAtlasProvider(port: port)
        let options = AIRequestOptions(model: "qwen3:4b", effort: "low", systemPrompt: "Test", webSearch: false)
        let health = try await provider.health()
        precondition(health.contains("qwen3:4b"))
        let answer = try await provider.answer("Hallo", options: options)
        precondition(answer == "Hallo Robin")
        let calculated = try await provider.answer("calculate", options: options)
        precondition(calculated == "391.")
        for input in ["incomplete", "error", "truncated", "redirect"] {
            var rejected = false
            do { _ = try await provider.answer(input, options: options) }
            catch { rejected = true }
            precondition(rejected, "Must reject \(input)")
        }
        var remote = options
        remote.model = "remote-model"
        var rejected = false
        do { _ = try await provider.answer("Hallo", options: remote) } catch { rejected = true }
        precondition(rejected)
        let action = try await provider.actionRequest(kind: "app", target: "calculator")
        try await provider.actionConfirm(token: action.token)
        let tools = FixtureTools()
        for try await _ in provider.runTurn(history: [.init(role: .user, text: "open two")], options: options, tools: tools) {}
        precondition(tools.targets == ["calculator", "notes"])
        tools.targets = []; tools.failFirst = true
        for try await _ in provider.runTurn(history: [.init(role: .user, text: "open two")], options: options, tools: tools) {}
        precondition(tools.targets == ["calculator"])
        for input in ["open two", "bad tool"] {
            var denied = false
            do { _ = try await provider.answer(input, options: options) } catch { denied = true }
            precondition(denied)
        }
        print("PASS action approval payload, sequential tools, stop after rejection, tool allowlist, no tools in headless call")
        print("PASS: Swift bridge health, streamed text, incomplete response, server error, token limit, redirect rejection, model allowlist (8 checks, including direct calculation)")
    }
}
