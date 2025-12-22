import SwiftUI
import SwiftData

struct RunGameView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var themeManager: ThemeManager

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
    @State private var isInPostRoundDecision = false

    @State private var showWinnerPicker = false
    @State private var showSkipConfirmation = false
    @State private var showEventStats = false

    @State private var showTransition = false
    @State private var pendingNextGame: EventGame?
    @State private var pendingShowAfterRoundDialog = false

    @State private var selectedWinnerTeamId: UUID?
    @State private var selectedSecondTeamId: UUID?
    @State private var showSecondPlacePicker = false
    @State private var showThirdPlacePicker = false

    // Winner celebration settings
    @AppStorage("winnerCelebration_enabled") private var winnerCelebrationEnabled: Bool = true
    @AppStorage("winnerCelebration_showForMultiRound") private var showCelebrationForMultiRound: Bool = false
    @AppStorage("winnerCelebration_useGifs") private var winnerCelebrationUseGifs: Bool = true

    // Winner celebration state
    @State private var showWinnerCelebrationOverlay = false
    @State private var celebrationTitle: String = ""
    @State private var celebrationLines: [String] = []

    @ViewBuilder
    private var winnerCelebrationLayer: some View {
        if showWinnerCelebrationOverlay {
            WinnerCelebrationOverlay(
                title: celebrationTitle,
                lines: celebrationLines,
                useGifs: winnerCelebrationUseGifs,
                onNext: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showWinnerCelebrationOverlay = false
                    }

                    // Always go to post-round menu after celebration
                    pendingShowAfterRoundDialog = false
                    isInPostRoundDecision = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        showAfterRoundDialog = true
                    }
                },
                onClose: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showWinnerCelebrationOverlay = false
                    }

                    // Always go to post-round menu after celebration, even on Close
                    pendingShowAfterRoundDialog = false
                    isInPostRoundDecision = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        showAfterRoundDialog = true
                    }
                }
            )
            .transition(.opacity.combined(with: .scale))
            .zIndex(200)
        }
    }

    var body: some View {
        ZStack {
            themeManager.background
                .ignoresSafeArea()

            // Scroll ONLY the main content (teams list gets tall)
            ScrollView {
                VStack(spacing: 12) {
                    content
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .safeAreaPadding(.top)
            .safeAreaPadding(.bottom)

            // Overlays stay above scroll content
            if event.status == .paused {
                pausedOverlay
            }

            winnerCelebrationLayer

            if showTransition {
                GameTransitionView {
                    completeTransition()
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .navigationTitle("Run Game")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        showEventStats = true
                    } label: {
                        Label("View Stats", systemImage: "chart.bar.fill")
                    }
                } label: {
                    Text("Event")
                        .foregroundColor(themeManager.text)
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                // Pause/Resume button
                if event.status == .active {
                    Button("Pause") {
                        do { try engine.pauseEvent(event) }
                        catch { show(error) }
                    }
                    .foregroundColor(themeManager.text)
                } else if event.status == .paused {
                    Button("Resume") {
                        do { try engine.resumeEvent(event) }
                        catch { show(error) }
                    }
                    .foregroundColor(themeManager.text)
                }

                // Skip Game button (only when game is active and not paused)
                if currentGame != nil && event.status == .active {
                    Button("Skip Game") { showSkipConfirmation = true }
                        .foregroundColor(themeManager.text)
                }

                // Pick Game button
                Button("Pick Game") { showPickNextGame = true }
                    .foregroundColor(themeManager.text)
                    .disabled(event.status == .paused)
            }
        }
        .sheet(isPresented: $showPickNextGame) {
            PickNextGameSheet(event: event) { selection, skipMode in
                handlePick(selection: selection, skipMode: skipMode)
            }
            .environmentObject(themeManager)
        }
        .sheet(isPresented: $showEventStats) {
            CurrentEventStatsSheet(event: event)
                .environmentObject(themeManager)
                .onDisappear {
                    // Reshow dialog if we were in post-round decision mode
                    if isInPostRoundDecision {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showAfterRoundDialog = true
                        }
                    }
                }
        }

        // ✅ UPDATED: Differentiated primary action using iconography + weight (Option 4)
        .confirmationDialog(
            "What would you like to do next?",
            isPresented: $showAfterRoundDialog,
            titleVisibility: .visible
        ) {
            if let eg = currentGame {
                Button {
                    do {
                        _ = try engine.createNextRound(for: eg)
                        isInPostRoundDecision = false
                        showAfterRoundDialog = false
                    } catch {
                        show(error)
                    }
                } label: {
                    Label("Play Another Round", systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    isInPostRoundDecision = false
                    showAfterRoundDialog = false
                    handlePickNextGameRandom(currentGame: eg)
                } label: {
                    Label("Continue to Next Game", systemImage: "arrow.right.circle.fill")
                }
                .fontWeight(.semibold)

                Button {
                    isInPostRoundDecision = false
                    showAfterRoundDialog = false
                    showPickNextGame = true
                } label: {
                    Label("Manually Choose Next Game", systemImage: "list.bullet.rectangle")
                }

                Button {
                    showEventStats = true
                    // Don't clear isInPostRoundDecision - we want to come back
                } label: {
                    Label("View Event Stats", systemImage: "chart.bar.fill")
                }

                Button(role: .cancel) { } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            } else {
                Button(role: .cancel) { } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            }
        }

        .confirmationDialog(
            "Select 2nd place",
            isPresented: $showSecondPlacePicker,
            titleVisibility: .visible
        ) {
            if let round = currentRound, let winnerId = selectedWinnerTeamId {
                ForEach(Array(round.teams.enumerated()), id: \.element.id) { index, t in
                    if t.id != winnerId {
                        Button("2nd: Team \(teamLabel(index)) – \(teamNames(t))") {
                            showSecondPlacePicker = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                completeSecondPlace(for: round, secondId: t.id)
                            }
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        }

        .confirmationDialog(
            "Select 3rd place",
            isPresented: $showThirdPlacePicker,
            titleVisibility: .visible
        ) {
            if let round = currentRound, let winnerId = selectedWinnerTeamId, let secondId = selectedSecondTeamId {
                ForEach(Array(round.teams.enumerated()), id: \.element.id) { index, t in
                    if t.id != winnerId && t.id != secondId {
                        Button("3rd: Team \(teamLabel(index)) – \(teamNames(t))") {
                            showThirdPlacePicker = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                completeThirdPlace(for: round, thirdId: t.id)
                            }
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        }

        .alert("Message", isPresented: $showMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message ?? "Unknown error")
        }

        .confirmationDialog(
            "Reset Event",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
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

        .confirmationDialog(
            "Skip Current Game",
            isPresented: $showSkipConfirmation,
            titleVisibility: .visible
        ) {
            Button("Skip to Next Game", role: .destructive) {
                handleSkipGame()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will skip the current game and move to the next available game. Current players will be carried over if possible.")
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
                // No active round - either all rounds complete or none created yet
                VStack(spacing: 16) {
                    if eg.rounds.isEmpty {
                        Text("No rounds created yet.")
                            .foregroundStyle(.secondary)

                        Button("Start First Round") {
                            do {
                                _ = try engine.createNextRound(for: eg)
                            } catch {
                                show(error)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(event.status == .paused)
                    } else {
                        // All rounds are complete - ready for next game
                        Text("All rounds complete!")
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        Button("Choose Next Game") {
                            isInPostRoundDecision = true
                            showAfterRoundDialog = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(event.status == .paused)
                    }
                }
                .padding()
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
            .environmentObject(themeManager)
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
                        selectedWinnerTeamId = t.id
                        showWinnerPicker = false

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            beginPlacementFlow(for: round)
                        }
                    } catch {
                        show(error)
                    }
                }
            }

            Button("Tie") {
                do {
                    try engine.finalizeRound(round, winnerTeamId: nil)
                    showWinnerPicker = false

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        handleRoundFinalized(round: round, winnerTeamId: nil)
                    }
                } catch {
                    show(error)
                }
            }

            Button("Cancel", role: .cancel) { }
        }
    }

    // MARK: - Placement Flow (1st / 2nd / 3rd)

    private func beginPlacementFlow(for round: Round) {
        guard let winnerId = selectedWinnerTeamId else { return }
        let teamCount = round.teams.count

        // 2 teams: auto-assign 2nd as the other team
        if teamCount <= 2 {
            let second = round.teams.first(where: { $0.id != winnerId })?.id
            do {
                try engine.finalizeRound(round, winnerTeamId: winnerId, secondTeamId: second, thirdTeamId: nil)
                handleRoundFinalized(round: round, winnerTeamId: winnerId)
            } catch {
                show(error)
            }
            return
        }

        // 3+ teams: ask for 2nd place
        selectedSecondTeamId = nil
        showSecondPlacePicker = true
    }

    private func completeSecondPlace(for round: Round, secondId: UUID) {
        selectedSecondTeamId = secondId
        guard let winnerId = selectedWinnerTeamId else { return }

        let teamCount = round.teams.count

        // 3 teams: auto-assign 3rd as the remaining team
        if teamCount == 3 {
            let third = round.teams.map(\.id).first(where: { $0 != winnerId && $0 != secondId })
            do {
                try engine.finalizeRound(round, winnerTeamId: winnerId, secondTeamId: secondId, thirdTeamId: third)
                handleRoundFinalized(round: round, winnerTeamId: winnerId)
            } catch {
                show(error)
            }
            return
        }

        // 4+ teams: ask for 3rd place
        showThirdPlacePicker = true
    }

    private func completeThirdPlace(for round: Round, thirdId: UUID) {
        guard let winnerId = selectedWinnerTeamId, let secondId = selectedSecondTeamId else { return }
        do {
            try engine.finalizeRound(round, winnerTeamId: winnerId, secondTeamId: secondId, thirdTeamId: thirdId)
            handleRoundFinalized(round: round, winnerTeamId: winnerId)
        } catch {
            show(error)
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

    private func handleRoundFinalized(round: Round, winnerTeamId: UUID?) {
        showTransition = false
        pendingNextGame = nil

        let shouldCelebrate = shouldShowWinnerCelebration(for: round)

        if winnerCelebrationEnabled && shouldCelebrate {
            buildCelebrationPayload(round: round, winnerTeamId: winnerTeamId)

            pendingShowAfterRoundDialog = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showWinnerCelebrationOverlay = true
            }
        } else {
            isInPostRoundDecision = true
            showAfterRoundDialog = true
        }
    }

    private func shouldShowWinnerCelebration(for round: Round) -> Bool {
        guard let eg = round.eventGame else { return true }
        let completedRoundCount = eg.rounds.filter { $0.completedAt != nil }.count

        if completedRoundCount > 1 {
            return showCelebrationForMultiRound
        }
        return true
    }

    private func buildCelebrationPayload(round: Round, winnerTeamId: UUID?) {
        if round.resultType == .tie || winnerTeamId == nil {
            celebrationTitle = "It’s a Tie!"
            celebrationLines = ["Everyone takes 1st place"]
            return
        }

        let placements = round.placements

        let first = placements
            .filter { $0.value == 1 }
            .compactMap { peopleById[$0.key]?.displayName }
            .sorted()

        let second = placements
            .filter { $0.value == 2 }
            .compactMap { peopleById[$0.key]?.displayName }
            .sorted()

        let third = placements
            .filter { $0.value == 3 }
            .compactMap { peopleById[$0.key]?.displayName }
            .sorted()

        celebrationTitle = "Congratulations!"
        var lines: [String] = []

        if !first.isEmpty { lines.append("1st Place: " + first.joined(separator: ", ")) }
        if !second.isEmpty { lines.append("2nd Place: " + second.joined(separator: ", ")) }
        if !third.isEmpty { lines.append("3rd Place: " + third.joined(separator: ", ")) }

        if lines.isEmpty { lines = ["Winners recorded"] }

        celebrationLines = lines
    }

    private func handlePickNextGameRandom(currentGame: EventGame) {
        do {
            try engine.completeGame(currentGame)

            if let next = try engine.pickNextGameRandom(event: event) {
                pendingNextGame = next
                withAnimation {
                    showTransition = true
                }
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

            if let cg = currentGame {
                try engine.completeGame(cg)
            }

            pendingNextGame = selection
            withAnimation {
                showTransition = true
            }
        } catch {
            show(error)
        }
    }

    private func completeTransition() {
        do {
            if let nextGame = pendingNextGame {
                try engine.start(event: event, eventGame: nextGame)
                try context.save()
            }

            withAnimation {
                showTransition = false
            }
            pendingNextGame = nil
        } catch {
            show(error)
            withAnimation {
                showTransition = false
            }
            pendingNextGame = nil
        }
    }

    private func handleSkipGame() {
        guard let game = currentGame else { return }

        let playerIds: [UUID]
        if let round = currentRound, !round.teams.isEmpty {
            playerIds = round.teams.flatMap { $0.memberPersonIds }
        } else {
            playerIds = []
        }

        do {
            try engine.skipToNextGame(game, keepingPlayers: playerIds)
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

    // Filter and sort state
    @State private var searchText = ""
    @AppStorage("pickNextGame_filterTeamSize") private var filterTeamSize: Int?
    @AppStorage("pickNextGame_filterTeamCount") private var filterTeamCount: Int?
    @AppStorage("pickNextGame_sortOption") private var sortOption: SortOption = .orderIndex
    @AppStorage("pickNextGame_teamTypeFilter") private var teamTypeFilter: TeamTypeFilter = .all
    @AppStorage("pickNextGame_statusFilter") private var statusFilter: StatusFilter = .active

    enum SortOption: String, CaseIterable, Codable {
        case orderIndex = "Order"
        case alphabetical = "A-Z"
        case reverseAlphabetical = "Z-A"
    }

    enum TeamTypeFilter: String, CaseIterable, Codable {
        case all = "All"
        case any = "Any"
        case maleOnly = "Male Only"
        case femaleOnly = "Female Only"
        case couplesOnly = "Couples Only"
    }

    enum StatusFilter: String, CaseIterable, Codable {
        case active = "Active"
        case notStarted = "Not Started"
        case allGames = "All Games"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search games...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Picker("Team Size", selection: $filterTeamSize) {
                            Text("Any").tag(nil as Int?)
                            ForEach(availableTeamSizes, id: \.self) { size in
                                Text("\(size)").tag(size as Int?)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Teams", selection: $filterTeamCount) {
                            Text("Any").tag(nil as Int?)
                            ForEach(availableTeamCounts, id: \.self) { count in
                                Text("\(count)").tag(count as Int?)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack {
                        Picker("Sort", selection: $sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Team Type", selection: $teamTypeFilter) {
                            ForEach(TeamTypeFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Picker("Status", selection: $statusFilter) {
                        ForEach(StatusFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("\(statusFilter.rawValue) Games (\(filteredAndSortedGames.count))")
                }

                Section("Select Game") {
                    ForEach(filteredAndSortedGames) { eg in
                        Button {
                            onPick(eg, nil)
                            dismiss()
                        } label: {
                            gameRow(for: eg)
                        }
                    }
                }

                if !filteredAndSortedGames.isEmpty {
                    Section("Skip Options") {
                        ForEach(filteredAndSortedGames) { eg in
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
            }
            .navigationTitle("Choose Next Game")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var availableTeamSizes: [Int] {
        let sizes = eligibleGames.compactMap { eg -> Int? in
            let t = template(for: eg)
            return eg.overridePlayersPerTeam ?? t?.defaultPlayersPerTeam
        }
        return Array(Set(sizes)).sorted()
    }

    private var availableTeamCounts: [Int] {
        let counts = eligibleGames.compactMap { eg -> Int? in
            let t = template(for: eg)
            return eg.overrideTeamCount ?? t?.defaultTeamCount
        }
        return Array(Set(counts)).sorted()
    }

    private var eligibleGames: [EventGame] {
        let games = event.eventGames

        switch statusFilter {
        case .notStarted:
            return games.filter { $0.status == .notStarted }

        case .active:
            return games.filter { eg in
                if eg.status == .notStarted { return true }

                if eg.status == .inProgress {
                    let hasCompletedRoundWithWinner = eg.rounds.contains { round in
                        round.completedAt != nil &&
                        (round.winningTeamId != nil || round.resultType == .tie)
                    }
                    return !hasCompletedRoundWithWinner
                }
                return false
            }

        case .allGames:
            return games
        }
    }

    private var filteredAndSortedGames: [EventGame] {
        var result = eligibleGames

        if !searchText.isEmpty {
            result = result.filter { eg in
                let t = template(for: eg)
                let name = t?.name ?? ""
                let group = t?.groupName ?? ""
                return name.localizedCaseInsensitiveContains(searchText) ||
                group.localizedCaseInsensitiveContains(searchText)
            }
        }

        if let filterTeamSize {
            result = result.filter { eg in
                let t = template(for: eg)
                let size = eg.overridePlayersPerTeam ?? t?.defaultPlayersPerTeam ?? 0
                return size == filterTeamSize
            }
        }

        if let filterTeamCount {
            result = result.filter { eg in
                let t = template(for: eg)
                let count = eg.overrideTeamCount ?? t?.defaultTeamCount ?? 0
                return count == filterTeamCount
            }
        }

        if teamTypeFilter != .all {
            result = result.filter { eg in
                let t = template(for: eg)
                let teamType = eg.overrideTeamType ?? t?.defaultTeamType ?? .any

                switch teamTypeFilter {
                case .all:
                    return true
                case .any:
                    return teamType == .any
                case .maleOnly:
                    return teamType == .maleOnly
                case .femaleOnly:
                    return teamType == .femaleOnly
                case .couplesOnly:
                    return teamType == .couplesOnly
                }
            }
        }

        switch sortOption {
        case .orderIndex:
            result.sort { $0.orderIndex < $1.orderIndex }
        case .alphabetical:
            result.sort { eg1, eg2 in
                let n1 = gameName(for: eg1)
                let n2 = gameName(for: eg2)
                return n1.localizedCaseInsensitiveCompare(n2) == .orderedAscending
            }
        case .reverseAlphabetical:
            result.sort { eg1, eg2 in
                let n1 = gameName(for: eg1)
                let n2 = gameName(for: eg2)
                return n1.localizedCaseInsensitiveCompare(n2) == .orderedDescending
            }
        }

        return result
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
    .environmentObject(ThemeManager())
}
