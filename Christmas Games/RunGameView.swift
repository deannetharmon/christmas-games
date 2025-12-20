import SwiftUI
import SwiftData

struct RunGameView: View {
    @Environment(\.modelContext) private var context
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

    @State private var showAfterRoundSheet = false
    @State private var showSkipConfirmation = false

    @State private var showWinnerPicker = false
    @State private var showEventStats = false

    var body: some View {
        mainView
            .sheet(isPresented: $showAfterRoundSheet) {
                if let game = currentGame {
                    AfterRoundSheet(
                        currentGame: game,
                        onNewRoundSamePlayers: {
                            createRoundWithSamePlayers(eventGame: game)
                        },
                        onNewRoundNewPlayers: {
                            createRoundWithNewPlayers(eventGame: game)
                        },
                        onNextGameRandom: {
                            handlePickNextGameRandom(currentGame: game)
                        },
                        onNextGameChoose: {
                            showPickNextGame = true
                        }
                    )
                }
            }
            .onChange(of: event.status) { oldValue, newValue in
                // Auto-show sheet when resuming if needed
                if oldValue == .paused && newValue == .active && shouldShowAfterRoundSheet {
                    showAfterRoundSheet = true
                }
            }
    }
    
    private var mainView: some View {
        ZStack {
            VStack(spacing: 12) {
                content
                Spacer()
            }
            .padding()
            
            // Paused overlay
            if event.status == .paused {
                pausedOverlay
            }
        }
        .navigationTitle("Run Game")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Stats button
                Button {
                    showEventStats = true
                } label: {
                    Image(systemName: "chart.bar")
                }
                
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
        .sheet(isPresented: $showEventStats) {
            EventStatsSheet(event: event, people: people)
        }
        .sheet(isPresented: $showSwap) {
            SwapPlayerSheet(
                event: event,
                currentRound: currentRound!,
                people: people,
                outgoing: swapOutgoing
            ) { incoming in
                do {
                    if let out = swapOutgoing, let round = currentRound {
                        try engine.swapPlayer(in: round, from: out, to: incoming)
                    }
                } catch { show(error) }
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
        .confirmationDialog("Skip this game?", isPresented: $showSkipConfirmation, titleVisibility: .visible) {
            Button("Skip Game", role: .destructive) {
                handleSkipGame()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will mark the current game as complete and start a new random game with the same players.")
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
    
    private var shouldShowAfterRoundSheet: Bool {
        guard let game = currentGame else { return false }
        
        // If there's an active unlocked round, don't show sheet
        if currentRound != nil { return false }
        
        // If last round is completed but no new round created, show sheet
        if let lastRound = game.rounds.sorted(by: { $0.roundIndex > $1.roundIndex }).first,
           lastRound.completedAt != nil {
            return true
        }
        
        return false
    }

    private func teamLabel(_ index: Int) -> String {
        let scalar = UnicodeScalar(65 + index)!
        return String(Character(scalar))
    }
    
    private func teamColor(_ index: Int) -> Color {
        let colors: [Color] = [
            .red,
            .blue,
            .green,
            .orange,
            .purple,
            Color(red: 0.0, green: 0.7, blue: 0.7) // Teal
        ]
        return colors[index % colors.count]
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
            } else if let lastRound = eg.rounds.sorted(by: { $0.roundIndex > $1.roundIndex }).first {
                roundCard(template: template, eventGame: eg, round: lastRound)
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
                .disabled(event.status == .paused)
            } else {
                teamsList(round: round)

                if !round.isLocked {
                    actionRowUnlocked(round: round)
                } else {
                    Button("Continue") { showAfterRoundSheet = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(event.status == .paused)
                }

                previousRoundsCompact(eventGame: eventGame)
            }
        }
    }

    private func teamsList(round: Round) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(round.teams.enumerated()), id: \.element.id) { index, team in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Team \(teamLabel(index))")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(teamColor(index))

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
                Button("Team \(teamLabel(index)) — \(teamNames(t))") {
                    do {
                        try engine.finalizeRound(round, winnerTeamId: t.id)
                        showAfterRoundSheet = true
                    } catch { show(error) }
                }
            }

            Button("Tie") {
                do {
                    try engine.finalizeRound(round, winnerTeamId: nil)
                    showAfterRoundSheet = true
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
            return "Round \(round.roundIndex + 1): Winner — \(names)"
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
    
    private func createRoundWithSamePlayers(eventGame: EventGame) {
        do {
            // Get the last completed round
            guard let lastRound = eventGame.rounds
                .sorted(by: { $0.roundIndex > $1.roundIndex })
                .first(where: { $0.completedAt != nil }) else {
                return
            }
            
            // Create new round
            let newRound = try engine.createNextRound(for: eventGame)
            
            // Copy teams from last round
            newRound.teams = lastRound.teams
            
            try context.save()
        } catch {
            show(error)
        }
    }
    
    private func createRoundWithNewPlayers(eventGame: EventGame) {
        do {
            // Create new round with empty teams
            _ = try engine.createNextRound(for: eventGame)
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

// MARK: - Event Stats Sheet

struct EventStatsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let event: Event
    let people: [Person]
    
    var body: some View {
        NavigationStack {
            if let stats = calculatedStats {
                List {
                    Section {
                        HStack {
                            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Games").frame(width: 50)
                            Text("1st").frame(width: 40)
                            Text("2nd").frame(width: 40)
                            Text("3rd").frame(width: 40)
                            Text("Rank").frame(width: 50)
                        }
                        .font(.caption)
                        .bold()
                    }
                    
                    ForEach(stats) { stat in
                        HStack {
                            Text(stat.displayName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(stat.gamesPlayed)")
                                .frame(width: 50)
                            Text("\(stat.firstPlace)")
                                .frame(width: 40)
                            Text("\(stat.secondPlace)")
                                .frame(width: 40)
                            Text("\(stat.thirdPlace)")
                                .frame(width: 40)
                            Text("\(stat.rank)")
                                .frame(width: 50)
                                .bold()
                        }
                        .font(.body)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Stats Available",
                    systemImage: "chart.bar",
                    description: Text("Play some games to see statistics")
                )
            }
        }
        .navigationTitle("\(event.name) Stats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
    
    private var calculatedStats: [PlayerStats]? {
        var statsDict: [UUID: PlayerStats] = [:]
        
        for eventGame in event.eventGames {
            for round in eventGame.rounds where round.completedAt != nil {
                // Process placements
                for (personId, placement) in round.placements {
                    var stat = statsDict[personId] ?? PlayerStats(personId: personId)
                    stat.gamesPlayed += 1
                    
                    switch placement {
                    case 1: stat.firstPlace += 1
                    case 2: stat.secondPlace += 1
                    case 3: stat.thirdPlace += 1
                    default: break
                    }
                    
                    statsDict[personId] = stat
                }
                
                // Handle ties
                if round.resultType == .tie, round.winningTeamId == nil {
                    for team in round.teams {
                        for personId in team.memberPersonIds {
                            var stat = statsDict[personId] ?? PlayerStats(personId: personId)
                            if round.placements[personId] == nil {
                                stat.gamesPlayed += 1
                            }
                            stat.firstPlace += 1
                            statsDict[personId] = stat
                        }
                    }
                }
            }
        }
        
        guard !statsDict.isEmpty else { return nil }
        
        let peopleById = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        
        var result = statsDict.values.map { stat -> PlayerStats in
            var s = stat
            s.displayName = peopleById[stat.personId]?.displayName ?? "Unknown"
            s.totalPoints = (s.firstPlace * 3) + (s.secondPlace * 2) + (s.thirdPlace * 1)
            return s
        }
        
        result.sort { lhs, rhs in
            if lhs.totalPoints != rhs.totalPoints {
                return lhs.totalPoints > rhs.totalPoints
            }
            return lhs.gamesPlayed < rhs.gamesPlayed
        }
        
        for (index, _) in result.enumerated() {
            result[index].rank = index + 1
        }
        
        return result
    }
    
    private struct PlayerStats: Identifiable {
        let id = UUID()
        let personId: UUID
        var displayName: String = ""
        var gamesPlayed: Int = 0
        var firstPlace: Int = 0
        var secondPlace: Int = 0
        var thirdPlace: Int = 0
        var totalPoints: Int = 0
        var rank: Int = 0
    }
}

// MARK: - After Round Sheet

struct AfterRoundSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let currentGame: EventGame
    let onNewRoundSamePlayers: () -> Void
    let onNewRoundNewPlayers: () -> Void
    let onNextGameRandom: () -> Void
    let onNextGameChoose: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Round Complete!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, 20)
                
                Divider()
                
                // Option 1: Play another round
                VStack(spacing: 12) {
                    Text("Play Another Round")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        Button {
                            onNewRoundSamePlayers()
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title2)
                                Text("Same Players")
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            onNewRoundNewPlayers()
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "shuffle")
                                    .font(.title2)
                                Text("New Players")
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Divider()
                
                // Option 2: Next game
                VStack(spacing: 12) {
                    Text("Move to Next Game")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        Button {
                            onNextGameRandom()
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "dice")
                                    .font(.title2)
                                Text("Random Game")
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            onNextGameChoose()
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "list.bullet")
                                    .font(.title2)
                                Text("Choose Game")
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
            }
            .padding()
            .presentationDetents([.medium])
            .interactiveDismissDisabled()
        }
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
