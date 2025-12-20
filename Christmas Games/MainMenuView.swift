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
    
    @AppStorage("selectedTheme") private var selectedThemeRaw: String = ColorTheme.christmas.rawValue
    @State private var showThemePicker = false
    
    private var selectedTheme: ColorTheme {
        ColorTheme(rawValue: selectedThemeRaw) ?? .christmas
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Themed gradient background
                LinearGradient(
                    colors: [selectedTheme.gradientStart, selectedTheme.gradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    header

                    ScrollView {
                        VStack(spacing: 14) {
                            NavigationLink {
                                EventsListView()
                            } label: {
                                MenuRow(
                                    title: "Events",
                                    subtitle: "\(events.count) total",
                                    systemImage: "calendar"
                                )
                            }

                            NavigationLink {
                                GameCatalogView()
                            } label: {
                                MenuRow(
                                    title: "Game Catalog",
                                    subtitle: "\(games.count) games",
                                    systemImage: "list.bullet.rectangle"
                                )
                            }

                            NavigationLink {
                                ParticipantCatalogView()
                            } label: {
                                MenuRow(
                                    title: "Participant Catalog",
                                    subtitle: "\(people.count) participants",
                                    systemImage: "person.3"
                                )
                            }

                            NavigationLink {
                                EventStatsView()
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showThemePicker = true
                    } label: {
                        Image(systemName: "paintpalette.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showThemePicker) {
                ThemePickerSheet(selectedTheme: $selectedThemeRaw)
            }
            .environment(\.colorTheme, selectedTheme)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Harmon Family Games")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)  // White text on colored background
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
                .fill(Color(UIColor.systemBackground))  // White/dark background for cards
                .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 2)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Theme Picker Sheet

struct ThemePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTheme: String
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(ColorTheme.allCases) { theme in
                    Button {
                        selectedTheme = theme.rawValue
                        dismiss()
                    } label: {
                        HStack(spacing: 16) {
                            // Theme preview
                            ZStack {
                                LinearGradient(
                                    colors: [theme.gradientStart, theme.gradientEnd],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .frame(width: 60, height: 60)
                                .cornerRadius(12)
                                
                                Text(theme.icon)
                                    .font(.title)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(theme.rawValue)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                // Team colors preview
                                HStack(spacing: 4) {
                                    ForEach(0..<min(6, theme.teamColors.count), id: \.self) { index in
                                        Circle()
                                            .fill(theme.teamColors[index])
                                            .frame(width: 16, height: 16)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            if selectedTheme == theme.rawValue {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Choose Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
