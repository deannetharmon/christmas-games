import SwiftUI

struct GameSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    // Existing toggle (keep this)
    @AppStorage("gameTransitionSound") private var soundEnabled: Bool = true

    // NEW: which sound to use
    // Values: "random", "jeopardy1", "jeopardy2", "jeopardy3", "off"
    @AppStorage("transitionSoundName") private var transitionSoundName: String = "random"

    var body: some View {
        NavigationStack {
            List {

                // MARK: - Game Transitions
                Section {
                    Toggle("Enable Transition Sound", isOn: $soundEnabled)

                    Picker("Transition Sound", selection: $transitionSoundName) {
                        Text("Random").tag("random")
                        Text("Jeopardy 1").tag("jeopardy1")
                        Text("Jeopardy 2").tag("jeopardy2")
                        Text("Jeopardy 3").tag("jeopardy3")
                        Text("Off").tag("off")
                    }
                    .disabled(!soundEnabled)

                } header: {
                    Text("Game Transitions")
                } footer: {
                    Text("Choose which sound plays while the app is selecting the next game.")
                }
            }
            .navigationTitle("Settings")
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
}

#Preview {
    GameSettingsView()
        .environmentObject(ThemeManager())
}
