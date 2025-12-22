import SwiftUI
import SwiftData

/// Shows live stats for a specific event in a dismissible sheet
struct CurrentEventStatsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject var themeManager: ThemeManager
    
    let event: Event
    
    @Query(sort: \Person.displayName)
    private var people: [Person]
    
    @State private var sortColumn: SortColumn = .rank
    @State private var sortAscending: Bool = true
    
    enum SortColumn {
        case name, games, first, second, third, rank
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.background
                    .ignoresSafeArea()
                
                if let stats = calculatedStats {
                    statsTable(stats: stats)
                        .scrollContentBackground(.hidden)
                } else {
                    ContentUnavailableView(
                        "No Stats Yet",
                        systemImage: "chart.bar",
                        description: Text("Play some games to see statistics.")
                    )
                    .padding()
                }
            }
            .navigationTitle("Current Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(themeManager.primary)
                }
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
            sortAscending = column == .name ? true : false // Name defaults to A-Z, numbers default to high-to-low
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
                            .frame(width: 50)
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
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Event.self, Person.self, configurations: config)
    
    let event = Event(name: "Test Event")
    container.mainContext.insert(event)
    
    return CurrentEventStatsSheet(event: event)
        .modelContainer(container)
        .environmentObject(ThemeManager())
}
