import Foundation
import Observation
import SwiftData
import UIKit

/// Das Herzstück von ATLAS: steuert Zuhören → Nachdenken → Sprechen.
@MainActor
@Observable
final class ConversationEngine {
    enum State: Equatable {
        case idle
        case listening
        case thinking
        case speaking
        case error(String)

        var label: String {
            switch self {
            case .idle: return "Bereit"
            case .listening: return "Hört zu"
            case .thinking: return "Denkt nach"
            case .speaking: return "Spricht"
            case .error: return "Hinweis"
            }
        }
    }

    // MARK: - Sichtbarer Zustand (für die Oberfläche)

    private(set) var state: State = .idle
    /// Was ATLAS gerade von Ihnen versteht.
    private(set) var liveTranscript = ""
    /// Die aktuelle bzw. letzte Antwort von ATLAS.
    private(set) var responseText = ""
    /// Mikrofonpegel 0...1
    private(set) var inputLevel: Float = 0
    /// Zählt gesprochene Wörter hoch – treibt die Sprechanimation.
    private(set) var spokenWordCount = 0
    /// Ein Gespräch läuft (Gesprächsmodus aktiv).
    private(set) var isInConversation = false

    // MARK: - Abhängigkeiten

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let provider: AIProvider
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let recognizer = SpeechRecognizer()
    @ObservationIgnored private let synthesizer = SpeechSynthesizer()

    // MARK: - Interner Zustand

    @ObservationIgnored private var history: [ChatTurn] = []
    @ObservationIgnored private var conversation: ConversationRecord?
    @ObservationIgnored private var responseTask: Task<Void, Never>?
    @ObservationIgnored private var silenceTask: Task<Void, Never>?
    @ObservationIgnored private var streamFinished = true
    @ObservationIgnored private var permissionsGranted = false
    /// Zählt Anfragen hoch, damit Reste unterbrochener Antworten ignoriert werden.
    @ObservationIgnored private var generation = 0

    /// Maximal so viele Beiträge werden an das Modell geschickt (Kosten & Tempo).
    private let maxHistoryTurns = 40
    /// Ohne Sprache wird das Zuhören nach dieser Zeit beendet.
    private let noSpeechTimeout: Double = 8

    private let endPhrases = [
        "danke das ist alles", "das ist alles", "das wars", "das war's", "ende", "stopp", "tschüss",
        "auf wiedersehen", "gute nacht", "that's all", "thank you that's all", "goodbye", "stop",
    ]

    init(settings: AppSettings, provider: AIProvider, modelContext: ModelContext) {
        self.settings = settings
        self.provider = provider
        self.modelContext = modelContext

        recognizer.onTranscript = { [weak self] text in self?.handleTranscript(text) }
        recognizer.onLevel = { [weak self] level in self?.inputLevel = level }
        recognizer.onStop = { [weak self] error in self?.handleRecognizerStop(error) }
        synthesizer.onWord = { [weak self] in self?.spokenWordCount += 1 }
        synthesizer.onFinishedAll = { [weak self] in self?.handleSpeechFinished() }
    }

    // MARK: - Bedienung

    /// Haupt-Aktion beim Tippen auf ATLAS.
    func primaryAction() {
        switch state {
        case .idle, .error:
            Task { await startListening() }
        case .listening:
            finishListening()
        case .thinking, .speaking:
            // Unterbrechen und direkt wieder zuhören.
            interrupt()
            Task { await startListening() }
        }
    }

    /// Antwort abbrechen (z. B. durch Tippen während ATLAS spricht).
    func interrupt() {
        responseTask?.cancel()
        responseTask = nil
        synthesizer.stop()
        streamFinished = true
        if state == .thinking || state == .speaking { state = .idle }
    }

    /// Alles beenden: Zuhören, Sprechen und Gesprächsmodus.
    func stopAll() {
        silenceTask?.cancel()
        recognizer.stop()
        interrupt()
        isInConversation = false
        liveTranscript = ""
        inputLevel = 0
        state = .idle
    }

    /// Getippte Nachricht senden (für ruhige Umgebungen).
    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recognizer.stop()
        interrupt()
        liveTranscript = trimmed
        respond(to: trimmed)
    }

    /// Neues Gespräch: ATLAS vergisst den bisherigen Gesprächsverlauf.
    func startNewConversation() {
        stopAll()
        history = []
        conversation = nil
        responseText = ""
    }

    /// Vom Gesprächsverlauf aus fortsetzen.
    func resume(_ record: ConversationRecord) {
        stopAll()
        conversation = record
        history = record.sortedMessages.map {
            ChatTurn(role: $0.isUser ? .user : .assistant, text: $0.text)
        }
        responseText = record.sortedMessages.last(where: { !$0.isUser })?.text ?? ""
    }

    // MARK: - Zuhören

    func startListening() async {
        if !permissionsGranted {
            permissionsGranted = await SpeechRecognizer.requestPermissions()
            guard permissionsGranted else {
                state = .error(SpeechRecognizer.RecognizerError.notAuthorized.localizedDescription)
                return
            }
        }

        do {
            liveTranscript = ""
            try recognizer.start(language: settings.language)
            state = .listening
            isInConversation = true
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            scheduleSilenceTimer(after: noSpeechTimeout)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func handleTranscript(_ text: String) {
        guard state == .listening else { return }
        liveTranscript = text
        // Nach jeder neuen Erkennung beginnt die Pausenerkennung von vorn.
        scheduleSilenceTimer(after: settings.silenceTimeout)
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
        guard state == .listening else { return }
        finishListening()
    }

    /// Zuhören beenden und – falls etwas gesagt wurde – antworten.
    private func finishListening() {
        guard state == .listening else { return }
        silenceTask?.cancel()
        recognizer.stop()
        inputLevel = 0

        let spoken = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else {
            // Niemand hat gesprochen: Gesprächsmodus beenden.
            isInConversation = false
            state = .idle
            return
        }

        if isEndPhrase(spoken) {
            isInConversation = false
            state = .speaking
            streamFinished = true
            say(settings.addressAsSir ? "Sehr wohl, Sir." : "Sehr wohl.")
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        respond(to: spoken)
    }

    private func isEndPhrase(_ text: String) -> Bool {
        let normalized = text.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}' ]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return endPhrases.contains(normalized)
    }

    // MARK: - Antworten

    private func respond(to userText: String) {
        state = .thinking
        responseText = ""
        streamFinished = false

        let apiText = Persona.contextLine(language: settings.language) + "\n" + userText
        history.append(ChatTurn(role: .user, text: apiText))
        persist(role: .user, text: userText)

        let options = AIRequestOptions(
            model: settings.model.rawValue,
            effort: settings.effort.rawValue,
            systemPrompt: Persona.systemPrompt(addressAsSir: settings.addressAsSir,
                                               userName: settings.userName,
                                               language: settings.language,
                                               webSearch: settings.webSearchEnabled),
            webSearch: settings.webSearchEnabled
        )
        let turns = trimmedHistory()

        generation += 1
        let currentGeneration = generation

        responseTask = Task { [weak self] in
            guard let self else { return }
            var full = ""
            var chunker = SentenceChunker()
            do {
                for try await delta in self.provider.streamReply(history: turns, options: options) {
                    guard self.generation == currentGeneration, !Task.isCancelled else { break }
                    full += delta
                    self.responseText = SpeechTextCleaner.clean(full)
                    for sentence in chunker.feed(delta) { self.say(sentence) }
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
                self.state = .error(message)
                self.isInConversation = false
            }
        }
    }

    private func finishResponse(_ full: String, generation finished: Int) {
        // Eine neuere Anfrage läuft bereits: diese (unterbrochene) Antwort verwerfen.
        guard finished == generation else { return }
        streamFinished = true
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
        guard streamFinished, state == .speaking || state == .thinking else { return }
        if settings.conversationMode && isInConversation {
            // Gesprächsmodus: nach der Antwort automatisch weiter zuhören.
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard self.state == .speaking || self.state == .thinking else { return }
                await self.startListening()
            }
        } else {
            isInConversation = false
            state = .idle
        }
    }

    /// Nur die letzten Beiträge senden. Die Liste muss mit einer Nutzernachricht beginnen.
    private func trimmedHistory() -> [ChatTurn] {
        var turns = Array(history.suffix(maxHistoryTurns))
        while let first = turns.first, first.role != .user { turns.removeFirst() }
        return turns
    }

    // MARK: - Speichern

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
