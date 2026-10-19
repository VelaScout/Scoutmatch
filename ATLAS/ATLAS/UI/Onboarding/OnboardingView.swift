import SwiftUI

/// Erster Start: API-Schlüssel hinterlegen.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    AtlasCoreView(state: .idle, inputLevel: 0, spokenWordCount: 0)
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)

                    Text("Guten Tag.\nIch bin ATLAS.")
                        .font(.largeTitle.weight(.semibold))

                    Text("Um für Sie denken zu können, benötige ich Zugang zu meinem Sprachmodell Claude von Anthropic. Bitte hinterlegen Sie dazu Ihren persönlichen API-Schlüssel.")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("sk-ant-…", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        Text("Der Schlüssel wird ausschließlich verschlüsselt in der Keychain dieses iPhones gespeichert und nur direkt an Anthropic gesendet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        KeychainStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: .anthropicAPIKey)
                        dismiss()
                    } label: {
                        Text("Speichern und beginnen")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!apiKey.trimmingCharacters(in: .whitespaces).hasPrefix("sk-ant-"))

                    Link("Wo bekomme ich einen API-Schlüssel?",
                         destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .font(.footnote)

                    Button("Später") { dismiss() }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
        }
        .preferredColorScheme(.dark)
    }
}
