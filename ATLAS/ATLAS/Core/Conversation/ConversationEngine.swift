import Foundation
import Observation
import SwiftData

/// Das Herzstück von ATLAS: steuert Bereitschaft → Zuhören → Nachdenken → Sprechen.
@MainActor
@Observable
final class ConversationEngine {
    enum State: Equatable {
        /// Nichts aktiv, Mikrofon aus.
        case idle
        /// Wartet bei geöffneter App auf das Wort „Atlas“ (Erkennung nur auf dem Gerät).
        case standby
        case listening
        case thinking
        case speaking
        /// Wartet auf Ihre Bestätigung einer sensiblen Aktion.
        case confirming
        case error(String)

        var label: String {
            switch self {
            case .idle: return "Bereit"
            case .standby: return "Wartet auf „Atlas“"
            case .listening: return "Hört zu"
            case .thinking: return "Denkt nach"
            case .speaking: return "Spricht"
            case .confirming: return "Bitte bestätigen"
            case .error: return "Hinweis"
            }
        }

        /// Mikrofon ist eingeschaltet.
        var micActive: Bool {
            self == .listening || self == .standby || self == .confirming
        }

        var isError: Bool {
            if case .error = self { return true }
            return false
        }
    }

    // MARK: - Sichtbarer Zustand (für die Oberfläche)

    private(set) var state: State = .idle
    /// Was ATLAS gerade von Ihnen versteht.
    private(set) var liveTranscript = ""
    /// Die aktuelle bzw. letzte Antwort von ATLAS.
    private(set) var responseText = ""
    /// Was ATLAS gerade im Hintergrund tut (z. B. „Prüft Ihren Kalender“).
    private(set) var statusDetail: String?
    /// Mikrofonpegel 0...1
    private(set) var inputLevel: Float = 0
    /// Zählt gesprochene Wörter hoch – treibt die Mundbewegung.
    private(set) var spokenWordCount = 0
    /// Buchstabenzahl des aktuell gesprochenen Wortes – bestimmt, wie lange der Mund sich bewegt.
    private(set) var spokenWordLength = 0
    /// Ein Gespräch läuft (Gesprächsmodus aktiv).
    private(set) var isInConversation = false
    /// Fotos und Dokumente für die nächste Frage.
    private(set) var attachments: [Attachment] = []
    /// Offene Bestätigung (Nachricht öffnen, Gedächtnis löschen …).
    private(set) var pendingConfirmation: ConfirmationRequest?

    // MARK: - Abhängigkeiten

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let provider: AIProvider
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let toolbox: AtlasToolbox
    @ObservationIgnored private let recognizer = SpeechRecognizer()
    @ObservationIgnored private let synthesizer = SpeechSynthesizer()

    // MARK: - Interner Zustand

    @ObservationIgnored private var history: [ChatTurn] = []
    @ObservationIgnored private var conversation: ConversationRecord?
    @ObservationIgnored private var responseTask: Task<Void, Never>?
    @ObservationIgnored private var silenceTask: Task<Void, Never>?
    @ObservationIgnored private var confirmTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var streamFinished = true
    @ObservationIgnored private var permissionsGranted = false
    /// Zählt Anfragen hoch, damit Reste unterbrochener Antworten ignoriert werden.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var confirmationContinuation: CheckedContinuation<Bool, Never>?
    /// Zuhören wurde durch „Atlas“ ausgelöst – das Wake-Word wird aus dem Text entfernt.
    @ObservationIgnored private var wakeTriggered = false
    /// Nach dem Sprechen auf jeden Fall wieder zuhören (z. B. nach „Ja, Sir?“).
    @ObservationIgnored private var listenAfterSpeech = false
    @ObservationIgnored private var sceneActive = true

    /// Maximal so viele Beiträge werden an das Modell geschickt (Kosten & Tempo).
    private let maxHistoryTurns = 40
    /// Ohne Sprache wird das Zuhören nach dieser Zeit beendet.
    private let noSpeechTimeout: Double = 8

    private let endPhrases: Set<String> = [
        "danke das ist alles", "das ist alles", "das wars", "das war's", "ende", "stopp", "tschüss",
        "auf wiedersehen", "gute nacht", "danke atlas", "that's all", "thank you that's all", "goodbye", "stop",
    ]
    private let yesWords = ["ja", "jawohl", "bestätigen", "bestätige", "okay", "ok", "mach das", "gerne",
                            "öffnen", "löschen", "senden", "yes", "sure", "do it", "confirm"]
    private let noWords = ["nein", "abbrechen", "nicht", "stopp", "lieber nicht", "no", "cancel", "don't"]

    init(settings: AppSettings, provider: AIProvider, modelContext: ModelContext) {
        self.settings = settings
        self.provider = provider
        self.modelContext = modelContext
        self.toolbox = AtlasToolbox(modelContext: modelContext, settings: settings)

        toolbox.confirm = { [weak self] request in
            guard let self else { return false }
            return await self.requestConfirmation(request)
        }
        recognizer.onTranscript = { [weak self] text in self?.handleTranscript(text) }
        recognizer.onLevel = { [weak self] level in self?.inputLevel = level }
        recognizer.onStop = { [weak self] error in self?.handleRecognizerStop(error) }
        synthesizer.onWord = { [weak self] length in
            self?.spokenWordLength = length
            self?.spokenWordCount += 1
        }
        synthesizer.onFinishedAll = { [weak self] in self?.handleSpeechFinished() }
    }

    // MARK: - Bedienung

    /// Haupt-Aktion beim Tippen auf ATLAS.
    func primaryAction() {
        switch state {
        case .idle, .standby, .error:
            Task { await startListening() }
        case .listening:
            finishListening()
        case .thinking, .speaking:
            // Unterbrechen und direkt wieder zuhören.
            interrupt()
            Task { await startListening() }
        case .confirming:
            break // Bestätigung über die Knöpfe oder per Stimme
        }
    }

    /// Antwort abbrechen (z. B. durch Tippen während ATLAS spricht).
    func interrupt() {
        if confirmationContinuation != nil { resolveConfirmation(false) }
        responseTask?.cancel()
        responseTask = nil
        synthesizer.stop()
        streamFinished = true
        statusDetail = nil
        listenAfterSpeech = false
        if state == .thinking || state == .speaking || state == .confirming { state = .idle }
    }

    /// Alles beenden: Zuhören, Sprechen und Gesprächsmodus. Mit Wake-Word geht ATLAS in Bereitschaft.
    func stopAll() {
        haltEverything()
        goIdle()
    }

    private func haltEverything() {
        silenceTask?.cancel()
        recognizer.stop()
        interrupt()
        isInConversation = false
        wakeTriggered = false
        liveTranscript = ""
        inputLevel = 0
        state = .idle
    }

    /// Getippte Nachricht senden (für ruhige Umgebungen).
    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        silenceTask?.cancel()
        recognizer.stop()
        interrupt()
        liveTranscript = trimmed
        respond(to: trimmed)
    }

    /// Neues Gespräch: ATLAS vergisst den bisherigen Gesprächsverlauf (das Gedächtnis bleibt).
    func startNewConversation() {
        haltEverything()
        history = []
        conversation = nil
        responseText = ""
        attachments = []
        goIdle()
    }

    /// Vom Gesprächsverlauf aus fortsetzen.
    func resume(_ record: ConversationRecord) {
        haltEverything()
        conversation = record
        history = record.sortedMessages.map {
            ChatTurn(role: $0.isUser ? .user : .assistant, text: $0.text)
        }
        responseText = record.sortedMessages.last(where: { !$0.isUser })?.text ?? ""
        goIdle()
    }

    // MARK: - Anhänge

    func addAttachment(_ attachment: Attachment) {
        attachments.append(attachment)
    }

    func removeAttachment(_ attachment: Attachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    // MARK: - Anfragen von Siri, Kurzbefehlen und Mitteilungen

    func handle(_ request: AtlasRequest) {
        switch request {
        case .listen:
            if state == .idle || state == .standby || state.isError {
                Task { await startListening() }
            }
        case .briefing(let kind):
            haltEverything()
            let label: String
            switch kind {
            case .morning: label = "Morgendliche Tagesübersicht"
            case .evening: label = "Tagesrückblick"
            case .planTomorrow: label = "Plan für morgen"
            }
            liveTranscript = label
            isInConversation = true
            respond(to: Persona.briefingRequest(kind), displayText: label)
        case .ask(let question):
            send(text: question)
        }
    }

    // MARK: - App-Lebenszyklus

    /// Die App wurde sichtbar bzw. verlässt den Bildschirm.
    func setSceneActive(_ active: Bool) {
        sceneActive = active
        if active {
            if state == .idle { goIdle() }
        } else {
            // Kein Mikrofon im Hintergrund – niemals heimlich zuhören.
            haltEverything()
        }
    }

    /// Wake-Word wurde in den Einstellungen umgeschaltet.
    func wakeWordSettingChanged() {
        if state == .standby || state == .idle || state.isError {
            recognizer.stop()
            state = .idle
            goIdle()
        }
    }

    /// Ruhezustand: mit Wake-Word in Bereitschaft, sonst Mikrofon aus.
    private func goIdle() {
        isInConversation = false
        wakeTriggered = false
        if settings.wakeWordEnabled && sceneActive {
            Task { await startStandby() }
        } else {
            recognizer.stop()
            inputLevel = 0
            if !state.isError { state = .idle }
        }
    }

    // MARK: - Wake-Word „Atlas“

    private func startStandby() async {
        guard settings.wakeWordEnabled, sceneActive else { return }
        guard state == .idle || state == .standby || state.isError else { return }
        guard await ensurePermissions() else { return }
        // Während der Berechtigungsabfrage kann sich der Zustand geändert haben.
        guard state == .idle || state == .standby || state.isError else { return }
        do {
            liveTranscript = ""
            try recognizer.start(language: settings.language, requireOnDevice: true)
            state = .standby
        } catch {
            settings.wakeWordEnabled = false
            state = .error(error.localizedDescription)
        }
    }

    /// Text nach dem letzten „Atlas“ – oder nil, wenn das Wort nicht vorkommt.
    private func commandAfterWakeWord(_ text: String) -> String? {
        guard let range = text.range(of: #"(?i)\b(at+las+|at las)\b"#, options: [.regularExpression, .backwards])
        else { return nil }
        return String(text[range.upperBound...])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    // MARK: - Zuhören

    private func ensurePermissions() async -> Bool {
        if !permissionsGranted {
            permissionsGranted = await SpeechRecognizer.requestPermissions()
        }
        if !permissionsGranted {
            state = .error(SpeechRecognizer.RecognizerError.notAuthorized.localizedDescription)
        }
        return permissionsGranted
    }

    func startListening() async {
        guard await ensurePermissions() else { return }
        do {
            liveTranscript = ""
            wakeTriggered = false
            listenAfterSpeech = false
            try recognizer.start(language: settings.language)
            state = .listening
            isInConversation = true
            Haptics.soft()
            scheduleSilenceTimer(after: noSpeechTimeout)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func handleTranscript(_ text: String) {
        switch state {
        case .standby:
            guard let command = commandAfterWakeWord(text) else { return }
            // „Atlas“ erkannt
            wakeTriggered = true
            isInConversation = true
            state = .listening
            liveTranscript = command
            Haptics.soft()
            scheduleSilenceTimer(after: command.isEmpty ? 0.9 : settings.silenceTimeout)
        case .listening:
            if wakeTriggered {
                liveTranscript = commandAfterWakeWord(text) ?? text
            } else {
                liveTranscript = text
            }
            // Nach jeder neuen Erkennung beginnt die Pausenerkennung von vorn.
            scheduleSilenceTimer(after: settings.silenceTimeout)
        case .confirming:
            handleConfirmationSpeech(text)
        default:
            break
        }
    }

    private func scheduleSilenceTimer(after seconds: Double) {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finishListening()
        }
    }

    private func handleRecognizerStop(_ error: Error?) {
        switch state {
        case .listening:
            finishListening()
        case .standby:
            // Die Erkennung endet nach etwa einer Minute von selbst – nahtlos neu starten.
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if self.state == .standby {
                    self.state = .idle
                    await self.startStandby()
                }
            }
        default:
            break
        }
    }

    /// Zuhören beenden und – falls etwas gesagt wurde – antworten.
    private func finishListening() {
        guard state == .listening else { return }
        silenceTask?.cancel()
        recognizer.stop()
        inputLevel = 0

        let spoken = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty || !attachments.isEmpty else {
            if wakeTriggered {
                // Nur „Atlas“ gesagt → „Ja, Sir?“ und zuhören.
                wakeTriggered = false
                acknowledge()
            } else {
                goIdle()
            }
            return
        }
        wakeTriggered = false

        if isEndPhrase(spoken) {
            state = .speaking
            streamFinished = true
            isInConversation = false
            say("Sehr wohl\(settings.sirSuffix).")
            return
        }

        Haptics.light()
        respond(to: spoken)
    }

    private func acknowledge() {
        state = .speaking
        streamFinished = true
        isInConversation = true
        listenAfterSpeech = true
        let phrase = settings.language == .german ? "Ja\(settings.sirSuffix)?" : "Yes\(settings.sirSuffix)?"
        say(phrase)
    }

    private func isEndPhrase(_ text: String) -> Bool {
        endPhrases.contains(normalize(text))
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}' ]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Bestätigungen

    private func requestConfirmation(_ request: ConfirmationRequest) async -> Bool {
        silenceTask?.cancel()
        recognizer.stop()
        statusDetail = nil
        pendingConfirmation = request
        state = .confirming
        say(request.spokenPrompt)

        confirmTimeoutTask?.cancel()
        confirmTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled else { return }
            self?.resolveConfirmation(false)
        }

        let approved = await withCheckedContinuation { continuation in
            confirmationContinuation = continuation
        }
        if state == .confirming { state = .thinking }
        return approved
    }

    /// Antwort auf eine Bestätigung (Knopf oder Stimme).
    func resolveConfirmation(_ approved: Bool) {
        confirmTimeoutTask?.cancel()
        recognizer.stop()
        pendingConfirmation = nil
        inputLevel = 0
        let continuation = confirmationContinuation
        confirmationContinuation = nil
        if approved { Haptics.success() }
        continuation?.resume(returning: approved)
    }

    private func handleConfirmationSpeech(_ text: String) {
        let normalized = " " + normalize(text) + " "
        if noWords.contains(where: { normalized.contains(" \($0) ") }) {
            resolveConfirmation(false)
        } else if yesWords.contains(where: { normalized.contains(" \($0) ") }) {
            resolveConfirmation(true)
        }
    }

    // MARK: - Antworten

    private func respond(to userText: String, displayText: String? = nil) {
        state = .thinking
        responseText = ""
        statusDetail = nil
        streamFinished = false

        var parts: [ContentPart] = attachments.map(\.contentPart)
        let question = userText.isEmpty ? defaultQuestion(for: attachments) : userText
        parts.append(.text(Persona.contextLine(language: settings.language) + "\n" + question))
        let markers = attachments.map { $0.kind == .image ? "[Foto]" : "[PDF: \($0.name)]" }.joined(separator: " ")
        let shown = displayText ?? question
        persist(role: .user, text: markers.isEmpty ? shown : "\(markers) \(shown)")
        history.append(ChatTurn(role: .user, parts: parts))
        attachments = []

        let memories = settings.memoryEnabled ? fetchMemories() : []
        let toolsOn = settings.toolsEnabled
        let options = AIRequestOptions(
            model: settings.model.rawValue,
            effort: settings.effort.rawValue,
            systemPrompt: Persona.systemPrompt(Persona.context(settings: settings, memories: memories)),
            webSearch: settings.webSearchEnabled,
            toolDefinitionsJSON: toolsOn ? ToolCatalog.definitionsJSON(memoryEnabled: settings.memoryEnabled) : nil
        )
        let turns = trimmedHistory()
        let tools: (any ToolExecuting)? = toolsOn ? toolbox : nil

        generation += 1
        let currentGeneration = generation

        responseTask = Task { [weak self] in
            guard let self else { return }
            var full = ""
            var chunker = SentenceChunker()
            do {
                for try await event in self.provider.runTurn(history: turns, options: options, tools: tools) {
                    guard self.generation == currentGeneration, !Task.isCancelled else { break }
                    switch event {
                    case .text(let delta):
                        full += delta
                        self.responseText = SpeechTextCleaner.clean(full)
                        for sentence in chunker.feed(delta) { self.say(sentence) }
                    case .toolStarted(let name):
                        // Angefangene Sätze vor der Werkzeugnutzung aussprechen.
                        if let rest = chunker.flush() { self.say(rest) }
                        if !full.isEmpty { full += " " }
                        self.statusDetail = ToolCatalog.statusText(for: name)
                    case .toolFinished:
                        self.statusDetail = nil
                    case .searching:
                        if let rest = chunker.flush() { self.say(rest) }
                        if !full.isEmpty { full += " " }
                        self.statusDetail = "Recherchiert im Internet"
                    }
                }
                guard self.generation == currentGeneration, !Task.isCancelled else {
                    self.finishResponse(full, generation: currentGeneration)
                    return
                }
                if let rest = chunker.flush() { self.say(rest) }
                self.finishResponse(full, generation: currentGeneration)
            } catch {
                self.finishResponse(full, generation: currentGeneration)
                guard self.generation == currentGeneration, !Task.isCancelled,
                      !(error is CancellationError) else { return }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.synthesizer.stop()
                self.responseText = message
                self.statusDetail = nil
                self.isInConversation = false
                self.state = .error(message)
                self.recoverFromErrorLater()
            }
        }
    }

    private func defaultQuestion(for attachments: [Attachment]) -> String {
        if attachments.contains(where: { $0.kind == .pdf }) {
            return "Bitte fasse dieses Dokument kurz zusammen und nenne die wichtigsten Punkte."
        }
        if !attachments.isEmpty { return "Bitte analysiere dieses Foto und beschreibe kurz, was wichtig ist." }
        return "Hallo"
    }

    /// Mit Wake-Word kehrt ATLAS nach einem Fehler von selbst in die Bereitschaft zurück.
    private func recoverFromErrorLater() {
        guard settings.wakeWordEnabled else { return }
        Task {
            try? await Task.sleep(for: .seconds(6))
            if self.state.isError {
                self.state = .idle
                self.goIdle()
            }
        }
    }

    private func finishResponse(_ full: String, generation finished: Int) {
        // Eine neuere Anfrage läuft bereits: diese (unterbrochene) Antwort verwerfen.
        guard finished == generation else { return }
        streamFinished = true
        statusDetail = nil
        let text = full.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            history.append(ChatTurn(role: .assistant, text: text))
            persist(role: .assistant, text: SpeechTextCleaner.clean(text))
        }
        if !synthesizer.isSpeaking, state == .thinking || state == .speaking {
            handleSpeechFinished()
        }
    }

    private func say(_ sentence: String) {
        if state == .thinking { state = .speaking }
        synthesizer.speak(sentence,
                          voiceIdentifier: settings.voiceIdentifier,
                          language: settings.language,
                          rate: settings.speechRate)
    }

    private func handleSpeechFinished() {
        if state == .confirming {
            // Frage ausgesprochen → auf „Ja“ oder „Nein“ hören.
            guard confirmationContinuation != nil else { return }
            try? recognizer.start(language: settings.language)
            return
        }
        guard streamFinished else {
            // ATLAS arbeitet noch (z. B. mit einem Werkzeug) – das Gesicht zeigt „denkt nach“.
            if state == .speaking { state = .thinking }
            return
        }
        guard state == .speaking || state == .thinking else { return }
        if listenAfterSpeech || (settings.conversationMode && isInConversation) {
            // Gesprächsmodus: nach der Antwort automatisch weiter zuhören.
            listenAfterSpeech = false
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard self.state == .speaking || self.state == .thinking else { return }
                await self.startListening()
            }
        } else {
            state = .idle
            goIdle()
        }
    }

    /// Nur die letzten Beiträge senden. Die Liste muss mit einer Nutzernachricht beginnen.
    private func trimmedHistory() -> [ChatTurn] {
        var turns = Array(history.suffix(maxHistoryTurns))
        while let first = turns.first, first.role != .user { turns.removeFirst() }
        return turns
    }

    // MARK: - Speichern

    private func fetchMemories() -> [String] {
        var descriptor = FetchDescriptor<MemoryItem>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 200
        let items = (try? modelContext.fetch(descriptor)) ?? []
        return items.map { "[\($0.category)] \($0.content)" }
    }

    private func persist(role: ChatTurn.Role, text: String) {
        if conversation == nil {
            let record = ConversationRecord(title: String(text.prefix(60)))
            modelContext.insert(record)
            conversation = record
        }
        let message = MessageRecord(role: role.rawValue, text: text)
        message.conversation = conversation
        modelContext.insert(message)
        try? modelContext.save()
    }
}
