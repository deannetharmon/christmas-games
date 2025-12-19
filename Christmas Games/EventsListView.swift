import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct EventsListView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Event.createdAt, order: .reverse)
    private var events: [Event]

    @State private var showAddEvent = false

    var body: some View {
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
        .navigationTitle("Events")
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
        case status = "Status"
    }
    
    enum StatusFilter: String, CaseIterable {
        case all = "All"
        case notStarted = "Not Started"
        case inProgress = "In Progress"
        case completed = "Completed"
    }

    var body: some View {
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
                
                // Sort and Status Filter
                HStack {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Picker("Status", selection: $statusFilter) {
                        ForEach(StatusFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Games (\(filteredAndSortedGames.count))")
            }
            
            // Games list
            Section {
                ForEach(filteredAndSortedGames) { eg in
                    gameRow(for: eg)
                }
            }
        }
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
    ToolbarItem(placement: .topBarLeading) {
        lifecycleButton()
    }
    ToolbarItemGroup(placement: .topBarTrailing) {
        // Only show Reset when event is not active
        if event.status != .active {
            Button("Reset") {
                message = "This will reset all games and statistics. Continue?"
                showResetConfirm = true
            }
        }
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
    
    // MARK: - Computed Properties
    
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
        switch event.status {
        case .available: return .secondary
        case .active: return .green
        case .paused: return .orange
        case .completed: return .blue
        }
    }
    
    private var availableTeamSizes: [Int] {
        let sizes = Set(event.eventGames.compactMap { eg -> Int? in
            let template = templates.first(where: { $0.id == eg.gameTemplateId })
            return eg.overridePlayersPerTeam ?? template?.defaultPlayersPerTeam
        })
        return sizes.sorted()
    }
    
    private var availableTeamCounts: [Int] {
        let counts = Set(event.eventGames.compactMap { eg -> Int? in
            let template = templates.first(where: { $0.id == eg.gameTemplateId })
            return eg.overrideTeamCount ?? template?.defaultTeamCount
        })
        return counts.sorted()
    }
    
    private var filteredAndSortedGames: [EventGame] {
        var games = event.eventGames
        
        // Apply status filter
        switch statusFilter {
        case .all:
            break
        case .notStarted:
            games = games.filter { $0.status == .notStarted }
        case .inProgress:
            games = games.filter { $0.status == .inProgress }
        case .completed:
            games = games.filter { $0.status == .completed }
        }
        
        // Apply team size filter
        if let filterTeamSize {
            games = games.filter { eg in
                let template = templates.first(where: { $0.id == eg.gameTemplateId })
                let playersPerTeam = eg.overridePlayersPerTeam ?? template?.defaultPlayersPerTeam ?? 0
                return playersPerTeam == filterTeamSize
            }
        }
        
        // Apply team count filter
        if let filterTeamCount {
            games = games.filter { eg in
                let template = templates.first(where: { $0.id == eg.gameTemplateId })
                let teamCount = eg.overrideTeamCount ?? template?.defaultTeamCount ?? 0
                return teamCount == filterTeamCount
            }
        }
        
        // Apply sort
        switch sortOption {
        case .orderIndex:
            games.sort { $0.orderIndex < $1.orderIndex }
        case .alphabetical:
            games.sort { game1, game2 in
                let name1 = templates.first(where: { $0.id == game1.gameTemplateId })?.name ?? ""
                let name2 = templates.first(where: { $0.id == game2.gameTemplateId })?.name ?? ""
                return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
            }
        case .status:
            games.sort { game1, game2 in
                if game1.statusRaw != game2.statusRaw {
                    return game1.statusRaw < game2.statusRaw
                }
                return game1.orderIndex < game2.orderIndex
            }
        }
        
        return games
    }
    
    // MARK: - Game Row
    
    private func gameRow(for eg: EventGame) -> some View {
        let template = templates.first(where: { $0.id == eg.gameTemplateId })
        let name = template?.name ?? "Unknown Game"
        let teamCount = eg.overrideTeamCount ?? template?.defaultTeamCount ?? 2
        let playersPerTeam = eg.overridePlayersPerTeam ?? template?.defaultPlayersPerTeam ?? 2
        
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.body)
                
                Text("\(teamCount) teams × \(playersPerTeam) players")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(eg.statusRaw.capitalized)
                .font(.caption)
                .foregroundStyle(gameStatusColor(eg.status))
        }
    }
    
    private func gameStatusColor(_ status: GameStatus) -> Color {
        switch status {
        case .notStarted: return .secondary
        case .inProgress: return .green
        case .completed: return .blue
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

#Preview {
    EventsListView()
        .modelContainer(for: [Event.self, Person.self, GameTemplate.self])
}
