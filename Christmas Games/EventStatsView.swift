import SwiftUI
import SwiftData

struct EventStatsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorTheme) private var theme

    @Query(sort: \Event.createdAt, order: .reverse)
    private var allEvents: [Event]

    @Query(sort: \Person.displayName)
    private var people: [Person]

    @State private var selectedEventId: UUID?

    @State private var showResetConfirm = false
    @State private var message: String?
    @State private var showMessage = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.gradientStart, theme.gradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { showResetConfirm = true }
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

                    // Handle ties (when resultType == .tie and winningTeamId == nil)
                    if round.resultType == .tie, round.winningTeamId == nil {
                        for team in round.teams {
                            for personId in team.memberPersonIds {
                                var stat = statsDict[personId] ?? PlayerStats(personId: personId)
                                if round.placements[personId] == nil {
                                    stat.gamesPlayed += 1
                                }
                                stat.firstPlace += 1 // Tie counts as 1st place for all
                                statsDict[personId] = stat
                            }
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

    private func statsTable(stats: [PlayerStats]) -> some View {
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
                    Text("\(stat.gamesPlayed)").frame(width: 50)
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
    var gamesPlayed: Int = 0
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
}
