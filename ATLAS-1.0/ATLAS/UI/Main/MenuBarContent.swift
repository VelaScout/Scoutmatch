#if os(macOS)
import AppKit
import SwiftUI

/// Symbol in der Mac-Menüleiste: zeigt jederzeit, ob das Mikrofon an ist, und erlaubt,
/// es mit einem Klick abzuschalten – auch wenn das Fenster geschlossen ist.
struct MenuBarContent: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ConversationEngine.self) private var engine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusText)
        Divider()
        Button(engine.isLive ? "Gespräch beenden" : "Mit A.T.L.A.S. sprechen") { engine.primaryAction() }
            .disabled(!settings.microphoneEnabled && !engine.isLive)
        Toggle("Mikrofon", isOn: Binding(get: { settings.microphoneEnabled },
                                         set: { engine.setMicrophoneEnabled($0) }))
        Toggle("Im Hintergrund auf „Atlas“ hören", isOn: Binding(get: { settings.backgroundListening },
                                                                  set: { settings.backgroundListening = $0 }))
        Divider()
        Button("Fenster öffnen") { showWindow() }
        Button("A.T.L.A.S. beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusText: String {
        if !settings.microphoneEnabled { return "Mikrofon aus" }
        if engine.isLive { return "Live-Gespräch · \(engine.state.label)" }
        return engine.state.label
    }

    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}

/// Menüleisten-Symbol: Wellen = hört bzw. spricht, durchgestrichen = Mikrofon aus.
struct MenuBarIcon: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ConversationEngine.self) private var engine

    var body: some View {
        Image(systemName: symbol)
    }

    private var symbol: String {
        if !settings.microphoneEnabled { return "mic.slash" }
        if engine.isLive || engine.state == .listening || engine.state == .speaking { return "waveform.circle.fill" }
        if engine.state.micActive { return "waveform.circle" }
        return "circle.dashed"
    }
}
#endif
