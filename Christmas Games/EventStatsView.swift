import SwiftUI
import SwiftData

struct EventStatsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var themeManager: ThemeManager

    @Query(sort: \Event.createdAt, order: .reverse)
    private var allEvents: [Event]

    @Query(sort: \Person.displayName)
    private var people: [Person]

    @State private var selectedEventId: UUID?

    @State private var showResetConfirm = false
    @State private var message: String?
    @State private var showMessage = false

    @State private var sortColumn: SortColumn = .rank
    @State private var sortAscending: Bool = true

    enum SortColumn {
        case name, games, rounds, first, second, third, rank
    }

    var body: some View {
        ZStack {
            themeManager.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                eventPicker

                if let stats = calculatedStats {
                    statsTable(stats: stats)
                        .scrollContentBackground(.hidden)
                } else {
                    ContentUnavailableView(
                        "No Stats Available",
                        systemImage: "chart.bar",
                        description: Text("Play some games to see statistics.")
                    )
                    .padding()
                }
            }
        }
        .navigationTitle("Event Stats")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { showResetConfirm = true }
                    .foregroundColor(themeManager.text)
                    .disabled(selectedEventId == nil)
            }
        }
        .confirmationDialog("Reset Event", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset Event", role: .destructive) {
                resetSelectedEvent()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will reset all games to 'not started', delete all rounds and statistics. Participants will be kept.")
        }
        .alert("Message", isPresented: $showMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message ?? "Unknown error")
        }
    }

    private var eventPicker: some View {
        Picker("Event", selection: $selectedEventId) {
            Text("All Events").tag(nil as UUID?)
            ForEach(allEvents) { event in
                Text(event.name).tag(event.id as UUID?)
            }
        }
        .pickerStyle(.menu)
        .padding()
    }

    private var calculatedStats: [PlayerStats]? {
        let eventsToAnalyze: [Event]
        if let selectedEventId {
            eventsToAnalyze = allEvents.filter { $0.id == selectedEventId }
        } else {
            eventsToAnalyze = allEvents
        }

        guard !eventsToAnalyze.isEmpty else { return nil }

        var statsDict: [UUID: PlayerStats] = [:]

        for event in eventsToAnalyze {
            for eventGame in event.eventGames {
                var peopleInThisGame: Set<UUID> = []

                for round in eventGame.rounds where round.completedAt != nil {
                    let participantsInRound: Set<UUID> = Set(round.teams.flatMap { $0.memberPersonIds })

                    // Rounds Played
                    for personId in participantsInRound {
                        var stat = statsDict[personId] ?? PlayerStats(personId: personId)
                        stat.roundsPlayed += 1
                        statsDict[personId] = stat
                    }

                    // For Games Played rollup
                    peopleInThisGame.formUnion(participantsInRound)

                    // Placements
                    if !round.placements.isEmpty {
                        for (personId, placement) in round.placements {
                            var stat = statsDict[personId] ?? PlayerStats(personId: personId)
                            switch placement {
                            case 1: stat.firstPlace += 1
                            case 2: stat.secondPlace += 1
                            case 3: stat.thirdPlace += 1
                            default: break
                            }
                            statsDict[personId] = stat
                        }
                    } else if round.resultType == .tie, round.winningTeamId == nil {
                        // Tie with no placements recorded: everyone in the round gets 1st
                        for personId in participantsInRound {
                            var stat = statsDict[personId] ?? PlayerStats(personId: personId)
                            stat.firstPlace += 1
                            statsDict[personId] = stat
                        }
                    }
                }

                // Games Played: +1 per game if person participated in any completed round within that game
                for personId in peopleInThisGame {
                    var stat = statsDict[personId] ?? PlayerStats(personId: personId)
                    stat.gamesPlayed += 1
                    statsDict[personId] = stat
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

        // Apply sorting based on selected column
        switch sortColumn {
        case .name:
            result.sort { lhs, rhs in
                sortAscending
                ? lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                : lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedDescending
            }
        case .games:
            result.sort { sortAscending ? $0.gamesPlayed < $1.gamesPlayed : $0.gamesPlayed > $1.gamesPlayed }
        case .rounds:
            result.sort { sortAscending ? $0.roundsPlayed < $1.roundsPlayed : $0.roundsPlayed > $1.roundsPlayed }
        case .first:
            result.sort { sortAscending ? $0.firstPlace < $1.firstPlace : $0.firstPlace > $1.firstPlace }
        case .second:
            result.sort { sortAscending ? $0.secondPlace < $1.secondPlace : $0.secondPlace > $1.secondPlace }
        case .third:
            result.sort { sortAscending ? $0.thirdPlace < $1.thirdPlace : $0.thirdPlace > $1.thirdPlace }
        case .rank:
            result.sort { sortAscending ? $0.totalPoints < $1.totalPoints : $0.totalPoints > $1.totalPoints }
        }

        // Assign ranks based on points (for display)
        let rankedByPoints = result.sorted { $0.totalPoints > $1.totalPoints }
        var rankMap: [UUID: Int] = [:]
        for (index, stat) in rankedByPoints.enumerated() {
            rankMap[stat.personId] = index + 1
        }

        for i in 0..<result.count {
            result[i].rank = rankMap[result[i].personId] ?? 0
        }

        return result
    }

    private func toggleSort(column: SortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = (column == .name) // Name defaults A-Z, numbers default high-to-low
        }
    }

    private func sortIndicator(for column: SortColumn) -> String {
        guard sortColumn == column else { return "" }
        return sortAscending ? " ↑" : " ↓"
    }

    private func statsTable(stats: [PlayerStats]) -> some View {
        List {
            Section {
                HStack {
                    Button(action: { toggleSort(column: .name) }) {
                        Text("Name\(sortIndicator(for: .name))")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Button(action: { toggleSort(column: .games) }) {
                        Text("Games\(sortIndicator(for: .games))")
                            .frame(width: 52)
                    }
                    .buttonStyle(.plain)

                    Button(action: { toggleSort(column: .rounds) }) {
                        Text("Rounds\(sortIndicator(for: .rounds))")
                            .frame(width: 60)
                    }
                    .buttonStyle(.plain)

                    Button(action: { toggleSort(column: .first) }) {
                        Text("1st\(sortIndicator(for: .first))")
                            .frame(width: 40)
                    }
                    .buttonStyle(.plain)

                    Button(action: { toggleSort(column: .second) }) {
                        Text("2nd\(sortIndicator(for: .second))")
                            .frame(width: 40)
                    }
                    .buttonStyle(.plain)

                    Button(action: { toggleSort(column: .third) }) {
                        Text("3rd\(sortIndicator(for: .third))")
                            .frame(width: 40)
                    }
                    .buttonStyle(.plain)

                    Button(action: { toggleSort(column: .rank) }) {
                        Text("Rank\(sortIndicator(for: .rank))")
                            .frame(width: 50)
                    }
                    .buttonStyle(.plain)
                }
                .font(.caption)
                .bold()
            }

            ForEach(stats) { stat in
                HStack {
                    Text(stat.displayName)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(stat.gamesPlayed)").frame(width: 52)
                    Text("\(stat.roundsPlayed)").frame(width: 60)

                    Text("\(stat.firstPlace)").frame(width: 40)
                    Text("\(stat.secondPlace)").frame(width: 40)
                    Text("\(stat.thirdPlace)").frame(width: 40)

                    Text("\(stat.rank)")
                        .frame(width: 50)
                        .bold()
                }
                .font(.body)
            }
        }
    }

    private func resetSelectedEvent() {
        guard let selectedEventId,
              let event = allEvents.first(where: { $0.id == selectedEventId }) else {
            return
        }

        do {
            try EventEngine(context: context).resetEvent(event)
            message = "Event '\(event.name)' has been reset successfully."
            showMessage = true
        } catch {
            message = error.localizedDescription
            showMessage = true
        }
    }
}

// MARK: - Stats Model

private struct PlayerStats: Identifiable {
    let id = UUID()
    let personId: UUID

    var displayName: String = ""

    /// Number of EventGames the player participated in (>= 1 completed round within the game)
    var gamesPlayed: Int = 0

    /// Number of completed rounds the player participated in (appeared on any team)
    var roundsPlayed: Int = 0

    var firstPlace: Int = 0
    var secondPlace: Int = 0
    var thirdPlace: Int = 0

    var totalPoints: Int = 0
    var rank: Int = 0
}

#Preview {
    NavigationStack {
        EventStatsView()
    }
    .modelContainer(for: [Event.self, Person.self])
    .environmentObject(ThemeManager())
}
