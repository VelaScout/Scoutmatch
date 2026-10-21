import Combine
import SwiftUI

/// Einstellungen für das Live-Gespräch (OpenAI Realtime), das Mikrofon und die Kosten.
struct LiveSettingsSections: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ConversationEngine.self) private var engine

    @State private var openAIKeyInput = ""
    @State private var hasOpenAIKey = KeychainStore.has(.openAIAPIKey)
    @State private var costs: [CostTracker.Source: Double] = [:]
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var confirmReset = false

    static let realtimeModels: [(id: String, name: String)] = [
        ("gpt-realtime-2.1", "Beste Qualität (gpt-realtime-2.1)"),
        ("gpt-realtime-2.1-mini", "Günstiger (gpt-realtime-2.1-mini)"),
    ]
    static let realtimeVoices: [(id: String, name: String)] = [
        ("cedar", "Cedar – ruhig, warm, männlich (empfohlen)"),
        ("marin", "Marin – klar, natürlich, weiblich"),
        ("ash", "Ash – locker, männlich"),
        ("ballad", "Ballad – sanft, britisch"),
        ("verse", "Verse – lebendig"),
        ("echo", "Echo – tief, männlich"),
        ("sage", "Sage – ruhig, weiblich"),
        ("coral", "Coral – freundlich, weiblich"),
        ("shimmer", "Shimmer – hell, weiblich"),
        ("alloy", "Alloy – neutral"),
    ]

    var body: some View {
        @Bindable var settings = settings

        Section {
            Toggle("Live-Gespräch (wie ChatGPT)", isOn: $settings.liveModeEnabled)
            if hasOpenAIKey {
                Label("OpenAI-Schlüssel ist sicher gespeichert", systemImage: "lock.fill")
                    .foregroundStyle(.green)
                Button("OpenAI-Schlüssel entfernen", role: .destructive) {
                    KeychainStore.delete(.openAIAPIKey)
                    hasOpenAIKey = false
                    engine.liveSettingChanged()
                }
            } else {
                SecureField("OpenAI-API-Schlüssel (sk-…)", text: $openAIKeyInput)
                    .atlasNoAutocapitalization()
                Button("Speichern") {
                    KeychainStore.save(openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines), for: .openAIAPIKey)
                    openAIKeyInput = ""
                    hasOpenAIKey = KeychainStore.has(.openAIAPIKey)
                    engine.liveSettingChanged()
                }
                .disabled(openAIKeyInput.isEmpty)
            }
            if settings.liveModeEnabled {
                Picker("Modell", selection: $settings.realtimeModel) {
                    ForEach(Self.realtimeModels, id: \.id) { Text($0.name).tag($0.id) }
                }
                Picker("Stimme", selection: $settings.realtimeVoice) {
                    ForEach(Self.realtimeVoices, id: \.id) { Text($0.name).tag($0.id) }
                }
                if CostTracker.shared.isOverBudget(settings.monthlyBudget) {
                    Label("Monatsbudget erreicht – A.T.L.A.S. nutzt bis Monatsende den klassischen Modus.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Live-Gespräch")
        } footer: {
            Text("Live-Gespräch: Sie sagen „Atlas“ (oder tippen auf den Kern) und reden einfach – A.T.L.A.S. antwortet mit natürlicher Stimme, lässt sich jederzeit unterbrechen und erkennt selbst, wann Sie fertig sind. Danach können Sie ohne „Atlas“ weiterreden; nach 45 Sekunden Ruhe endet das Gespräch. Für Wissen, Recherche, E-Mails, Kalender, Spotify usw. fragt die Live-Stimme im Hintergrund Claude. Erst nach „Atlas“ wird Ton an OpenAI übertragen (verschlüsselt), vorher bleibt alles auf dem Gerät. Die ChatGPT-Stimme „Arbor“ gibt es für Entwickler nicht – „Cedar“ kommt ihr am nächsten. Benötigt einen API-Schlüssel von platform.openai.com mit Guthaben (das ChatGPT-Abo zählt nicht).")
        }

        Section {
            Toggle("Mikrofon", isOn: Binding(get: { settings.microphoneEnabled },
                                             set: { engine.setMicrophoneEnabled($0) }))
            #if os(macOS)
            Toggle("Im Hintergrund auf „Atlas“ hören", isOn: $settings.backgroundListening)
            Toggle("Beim Anmelden automatisch starten", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    LaunchAtLogin.set(enabled)
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            #endif
        } header: {
            Text("Mikrofon")
        } footer: {
            Text(PlatformBridge.isMac
                 ? "Mikrofon aus: A.T.L.A.S. hört überhaupt nicht zu – schreiben geht weiterhin. Im Hintergrund: Auch bei geschlossenem Fenster wartet A.T.L.A.S. auf „Atlas“ (Erkennung nur auf dem Mac). Das Symbol in der Menüleiste zeigt jederzeit, ob das Mikrofon an ist, und schaltet es mit einem Klick aus; macOS zeigt zusätzlich den orangen Mikrofon-Punkt."
                 : "Mikrofon aus: A.T.L.A.S. hört überhaupt nicht zu – schreiben geht weiterhin. Auf dem iPhone hört A.T.L.A.S. nur zu, solange die App geöffnet ist (Apple erlaubt kein Dauerzuhören im Hintergrund).")
        }

        Section {
            HStack {
                Text("Monatsbudget")
                Spacer()
                TextField("Budget", value: $settings.monthlyBudget, format: .number.precision(.fractionLength(0...2)))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                Text("US-$")
                    .foregroundStyle(.secondary)
            }
            ForEach(CostTracker.Source.allCases, id: \.self) { source in
                LabeledContent(source.displayName, value: Self.format(costs[source] ?? 0))
            }
            LabeledContent("Diesen Monat gesamt (geschätzt)", value: Self.format(costs.values.reduce(0, +)))
                .fontWeight(.semibold)
            Button("Zähler für diesen Monat zurücksetzen", role: .destructive) { confirmReset = true }
        } header: {
            Text("Kosten & Budget")
        } footer: {
            Text("""
            Kostenlos und lokal: Wake-Word „Atlas“, Spracherkennung im klassischen Modus, Apple-Stimmen, eigene XTTS-Stimme, Gedächtnis, Verlauf und Kalender/Erinnerungen auf dem Gerät.
            Kostenpflichtig: Claude (jede Antwort, ca. 0,1–1 Cent), OpenAI-Live-Gespräch (ca. 3–15 Cent pro Gesprächsminute mit dem großen Modell, mit „mini“ etwa ein Drittel), OpenAI-Stimme im klassischen Modus (ca. 1,5 Cent pro Minute), ElevenLabs.
            Ist das Budget erreicht, schaltet A.T.L.A.S. das Live-Gespräch bis Monatsende ab und nutzt den klassischen Modus (0 = ohne Grenze). Die Zahlen sind Schätzungen aus den Verbrauchsangaben der Anbieter – maßgeblich ist Ihre Abrechnung bei Anthropic und OpenAI.
            """)
        }
        .onAppear(perform: reloadCosts)
        .onReceive(NotificationCenter.default.publisher(for: CostTracker.changedNotification)) { _ in reloadCosts() }
        .confirmationDialog("Kostenzähler zurücksetzen?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) {
                CostTracker.shared.resetCurrentMonth()
                reloadCosts()
            }
        } message: {
            Text("Setzt nur die Schätzung in A.T.L.A.S. zurück, nicht Ihre echte Abrechnung.")
        }
    }

    private func reloadCosts() {
        costs = CostTracker.shared.currentMonth()
    }

    private static func format(_ usd: Double) -> String {
        usd.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}
