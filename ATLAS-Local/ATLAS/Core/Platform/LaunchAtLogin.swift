import Foundation
#if os(macOS)
import ServiceManagement
#endif

/// „Beim Anmelden starten“ (nur Mac) über Apples offiziellen Anmeldeobjekt-Dienst.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        #if os(macOS)
        return SMAppService.mainApp.status == .enabled
        #else
        return false
        #endif
    }

    static func set(_ enabled: Bool) {
        #if os(macOS)
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Schlägt z. B. fehl, wenn die App nicht im Programme-Ordner liegt – dann bleibt es aus.
        }
        #endif
    }
}
