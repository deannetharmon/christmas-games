import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct GameCatalogView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \GameTemplate.name)
    private var templates: [GameTemplate]

    @State private var showCreateTemplate = false
    @State private var showCSVImporter = false
    @State private var editingTemplate: GameTemplate?

    @State private var pendingCSVData: Data?
    @State private var pendingCSVFilename: String?
    @State private var showCSVPreview = false

    @State private var alertTitle = "Message"
    @State private var alertMessage: String?
    @State private var showAlert = false
    
    // Filter and sort state
    @AppStorage("gameCatalog_filterTeamSize") private var filterTeamSize: Int?
    @AppStorage("gameCatalog_filterTeamCount") private var filterTeamCount: Int?
    @AppStorage("gameCatalog_sortOption") private var sortOption: SortOption = .alphabetical
    @AppStorage("gameCatalog_teamTypeFilter") private var teamTypeFilter: TeamTypeFilter = .all
    
    enum SortOption: String, CaseIterable, Codable {
        case alphabetical = "A-Z"
        case reverseAlphabetical = "Z-A"
        case status = "Status"
    }
    
    enum TeamTypeFilter: String, CaseIterable, Codable {
        case all = "All"
        case any = "Any"
        case maleOnly = "Male Only"
        case femaleOnly = "Female Only"
        case couplesOnly = "Couples Only"
    }

    var body: some View {
        List {
            // Filters section
            Section {
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
            } header: {
                Text("Games (\(filteredAndSortedTemplates.count))")
            }
            
            // Games list
            Section {
                ForEach(filteredAndSortedTemplates) { template in
                    Button {
                        editingTemplate = template
                    } label: {
                        gameRow(for: template)
                    }
                }
                .onDelete(perform: deleteTemplates)
            }
        }
        .navigationTitle("Game Catalog")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Add") { showCreateTemplate = true }
                Button("Import CSV") { showCSVImporter = true }
            }
        }
        .sheet(isPresented: $showCreateTemplate) {
            CreateGameTemplateSheet { _ in }
        }
        .sheet(item: $editingTemplate) { template in
            EditGameTemplateSheet(template: template)
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
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage ?? "Unknown error")
        }
    }
    
    // MARK: - Computed Properties
    
    private var availableTeamSizes: [Int] {
        Set(templates.map { $0.defaultPlayersPerTeam }).sorted()
    }
    
    private var availableTeamCounts: [Int] {
        Set(templates.map { $0.defaultTeamCount }).sorted()
    }
    
    private var filteredAndSortedTemplates: [GameTemplate] {
        var result = templates
        
        // Apply team size filter
        if let filterTeamSize {
            result = result.filter { $0.defaultPlayersPerTeam == filterTeamSize }
        }
        
        // Apply team count filter
        if let filterTeamCount {
            result = result.filter { $0.defaultTeamCount == filterTeamCount }
        }
        
        // Apply team type filter
        switch teamTypeFilter {
        case .all:
            break
        case .any:
            result = result.filter { $0.defaultTeamType == .any }
        case .maleOnly:
            result = result.filter { $0.defaultTeamType == .maleOnly }
        case .femaleOnly:
            result = result.filter { $0.defaultTeamType == .femaleOnly }
        case .couplesOnly:
            result = result.filter { $0.defaultTeamType == .couplesOnly }
        }
        
        // Apply sort
        switch sortOption {
        case .alphabetical:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .reverseAlphabetical:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .status:
            // For GameCatalog, we can sort by group name as a proxy for "status"
            result.sort { lhs, rhs in
                let lGroup = lhs.groupName ?? ""
                let rGroup = rhs.groupName ?? ""
                if lGroup != rGroup {
                    return lGroup.localizedCaseInsensitiveCompare(rGroup) == .orderedAscending
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
        
        return result
    }
    
    private func gameRow(for template: GameTemplate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.name)
                .font(.body)
                .foregroundStyle(.primary)
            
            HStack {
                if let group = template.groupName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !group.isEmpty {
                    Text(group)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Text("Teams: \(template.defaultTeamCount) × \(template.defaultPlayersPerTeam)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                Text("•")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                Text("Rounds: \(template.defaultRoundsPerGame)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deleteTemplates(at offsets: IndexSet) {
        for index in offsets {
            let template = filteredAndSortedTemplates[index]
            if let original = templates.first(where: { $0.id == template.id }) {
                context.delete(original)
            }
        }
        try? context.save()
    }
}

// MARK: - Edit Game Template Sheet

private struct EditGameTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let template: GameTemplate

    @State private var name = ""
    @State private var groupName = ""
    @State private var defaultTeamCount = 2
    @State private var defaultPlayersPerTeam = 2
    @State private var defaultRoundsPerGame = 1
    @State private var teamType: TeamType = .any
    @State private var playInstructions = ""
    @State private var setupInstructions = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Name", text: $name)
                    TextField("Group (optional)", text: $groupName)
                }

                Section("Defaults") {
                    Stepper("Teams: \(defaultTeamCount)", value: $defaultTeamCount, in: 1...20)
                    Stepper("Players per Team: \(defaultPlayersPerTeam)", value: $defaultPlayersPerTeam, in: 1...20)
                    Stepper("Rounds: \(defaultRoundsPerGame)", value: $defaultRoundsPerGame, in: 1...50)

                    Picker("Team Type", selection: $teamType) {
                        Text("Any").tag(TeamType.any)
                        Text("Male Only").tag(TeamType.maleOnly)
                        Text("Female Only").tag(TeamType.femaleOnly)
                        Text("Couples Only").tag(TeamType.couplesOnly)
                    }
                }

                Section("Instructions") {
                    TextField("Setup Instructions (optional)", text: $setupInstructions, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Playing Instructions (optional)", text: $playInstructions, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Edit Game Template")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = template.name
                groupName = template.groupName ?? ""
                defaultTeamCount = template.defaultTeamCount
                defaultPlayersPerTeam = template.defaultPlayersPerTeam
                defaultRoundsPerGame = template.defaultRoundsPerGame
                teamType = template.defaultTeamType
                playInstructions = template.playInstructions ?? ""
                setupInstructions = template.setupInstructions ?? ""
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        template.name = trimmedName
        template.groupName = groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : groupName
        template.defaultTeamCount = defaultTeamCount
        template.defaultPlayersPerTeam = defaultPlayersPerTeam
        template.defaultRoundsPerGame = defaultRoundsPerGame
        template.defaultTeamType = teamType
        template.playInstructions = playInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : playInstructions
        template.setupInstructions = setupInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : setupInstructions

        try? context.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        GameCatalogView()
    }
    .modelContainer(for: [GameTemplate.self])
}
