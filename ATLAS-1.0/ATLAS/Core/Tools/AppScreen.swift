import Foundation

/// Ansichten der App, die ATLAS auf Zuruf öffnen kann – die Oberfläche selbst bleibt leer.
enum AppScreen: String, CaseIterable, Identifiable, Sendable {
    case settings, history, tasks, memory, permissions, activity, voiceStudio, connections, learning
    case photoPicker, camera, fileImporter, onboarding

    var id: String { rawValue }

    /// Kurze Bestätigung, die ATLAS spricht.
    var confirmation: String {
        switch self {
        case .settings: return "Die Einstellungen sind geöffnet."
        case .history: return "Hier ist Ihr Gesprächsverlauf."
        case .tasks: return "Hier sind Ihre Termine und Aufgaben."
        case .memory: return "Hier ist mein Gedächtnis."
        case .permissions: return "Hier sind die Berechtigungen."
        case .activity: return "Hier ist das Aktivitätsprotokoll."
        case .voiceStudio: return "Das Stimmen-Studio ist geöffnet."
        case .connections: return "Hier verbinden Sie E-Mail und Spotify."
        case .learning: return "Hier sehen Sie, was ich gelernt habe und was auf Ihre Freigabe wartet."
        case .photoPicker: return "Bitte wählen Sie ein Foto."
        case .camera: return "Die Kamera ist bereit."
        case .fileImporter: return "Bitte wählen Sie die Datei."
        case .onboarding: return "Bitte hinterlegen Sie den API-Schlüssel."
        }
    }
}
