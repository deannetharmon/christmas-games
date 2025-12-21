import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct EventsListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorTheme) private var theme

    @Query(sort: \Event.createdAt, order: .reverse)
    private var events: [Event]

    @State private var showAddEvent = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.gradientStart, theme.gradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

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
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Events")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Event") { showAddEvent = true }
            }
        }
        .sheet(isPresented: $showAddEvent) {
            AddEventSheet()
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
    @Environment(\.colorTheme) private var theme

    let event: Event

    @Query(sort: \GameTemplate.name)
    private var templates: [GameTemplate]

    @State private var showAddGame = false
    @State private var showPlayers = false
    @State private var showResetConfirm = false

    @State private var message: String?
    @State private var showMessage = false

    // Filter and sort state
    @State private var filterTeamSize: Int? = nil
    @State private var filterTeamCount: Int? = nil
    @State private var sortOption: SortOption = .orderIndex
    @State private var statusFilter: StatusFilter = .all

    enum SortOption: String, CaseIterable {
        case orderIndex = "Order"
        case alphabetical = "A-Z"
        case reverseAlphabetical = "Z-A"
        case status = "Status"
    }

    enum StatusFilter: String, CaseIterable {
        case all = "All"
        case notStarted = "Not Started"
        case inProgress = "In Progress"
        case completed = "Completed"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.gradientStart, theme.gradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            List {
                // Compact stats section
                Section {
                    HStack {
                        Label("\(event.participantIds.count)", systemImage: "person.2")
                        Spacer()
                        Label("\(completedGamesCount)/\(event.eventGames.count)", systemImage: "gamecontroller")
                        Spacer()
                        Label(event.statusRaw.capitalized, systemImage: statusIcon)
                            .foregroundStyle(statusColor)
                    }
                    .font(.subheadline)
                }

                Section {
                    NavigationLink("Run Event") {
                        RunGameView(event: event)
                    }
                    .disabled(event.eventGames.isEmpty || event.participantIds.isEmpty)
                } header: {
                    Text("Host")
                }

                Section {
                    // Filters
                    HStack {
                        Picker("Team Size", selection: $filterTeamSize) {
                            Text("Any").tag(Int?.none)
                            ForEach(allTeamSizes, id: \.self) { size in
                                Text("\(size)").tag(Int?.some(size))
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Team Count", selection: $filterTeamCount) {
                            Text("Any").tag(Int?.none)
                            ForEach(allTeamCounts, id: \.self) { count in
                                Text("\(count)").tag(Int?.some(count))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Picker("Status", selection: $statusFilter) {
                        ForEach(StatusFilter.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Sort", selection: $sortOption) {
                        ForEach(SortOption.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Filters & Sort")
                }

                Section {
                    Button("Participants") { showPlayers = true }
                        .disabled(event.participantIds.isEmpty)
                } header: {
                    Text("Manage")
                }

                Section {
                    Button("Add Games") { showAddGame = true }
                    Button("Reset Event", role: .destructive) { showResetConfirm = true }
                } header: {
                    Text("Actions")
                }

                Section {
                    ForEach(filteredAndSortedGames) { eg in
                        NavigationLink {
                            EventGameDetailView(event: event, eventGame: eg)
                        } label: {
                            gameRow(for: eg)
                        }
                    }
                    .onDelete(perform: deleteEventGames)
                    .onMove(perform: moveEventGames)
                } header: {
                    Text("Games")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                lifecycleButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showPlayers) {
            ParticipantPickerSheet(event: event)
        }
        .sheet(isPresented: $showAddGame) {
            AddGamesSheet(event: event, templates: templates)
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
                    message = error.localizedDescription
                    showMessage = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will reset all games to 'not started', delete all rounds and statistics. Participants will be kept.")
        }
    }

    // MARK: - Derived data

    private var engine: EventEngine { EventEngine(context: context) }

    private var completedGamesCount: Int {
        event.eventGames.filter { $0.status == .completed }.count
    }

    private var statusIcon: String {
        switch event.status {
        case .available: return "pause.circle"
        case .active: return "play.circle"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        theme.statusColor(event.status)
    }

    private var allTeamSizes: [Int] {
        let values = event.eventGames.compactMap { eg -> Int? in
            if let t = templates.first(where: { $0.id == eg.gameTemplateId }) {
                return eg.overridePlayersPerTeam ?? t.defaultPlayersPerTeam
            }
            return nil
        }
        return Array(Set(values)).sorted()
    }

    private var allTeamCounts: [Int] {
        let values = event.eventGames.compactMap { eg -> Int? in
            if let t = templates.first(where: { $0.id == eg.gameTemplateId }) {
                return eg.overrideTeamCount ?? t.defaultTeamCount
            }
            return nil
        }
        return Array(Set(values)).sorted()
    }

    private var filteredAndSortedGames: [EventGame] {
        var list = event.eventGames

        // status filter
        switch statusFilter {
        case .all:
            break
        case .notStarted:
            list = list.filter { $0.status == .notStarted }
        case .inProgress:
            list = list.filter { $0.status == .inProgress }
        case .completed:
            list = list.filter { $0.status == .completed }
        }

        // team size filter
        if let size = filterTeamSize {
            list = list.filter { eg in
                let t = templates.first(where: { $0.id == eg.gameTemplateId })
                let playersPerTeam = eg.overridePlayersPerTeam ?? t?.defaultPlayersPerTeam ?? 0
                return playersPerTeam == size
            }
        }

        // team count filter
        if let count = filterTeamCount {
            list = list.filter { eg in
                let t = templates.first(where: { $0.id == eg.gameTemplateId })
                let teamCount = eg.overrideTeamCount ?? t?.defaultTeamCount ?? 0
                return teamCount == count
            }
        }

        // sorting
        switch sortOption {
        case .orderIndex:
            list = list.sorted { $0.orderIndex < $1.orderIndex }
        case .alphabetical:
            list = list.sorted {
                gameName(for: $0).localizedCaseInsensitiveCompare(gameName(for: $1)) == .orderedAscending
            }
        case .reverseAlphabetical:
            list = list.sorted {
                gameName(for: $0).localizedCaseInsensitiveCompare(gameName(for: $1)) == .orderedDescending
            }
        case .status:
            list = list.sorted { $0.statusRaw < $1.statusRaw }
        }

        return list
    }

    // MARK: - UI pieces

    private var lifecycleButton: some View {
        Menu {
            Button("Start") {
                do { try engine.startEvent(event) } catch { present(error) }
            }
            Button("Pause") {
                do { try engine.pauseEvent(event) } catch { present(error) }
            }
            Button("Resume") {
                do { try engine.resumeEvent(event) } catch { present(error) }
            }
            Button("Complete") {
                do { try engine.completeEvent(event) } catch { present(error) }
            }
        } label: {
            Text("Event")
        }
    }

    private func gameName(for eg: EventGame) -> String {
        templates.first(where: { $0.id == eg.gameTemplateId })?.name ?? "Unknown"
    }

    private func gameRow(for eg: EventGame) -> some View {
        let t = templates.first(where: { $0.id == eg.gameTemplateId })
        let name = t?.name ?? "Unknown Game"

        let teamCount = eg.overrideTeamCount ?? t?.defaultTeamCount ?? 2
        let playersPerTeam = eg.overridePlayersPerTeam ?? t?.defaultPlayersPerTeam ?? 2

        let group = t?.groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupText = (group?.isEmpty == false) ? group! : nil

        let subtitleBits = [
            groupText,
            "Teams: \(teamCount) × \(playersPerTeam)",
            "Status: \(eg.statusRaw.capitalized)"
        ].compactMap { $0 }

        return VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.body)
            Text(subtitleBits.joined(separator: " • "))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Mutations

    private func deleteEventGames(at offsets: IndexSet) {
        for index in offsets {
            let eg = filteredAndSortedGames[index]
            context.delete(eg)
            if let i = event.eventGames.firstIndex(where: { $0.id == eg.id }) {
                event.eventGames.remove(at: i)
            }
        }
        try? context.save()
    }

    private func moveEventGames(from source: IndexSet, to destination: Int) {
        // Move within the underlying array using the view's ordering
        var underlying = filteredAndSortedGames
        underlying.move(fromOffsets: source, toOffset: destination)

        // Re-apply orderIndex according to new ordering
        for (i, eg) in underlying.enumerated() {
            eg.orderIndex = i
        }

        // Also update event.eventGames to keep a consistent ordering
        event.eventGames = underlying

        try? context.save()
    }

    private func present(_ error: Error) {
        message = error.localizedDescription
        showMessage = true
    }
}

#Preview {
    EventsListView()
        .modelContainer(for: [Event.self, Person.self, GameTemplate.self])
}
