import SwiftUI
import SwiftData

/// Main Menu matching the PDF wireframe (vertical menu buttons).
/// Order (per wireframe): Events → Game Catalog → Participant Catalog → Start/Resume Event → Event Stats
struct MainMenuView: View {
    @Query(sort: \Event.createdAt, order: .reverse)
    private var events: [Event]

    @Query(sort: \Person.displayName)
    private var people: [Person]

    @Query(sort: \GameTemplate.name)
    private var games: [GameTemplate]
    
    @StateObject private var themeManager = ThemeManager()
    @State private var showThemeSettings = false
    @State private var showGameSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Solid color background based on theme
                themeManager.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    header

                    ScrollView {
                        VStack(spacing: 14) {
                            NavigationLink {
                                EventsListView()
                                    .environmentObject(themeManager)
                            } label: {
                                MenuRow(
                                    title: "Events",
                                    subtitle: "\(events.count) total",
                                    systemImage: "calendar"
                                )
                            }

                            NavigationLink {
                                GameCatalogView()
                                    .environmentObject(themeManager)
                            } label: {
                                MenuRow(
                                    title: "Game Catalog",
                                    subtitle: "\(games.count) games",
                                    systemImage: "list.bullet.rectangle"
                                )
                            }

                            NavigationLink {
                                ParticipantCatalogView()
                                    .environmentObject(themeManager)
                            } label: {
                                MenuRow(
                                    title: "Participant Catalog",
                                    subtitle: "\(people.count) participants",
                                    systemImage: "person.3"
                                )
                            }

                            NavigationLink {
                                EventStatsView()
                                    .environmentObject(themeManager)
                            } label: {
                                MenuRow(
                                    title: "Event Stats",
                                    subtitle: "Results grid",
                                    systemImage: "chart.bar"
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showGameSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .foregroundColor(themeManager.text)
                            .font(.title3)
                    }
                    
                    Button {
                        showThemeSettings = true
                    } label: {
                        Image(systemName: "paintpalette.fill")
                            .foregroundColor(themeManager.text)
                            .font(.title3)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showThemeSettings) {
                ThemeSettingsView()
                    .environmentObject(themeManager)
            }
            .sheet(isPresented: $showGameSettings) {
                GameSettingsView()
                    .environmentObject(themeManager)
            }
        }
        .environmentObject(themeManager)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Harmon Family Games")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(themeManager.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

private struct MenuRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 28)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 2)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Theme Settings View

struct ThemeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var selectedColor: Color = .red
    @State private var themeIntensity: Double = 0.15
    
    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Preview Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Preview")
                                .font(.title2)
                                .bold()
                                .foregroundColor(themeManager.primary)
                            
                            VStack(spacing: 16) {
                                // Sample card showing how the theme looks
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(themeManager.primary)
                                        Text("Sample Item")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                    }
                                    Text("This is how text will appear with your theme")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(themeManager.card)
                                .cornerRadius(12)
                                
                                // Sample button
                                Button(action: {}) {
                                    Text("Sample Button")
                                        .font(.headline)
                                        .foregroundColor(themeManager.onPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(themeManager.primary)
                                        .cornerRadius(12)
                                }
                            }
                        }
                        .padding()
                        .background(themeManager.card)
                        .cornerRadius(12)
                        
                        // Color Picker Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Theme & Background")
                                .font(.title2)
                                .bold()
                                .foregroundColor(themeManager.primary)
                            
                            ColorPicker(selection: $selectedColor, supportsOpacity: false) {
                                Text("Pick your primary color")
                                    .foregroundColor(.primary)
                            }
                            .padding()
                            .background(themeManager.card)
                            .cornerRadius(8)
                            .onChange(of: selectedColor) { _, newValue in
                                if let hex = newValue.toHex() {
                                    themeManager.selectedThemeId = hex
                                }
                            }
                            
                            // Intensity Slider
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Background Intensity")
                                    Spacer()
                                    Text("\(Int(themeIntensity * 100))%")
                                        .font(.caption)
                                        .bold()
                                        .foregroundColor(themeManager.secondary)
                                }
                                
                                Slider(value: $themeIntensity, in: 0.05...1.0, step: 0.05)
                                    .tint(themeManager.primary)
                                    .onChange(of: themeIntensity) { _, newValue in
                                        themeManager.currentIntensity = newValue
                                    }
                            }
                            .padding()
                            .background(themeManager.card)
                            .cornerRadius(8)
                        }
                        .padding()
                        .background(themeManager.card)
                        .cornerRadius(12)
                        
                        // Quick Color Presets
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Quick Presets")
                                .font(.title2)
                                .bold()
                                .foregroundColor(themeManager.primary)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                ColorPresetButton(name: "Christmas", color: Color(hex: "B22222"), selectedColor: $selectedColor)
                                ColorPresetButton(name: "Ocean", color: Color(hex: "1A5490"), selectedColor: $selectedColor)
                                ColorPresetButton(name: "Forest", color: Color(hex: "228B22"), selectedColor: $selectedColor)
                                ColorPresetButton(name: "Sunset", color: Color(hex: "CC5500"), selectedColor: $selectedColor)
                                ColorPresetButton(name: "Purple", color: Color(hex: "6A0DAD"), selectedColor: $selectedColor)
                                ColorPresetButton(name: "Classic", color: Color(hex: "007AFF"), selectedColor: $selectedColor)
                            }
                        }
                        .padding()
                        .background(themeManager.card)
                        .cornerRadius(12)
                    }
                    .padding()
                }
            }
            .navigationTitle("Theme Settings")
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
        .onAppear {
            selectedColor = Color(hex: themeManager.selectedThemeId)
            themeIntensity = themeManager.currentIntensity
        }
    }
}

// MARK: - Color Preset Button

private struct ColorPresetButton: View {
    let name: String
    let color: Color
    @Binding var selectedColor: Color
    
    var body: some View {
        Button {
            selectedColor = color
        } label: {
            VStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    )
                
                Text(name)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}
