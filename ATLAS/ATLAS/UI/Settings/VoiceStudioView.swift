import AVFoundation
import SwiftUI

/// Stimmen-Studio: ATLAS bekommt eine eigene, einzigartige Stimme.
/// Sie beschreiben die Stimme, ElevenLabs entwirft mehrere Varianten, Sie hören rein und wählen.
struct VoiceStudioView: View {
    @Environment(AppSettings.self) private var settings

    @State private var description = PremiumVoice.defaultVoiceDescription
    @State private var sampleText = PremiumVoice.designSampleText
    @State private var voiceName = "ATLAS"
    @State private var previews: [PremiumVoice.DesignedPreview] = []
    @State private var selectedID: String?
    @State private var playingID: String?
    @State private var player: AVAudioPlayer?
    @State private var isWorking = false
    @State private var message: String?
    @State private var savedVoiceID: String?

    private var apiKey: String? { KeychainStore.read(.elevenLabsAPIKey) }

    var body: some View {
        Form {
            if apiKey == nil {
                Section {
                    Label("Bitte zuerst unter „Premium-Stimme“ einen ElevenLabs-Schlüssel speichern.",
                          systemImage: "key")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                TextField("Beschreibung", text: $description, axis: .vertical)
                    .lineLimit(4...10)
            } header: {
                Text("1 · So soll ATLAS klingen")
            } footer: {
                Text("Auf Englisch beschrieben gelingt es am zuverlässigsten. Ändern Sie Alter, Wärme, Tempo, Akzent – zum Beispiel „deeper“, „more energetic“ oder „slightly American“.")
            }

            Section {
                TextField("Probetext", text: $sampleText, axis: .vertical)
                    .lineLimit(3...8)
                Text("\(sampleText.count) Zeichen (100–1.000)")
                    .font(.caption)
                    .foregroundStyle(sampleText.count < 100 || sampleText.count > 1000 ? .orange : .secondary)
            } header: {
                Text("2 · Probetext")
            } footer: {
                Text("Der Text mischt bewusst Deutsch und Englisch – so hören Sie sofort, ob beide Sprachen ohne Akzent klingen.")
            }

            Section {
                Button {
                    design()
                } label: {
                    if isWorking && previews.isEmpty {
                        Label("Stimmen werden entworfen …", systemImage: "hourglass")
                    } else {
                        Label(previews.isEmpty ? "Stimmen entwerfen" : "Neue Varianten entwerfen", systemImage: "waveform.badge.plus")
                    }
                }
                .disabled(apiKey == nil || isWorking || sampleText.count < 100 || sampleText.count > 1000)

                ForEach(Array(previews.enumerated()), id: \.element.id) { index, preview in
                    HStack(spacing: 12) {
                        Button {
                            play(preview)
                        } label: {
                            Image(systemName: playingID == preview.id ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(playingID == preview.id ? "Anhalten" : "Anhören")

                        Text("Variante \(index + 1)")
                        Spacer()
                        Image(systemName: selectedID == preview.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedID == preview.id ? .green : .secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = preview.id }
                }
            } header: {
                Text("3 · Anhören und auswählen")
            }

            if selectedID != nil {
                Section {
                    TextField("Name der Stimme", text: $voiceName)
                    Button {
                        save()
                    } label: {
                        Label(isWorking ? "Wird gespeichert …" : "Als ATLAS-Stimme verwenden", systemImage: "checkmark.seal")
                    }
                    .disabled(isWorking || voiceName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("4 · Übernehmen")
                } footer: {
                    Text("Die Stimme wird in Ihrem ElevenLabs-Konto gespeichert und gehört nur Ihnen.")
                }
            }

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(savedVoiceID != nil ? .green : .orange)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Stimmen-Studio")
        .atlasInlineTitle()
        .onDisappear { player?.stop() }
    }

    private func design() {
        guard let apiKey else { return }
        isWorking = true
        message = nil
        selectedID = nil
        savedVoiceID = nil
        player?.stop()
        Task {
            do {
                previews = try await PremiumVoice.designVoices(apiKey: apiKey, description: description,
                                                               sampleText: sampleText)
                if previews.isEmpty { message = "ElevenLabs hat keine Varianten geliefert. Bitte erneut versuchen." }
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isWorking = false
        }
    }

    private func play(_ preview: PremiumVoice.DesignedPreview) {
        if playingID == preview.id {
            player?.stop()
            playingID = nil
            return
        }
        try? AudioSessionManager.activate()
        player = try? AVAudioPlayer(data: preview.audio)
        player?.play()
        playingID = preview.id
        selectedID = preview.id
        let duration = player?.duration ?? 0
        Task {
            try? await Task.sleep(for: .seconds(duration + 0.2))
            if playingID == preview.id { playingID = nil }
        }
    }

    private func save() {
        guard let apiKey, let selectedID else { return }
        isWorking = true
        message = nil
        Task {
            do {
                let voiceID = try await PremiumVoice.saveDesignedVoice(
                    apiKey: apiKey, name: voiceName.trimmingCharacters(in: .whitespaces),
                    description: description, previewID: selectedID)
                settings.premiumVoiceID = voiceID
                settings.premiumVoiceEnabled = true
                savedVoiceID = voiceID
                message = "✓ ATLAS spricht ab sofort mit dieser Stimme."
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isWorking = false
        }
    }
}
