import SwiftUI

/// Verbindungen zu anderen Diensten: E-Mail-Postfach und Spotify.
struct ConnectionsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var mailPassword = ""
    @State private var hasMailPassword = KeychainStore.has(.mailPassword)
    @State private var mailStatus: String?
    @State private var testingMail = false

    @State private var spotifyConnected = SpotifyService.shared.isConnected
    @State private var spotifyStatus: String?
    @State private var connectingSpotify = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("Anbieter", selection: $settings.mailProvider) {
                    ForEach(MailProvider.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("E-Mail-Adresse", text: $settings.mailAddress)
                    .atlasNoAutocapitalization()
                if hasMailPassword {
                    HStack {
                        Label("Passwort sicher gespeichert", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Entfernen", role: .destructive) {
                            KeychainStore.delete(.mailPassword)
                            hasMailPassword = false
                            mailStatus = nil
                        }
                    }
                } else {
                    SecureField("App-spezifisches Passwort", text: $mailPassword)
                        .atlasNoAutocapitalization()
                    Button("Passwort speichern") {
                        KeychainStore.save(mailPassword.trimmingCharacters(in: .whitespacesAndNewlines), for: .mailPassword)
                        mailPassword = ""
                        hasMailPassword = KeychainStore.has(.mailPassword)
                    }
                    .disabled(mailPassword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button(testingMail ? "Verbindung wird geprüft …" : "Verbindung testen") { testMail() }
                    .disabled(testingMail || !hasMailPassword || settings.mailAddress.isEmpty)
                if let mailStatus {
                    Text(mailStatus).font(.footnote)
                }
            } header: {
                Text("E-Mail")
            } footer: {
                Text(settings.mailProvider.passwordHelp
                     + "\n\nA.T.L.A.S. liest Ihre Mails nur, wenn Sie danach fragen, und sendet nur nach Ihrer ausdrücklichen Bestätigung. Zum Zusammenfassen wird der Inhalt an Claude (Anthropic) übermittelt.")
            }

            Section {
                TextField("Client-ID", text: $settings.spotifyClientID)
                    .atlasNoAutocapitalization()
                if spotifyConnected {
                    HStack {
                        Label("Mit Spotify verbunden", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Trennen", role: .destructive) {
                            SpotifyService.shared.disconnect()
                            spotifyConnected = false
                        }
                    }
                } else {
                    Button(connectingSpotify ? "Anmeldung läuft …" : "Mit Spotify verbinden") { connectSpotify() }
                        .disabled(connectingSpotify || settings.spotifyClientID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let spotifyStatus {
                    Text(spotifyStatus).font(.footnote)
                }
            } header: {
                Text("Spotify (Premium)")
            } footer: {
                Text("""
                Einmalig einrichten (ca. 3 Minuten):
                1. developer.spotify.com/dashboard öffnen und mit Ihrem Spotify-Konto anmelden.
                2. „Create app“: Name „A.T.L.A.S.“, Beschreibung beliebig.
                3. Redirect URI genau so eintragen: \(SpotifyService.redirectURI)
                4. Bei „Which API/SDKs“ „Web API“ anhaken, speichern.
                5. Die „Client ID“ kopieren, oben einfügen und „Mit Spotify verbinden“ tippen.
                Ihr Spotify-Passwort sieht A.T.L.A.S. nie.
                """)
            }
        }
        .navigationTitle("Verbindungen")
        .atlasInlineTitle()
    }

    private func testMail() {
        guard let account = MailService.account(settings: settings) else { return }
        testingMail = true
        mailStatus = nil
        Task {
            do {
                try await MailService.test(account)
                mailStatus = "✓ Lesen und Senden funktionieren."
            } catch {
                mailStatus = "Fehler: " + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            testingMail = false
        }
    }

    private func connectSpotify() {
        connectingSpotify = true
        spotifyStatus = nil
        Task {
            do {
                try await SpotifyService.shared.connect(clientID: settings.spotifyClientID)
                spotifyConnected = true
                spotifyStatus = "✓ Verbunden. Sagen Sie zum Beispiel: „Spiel meine Lieblingssongs.“"
            } catch {
                spotifyStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            connectingSpotify = false
        }
    }
}
