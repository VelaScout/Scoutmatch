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
    /// Ansicht, die ATLAS auf Zuruf öffnen soll (die Oberfläche hat bewusst keine Knöpfe).
    private(set) var screenRequest: AppScreen?
    /// Zählt hoch, damit dieselbe Ansicht auch zweimal hintereinander geöffnet werden kann.
    private(set) var screenRequestSequence = 0

    // MARK: - Abhängigkeiten

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let provider: AIProvider
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let toolbox: AtlasToolbox
    /// Bis zu welchem Beitrag das aktuelle Gespräch schon ausgewertet (gelernt) wurde.
    @ObservationIgnored private var learnedTurnCount = 0
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
    private let maxHistoryTurns = 16
    /// Ohne Sprache wird das Zuhören nach dieser Zeit beendet.
    /// So lange hört A.T.L.A.S. nach einer Antwort weiter zu, ohne dass „Atlas“ nötig ist.
    private let noSpeechTimeout: Double = 15
    /// Fehlgeschlagene Starts der Bereitschaft in Folge – für das erneute Versuchen.
    @ObservationIgnored private var standbyFailures = 0
    /// Kurze Denk-Laute („Hm, Moment …“) in der laufenden Antwort.
    @ObservationIgnored private var fillersThisTurn = 0
    /// Das Modell hat in dieser Antwort schon etwas gesagt – dann keine zusätzlichen Denk-Laute.
    @ObservationIgnored private var modelSpokeThisTurn = false
    /// Bereits erkannte Wörter, wenn der Nutzer A.T.L.A.S. ins Wort gefallen ist.
    @ObservationIgnored private var listeningPrefix = ""
    @ObservationIgnored private var lastCaptionUpdate = Date.distantPast
    @ObservationIgnored private var micCheckTask: Task<Void, Never>?
    /// Hinweis unter dem Kern, wenn beim Zuhören kein Ton vom Mikrofon ankommt.
    private(set) var listeningHint: String?
    @ObservationIgnored private var fillerTask: Task<Void, Never>?

    // MARK: Live-Gespräch (OpenAI Realtime)

    /// Ein Live-Gespräch ist geöffnet (Audio geht an OpenAI, bis es endet).
    private(set) var isLive = false
    @ObservationIgnored private var liveSession: RealtimeSession?
    @ObservationIgnored private var liveIdleTask: Task<Void, Never>?
    @ObservationIgnored private var liveDrainTask: Task<Void, Never>?
    @ObservationIgnored private var liveClaudeTask: Task<Void, Never>?
    /// Verbindung steht (Sitzung vom Server bestätigt).
    @ObservationIgnored private var liveReady = false
    @ObservationIgnored private var liveLastError: String?
    /// Nach der laufenden Antwort beenden (Verabschiedung oder Budget erreicht).
    @ObservationIgnored private var liveEnding = false
    @ObservationIgnored private var liveBudgetReached = false
    /// Laufender `ask_atlas`-Aufruf – und ob ihm wegen einer Rückfrage schon geantwortet wurde.
    @ObservationIgnored private var liveCallID: String?
    @ObservationIgnored private var liveCallAnswered = false
    /// Nach so vielen Sekunden Ruhe endet das Live-Gespräch (danach wieder „Atlas“ sagen).
    private let liveIdleTimeout: Double = 45

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

        toolbox.openScreen = { [weak self] screen in self?.requestScreen(screen) }
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
        if isLive {
            // Tippen im Live-Gespräch: Spricht A.T.L.A.S., verstummt er – sonst endet das Gespräch.
            if state == .speaking {
                liveSession?.interrupt()
                state = .listening
            } else {
                endLive()
            }
            return
        }
        switch state {
        case .idle, .standby, .error:
            Task { await activate() }
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
        if isLive { liveSession?.interrupt() }
        fillerTask?.cancel()
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
        stopLive()
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
        stopLive()
        silenceTask?.cancel()
        recognizer.stop()
        interrupt()
        liveTranscript = trimmed
        if attachments.isEmpty, handleLocalCommand(trimmed) { return }
        respond(to: trimmed)
    }

    /// Neues Gespräch: ATLAS vergisst den bisherigen Gesprächsverlauf (das Gedächtnis bleibt).
    func startNewConversation() {
        haltEverything()
        learnFromConversation()
        history = []
        learnedTurnCount = 0
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
        learnedTurnCount = history.count
        goIdle()
    }

    // MARK: - Ansichten auf Zuruf

    func requestScreen(_ screen: AppScreen) {
        screenRequest = screen
        screenRequestSequence += 1
    }

    /// Offensichtliche Befehle wie „Öffne die Einstellungen“ sofort ausführen –
    /// ohne Umweg über das Sprachmodell. Alles andere beantwortet Claude.
    private func handleLocalCommand(_ text: String) -> Bool {
        let t = normalize(text)
        let wantsOpen = ["öffne", "öffnen", "zeig", "zeige", "geh zu", "open", "show"].contains { t.contains($0) }
        guard wantsOpen else { return false }
        let map: [(keys: [String], screen: AppScreen)] = [
            (["stimmen studio", "stimmenstudio", "eigene stimme", "voice studio"], .voiceStudio),
            (["verbindung", "connections"], .connections),
            (["einstellung", "settings"], .settings),
            (["verlauf", "history", "gespräche"], .history),
            (["gedächtnis", "memory"], .memory),
            (["berechtigung", "permission"], .permissions),
            (["aktivität", "protokoll", "activity"], .activity),
            (["aufgaben", "to do", "todo", "aufgabenliste"], .tasks),
        ]
        guard let match = map.first(where: { entry in entry.keys.contains { t.contains($0) } }) else { return false }
        requestScreen(match.screen)
        state = .speaking
        streamFinished = true
        responseText = match.screen.confirmation
        say(match.screen.confirmation)
        return true
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
                Task { await activate() }
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
        } else if PlatformBridge.isMac && settings.backgroundListening && settings.microphoneEnabled {
            // Mac mit „Im Hintergrund hören“: Fenster zu, A.T.L.A.S. wartet weiter auf „Atlas“ –
            // sichtbar am Symbol in der Menüleiste (und Apples orangem Mikrofon-Punkt).
            sceneActive = true
            learnFromConversation()
        } else {
            // Kein Mikrofon im Hintergrund – niemals heimlich zuhören.
            haltEverything()
            AudioHub.shared.shutdown()
            learnFromConversation()
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
        guard !isLive else { return }
        learnFromConversation()
        isInConversation = false
        wakeTriggered = false
        guard settings.microphoneEnabled else {
            // Mikrofon per Hauptschalter aus: nichts hört zu.
            recognizer.stop()
            inputLevel = 0
            AudioHub.shared.setPrerollEnabled(false)
            if !synthesizer.isSpeaking { AudioHub.shared.shutdown() }
            if !state.isError { state = .idle }
            return
        }
        // „Immer zuhören“: Solange die App offen ist, einfach losreden – ohne „Atlas“.
        // Im Live-Modus startet ein Gespräch dagegen erst mit „Atlas“: Vorher verlässt kein Ton das Gerät.
        if settings.alwaysListen && !settings.liveModeAvailable && sceneActive && true && !state.isError {
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard self.state == .idle || self.state == .standby, self.sceneActive else { return }
                await self.startListening(quiet: true)
            }
            if state != .listening { state = .idle }
            return
        }
        if listensForWakeWord && sceneActive && true {
            Task { await startStandby() }
        } else {
            recognizer.stop()
            inputLevel = 0
            // Ohne Wake-Word ist das Mikrofon in Ruhe komplett aus.
            if !synthesizer.isSpeaking { AudioHub.shared.shutdown() }
            if !state.isError { state = .idle }
        }
    }

    // MARK: - Wake-Word „Atlas“

    /// Wartet auf „Atlas“ – mit Wake-Word-Einstellung oder im Live-Modus.
    private var listensForWakeWord: Bool {
        settings.microphoneEnabled && (settings.wakeWordEnabled || settings.liveModeAvailable)
    }

    private func startStandby() async {
        guard listensForWakeWord, sceneActive, true, !isLive else { return }
        guard state == .idle || state == .standby || state.isError else { return }
        guard await ensurePermissions() else { return }
        // Während der Berechtigungsabfrage kann sich der Zustand geändert haben.
        guard state == .idle || state == .standby || state.isError else { return }
        do {
            liveTranscript = ""
            try recognizer.start(language: settings.language, requireOnDevice: true)
            // Live-Modus: die letzten Sekunden im Arbeitsspeicher bereithalten (nichts wird gesendet).
            AudioHub.shared.setPrerollEnabled(settings.liveModeAvailable)
            state = .standby
            standbyFailures = 0
        } catch {
            // Nie dauerhaft abschalten (sonst bliebe nur der Knopf): beim ersten Mal kurz Bescheid
            // geben, dann still im Hintergrund erneut versuchen – z. B. sobald die Spracherkennung bereit ist.
            standbyFailures += 1
            state = standbyFailures == 1 ? .error(error.localizedDescription) : .idle
            let delay = min(30, 2 * Double(standbyFailures))
            Task {
                try? await Task.sleep(for: .seconds(delay))
                guard self.listensForWakeWord, self.sceneActive, self.state == .idle || self.state.isError else { return }
                self.state = .idle
                await self.startStandby()
            }
        }
    }

    /// Text nach dem letzten „Atlas“ – oder nil, wenn das Wort nicht vorkommt.
    private func commandAfterWakeWord(_ text: String) -> String? {
        guard let range = text.range(of: #"(?i)\b(a[td]+ ?las+)\b"#, options: [.regularExpression, .backwards])
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

    func startListening(prefix: String = "", quiet: Bool = false) async {
        guard settings.microphoneEnabled else {
            state = .error("Das Mikrofon ist ausgeschaltet. Schalten Sie es in der Menüleiste oder den Einstellungen wieder ein – oder schreiben Sie mir.")
            return
        }
        guard await ensurePermissions() else { return }
        do {
            listeningPrefix = prefix
            liveTranscript = prefix
            wakeTriggered = false
            listenAfterSpeech = false
            try recognizer.start(language: settings.language)
            state = .listening
            isInConversation = true
            if !quiet { Haptics.soft() }
            scheduleSilenceTimer(after: noSpeechTimeout)
            startMicCheck()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func handleTranscript(_ text: String) {
        switch state {
        case .standby:
            guard let command = commandAfterWakeWord(text) else { return }
            // „Atlas“ erkannt – im Live-Modus übernimmt ab hier das Live-Gespräch.
            if settings.liveModeAvailable {
                // Erkennung sofort anhalten; der Vorlauf läuft im Audio-Hub weiter.
                recognizer.stop()
                state = .listening
                Haptics.soft()
                Task {
                    if await self.startLive(usePreroll: true) { return }
                    self.state = .idle
                    self.goIdle()
                }
                return
            }
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
                liveTranscript = listeningPrefix.isEmpty ? text : listeningPrefix + " " + text
            }
            listeningHint = nil
            // Nach jeder neuen Erkennung beginnt die Pausenerkennung von vorn.
            scheduleSilenceTimer(after: settings.silenceTimeout)
        case .confirming:
            handleConfirmationSpeech(text)
        case .thinking, .speaking:
            handleBargeIn(text)
        default:
            break
        }
    }

    // MARK: - Unterbrechen per Stimme

    private static let stopWords: Set<String> = [
        "stopp", "stop", "halt", "warte", "ruhe", "still", "pause", "atlas", "moment", "aufhören", "hör",
    ]
    private static let fillerWords: Set<String> = ["bitte", "mal", "doch", "jetzt", "kurz", "ok", "okay", "auf", "ja", "nein"]

    /// Während A.T.L.A.S. denkt oder spricht, hört er weiter zu (mit Echo-Unterdrückung).
    private func startBargeInListening() {
        // Nur mit Echo-Unterdrückung – sonst würde A.T.L.A.S. sich selbst hören und unterbrechen.
        guard settings.bargeIn, permissionsGranted, sceneActive, AudioHub.shared.echoCancellationActive else { return }
        try? recognizer.start(language: settings.language)
    }

    /// Sagt der Nutzer „Stopp“ oder etwas Neues, verstummt A.T.L.A.S. sofort und hört zu.
    private func handleBargeIn(_ text: String) {
        let words = normalize(text).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return }
        // Nur die letzten Wörter zählen – und nichts, was A.T.L.A.S. selbst gerade gesagt hat.
        let echo = Set(normalize(synthesizer.spokenLog).split(separator: " ").map(String.init))
        let recent = words.suffix(6).filter { !echo.contains($0) }
        let hasStop = recent.contains { Self.stopWords.contains($0) }
        let userIsTalking = recent.count >= 3 && AudioMeter.shared.input > 0.3
        guard hasStop || userIsTalking else { return }

        let onlyStop = recent.allSatisfy { Self.stopWords.contains($0) || Self.fillerWords.contains($0) }
        interrupt()
        Haptics.soft()
        let prefix = onlyStop ? "" : recent.joined(separator: " ")
        Task { await self.startListening(prefix: prefix) }
    }

    /// Prüft beim Zuhören, ob das Mikrofon überhaupt Ton liefert, und sagt sonst, woran es liegt.
    private func startMicCheck() {
        micCheckTask?.cancel()
        _ = AudioMeter.shared.takeInputPeak()
        micCheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled, self.state == .listening else { return }
            let peak = AudioMeter.shared.takeInputPeak()
            if peak < 0.02 {
                self.listeningHint = PlatformBridge.isMac
                    ? "Ich höre nichts vom Mikrofon. Bitte prüfen: Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon → A.T.L.A.S. an, und Systemeinstellungen → Ton → Eingang: das richtige Mikrofon."
                    : "Ich höre nichts vom Mikrofon. Bitte prüfen: Einstellungen → A.T.L.A.S. → Mikrofon an."
            } else if self.listeningHint?.hasPrefix("Ich höre nichts") == true {
                self.listeningHint = nil
            }
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
            if let error, liveTranscript.trimmingCharacters(in: .whitespaces).isEmpty {
                // Fehler der Spracherkennung sichtbar machen statt still neu zu starten.
                let nsError = error as NSError
                listeningHint = "Spracherkennung: \(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
                silenceTask?.cancel()
                recognizer.stop()
                state = .idle
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard self.state == .idle else { return }
                    self.goIdle()
                }
                return
            }
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
        case .thinking, .speaking:
            // Weiter auf Unterbrechungen achten.
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                if self.state == .thinking || self.state == .speaking, !self.recognizer.isRunning {
                    self.startBargeInListening()
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
        // Beim Dauerzuhören einzelne Geräusche oder „Äh“ überhören.
        if settings.alwaysListen, !wakeTriggered, attachments.isEmpty,
           spoken.split(separator: " ").count < 2, commandAfterWakeWord(spoken) == nil {
            liveTranscript = ""
            goIdle()
            return
        }
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
            say(["Alles klar\(settings.sirSuffix).", "Okay, bis später.", "Gern geschehen."].randomElement() ?? "Alles klar.")
            return
        }

        Haptics.light()
        if handleLocalCommand(spoken) { return }
        respond(to: spoken)
    }

    private func acknowledge() {
        state = .speaking
        streamFinished = true
        isInConversation = true
        listenAfterSpeech = true
        let phrase = settings.language == .german
            ? (["Ja\(settings.sirSuffix)?", "Was gibt's?", "Ja, ich höre?", "Hm?"].randomElement() ?? "Ja?")
            : (["Yes\(settings.sirSuffix)?", "What's up?", "I'm listening."].randomElement() ?? "Yes?")
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
        if isLive {
            // Die Live-Stimme fragt nach und meldet die Antwort über confirm_pending_action.
            askLiveForConfirmation(request)
        } else {
            say(request.spokenPrompt)
        }

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
        guard attachments.isEmpty else {
            state = .error("Qwen3 verarbeitet hier Text. Bitte entfernen Sie Fotos/PDFs und fügen Sie den gewünschten Text ein.")
            return
        }
        guard userText.count <= 3800 else {
            state = .error("Bitte kürzen Sie die Nachricht auf höchstens 3800 Zeichen.")
            return
        }
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
            systemPrompt: Persona.systemPrompt(Persona.context(settings: settings, memories: memories,
                                                              recentActivity: settings.memoryEnabled ? recentActivity() : [])),
            webSearch: settings.webSearchEnabled,
            toolDefinitionsJSON: ToolCatalog.definitionsJSON(memoryEnabled: settings.memoryEnabled, deviceTools: toolsOn)
        )
        let turns = trimmedHistory()
        let tools: (any ToolExecuting)? = toolbox
        let premiumVoice = settings.premiumVoiceConfig != nil

        generation += 1
        let currentGeneration = generation
        scheduleThinkingFiller(generation: currentGeneration)
        startBargeInListening()

        responseTask = Task { [weak self] in
            guard let self else { return }
            var full = ""
            // Premium-Stimme: größere Abschnitte – klingt fließender und spart Ladepausen.
            var chunker = premiumVoice
                // KI-Stimme: erster Satz sofort, danach der ganze Rest am Stück – so setzt sie
                // Pausen und Betonung über die ganze Antwort natürlich statt Satz für Satz.
                ? SentenceChunker(firstMinimum: 60, minimum: 1_500)
                : SentenceChunker(firstMinimum: 40, minimum: 260)
            do {
                for try await event in self.provider.runTurn(history: turns, options: options, tools: tools) {
                    guard self.generation == currentGeneration, !Task.isCancelled else { break }
                    switch event {
                    case .text(let delta):
                        full += delta
                        // Untertitel höchstens ~8× pro Sekunde aktualisieren – schont die Animation.
                        if Date.now.timeIntervalSince(lastCaptionUpdate) > 0.12 {
                            self.responseText = SpeechTextCleaner.clean(full)
                            self.lastCaptionUpdate = .now
                        }
                        for sentence in chunker.feed(delta) {
                            self.modelSpokeThisTurn = true
                            self.say(sentence)
                        }
                    case .toolStarted(let name):
                        // Angefangene Sätze vor der Werkzeugnutzung aussprechen.
                        // Kurze Vorrede vor einer Suche („Ich schau mal nach …“) nicht vorlesen –
                        // die Wartezeit überbrückt A.T.L.A.S. selbst; so klingt es nach einer Antwort.
                        if let rest = chunker.flush(), self.modelSpokeThisTurn || rest.count > 150 {
                            self.modelSpokeThisTurn = true
                            self.say(rest)
                        }
                        if Self.slowTools.contains(name) { self.sayFiller(.tool) }
                        if !full.isEmpty { full += " " }
                        self.statusDetail = ToolCatalog.statusText(for: name)
                    case .toolFinished:
                        self.statusDetail = nil
                    case .searching:
                        // Kurze Vorrede vor einer Suche („Ich schau mal nach …“) nicht vorlesen –
                        // die Wartezeit überbrückt A.T.L.A.S. selbst; so klingt es nach einer Antwort.
                        if let rest = chunker.flush(), self.modelSpokeThisTurn || rest.count > 150 {
                            self.modelSpokeThisTurn = true
                            self.say(rest)
                        }
                        self.sayFiller(.searching)
                        if !full.isEmpty { full += " " }
                        self.statusDetail = "Recherchiert im Internet"
                    }
                }
                guard self.generation == currentGeneration, !Task.isCancelled else {
                    return
                }
                if let rest = chunker.flush() { self.say(rest) }
                self.finishResponse(full, generation: currentGeneration)
            } catch {
                self.streamFinished = true
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

    // MARK: - Denkpausen überbrücken

    private enum FillerKind { case thinking, searching, tool }

    /// Werkzeuge, die spürbar dauern – nur dann lohnt ein „Moment, ich schau nach“.
    private static let slowTools: Set<String> = [
        "list_emails", "read_email", "get_calendar_events", "list_reminders", "search_contacts",
        "get_current_location", "spotify_play",
    ]

    /// Kommt nach gut einer Sekunde noch keine Antwort, sagt A.T.L.A.S. etwas wie „Hm, Moment …“.
    private func scheduleThinkingFiller(generation turn: Int) {
        fillersThisTurn = 0
        modelSpokeThisTurn = false
        fillerTask?.cancel()
        fillerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.1))
            guard let self, !Task.isCancelled, self.generation == turn else { return }
            self.sayFiller(.thinking)
        }
    }

    private func sayFiller(_ kind: FillerKind) {
        guard settings.thinkingFillers, fillersThisTurn < 2, !modelSpokeThisTurn, state == .thinking,
              !synthesizer.isSpeaking else { return }
        fillersThisTurn += 1
        let english = settings.language == .britishEnglish
        let options: [String]
        switch kind {
        case .thinking:
            options = english
                ? ["Hm, one moment …", "Let me think …", "Okay, give me a second …"]
                : ["Hm, Moment …", "Lass mich kurz überlegen.", "Okay, Sekunde …", "Mal sehen …"]
        case .searching:
            options = english
                ? ["Let me check that quickly.", "One sec, looking it up."]
                : ["Ich schau mal schnell nach.", "Moment, ich check das kurz.", "Sekunde, ich such das raus."]
        case .tool:
            options = english ? ["One moment.", "On it."] : ["Moment, ich schau kurz nach.", "Bin dran.", "Einen Augenblick."]
        }
        say(options.randomElement() ?? options[0])
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
        guard settings.wakeWordEnabled || settings.alwaysListen || settings.liveModeEnabled else { return }
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
        if !text.isEmpty { responseText = SpeechTextCleaner.clean(text) }
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
                          rate: settings.speechRate,
                          premium: settings.premiumVoiceConfig)
    }

    private func handleSpeechFinished() {
        // Im Live-Gespräch steuert die Realtime-Sitzung den Ablauf (gleiche Audio-Leitung).
        guard !isLive else { return }
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
                // Im Live-Modus direkt ins Live-Gespräch, sonst klassisch zuhören.
                await self.activate()
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

    // MARK: - Ansagen

    /// Frei für eine Ansage: in Ruhe, in Bereitschaft oder beim Dauerzuhören, solange niemand spricht.
    private var isFree: Bool {
        state == .idle || state == .standby || (state == .listening && liveTranscript.isEmpty)
    }

    /// Kurze Ansage von A.T.L.A.S. (z. B. nach einer Übertragung) – nur, wenn er gerade frei ist.
    func announce(_ text: String) {
        responseText = text
        guard isFree || state.isError else { return }
        state = .speaking
        streamFinished = true
        isInConversation = false
        listenAfterSpeech = false
        say(text)
    }

    // MARK: - Begrüßung

    /// Kurze Begrüßung beim Öffnen, wie ein persönlicher Butler – höchstens alle drei Stunden.
    func greetOnLaunch() {
        guard settings.greetOnLaunch, sceneActive, true, isFree else { return }
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: "lastGreeting") as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(last) > 3 * 3600 else { return }
        defaults.set(Date.now, forKey: "lastGreeting")

        let text = greetingText()
        state = .speaking
        streamFinished = true
        // Nach der Begrüßung direkt zuhören – ohne dass erst „Atlas“ gesagt werden muss.
        isInConversation = true
        listenAfterSpeech = true
        responseText = text
        say(text)
    }

    private func greetingText(now: Date = .now) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let suffix = settings.sirSuffix
        let name = !suffix.isEmpty ? suffix : (settings.userName.isEmpty ? "" : ", \(settings.userName)")
        let time = DateFormatter()
        time.dateFormat = "H:mm"
        let english = settings.language == .britishEnglish

        let salutation: String
        switch hour {
        case 5..<11: salutation = english ? "Good morning" : "Guten Morgen"
        case 11..<17: salutation = english ? "Good afternoon" : "Guten Tag"
        case 17..<22: salutation = english ? "Good evening" : "Guten Abend"
        default: salutation = english ? "Burning the midnight oil" : "Noch so spät auf den Beinen"
        }
        var parts = ["\(salutation)\(name).", english ? "It's \(time.string(from: now))." : "Es ist \(time.string(from: now)) Uhr."]

        let calendar = EventKitService.shared
        if calendar.calendarAuthorized {
            let upcoming = calendar.events(from: now, days: 1)
                .filter { !$0.isAllDay && $0.start > now && Calendar.current.isDate($0.start, inSameDayAs: now) }
            if let next = upcoming.first {
                parts.append(english
                    ? "Your next appointment: \(next.title) at \(time.string(from: next.start))."
                    : "Ihr nächster Termin: \(next.title) um \(time.string(from: next.start)) Uhr.")
            } else if hour < 17 {
                parts.append(english ? "Your calendar is clear for the rest of the day." : "Ihr Kalender ist für heute frei.")
            }
        }
        let closings = english
            ? ["All systems online.", "What's the plan?", "What can I do for you?"]
            : ["Alle Systeme laufen.", "Was steht an?", "Was kann ich für Sie tun?"]
        parts.append(closings.randomElement() ?? closings[0])
        return parts.joined(separator: " ")
    }

    /// Wertet das gerade beendete Gespräch im Hintergrund aus und ergänzt das Gedächtnis.
    private func learnFromConversation() {
        guard settings.memoryEnabled, settings.autoLearn, history.count - learnedTurnCount >= 2 else { return }
        let turns = history.dropFirst(learnedTurnCount)
        learnedTurnCount = history.count
        let transcript = turns.map { turn -> String in
            // Kontextzeile mit Datum/Uhrzeit weglassen
            let text = turn.plainText.split(separator: "\n").filter { !$0.hasPrefix("[Kontext") }.joined(separator: "\n")
            return "\(turn.role == .user ? "Nutzer" : "A.T.L.A.S."): \(text)"
        }.joined(separator: "\n")
        let known = (try? modelContext.fetch(FetchDescriptor<MemoryItem>())) ?? []
        let knownTexts = known.map(\.content)
        let provider = self.provider
        Task { [weak self] in
            let insights = await LearningService.reflect(transcript: String(transcript.suffix(12_000)),
                                                         known: knownTexts, provider: provider)
            self?.apply(insights)
        }
    }

    private func apply(_ insights: [LearningService.Insight]) {
        guard !insights.isEmpty else { return }
        let items = (try? modelContext.fetch(FetchDescriptor<MemoryItem>())) ?? []
        for insight in insights {
            switch insight {
            case .add(let content, let category):
                guard !items.contains(where: { $0.content.caseInsensitiveCompare(content) == .orderedSame }) else { continue }
                modelContext.insert(MemoryItem(content: content, category: category, learned: true))
                modelContext.insert(ActivityRecord(title: "Dazugelernt", detail: content, succeeded: true))
            case .replace(let old, let new, let category):
                if let item = items.first(where: { $0.content == old || $0.content.contains(old) || old.contains($0.content) }) {
                    item.content = new
                    item.category = category.rawValue
                    item.updatedAt = .now
                    item.learned = true
                } else {
                    modelContext.insert(MemoryItem(content: new, category: category, learned: true))
                }
                modelContext.insert(ActivityRecord(title: "Gedächtnis aktualisiert", detail: new, succeeded: true))
            }
        }
        try? modelContext.save()
    }

    /// Die letzten Aktionen mit Wochentag und Uhrzeit – daraus erkennt A.T.L.A.S. Gewohnheiten.
    private func recentActivity() -> [String] {
        var descriptor = FetchDescriptor<ActivityRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 30
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE HH:mm"
        let records = (try? modelContext.fetch(descriptor)) ?? []
        return records.filter(\.succeeded).map { "\(formatter.string(from: $0.date)) \($0.title): \($0.detail.prefix(80))" }
    }

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

// MARK: - Live-Gespräch (OpenAI Realtime)

extension ConversationEngine {
    /// Tippen, Siri oder Kurzbefehl: im Live-Modus ein Live-Gespräch, sonst klassisch zuhören.
    func activate() async {
        if settings.liveModeAvailable, await startLive(usePreroll: false) { return }
        await startListening()
    }

    /// Hauptschalter für das Mikrofon (Menüleiste, Einstellungen).
    func setMicrophoneEnabled(_ enabled: Bool) {
        settings.microphoneEnabled = enabled
        if enabled {
            if state == .idle || state.isError { state = .idle; goIdle() }
        } else {
            haltEverything()
            AudioHub.shared.setPrerollEnabled(false)
            AudioHub.shared.shutdown()
            listeningHint = nil
        }
    }

    /// Live-Modus oder Hintergrund-Einstellung wurde umgeschaltet.
    func liveSettingChanged() {
        if isLive && !settings.liveModeEnabled { endLive() }
        wakeWordSettingChanged()
    }

    /// Öffnet ein Live-Gespräch. Gibt `false` zurück, wenn es nicht möglich ist
    /// (dann übernimmt der klassische Modus).
    private func startLive(usePreroll: Bool) async -> Bool {
        guard settings.liveModeAvailable, settings.microphoneEnabled, !isLive,
              true,
              let key = KeychainStore.read(.openAIAPIKey), !key.isEmpty else { return false }
        guard await ensurePermissions() else { return false }
        guard !isLive else { return true }

        silenceTask?.cancel()
        recognizer.stop()
        fillerTask?.cancel()
        responseTask?.cancel()
        synthesizer.stop()
        do {
            // Gleiche Audio-Einstellung wie in der Bereitschaft – kein Neustart, kein Haken.
            try AudioHub.shared.enableInput()
        } catch {
            return false
        }

        let memories = settings.memoryEnabled ? fetchMemories() : []
        var instructions = Persona.realtimeInstructions(Persona.context(settings: settings, memories: memories))
        let recent = history.suffix(8).map { turn -> String in
            let text = turn.plainText.split(separator: "\n").filter { !$0.hasPrefix("[Kontext") }.joined(separator: " ")
            return "\(turn.role == .user ? "Nutzer" : "A.T.L.A.S."): \(text.prefix(400))"
        }
        if !recent.isEmpty {
            instructions += "\n\nZuletzt im Gespräch:\n" + recent.joined(separator: "\n")
        }
        instructions += "\n\n" + Persona.contextLine(language: settings.language)

        let session = RealtimeSession()
        session.onEvent = { [weak self] event in self?.handleLive(event) }
        let configuration = RealtimeSession.Configuration(apiKey: key, model: settings.realtimeModel,
                                                          voice: settings.realtimeVoice,
                                                          instructions: instructions, tools: Persona.realtimeTools)
        do {
            try session.open(configuration, usePreroll: usePreroll)
        } catch {
            return false
        }
        liveSession = session
        isLive = true
        liveReady = false
        liveLastError = nil
        liveEnding = false
        liveBudgetReached = false
        isInConversation = true
        liveTranscript = ""
        listeningHint = nil
        statusDetail = nil
        state = .listening
        if !usePreroll { Haptics.soft() }
        scheduleLiveIdle()
        return true
    }

    /// Live-Gespräch beenden und zurück in die Bereitschaft („Atlas“).
    func endLive() {
        let budget = liveBudgetReached
        stopLive()
        isInConversation = false
        state = .idle
        if budget {
            announce("Das Monatsbudget für das Live-Gespräch ist erreicht. Ich mache im Sparmodus weiter.")
        } else {
            goIdle()
        }
    }

    /// Schließt die Verbindung, ohne den Ruhezustand anzustoßen.
    private func stopLive() {
        guard let session = liveSession else { return }
        liveSession = nil
        isLive = false
        liveEnding = false
        liveIdleTask?.cancel()
        liveDrainTask?.cancel()
        liveClaudeTask?.cancel()
        liveCallID = nil
        liveCallAnswered = false
        if confirmationContinuation != nil { resolveConfirmation(false) }
        session.close(notify: false)
        statusDetail = nil
        inputLevel = 0
    }

    private func handleLive(_ event: RealtimeSession.Event) {
        guard liveSession != nil else { return }
        switch event {
        case .ready:
            liveReady = true

        case .userStartedSpeaking:
            liveIdleTask?.cancel()
            liveDrainTask?.cancel()
            listeningHint = nil
            if state != .confirming { state = .listening }

        case .userStoppedSpeaking:
            if state == .listening { state = .thinking }
            // Absicherung, falls keine Antwort kommt (z. B. nur ein Geräusch).
            scheduleLiveIdle()

        case .userTranscript(let text):
            liveTranscript = text
            history.append(ChatTurn(role: .user, text: Persona.contextLine(language: settings.language) + "\n" + text))
            persist(role: .user, text: text)

        case .assistantStartedSpeaking:
            liveIdleTask?.cancel()
            if state != .confirming { state = .speaking }

        case .assistantTranscript(let text):
            let clean = SpeechTextCleaner.clean(text)
            guard !clean.isEmpty else { return }
            responseText = clean
            history.append(ChatTurn(role: .assistant, text: clean))
            persist(role: .assistant, text: clean)

        case .toolCall(let callID, let name, let arguments):
            handleLiveTool(callID: callID, name: name, arguments: arguments)

        case .responseFinished(let hadToolCalls):
            if CostTracker.shared.isOverBudget(settings.monthlyBudget) {
                liveBudgetReached = true
                liveEnding = true
            }
            // Nach einem Werkzeugaufruf folgt gleich die eigentliche Antwort.
            if !hadToolCalls || liveEnding { waitForLivePlayback() }

        case .error(let message):
            liveLastError = message
            listeningHint = message
            // Fehler schon beim Verbinden: schließen – danach übernimmt der klassische Modus.
            if !liveReady { liveSession?.close() }

        case .closed:
            let error = liveLastError
            let wasReady = liveReady
            stopLive()
            isInConversation = false
            if let error, !wasReady {
                // Verbindung kam nicht zustande: diesmal klassisch weitermachen.
                listeningHint = "Live-Gespräch nicht verfügbar (\(error)) – ich höre im klassischen Modus zu."
                state = .idle
                Task { await self.startListening() }
            } else if let error {
                state = .error(error)
                recoverFromErrorLater()
            } else {
                state = .idle
                goIdle()
            }
        }
    }

    private func handleLiveTool(callID: String, name: String, arguments: String) {
        let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
        switch name {
        case "ask_atlas":
            let task = (args["task"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            liveIdleTask?.cancel()
            liveCallID = callID
            liveCallAnswered = false
            if state != .speaking { state = .thinking }
            liveClaudeTask = Task { [weak self] in
                guard let self else { return }
                let result = await self.askClaude(task.isEmpty ? "Hallo" : task)
                guard !Task.isCancelled, self.isLive, let session = self.liveSession else { return }
                if self.liveCallID == callID && self.liveCallAnswered {
                    // Wegen einer Rückfrage wurde schon geantwortet – Ergebnis nachreichen.
                    session.sendNote("Ergebnis von A.T.L.A.S. zur Aufgabe „\(task)“: \(result)")
                } else {
                    session.sendToolOutput(callID: callID, output: result)
                }
                if self.liveCallID == callID { self.liveCallID = nil }
            }

        case "confirm_pending_action":
            let approved = args["approved"] as? Bool ?? false
            liveSession?.sendToolOutput(callID: callID, output: approved
                ? "Bestätigt. Die Aktion wird ausgeführt – das Ergebnis kommt gleich."
                : "Abgebrochen. Nichts wurde ausgeführt.")
            if confirmationContinuation != nil {
                resolveConfirmation(approved)
                state = approved ? .thinking : .speaking
            }

        case "end_conversation":
            liveEnding = true
            liveSession?.sendToolOutput(callID: callID, output: "Gespräch wird beendet.", respond: false)

        default:
            liveSession?.sendToolOutput(callID: callID, output: "Unbekanntes Werkzeug.")
        }
    }

    /// Bestätigung im Live-Gespräch: Die Live-Stimme fragt nach.
    private func askLiveForConfirmation(_ request: ConfirmationRequest) {
        guard let session = liveSession else { return }
        let text = "Bestätigung nötig: \(request.title) – \(request.detail). Frag den Nutzer kurz und klar (z. B. „\(request.spokenPrompt)“) und rufe danach confirm_pending_action mit seiner Antwort auf."
        if let callID = liveCallID, !liveCallAnswered {
            liveCallAnswered = true
            session.sendToolOutput(callID: callID, output: text)
        } else {
            session.sendNote(text)
        }
    }

    /// Claude als Gehirn: erledigt die Aufgabe mit Werkzeugen und Gedächtnis, ohne selbst zu sprechen.
    private func askClaude(_ task: String) async -> String {
        let memories = settings.memoryEnabled ? fetchMemories() : []
        let context = Persona.context(settings: settings, memories: memories,
                                      recentActivity: settings.memoryEnabled ? recentActivity() : [])
        let options = AIRequestOptions(
            model: settings.model.rawValue,
            effort: settings.effort.rawValue,
            systemPrompt: Persona.systemPrompt(context) + "\n\n" + Persona.liveDelegationNote,
            webSearch: settings.webSearchEnabled,
            toolDefinitionsJSON: ToolCatalog.definitionsJSON(memoryEnabled: settings.memoryEnabled,
                                                             deviceTools: settings.toolsEnabled)
        )
        var turns = trimmedHistory()
        turns.append(ChatTurn(role: .user, text: Persona.contextLine(language: settings.language)
            + "\n[Aufgabe aus dem Live-Gespräch] " + task))
        var full = ""
        do {
            for try await event in provider.runTurn(history: turns, options: options, tools: toolbox) {
                guard isLive, !Task.isCancelled else { break }
                switch event {
                case .text(let delta):
                    full += delta
                case .toolStarted(let name):
                    if !full.isEmpty { full += " " }
                    statusDetail = ToolCatalog.statusText(for: name)
                case .toolFinished:
                    statusDetail = nil
                case .searching:
                    if !full.isEmpty { full += " " }
                    statusDetail = "Recherchiert im Internet"
                }
            }
        } catch {
            statusDetail = nil
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return "Fehler: \(message)"
        }
        statusDetail = nil
        let text = SpeechTextCleaner.clean(full)
        return text.isEmpty ? "Erledigt." : text
    }

    /// Wartet, bis die Antwort fertig abgespielt ist, und hört dann weiter zu.
    private func waitForLivePlayback() {
        liveDrainTask?.cancel()
        liveDrainTask = Task { [weak self] in
            while !Task.isCancelled, AudioHub.shared.isPlaying {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let self, !Task.isCancelled, self.isLive else { return }
            if self.liveEnding {
                self.endLive()
                return
            }
            if self.state == .speaking || self.state == .thinking { self.state = .listening }
            self.scheduleLiveIdle()
        }
    }

    /// Ohne Gespräch endet die Live-Verbindung nach kurzer Zeit – spart Kosten.
    private func scheduleLiveIdle() {
        liveIdleTask?.cancel()
        let timeout = liveIdleTimeout
        liveIdleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self, !Task.isCancelled, self.isLive, self.state != .speaking,
                  self.liveCallID == nil, self.confirmationContinuation == nil else { return }
            self.endLive()
        }
    }
}
