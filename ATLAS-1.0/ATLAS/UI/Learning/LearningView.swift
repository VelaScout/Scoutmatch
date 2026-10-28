import Charts
import SwiftUI

// MARK: - Ansicht „ATLAS – LEARNING & EVOLUTION“

/// Was ATLAS gelernt hat, was auf Freigabe wartet, wie sich die Qualität entwickelt.
/// Alles lässt sich hier ansehen, korrigieren, zurücknehmen und löschen.
struct LearningView: View {
    @State private var overview: LearningOverview?
    @State private var error: String?
    @State private var newSkill = ""
    @State private var newTopic = ""
    @State private var editing: LearningOverview.Rule?
    @State private var editText = ""
    @State private var securityCheck: LearningOverview.Announcement?
    @State private var message: String?
    @State private var exportText: String?
    private let provider = LocalAtlasProvider()

    var body: some View {
        Form {
            Section {
                Text("Alles Dauerhafte – neue Fähigkeiten, Verbesserungen, Code-Änderungen – wird erst nach Ihrer Freigabe aktiv. Gelerntes ist gespeichertes Wissen; das Sprachmodell selbst wird nicht verändert.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let message { Text(message).font(.footnote).foregroundStyle(.cyan) }
                if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
            }
            if let overview {
                approvals(overview)
                metrics(overview)
                rules(overview)
                skills(overview)
                knowledge(overview)
                improvements(overview)
                experiences(overview)
                jobs(overview)
                settings(overview)
            } else if error == nil {
                ProgressView()
            }
        }
        .navigationTitle("ATLAS – Learning & Evolution")
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Regel bearbeiten", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Regel", text: $editText)
            Button("Speichern") {
                if let rule = editing { act("rule", ["id": rule.id, "text": editText]) }
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog("Sicherheitsrelevante Änderung", isPresented: Binding(get: { securityCheck != nil },
                                                                              set: { if !$0 { securityCheck = nil } })) {
            Button("Trotzdem übernehmen", role: .destructive) {
                if let item = securityCheck { act("decide", ["id": item.id, "approved": true, "confirm_security": true]) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Diese Änderung betrifft Berechtigungen, Sicherheitsprüfungen oder Tests. Sie wurde isoliert getestet, kann aber Schutzmechanismen verändern. Nur übernehmen, wenn Sie sicher sind.")
        }
    }

    // MARK: Abschnitte

    @ViewBuilder private func approvals(_ data: LearningOverview) -> some View {
        Section("Wartet auf Ihre Freigabe") {
            if data.announcements.isEmpty {
                Text("Nichts offen.").foregroundStyle(.secondary)
            }
            ForEach(data.announcements) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Label(item.text, systemImage: item.securityRelevant ? "exclamationmark.shield" : "sparkles")
                        .foregroundStyle(item.securityRelevant ? .orange : .primary)
                    HStack {
                        Button("Aktivieren") {
                            if item.securityRelevant { securityCheck = item } else { act("decide", ["id": item.id, "approved": true]) }
                        }.buttonStyle(.borderedProminent)
                        Button("Ablehnen") { act("decide", ["id": item.id, "approved": false]) }.buttonStyle(.bordered)
                    }
                }.padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder private func metrics(_ data: LearningOverview) -> some View {
        let m = data.metrics
        Section("Kennzahlen (letzte 30 Tage)") {
            row("Aufgaben mit Werkzeugen", "\(m.tasks)")
            row("Erfolgsquote komplexer Aufgaben", percent(m.successRate))
            row("Zuverlässigkeit der Werkzeuge", percent(m.toolReliability))
            row("Durchschnittliche Dauer", m.avgDurationS.map { String(format: "%.1f s", $0) } ?? "–")
            row("Wiederholte Fehler", "\(m.repeatedErrors)")
            row("Korrekturen durch Sie", "\(m.corrections)")
            row("Gedächtnis korrekt (ohne Nachbesserung)", percent(m.memoryCorrectness))
            row("Fähigkeiten aktiv / getestet", "\(data.skills.filter { $0.status == "aktiv" }.count) / "
                + "\(data.skills.filter { ["aktiv", "getestet", "archiviert"].contains($0.status) }.count)")
            let points = data.history.filter { $0.successRate != nil }
            if points.count >= 2 {
                Chart(points) { point in
                    LineMark(x: .value("Tag", point.day), y: .value("Erfolg", (point.successRate ?? 0) * 100))
                        .foregroundStyle(.cyan)
                }
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("Erfolgsquote %")
                .frame(height: 140)
            } else {
                Text("Der Verlauf erscheint, sobald an mindestens zwei Tagen ausgewertet wurde.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(m.topErrors.enumerated()), id: \.offset) { _, error in
                Text("Häufiger Fehler: \(error.tool) (\(error.kind)) – \(error.count)×").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func rules(_ data: LearningOverview) -> some View {
        Section("Gelernte Regeln und Vorlieben") {
            if data.rules.isEmpty { Text("Noch keine. Korrigieren Sie mich einfach, z. B. „Nein, speichere ab jetzt immer in Dokumente.“").foregroundStyle(.secondary) }
            ForEach(data.rules) { rule in
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.text).strikethrough(rule.active == 0)
                    Text("\(rule.kind == "verbesserung" ? "Verbesserung" : "Korrektur") · \(rule.scope == "dauerhaft" ? "gilt immer" : "für ähnliche Aufgaben") · \(rule.uses)× genutzt")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(rule.active == 1 ? "Ausschalten" : "Einschalten") { act("rule", ["id": rule.id, "active": rule.active == 0]) }
                        Button("Bearbeiten") { editText = rule.text; editing = rule }
                        Button("Löschen", role: .destructive) { act("delete", ["kind": "rules", "id": rule.id]) }
                    }.buttonStyle(.borderless).font(.caption)
                }
            }
        }
    }

    @ViewBuilder private func skills(_ data: LearningOverview) -> some View {
        Section("Fähigkeiten, die ATLAS selbst entwickelt hat") {
            HStack {
                TextField("Neue Fähigkeit, z. B. PowerPoint-Präsentationen erstellen", text: $newSkill)
                Button("Lernen") { act("job", ["kind": "skill", "text": newSkill]); newSkill = "" }
                    .disabled(newSkill.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(data.skills.filter { $0.status != "verworfen" }) { skill in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(skill.name) · v\(skill.version) · \(statusText(skill.status))").font(.subheadline.weight(.medium))
                    Text(skill.description).font(.caption).foregroundStyle(.secondary)
                    if skill.status == "aktiv" {
                        HStack {
                            Button("Auf vorige Version zurück") { act("skill", ["name": skill.name, "do": "rollback"]) }
                            Button("Deaktivieren", role: .destructive) { act("skill", ["name": skill.name, "do": "disable"]) }
                        }.buttonStyle(.borderless).font(.caption)
                    }
                }
            }
            let discarded = data.skills.filter { $0.status == "verworfen" }.count
            if discarded > 0 { Text("\(discarded) Versuche mit fehlgeschlagenen Tests wurden verworfen.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func knowledge(_ data: LearningOverview) -> some View {
        Section("Wissen (mit Quellen)") {
            HStack {
                TextField("Thema, z. B. Unternehmensbewertung", text: $newTopic)
                Button("Lernen") { act("job", ["kind": "topic", "text": newTopic]); newTopic = "" }
                    .disabled(newTopic.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(data.topics) { topic in
                NavigationLink {
                    TopicFactsView(topic: topic)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topic.topic).font(.subheadline.weight(.medium))
                        Text("\(statusText(topic.status)) · \(topic.facts) Aussagen · \(topic.sources) Quellen").font(.caption).foregroundStyle(.secondary)
                        if !topic.gaps.isEmpty { Text("Lücken: " + topic.gaps.prefix(2).joined(separator: "; ")).font(.caption2).foregroundStyle(.orange) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func improvements(_ data: LearningOverview) -> some View {
        Section("Verbesserungen und Code-Änderungen") {
            if data.hints.isEmpty && data.codeChanges.isEmpty { Text("Noch keine.").foregroundStyle(.secondary) }
            ForEach(data.hints) { hint in
                VStack(alignment: .leading, spacing: 4) {
                    Text(hint.text).font(.subheadline)
                    Text("\(statusText(hint.status))\(hint.result.isEmpty ? "" : " · " + hint.result)").font(.caption).foregroundStyle(.secondary)
                    if hint.status == "aktiv" { Button("Zurücknehmen") { act("hint/rollback", ["id": hint.id]) }.buttonStyle(.borderless).font(.caption) }
                }
            }
            ForEach(data.codeChanges) { change in
                VStack(alignment: .leading, spacing: 4) {
                    Label(change.title, systemImage: change.securityRelevant == 1 ? "exclamationmark.shield" : "chevron.left.forwardslash.chevron.right")
                    Text("\(statusText(change.status)) · \(change.files.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                    if change.status == "aktiv" { Button("Vorherigen Stand wiederherstellen") { act("code/rollback", ["id": change.id]) }.buttonStyle(.borderless).font(.caption) }
                }
            }
        }
    }

    @ViewBuilder private func experiences(_ data: LearningOverview) -> some View {
        Section("Erfahrungen (neueste)") {
            ForEach(data.experiences.prefix(15)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Label(item.goal, systemImage: icon(item)).foregroundStyle(item.outcome == "erfolg" ? Color.primary : .orange)
                    Text(item.lesson).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("War richtig") { act("confirm", ["id": item.id, "good": true]) }
                        Button("War falsch") { act("confirm", ["id": item.id, "good": false]) }
                        Button("Löschen", role: .destructive) { act("delete", ["kind": "experiences", "id": item.id]) }
                    }.buttonStyle(.borderless).font(.caption)
                }
            }
        }
    }

    @ViewBuilder private func jobs(_ data: LearningOverview) -> some View {
        Section("Lernaufträge") {
            if data.jobs.isEmpty { Text("Keine.").foregroundStyle(.secondary) }
            ForEach(data.jobs.prefix(10)) { job in
                HStack {
                    Text("\(jobName(job.kind)) · \(statusText(job.status))\(job.origin == "zyklus" ? " · automatisch" : "")")
                    Spacer()
                    if job.status == "wartet" || job.status == "läuft" {
                        Button("Abbrechen") { act("cancel", ["id": job.id]) }.buttonStyle(.borderless).font(.caption)
                    }
                }
            }
        }
    }

    @ViewBuilder private func settings(_ data: LearningOverview) -> some View {
        let s = data.settings
        Section {
            Toggle("Eigenständige Lernzyklen", isOn: Binding(get: { s.enabled }, set: { act("settings", ["enabled": $0]) }))
            Toggle("Pausiert", isOn: Binding(get: { s.paused }, set: { act("settings", ["paused": $0]) }))
            Stepper("Rechenzeit pro Tag: \(s.maxMinutesPerDay) min (heute \(Int(data.usedMinutesToday)))",
                    value: Binding(get: { s.maxMinutesPerDay }, set: { act("settings", ["max_minutes_per_day": $0]) }),
                    in: 5...600, step: 5)
            Toggle("Internet für Lernaufträge", isOn: Binding(get: { s.allowNetwork }, set: { act("settings", ["allow_network": $0]) }))
            Button("Jetzt Fehler auswerten") { act("job", ["kind": "analyse"]) }
            Button("Trainingsdaten exportieren") { Task { await export() } }
            if let exportText {
                ShareLink(item: exportText, preview: SharePreview("atlas-training.jsonl")) { Label("Export teilen", systemImage: "square.and.arrow.up") }
            }
        } header: {
            Text("Lernzyklen")
        } footer: {
            Text("Kosten: keine – ATLAS nutzt nur lokale Modelle und frei zugängliche Webseiten. Ein Modelltraining findet nicht automatisch statt; der Export enthält nur bestätigte Beispiele.")
        }
    }

    // MARK: Hilfen

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary).monospacedDigit() }
    }

    private func percent(_ value: Double?) -> String { value.map { "\(Int(($0 * 100).rounded())) %" } ?? "–" }

    private func icon(_ item: LearningOverview.Experience) -> String {
        if item.corrected == 1 { return "arrow.uturn.backward.circle" }
        switch item.outcome {
        case "erfolg": return item.verified == 1 ? "checkmark.seal" : "checkmark.circle"
        case "teilweise": return "circle.lefthalf.filled"
        default: return "xmark.circle"
        }
    }

    private func jobName(_ kind: String) -> String {
        ["skill": "Fähigkeit entwickeln", "topic": "Thema lernen", "analyse": "Fehleranalyse", "code": "Code verbessern"][kind] ?? kind
    }

    private func statusText(_ status: String) -> String {
        ["aktiv": "aktiv", "getestet": "getestet, wartet auf Freigabe", "archiviert": "frühere Version", "zurueckgesetzt": "zurückgesetzt",
         "wartet": "wartet", "läuft": "läuft", "fertig": "fertig", "fehlgeschlagen": "fehlgeschlagen", "abgebrochen": "abgebrochen",
         "blockiert": "blockiert (Internet aus)", "abgelehnt": "abgelehnt", "deaktiviert": "deaktiviert", "gelernt": "gelernt",
         "in_arbeit": "in Arbeit", "verworfen": "verworfen", "braucht_paket": "braucht Bibliothek"][status] ?? status
    }

    private func act(_ action: String, _ object: [String: Any]) {
        Task {
            do {
                let data = try await provider.learning(action, object)
                let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                message = (reply?["message"] as? String) ?? (reply?["result"] as? String)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
            await reload()
        }
    }

    private func reload() async {
        do {
            overview = try LearningOverview.decode(try await provider.learning("overview"))
            error = nil
        } catch {
            self.error = "Übersicht nicht verfügbar: \(error.localizedDescription)"
        }
    }

    private func export() async {
        do {
            let data = try await provider.learning("export")
            let examples = ((try JSONSerialization.jsonObject(with: data)) as? [String: Any])?["examples"] as? [Any] ?? []
            exportText = try examples.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
                .joined(separator: "\n")
            message = "\(examples.count) bestätigte Beispiele exportiert."
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Aussagen eines Themas – mit Status, Quelle und Abrufdatum; korrigier- und löschbar.
struct TopicFactsView: View {
    let topic: LearningOverview.Topic
    @State private var facts: [KnowledgeFact] = []
    @State private var error: String?
    private let provider = LocalAtlasProvider()

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.orange) }
            Section { Text(topic.note).font(.footnote).foregroundStyle(.secondary) }
            ForEach(facts) { fact in
                VStack(alignment: .leading, spacing: 4) {
                    Text(fact.statement)
                    Text("\(label(fact.status)) · \(fact.sourceTitle.isEmpty ? fact.sourceUrl : fact.sourceTitle) · \(fact.retrievedAt)")
                        .font(.caption).foregroundStyle(color(fact.status))
                    if let url = URL(string: fact.sourceUrl), url.scheme == "https" || url.scheme == "http" {
                        Link("Quelle öffnen", destination: url).font(.caption)
                    }
                    HStack {
                        if fact.status != "vermutung" { Button("Als Vermutung markieren") { change(["id": fact.id, "status": "vermutung"]) } }
                        Button("Löschen", role: .destructive) { remove(fact.id) }
                    }.buttonStyle(.borderless).font(.caption)
                }
            }
            if !topic.gaps.isEmpty {
                Section("Wissenslücken") { ForEach(topic.gaps, id: \.self) { Text($0) } }
            }
        }
        .navigationTitle(topic.topic)
        .task { await load() }
    }

    private func label(_ status: String) -> String {
        ["belegt": "belegt (1 Quelle)", "mehrfach_belegt": "mehrfach belegt", "vermutung": "Vermutung/Meinung",
         "widerspruch": "Widerspruch zwischen Quellen"][status] ?? status
    }

    private func color(_ status: String) -> Color {
        switch status {
        case "mehrfach_belegt": return .green
        case "widerspruch": return .orange
        case "vermutung": return .yellow
        default: return .secondary
        }
    }

    private func load() async {
        do {
            let data = try await provider.learning("facts", ["id": topic.id])
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            struct Reply: Decodable { let facts: [KnowledgeFact] }
            facts = try decoder.decode(Reply.self, from: data).facts
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func change(_ object: [String: Any]) {
        Task { _ = try? await provider.learning("fact", object); await load() }
    }

    private func remove(_ id: Int) {
        Task { _ = try? await provider.learning("delete", ["kind": "fact", "id": id]); await load() }
    }
}
