import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Kleine Helfer, die auf iPhone und Mac unterschiedlich umgesetzt sind.
@MainActor
enum PlatformBridge {
    static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    static func open(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    /// Öffnet die Systemeinstellungen zu den Berechtigungen von ATLAS.
    static func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

/// Haptisches Feedback (nur iPhone).
@MainActor
enum Haptics {
    static func soft() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    static func light() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

extension View {
    /// Kompakter Navigationstitel (auf dem Mac ohne Wirkung).
    func atlasInlineTitle() -> some View {
        #if os(iOS)
        return self.navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }

    /// Keine automatische Großschreibung (für Schlüssel, E-Mail-Adressen).
    func atlasNoAutocapitalization() -> some View {
        #if os(iOS)
        return self.textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        return self.autocorrectionDisabled()
        #endif
    }

    /// Vollbild auf dem iPhone, Fenster-Sheet auf dem Mac.
    func atlasFullScreenCover<Content: View>(isPresented: Binding<Bool>,
                                             @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        return self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        return self.sheet(isPresented: isPresented) {
            content().frame(minWidth: 460, minHeight: 640)
        }
        #endif
    }

    /// Sinnvolle Mindestgröße für Sheets auf dem Mac.
    func atlasSheetSize() -> some View {
        #if os(macOS)
        return self.frame(minWidth: 520, minHeight: 620)
        #else
        return self
        #endif
    }
}
