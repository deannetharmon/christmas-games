import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Event.createdAt, order: .reverse)
    private var events: [Event]

    @State private var showAddEvent = false

    @AppStorage("didSeedRoster_v2") private var didSeedRoster = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(events) { event in
                    NavigationLink {
                        EventDetailView(event: event)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.name).font(.headline)
                            Text(event.statusRaw.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteEvents)
            }
            .navigationTitle("Christmas Games")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Event") { showAddEvent = true }
                }
            }
            .sheet(isPresented: $showAddEvent) {
                AddEventSheet()
            }
            .task {
                guard !didSeedRoster else { return }
                do {
                    try SeedData.seedOrUpdateRoster(context: context)
                    didSeedRoster = true
                } catch {
                    print("Roster seed failed: \(error)")
                }
            }
        }
    }

    private func deleteEvents(at offsets: IndexSet) {
        for index in offsets { context.delete(events[index]) }
        try? context.save()
    }
}

// MARK: - Event Detail

private struct EventDetailView: View {
    @Environment(\.modelContext) private var context

    let event: Event

    @Query(sort: \GameTemplate.name)
    private var templates: [GameTemplate]

    @State private var showAddGame = false
    @State private var showPlayers = false

    @State private var message: String?
    @State private var showMessage = false

    var body: some View {
        let sortedGames = event.eventGames.sorted { $0.orderIndex < $1.orderIndex }

        List {
            Section {
                HStack { Text("Players"); Spacer(); Text("\(event.participantIds.count)").foregroundStyle(.secondary) }
                HStack { Text("Games"); Spacer(); Text("\(event.eventGames.count)").foregroundStyle(.secondary) }
                HStack { Text("Status"); Spacer(); Text(event.statusRaw.capitalized).foregroundStyle(.secondary) }
            }

            Section {
                NavigationLink("Run Game") {
                    RunGameView(event: event)
                }
                .disabled(event.eventGames.isEmpty || event.participantIds.isEmpty)
            } header: {
                Text("Host")
            }

            Section("Games") {
                ForEach(sortedGames) { eg in
                    let name = templates.first(where: { $0.id == eg.gameTemplateId })?.name ?? "Unknown Game"
                    HStack {
                        Text(name)
                        Spacer()
                        Text(eg.statusRaw.capitalized).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(event.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                lifecycleButton()
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Players") { showPlayers = true }
                Button("Add Games") { showAddGame = true }
            }
        }
        .sheet(isPresented: $showAddGame) {
            AddGameToEventSheet(event: event)
        }
        .sheet(isPresented: $showPlayers) {
            SelectEventPlayersSheet(event: event)
        }
        .alert("Message", isPresented: $showMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func lifecycleButton() -> some View {
        let engine = EventEngine(context: context)

        switch event.status {
        case .available:
            Button("Start") {
                do { try engine.startEvent(event) }
                catch { show(error) }
            }
            .disabled(event.eventGames.isEmpty || event.participantIds.isEmpty)

        case .active:
            Button("Pause") {
                do { try engine.pauseEvent(event) }
                catch { show(error) }
            }

        case .paused:
            Button("Resume") {
                do { try engine.resumeEvent(event) }
                catch { show(error) }
            }

        case .completed:
            EmptyView()
        }
    }

    private func show(_ error: Error) {
        message = error.localizedDescription
        showMessage = true
    }
}

// MARK: - Event Players Sheet

private struct SelectEventPlayersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let event: Event

    @Query(sort: \Person.displayName)
    private var people: [Person]

    @State private var selectedIds: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            List(selection: $selectedIds) {
                ForEach(activePeople) { person in
                    Text(person.displayName).tag(person.id)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Select Players")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save (\(selectedIds.count))") { save() }
                        .disabled(selectedIds.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("Select All") { selectedIds = Set(activePeople.map { $0.id }) }
                        Button("Select None") { selectedIds.removeAll() }
                    }
                }
            }
            .onAppear { selectedIds = Set(event.participantIds) }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var activePeople: [Person] {
        people.filter { $0.isActive }
    }

    private func save() {
        do {
            try EventEngine(context: context).setParticipants(for: event, participantIds: Array(selectedIds))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}


// MARK: - Run Game Screen



private struct RunGameView: View {
    @Environment(\.modelContext) private var context
    let event: Event

    @Query(sort: \Person.displayName)
    private var people: [Person]

    @Query(sort: \GameTemplate.name)
    private var templates: [GameTemplate]

    @State private var message: String?
    @State private var showMessage = false

    @State private var showPickNextGame = false

    @State private var showSwap = false
    @State private var swapOutgoing: UUID?

    @State private var showAfterRoundDialog = false
    @State private var showAfterGameDialog = false

    @State private var showWinnerPicker = false

    var body: some View {
        VStack(spacing: 12) {
            content
            Spacer()
        }
        .padding()
        .navigationTitle("Run Game")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Pick Game") { showPickNextGame = true }
            }
        }
        .sheet(isPresented: $showPickNextGame) {
            PickNextGameSheet(event: event) { selection, skipMode in
                handlePick(selection: selection, skipMode: skipMode)
            }
        }
        .alert("Message", isPresented: $showMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message ?? "Unknown error")
        }
    }

    // MARK: - Derived

    private var engine: EventEngine { EventEngine(context: context) }

    private var peopleById: [UUID: Person] {
        Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
    }

    private var currentGame: EventGame? {
        guard let id = event.currentEventGameId else { return nil }
        return event.eventGames.first(where: { $0.id == id })
    }

    private var currentTemplate: GameTemplate? {
        guard let eg = currentGame else { return nil }
        return templates.first(where: { $0.id == eg.gameTemplateId })
    }

    private var currentRound: Round? {
        guard let eg = currentGame else { return nil }
        // Current round = the latest round that has not been completed.
        return eg.rounds
            .sorted(by: { $0.roundIndex > $1.roundIndex })
            .first(where: { $0.completedAt == nil })
    }

    private func teamLabel(_ index: Int) -> String {
        let scalar = UnicodeScalar(65 + index)!   // 0->A, 1->B, ...
        return String(Character(scalar))
    }

    private func teamNames(_ team: RoundTeam) -> String {
        team.memberPersonIds
            .compactMap { peopleById[$0]?.displayName }
            .joined(separator: ", ")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let eg = currentGame, let template = currentTemplate {
            header(template: template, eventGame: eg)
            if let round = currentRound {
                roundCard(template: template, eventGame: eg, round: round)
            } else {
                Text("No active round.").foregroundStyle(.secondary)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No game is currently running.")
                .foregroundStyle(.secondary)

            Button("Start Event") {
                do { try engine.startEvent(event) }
                catch { show(error) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(event.eventGames.isEmpty || event.participantIds.isEmpty)
        }
    }

    private func header(template: GameTemplate, eventGame: EventGame) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(template.name).font(.title2).bold()

            if let instructions = (eventGame.overrideInstructions ?? template.instructions),
               !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(instructions)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Status: \(eventGame.statusRaw.capitalized)")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Players: \(event.participantIds.count)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func roundCard(template: GameTemplate, eventGame: EventGame, round: Round) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Round \(round.roundIndex + 1)").font(.headline)
                Spacer()
                if round.isLocked { Text("Locked").foregroundStyle(.secondary) }
            }

            if round.teams.isEmpty {
                Button("Generate Teams") {
                    do { try engine.generateTeams(for: round) }
                    catch { show(error) }
                }
                .buttonStyle(.borderedProminent)
            } else {
                teamsList(round: round)

                if !round.isLocked {
                    actionRowUnlocked(round: round)
                } else {
                    Button("Continue") { showAfterRoundDialog = true }
                        .buttonStyle(.borderedProminent)
                }

                previousRoundsCompact(eventGame: eventGame)
            }
        }
        .sheet(isPresented: $showSwap) {
            SwapPlayerSheet(
                event: event,
                currentRound: round,
                people: people,
                outgoing: swapOutgoing
            ) { incoming in
                do {
                    if let out = swapOutgoing {
                        try engine.swapPlayer(in: round, from: out, to: incoming)
                    }
                } catch { show(error) }
            }
        }
        .confirmationDialog("Play another round of this game?", isPresented: $showAfterRoundDialog, titleVisibility: .visible) {
            Button("Yes – New Round") {
                do { _ = try engine.createNextRound(for: eventGame) }
                catch { show(error) }
            }
            Button("No – Next Game") { showAfterGameDialog = true }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Next game", isPresented: $showAfterGameDialog, titleVisibility: .visible) {
            Button("Pick next game (random)") {
                do {
                    try engine.completeGame(eventGame)
                    if let next = try engine.pickNextGameRandom(event: event) {
                        try engine.start(event: event, eventGame: next)
                    } else {
                        event.status = .completed
                        try context.save()
                    }
                } catch { show(error) }
            }
            Button("Choose from list") { showPickNextGame = true }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func teamsList(round: Round) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(round.teams.enumerated()), id: \.element.id) { index, team in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Team \(teamLabel(index))")
                        .font(.subheadline)
                        .bold()

                    ForEach(team.memberPersonIds, id: \.self) { pid in
                        HStack {
                            Text(peopleById[pid]?.displayName ?? "Unknown")
                            Spacer()
                            if !round.isLocked {
                                Button("Swap") {
                                    swapOutgoing = pid
                                    showSwap = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func actionRowUnlocked(round: Round) -> some View {
        HStack {
            Button("Regenerate") {
                do { try engine.generateTeams(for: round) }
                catch { show(error) }
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Select Winner") {
                showWinnerPicker = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(round.teams.isEmpty)
        }
        // Reliable downward presentation (vs Menu which can pop up/down based on space)
        .confirmationDialog("Select winner", isPresented: $showWinnerPicker, titleVisibility: .visible) {
            ForEach(Array(round.teams.enumerated()), id: \.element.id) { index, t in
                Button("Team \(teamLabel(index)) — \(teamNames(t))") {
                    do {
                        try engine.finalizeRound(round, winnerTeamId: t.id)
                        showAfterRoundDialog = true
                    } catch { show(error) }
                }
            }

            Button("Tie") {
                do {
                    try engine.finalizeRound(round, winnerTeamId: nil)
                    showAfterRoundDialog = true
                } catch { show(error) }
            }

            Button("Cancel", role: .cancel) { }
        }
    }

    private func previousRoundsCompact(eventGame: EventGame) -> some View {
        let completed = eventGame.rounds
            .sorted { $0.roundIndex > $1.roundIndex }
            .filter { $0.completedAt != nil }

        return Group {
            if !completed.isEmpty {
                Divider()
                Text("Previous Rounds").font(.subheadline).bold()
                ForEach(completed.prefix(3)) { r in
                    Text(historyLine(r))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func historyLine(_ round: Round) -> String {
        if round.resultType == .tie {
            return "Round \(round.roundIndex + 1): Tie"
        }
        if let winTeam = round.winningTeamId,
           let team = round.teams.first(where: { $0.id == winTeam }) {
            let names = team.memberPersonIds
                .compactMap { peopleById[$0]?.displayName }
                .joined(separator: ", ")
            return "Round \(round.roundIndex + 1): Winner – \(names)"
        }
        return "Round \(round.roundIndex + 1): Completed"
    }

    // MARK: - Pick game handling

    private func handlePick(selection: EventGame, skipMode: PickNextGameSheet.SkipMode?) {
        do {
            if let skipMode {
                if skipMode == .pushLater { try engine.pushGameToLater(selection) }
                if skipMode == .remove { try engine.removeGameFromEvent(selection) }
                return
            }

            if let cg = currentGame { try engine.completeGame(cg) }
            try engine.start(event: event, eventGame: selection)
        } catch {
            show(error)
        }
    }

    private func show(_ error: Error) {
        message = error.localizedDescription
        showMessage = true
    }
}



// MARK: - Pick Next Game

private struct PickNextGameSheet: View {
    enum SkipMode { case pushLater, remove }

    @Environment(\.dismiss) private var dismiss

    let event: Event
    let onPick: (EventGame, SkipMode?) -> Void

    @Query(sort: \GameTemplate.name)
    private var templates: [GameTemplate]

    var body: some View {
        NavigationStack {
            List {
                Section("Eligible (not started)") {
                    ForEach(eligibleGames) { eg in
                        Button {
                            onPick(eg, nil)
                            dismiss()
                        } label: {
                            gameRow(for: eg)
                        }
                    }
                }

                Section("Skip options") {
                    ForEach(eligibleGames) { eg in
                        Menu {
                            Button("Push to later") {
                                onPick(eg, .pushLater)
                                dismiss()
                            }
                            Button("Remove from event", role: .destructive) {
                                onPick(eg, .remove)
                                dismiss()
                            }
                        } label: {
                            Text("Skip \(gameName(for: eg))")
                        }
                    }
                }
            }
            .navigationTitle("Choose Next Game")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Helpers

    private var eligibleGames: [EventGame] {
        event.eventGames
            .filter { $0.status == .notStarted }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private func template(for eg: EventGame) -> GameTemplate? {
        templates.first(where: { $0.id == eg.gameTemplateId })
    }

    private func gameName(for eg: EventGame) -> String {
        template(for: eg)?.name ?? "Unknown Game"
    }

    private func gameRow(for eg: EventGame) -> some View {
        let t = template(for: eg)

        let name = t?.name ?? "Unknown Game"
        let group = t?.groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupText = (group?.isEmpty == false) ? group! : nil

        // Prefer per-game overrides, otherwise fall back to template defaults
        let teamCount = eg.overrideTeamCount ?? t?.defaultTeamCount ?? 2
        let playersPerTeam = eg.overridePlayersPerTeam ?? t?.defaultPlayersPerTeam ?? 2

        let teamSizeText = "Teams: \(teamCount) × \(playersPerTeam)"
        let subtitle = groupText != nil ? "\(groupText!) • \(teamSizeText)" : teamSizeText

        return VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.body)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}


// MARK: - Swap Player

private struct SwapPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let event: Event
    let currentRound: Round
    let people: [Person]
    let outgoing: UUID?

    let onSwap: (UUID) -> Void

    var body: some View {
        let inRound = Set(currentRound.teams.flatMap { $0.memberPersonIds })
        let bench = people.filter { event.participantIds.contains($0.id) && !inRound.contains($0.id) && $0.isActive }

        NavigationStack {
            List {
                Section {
                    Text("Outgoing: \(name(outgoing))")
                        .foregroundStyle(.secondary)
                }

                Section("Choose replacement") {
                    ForEach(bench) { p in
                        Button(p.displayName) {
                            onSwap(p.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Swap Player")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func name(_ id: UUID?) -> String {
        guard let id else { return "None" }
        return people.first(where: { $0.id == id })?.displayName ?? "Unknown"
    }
}


// MARK: - Add Event

private struct AddEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Event Name", text: $name)
            }
            .navigationTitle("New Event")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.insert(Event(name: trimmed))
        try? context.save()
        dismiss()
    }
}


// MARK: - Add Games
private struct AddGameToEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let event: Event

    @Query(sort: \GameTemplate.name)
    private var templates: [GameTemplate]

    @State private var selectedIds: Set<UUID> = []
    @State private var showCSVImporter = false
    @State private var showCreateTemplate = false

    @State private var alertTitle = "Message"
    @State private var alertMessage: String?
    @State private var showAlert = false

    @State private var pendingCSVData: Data?
    @State private var pendingCSVFilename: String?
    @State private var showCSVPreview = false

    var body: some View {
        NavigationStack {
            List(selection: $selectedIds) {
                Section("Select games to add") {
                    ForEach(templates) { t in
                        HStack {
                            Text(t.name)
                            Spacer()
                            if alreadyInEvent(t) {
                                Text("Added")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(t.id)
                        .contentShape(Rectangle())
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Add Games")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add (\(selectedAddableCount))") { addSelected() }
                        .disabled(selectedAddableCount == 0)
                }

                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("Select All") { selectedIds = Set(templates.map { $0.id }) }
                            .disabled(templates.isEmpty)

                        Button("None") { selectedIds.removeAll() }
                            .disabled(selectedIds.isEmpty)

                        Spacer()

                        Button("Import CSV") { showCSVImporter = true }
                        Button("New Template") { showCreateTemplate = true }
                    }
                }
            }
            .fileImporter(
                isPresented: $showCSVImporter,
                allowedContentTypes: [UTType.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                do {
                    let urls = try result.get()
                    guard let url = urls.first else { return }

                    let didStart = url.startAccessingSecurityScopedResource()
                    defer { if didStart { url.stopAccessingSecurityScopedResource() } }

                    let data = try Data(contentsOf: url)

                    pendingCSVData = data
                    pendingCSVFilename = url.lastPathComponent
                    showCSVPreview = true

                } catch {
                    alertTitle = "Import failed"
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
            .sheet(isPresented: $showCSVPreview) {
                if let data = pendingCSVData {
                    CSVImportPreviewSheet(csvData: data, filename: pendingCSVFilename)
                } else {
                    Text("No CSV loaded.")
                        .padding()
                }
            }
            .sheet(isPresented: $showCreateTemplate) {
                CreateGameTemplateSheet { newTemplate in
                    selectedIds.insert(newTemplate.id)
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage ?? "Unknown error")
            }
        }
    }

    private func alreadyInEvent(_ template: GameTemplate) -> Bool {
        event.eventGames.contains(where: { $0.gameTemplateId == template.id })
    }

    private var selectedAddableCount: Int {
        let existing = Set(event.eventGames.map { $0.gameTemplateId })
        return selectedIds.filter { !existing.contains($0) }.count
    }

    private func addSelected() {
        let existing = Set(event.eventGames.map { $0.gameTemplateId })
        var nextOrder = (event.eventGames.map(\.orderIndex).max() ?? -1) + 1

        for tid in selectedIds {
            guard !existing.contains(tid) else { continue }
            let eg = EventGame(event: event, gameTemplateId: tid, orderIndex: nextOrder, status: .notStarted)
            nextOrder += 1
            context.insert(eg)
            event.eventGames.append(eg)
        }

        do {
            try context.save()
            dismiss()
        } catch {
            alertTitle = "Add failed"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}


// MARK: - Players + Add Games sheets
// IMPORTANT: Keep your existing working implementations for SelectEventPlayersSheet and AddGameToEventSheet.
// If you want, I can paste those two again as full, consistent blocks in the next message.
