import Foundation
import Observation

/// Anfragen von außen (Siri, Kurzbefehle, Mitteilungen) an die laufende App.
enum AtlasRequest: Equatable, Sendable {
    case listen
    case briefing(BriefingKind)
    case ask(String)
}

/// Nimmt Anfragen von Siri / Kurzbefehlen / Mitteilungen entgegen; die Oberfläche
/// arbeitet sie ab, sobald die App sichtbar ist.
@MainActor
@Observable
final class IntentRouter {
    static let shared = IntentRouter()

    private(set) var pending: AtlasRequest?
    /// Zählt hoch, damit auch dieselbe Anfrage zweimal hintereinander erkannt wird.
    private(set) var sequence = 0

    func request(_ request: AtlasRequest) {
        pending = request
        sequence += 1
    }

    func take() -> AtlasRequest? {
        defer { pending = nil }
        return pending
    }
}
