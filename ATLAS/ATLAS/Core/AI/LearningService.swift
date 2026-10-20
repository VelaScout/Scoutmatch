import Foundation

/// Selbstständiges Lernen: Nach jedem Gespräch überlegt A.T.L.A.S. im Hintergrund, was er
/// Dauerhaftes über den Nutzer erfahren hat (Vorlieben, Gewohnheiten, Ziele, Personen …),
/// und ergänzt oder aktualisiert sein Gedächtnis. Alles bleibt in „Gedächtnis“ sichtbar,
/// als „gelernt“ markiert und jederzeit löschbar.
enum LearningService {
    enum Insight: Sendable {
        case add(String, MemoryCategory)
        case replace(old: String, new: String, MemoryCategory)
    }

    /// Wertet ein Gespräch aus. Nutzt das schnelle, günstige Modell.
    static func reflect(transcript: String, known: [String], provider: AIProvider) async -> [Insight] {
        let categories = MemoryCategory.allCases.map(\.rawValue).joined(separator: ", ")
        let system = """
        Du bist das Langzeitgedächtnis des persönlichen Assistenten A.T.L.A.S. Du liest ein Gespräch zwischen dem Nutzer und A.T.L.A.S. und hältst fest, was A.T.L.A.S. dauerhaft über den Nutzer wissen sollte, um ihm künftig besser zu helfen:
        Vorlieben und Abneigungen (auch zu Musik, Essen, Stil, Ton der Antworten), Gewohnheiten und Tagesabläufe, Ziele, Projekte, wichtige Personen und Beziehungen, Arbeitsweise, wiederkehrende Bedürfnisse.
        Regeln:
        - Nur was klar aus dem Gespräch hervorgeht oder sich deutlich zeigt. Nichts Vorübergehendes (z. B. „fragt heute nach dem Wetter“).
        - Niemals Passwörter, Zugangsdaten, PINs oder Kontonummern.
        - Nichts, was schon bekannt ist. Ist ein bekannter Eintrag veraltet oder ungenau, ersetze ihn.
        - Höchstens 3 Einträge, je ein kurzer, eigenständiger Satz in der dritten Person („Der Nutzer …“).
        Antwortformat, eine Zeile pro Eintrag, sonst nichts:
        NEU | Kategorie | Satz
        ERSETZE | Kategorie | alter Satz (genau wie bekannt) => neuer Satz
        Kategorien: \(categories)
        Gibt es nichts Neues, antworte nur: NICHTS
        """
        let knownText = known.isEmpty ? "(noch nichts)" : known.map { "- \($0)" }.joined(separator: "\n")
        let prompt = "Bereits bekannt:\n\(knownText)\n\nGespräch:\n\(transcript)"
        let options = AIRequestOptions(model: AtlasModel.haiku.rawValue, effort: AtlasEffort.low.rawValue,
                                       systemPrompt: system, webSearch: false, maxTokens: 600)
        guard let answer = try? await provider.answer(prompt, options: options) else { return [] }
        return parse(answer)
    }

    static func parse(_ answer: String) -> [Insight] {
        answer.split(separator: "\n").compactMap { rawLine -> Insight? in
            let parts = rawLine.split(separator: "|", maxSplits: 2).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 3 else { return nil }
            let category = MemoryCategory(rawValue: parts[1]) ?? .other
            switch parts[0].uppercased() {
            case "NEU":
                return parts[2].isEmpty ? nil : .add(parts[2], category)
            case "ERSETZE":
                let pair = parts[2].components(separatedBy: "=>").map { $0.trimmingCharacters(in: .whitespaces) }
                guard pair.count == 2, !pair[1].isEmpty else { return nil }
                return .replace(old: pair[0], new: pair[1], category)
            default:
                return nil
            }
        }
        .prefix(3)
        .map { $0 }
    }
}
