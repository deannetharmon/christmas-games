import SwiftUI
import SwiftData

struct CreateGameTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let onCreated: (GameTemplate) -> Void

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
            .navigationTitle("New Game Template")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let template = GameTemplate(
            externalId: "user_\(UUID().uuidString.lowercased())",
            name: trimmedName,
            groupName: groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : groupName,
            defaultTeamCount: defaultTeamCount,
            defaultPlayersPerTeam: defaultPlayersPerTeam,
            defaultRoundsPerGame: defaultRoundsPerGame,
            defaultTeamType: teamType,
            playInstructions: playInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : playInstructions,
            setupInstructions: setupInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : setupInstructions
        )

        context.insert(template)
        try? context.save()

        onCreated(template)
        dismiss()
    }
}
