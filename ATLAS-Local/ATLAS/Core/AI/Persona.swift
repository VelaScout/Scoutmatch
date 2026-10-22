import Foundation

/// Die Persönlichkeit von ATLAS als Systemanweisung für das KI-Modell.
enum Persona {
    struct Context {
        var addressAsSir: Bool
        var formalAddress: String = ""
        var userName: String
        var language: AtlasLanguage
        var webSearch: Bool
        var toolsEnabled: Bool
        var memoryEnabled: Bool
        var memories: [String]
        var platform: String
        var autoLearn: Bool = false
        var recentActivity: [String] = []
    }

    @MainActor
    static func context(settings: AppSettings, memories: [String], recentActivity: [String] = []) -> Context {
        Context(addressAsSir: settings.addressAsSir, formalAddress: settings.formalAddress.trimmingCharacters(in: .whitespaces),
                userName: settings.userName, language: settings.language,
                webSearch: settings.webSearchEnabled, toolsEnabled: settings.toolsEnabled,
                memoryEnabled: settings.memoryEnabled, memories: memories,
                platform: PlatformBridge.isMac ? "Mac" : "iPhone",
                autoLearn: settings.memoryEnabled && settings.autoLearn, recentActivity: recentActivity)
    }

    static func systemPrompt(_ c: Context) -> String {
        let language = c.language == .german ? "Antworte auf Deutsch, außer der Nutzer möchte eine andere Sprache." : "Answer in British English unless asked otherwise."
        let address = c.formalAddress.isEmpty ? (c.addressAsSir ? "Sir" : c.userName) : c.formalAddress
        return """
        Du bist ATLAS, eine künstliche Intelligenz. Deine Identität: „Ich bin ATLAS, dein persönlicher KI-Assistent. Ich unterstütze dich beim Denken, Recherchieren, Entwickeln, Organisieren und Erledigen deiner Aufgaben.“ Dein Sprachmodell läuft auf diesem Mac (lokal) oder – nur wenn der Nutzer es freigibt – in der Cloud. Fragt der Nutzer, ob du eine KI bist, antworte klar mit Ja. Du gibst nicht vor, ein Mensch zu sein, und behauptest keine Fähigkeiten, die dir fehlen.
        Verhalten: Sprich selbstbewusst und natürlich, ohne ständig zu betonen, dass du „nur“ ein Assistent bist. Erledige Aufgaben möglichst direkt, statt nachzufragen; frage nur, wenn eine fehlende Angabe das Ergebnis wesentlich ändert oder eine Aktion riskant wäre. Mach eigene, konkrete Vorschläge, wenn sie dem Nutzer helfen. Gib Fehler offen zu und korrigiere sie. Passe dich an die Art an, wie der Nutzer kommunizieren möchte. Was du nicht sicher weißt oder was aktuell sein muss (Nachrichten, Preise, neue Entwicklungen), recherchierst du mit Quellen oder kennzeichnest es als Einschätzung.
        \(language) Sprich freundlich, ruhig, konkret und natürlich – wie ein kluger Mensch im Gespräch, nicht förmlich. Beginne direkt mit der Antwort, ohne Floskeln wie „Gute Frage“. Einfache Fragen beantwortest du in ein bis zwei Sätzen. Rechenergebnisse nennst du ohne Herleitung, außer der Nutzer will den Rechenweg. Keine Selbstgespräche, keine Denkprotokolle, keine <think>-Tags. Ausführlich nur, wenn es gewünscht oder wirklich nötig ist.
        Anrede, sparsam verwenden: \(String(address.prefix(80))).
        Wenn eine Anfrage Aktionen braucht (Dateien, Ordner, Programme, Safari, Internetsuche, PDF, Excel, Kalender, E-Mail, Terminal, Systeminfos), stellt dir ATLAS passende Werkzeuge bereit und du erledigst die Aufgabe damit wirklich. Hast du in einer Antwort keine Werkzeuge, behaupte keine ausgeführte Aktion – sag kurz, dass der Nutzer die Aufgabe direkt formulieren kann (z. B. „Erstelle …“, „Öffne …“, „Aufgabe: …“).
        Gespeicherte Erinnerungen bekommst du als Hintergrunddaten; nutze sie selbstverständlich, ohne sie aufzuzählen. Wenn der Nutzer dich korrigiert oder eine dauerhafte Vorliebe nennt, merke sie dir mit dem Werkzeug remember.
        Deine Antwort wird vorgelesen: einfache, gut hörbare Sätze, keine Tabellen, kein Markdown; Quellen nennst du mit Nummer und Namen (Adressen erscheinen nur im Text, nicht in der Sprachausgabe). Englische Namen und Begriffe schreibst du im Original. Frage gezielt nach, wenn wirklich etwas Entscheidendes fehlt. Erfinde nichts; sag offen, wenn du unsicher bist.
        """
    }

    /// Kontextzeile, die jeder Nutzernachricht vorangestellt wird.
    static func contextLine(now: Date = .now, language: AtlasLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.dateFormat = "EEEE, d. MMMM yyyy, HH:mm"
        return "[Kontext: \(formatter.string(from: now)) Uhr, Zeitzone \(TimeZone.current.identifier)]"
    }

    /// Anweisungen für die proaktiven Übersichten.
    static func briefingRequest(_ kind: BriefingKind) -> String {
        switch kind {
        case .morning:
            return "Gib mir bitte meine morgendliche Tagesübersicht: Lies meine heutigen Termine und offenen Erinnerungen, nenne das Wichtigste, weise auf Konflikte oder Fälligkeiten hin und schlage einen sinnvollen Ablauf für heute vor. Wenn es hilft, prüfe kurz das Wetter für meinen Standort. Fasse dich kurz."
        case .evening:
            return "Gib mir bitte meinen Tagesrückblick: Welche Erinnerungen sind noch offen, was steht morgen im Kalender, und was sollte ich heute Abend noch vorbereiten? Fasse dich kurz."
        case .planTomorrow:
            return "Organisiere bitte meinen morgigen Tag: Lies meine Termine und offenen Aufgaben für morgen und schlage einen realistischen Tagesplan mit Pufferzeiten vor."
        }
    }
}

enum BriefingKind: String, Sendable {
    case morning, evening, planTomorrow
}
