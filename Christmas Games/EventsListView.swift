import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct EventsListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var themeManager: ThemeManager

    @Query(sort: \Event.createdAt, order: .reverse)
    private var events: [Event]

    @State private var showAddEvent = false

    var body: some View {
        ZStack {
            themeManager.background
                .ignoresSafeArea()

            List {
                ForEach(events) { event in
                    NavigationLink {
                        EventDetailView(event: event)
                            .environmentObject(themeManager)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Event") { showAddEvent = true }
                    .foregroundColor(themeManager.text)
            }
        }
        .sheet(isPresented: $showAddEvent) {
            AddEventSheet()
                .environmentObject(themeManager)
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
    @EnvironmentObject var themeManager: ThemeManager

    let event: Event

    @Query(sort: \GameTemplate.name)
    private var templates: [GameTemplate]

    @State private var showAddGame = false
    @State private var showPlayers = false
    @State private var showResetConfirm = false
    @State private var showEventStats = false

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
        
        var gameStatus: GameStatus? {
            switch self {
            case .all: return nil
            case .notStarted: return .notStarted
            case .inProgress: return .inProgress
            case .completed: return .completed
            }
        }
    }

    var body: some View {
        ZStack {
            themeManager.background
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
                            .environmentObject(themeManager)
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
                    Button {
                        showPlayers = true
                    } label: {
                        Label("Manage Participants", systemImage: "person.3")
                    }

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
                                .environmentObject(themeManager)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(event.name)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundColor(themeManager.text)
            }
            
            ToolbarItem(placement: .topBarLeading) {
                lifecycleButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .foregroundColor(themeManager.text)
            }
        }
        .sheet(isPresented: $showPlayers) {
            ParticipantPickerSheet(event: event)
                .environmentObject(themeManager)
        }
        .sheet(isPresented: $showAddGame) {
            AddGamesSheet(event: event, templates: templates)
                .environmentObject(themeManager)
        }
        .sheet(isPresented: $showEventStats) {
            CurrentEventStatsSheet(event: event)
                .environmentObject(themeManager)
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
        case .available: return "circle"
        case .active: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        themeManager.statusColor(event.status)
    }

    private var allTeamSizes: [Int] {
        let arr = Array(Set(event.eventGames.compactMap { eg -> Int? in
            let t = templates.first(where: { $0.id == eg.gameTemplateId })
            return eg.overridePlayersPerTeam ?? t?.defaultPlayersPerTeam
        }))
        return arr.sorted()
    }

    private var allTeamCounts: [Int] {
        let arr = Array(Set(event.eventGames.compactMap { eg -> Int? in
            let t = templates.first(where: { $0.id == eg.gameTemplateId })
            return eg.overrideTeamCount ?? t?.defaultTeamCount
        }))
        return arr.sorted()
    }

    private var filteredAndSortedGames: [EventGame] {
        var games = event.eventGames

        // Apply team size filter
        if let size = filterTeamSize {
            games = games.filter { eg in
                let t = templates.first(where: { $0.id == eg.gameTemplateId })
                let ppt = eg.overridePlayersPerTeam ?? t?.defaultPlayersPerTeam ?? 0
                return ppt == size
            }
        }

        // Apply team count filter
        if let count = filterTeamCount {
            games = games.filter { eg in
                let t = templates.first(where: { $0.id == eg.gameTemplateId })
                let tc = eg.overrideTeamCount ?? t?.defaultTeamCount ?? 0
                return tc == count
            }
        }

        // Apply status filter
        if let targetStatus = statusFilter.gameStatus {
            games = games.filter { $0.status == targetStatus }
        }

        // Apply sorting
        switch sortOption {
        case .orderIndex:
            games.sort { $0.orderIndex < $1.orderIndex }
        case .alphabetical:
            games.sort { eg1, eg2 in
                let n1 = templates.first(where: { $0.id == eg1.gameTemplateId })?.name ?? ""
                let n2 = templates.first(where: { $0.id == eg2.gameTemplateId })?.name ?? ""
                return n1 < n2
            }
        case .reverseAlphabetical:
            games.sort { eg1, eg2 in
                let n1 = templates.first(where: { $0.id == eg1.gameTemplateId })?.name ?? ""
                let n2 = templates.first(where: { $0.id == eg2.gameTemplateId })?.name ?? ""
                return n1 > n2
            }
        case .status:
            games.sort { $0.statusRaw < $1.statusRaw }
        }

        return games
    }

    // MARK: - Lifecycle UI

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
                do {
                    event.status = .completed
                    event.currentEventGameId = nil
                    try context.save()
                } catch {
                    present(error)
                }
            }
            
            Divider()
            
            Button {
                showEventStats = true
            } label: {
                Label("View Stats", systemImage: "chart.bar.fill")
            }
            Button {
                showPlayers = true
            } label: {
                Label("Manage Participants", systemImage: "person.3")
            }
        } label: {
            Text("Event")
                .foregroundColor(themeManager.text)
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

// MARK: - Missing Screens (Minimal Implementations)
// These are intentionally simple so the app compiles.
// You can enhance them later without blocking builds.

private struct AddEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject var themeManager: ThemeManager

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Event name") {
                    TextField("Christmas Party", text: $name)
                }
            }
            .navigationTitle("New Event")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(themeManager.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .foregroundColor(themeManager.primary)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Your RunGameView preview proves Event(name:) exists.
        let event = Event(name: trimmed)
        context.insert(event)
        try? context.save()
        dismiss()
    }
}

private struct ParticipantPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject var themeManager: ThemeManager

    let event: Event

    @Query(sort: \Person.displayName)
    private var people: [Person]

    @State private var selected: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(people.filter { $0.isActive }) { person in
                    Button {
                        toggle(person.id)
                    } label: {
                        HStack {
                            Text(person.displayName)
                            Spacer()
                            if selected.contains(person.id) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(themeManager.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Participants")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(themeManager.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { commit() }
                        .foregroundColor(themeManager.primary)
                }
            }
            .onAppear {
                selected = Set(event.participantIds)
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func commit() {
        event.participantIds = Array(selected)
        try? context.save()
        dismiss()
    }
}

private struct AddGamesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    let event: Event
    let templates: [GameTemplate]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This screen is a minimal placeholder so the project builds.")
                        .foregroundStyle(.secondary)
                    Text("Next step is wiring this to create EventGame records from selected GameTemplates.")
                        .foregroundStyle(.secondary)
                }

                Section("Templates in catalog") {
                    ForEach(templates) { t in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.name).font(.headline)
                            if let group = t.groupName, !group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(group).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Games")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(themeManager.primary)
                }
            }
        }
    }
}

private struct EventGameDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    let event: Event
    let eventGame: EventGame

    var body: some View {
        Form {
            Section("Game") {
                Text("This is a placeholder detail view.")
                    .foregroundStyle(.secondary)
            }
            Section("IDs") {
                Text("EventGame ID: \(eventGame.id.uuidString)")
            }
        }
        .navigationTitle("Game Detail")
    }
}


#Preview {
    EventsListView()
        .modelContainer(for: [Event.self, Person.self, GameTemplate.self])
        .environmentObject(ThemeManager())
}
