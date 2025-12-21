import SwiftUI
import SwiftData

struct RunGameView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorTheme) private var theme

    let event: Event

    @Query(sort: \Person.displayName)
    private var people: [Person]

    @Query(sort: \GameTemplate.name)
    private var templates: [GameTemplate]
    
    @State private var message: String?
    @State private var showMessage = false

    @State private var showPickNextGame = false
    @State private var showResetConfirm = false


    @State private var showSwap = false
    @State private var swapOutgoing: UUID?

    @State private var showAfterRoundDialog = false
    @State private var showAfterGameDialog = false

    @State private var showWinnerPicker = false
    @State private var showSkipConfirmation = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.gradientStart, theme.gradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                content
                Spacer()
            }
            .padding()

            if event.status == .paused {
                pausedOverlay
            }
        }
        .navigationTitle("Run Game")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Pause/Resume button
                if event.status == .active {
                    Button("Pause") {
                        do { try engine.pauseEvent(event) }
                        catch { show(error) }
                    }
                } else if event.status == .paused {
                    Button("Resume") {
                        do { try engine.resumeEvent(event) }
                        catch { show(error) }
                    }
                }
                
                // Skip Game button (only when game is active and not paused)
                if currentGame != nil && event.status == .active {
                    Button("Skip Game") { showSkipConfirmation = true }
                }
                
                // Pick Game button
                Button("Pick Game") { showPickNextGame = true }
                    .disabled(event.status == .paused)
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
        .confirmationDialog("Reset Event", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset Event", role: .destructive) {
                do {
                    try EventEngine(context: context).resetEvent(event)
                } catch {
                    show(error)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will reset all games to 'not started', delete all rounds and statistics. Participants will be kept.")
        }
    }

    private var pausedOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                
                Text("Event Paused")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                Button("Resume") {
                    do { try engine.resumeEvent(event) }
                    catch { show(error) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

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
        return eg.rounds
            .sorted(by: { $0.roundIndex > $1.roundIndex })
            .first(where: { $0.completedAt == nil })
    }

    private func teamLabel(_ index: Int) -> String {
        let scalar = UnicodeScalar(65 + index)!
        return String(Character(scalar))
    }

    private func teamNames(_ team: RoundTeam) -> String {
        team.memberPersonIds
            .compactMap { peopleById[$0]?.displayName }
            .joined(separator: ", ")
    }

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
            .disabled(event.eventGames.isEmpty || event.participantIds.isEmpty || event.status == .paused)
        }
    }

    private func header(template: GameTemplate, eventGame: EventGame) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(template.name).font(.title2).bold()

            if let playInstructions = (eventGame.overridePlayInstructions ?? template.playInstructions),
               !playInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(playInstructions)
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
                .disabled(event.status == .paused)
            } else {
                teamsList(round: round)

                if !round.isLocked {
                    actionRowUnlocked(round: round)
                } else {
                    Button("Continue") { showAfterRoundDialog = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(event.status == .paused)
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
                handlePickNextGameRandom(currentGame: eventGame)
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
                        .foregroundColor(teamColor(for: index))

                    ForEach(team.memberPersonIds, id: \.self) { pid in
                        HStack {
                            Text(peopleById[pid]?.displayName ?? "Unknown")
                            Spacer()
                            if !round.isLocked && event.status != .paused {
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
    
    private func teamColor(for index: Int) -> Color {
        let colors: [Color] = [.red, .green, .yellow, .blue, .orange, .purple]
        return index < colors.count ? colors[index] : .primary
    }

    private func actionRowUnlocked(round: Round) -> some View {
        HStack {
            Button("Regenerate") {
                do { try engine.generateTeams(for: round) }
                catch { show(error) }
            }
            .buttonStyle(.bordered)
            .disabled(event.status == .paused)

            Spacer()

            Button("Select Winner") {
                showWinnerPicker = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(round.teams.isEmpty || event.status == .paused)
        }
        .confirmationDialog("Select winner", isPresented: $showWinnerPicker, titleVisibility: .visible) {
            ForEach(Array(round.teams.enumerated()), id: \.element.id) { index, t in
                Button("Team \(teamLabel(index)) – \(teamNames(t))") {
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

    private func handlePickNextGameRandom(currentGame: EventGame) {
        do {
            try engine.completeGame(currentGame)
            
            if let next = try engine.pickNextGameRandom(event: event) {
                try engine.start(event: event, eventGame: next)
                
                // Force view refresh by saving again
                try context.save()
            } else {
                event.status = .completed
                try context.save()
            }
        } catch {
            show(error)
        }
    }

    private func handlePick(selection: EventGame, skipMode: PickNextGameSheet.SkipMode?) {
        do {
            if let skipMode {
                if skipMode == .pushLater { try engine.pushGameToLater(selection) }
                if skipMode == .remove { try engine.removeGameFromEvent(selection) }
                return
            }

            if let cg = currentGame { try engine.completeGame(cg) }
            try engine.start(event: event, eventGame: selection)
            
            // Force view refresh
            try context.save()
        } catch {
            show(error)
        }
    }

    private func handleSkipGame() {
        guard let game = currentGame else { return }
        
        // Get current player IDs
        let playerIds: [UUID]
        if let round = currentRound, !round.teams.isEmpty {
            playerIds = round.teams.flatMap { $0.memberPersonIds }
        } else {
            playerIds = []
        }
        
        do {
            try engine.skipToNextGame(game, keepingPlayers: playerIds)
            
            // Force view refresh
            try context.save()
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

struct PickNextGameSheet: View {
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

struct SwapPlayerSheet: View {
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

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Event.self, Person.self, GameTemplate.self, configurations: config)
    
    let event = Event(name: "Test Event")
    container.mainContext.insert(event)
    
    return NavigationStack {
        RunGameView(event: event)
    }
    .modelContainer(container)
}
