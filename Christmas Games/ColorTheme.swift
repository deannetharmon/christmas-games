import SwiftUI

// MARK: - Color Theme System

enum ColorTheme: String, CaseIterable, Identifiable {
    case christmas = "Christmas"
    case ocean = "Ocean"
    case sunset = "Sunset"
    case forest = "Forest"
    case classic = "Classic"
    
    var id: String { rawValue }
    
    // Background gradient colors
    var gradientStart: Color {
        switch self {
        case .christmas:
            return Color(red: 0.7, green: 0.15, blue: 0.15)  // Deep red
        case .ocean:
            return Color(red: 0.1, green: 0.3, blue: 0.6)    // Deep blue
        case .sunset:
            return Color(red: 0.8, green: 0.3, blue: 0.2)    // Orange-red
        case .forest:
            return Color(red: 0.15, green: 0.4, blue: 0.2)   // Dark green
        case .classic:
            return Color(red: 0.3, green: 0.3, blue: 0.35)   // Neutral gray
        }
    }
    
    var gradientEnd: Color {
        switch self {
        case .christmas:
            return Color(red: 0.15, green: 0.5, blue: 0.2)   // Forest green
        case .ocean:
            return Color(red: 0.1, green: 0.5, blue: 0.5)    // Teal
        case .sunset:
            return Color(red: 0.9, green: 0.6, blue: 0.3)    // Golden
        case .forest:
            return Color(red: 0.3, green: 0.6, blue: 0.3)    // Light green
        case .classic:
            return Color(red: 0.5, green: 0.5, blue: 0.55)   // Light gray
        }
    }
    
    // Team colors for gameplay
    var teamColors: [Color] {
        switch self {
        case .christmas:
            return [
                .red,
                Color(red: 0.0, green: 0.5, blue: 0.2),      // Green
                Color(red: 0.8, green: 0.7, blue: 0.2),      // Gold
                .white,
                Color(red: 0.6, green: 0.3, blue: 0.0),      // Brown
                Color(red: 0.3, green: 0.3, blue: 0.8)       // Blue
            ]
        case .ocean:
            return [
                Color(red: 0.0, green: 0.3, blue: 0.8),      // Deep blue
                Color(red: 0.0, green: 0.7, blue: 0.7),      // Cyan
                Color(red: 0.3, green: 0.5, blue: 0.9),      // Light blue
                Color(red: 0.0, green: 0.5, blue: 0.5),      // Teal
                Color(red: 0.5, green: 0.7, blue: 1.0),      // Sky blue
                Color(red: 0.0, green: 0.4, blue: 0.6)       // Navy
            ]
        case .sunset:
            return [
                Color(red: 0.9, green: 0.3, blue: 0.2),      // Red-orange
                Color(red: 1.0, green: 0.6, blue: 0.2),      // Orange
                Color(red: 1.0, green: 0.8, blue: 0.3),      // Yellow
                Color(red: 0.8, green: 0.4, blue: 0.6),      // Pink
                Color(red: 0.6, green: 0.3, blue: 0.8),      // Purple
                Color(red: 0.9, green: 0.5, blue: 0.3)       // Peach
            ]
        case .forest:
            return [
                Color(red: 0.2, green: 0.6, blue: 0.3),      // Green
                Color(red: 0.4, green: 0.5, blue: 0.2),      // Olive
                Color(red: 0.5, green: 0.4, blue: 0.2),      // Brown
                Color(red: 0.3, green: 0.7, blue: 0.4),      // Light green
                Color(red: 0.6, green: 0.6, blue: 0.3),      // Yellow-green
                Color(red: 0.3, green: 0.5, blue: 0.5)       // Teal
            ]
        case .classic:
            return [
                .red,
                .blue,
                .green,
                .orange,
                .purple,
                Color(red: 0.0, green: 0.7, blue: 0.7)       // Teal
            ]
        }
    }
    
    // Accent color for buttons and highlights
    var accentColor: Color {
        switch self {
        case .christmas:
            return Color(red: 0.8, green: 0.7, blue: 0.2)    // Gold
        case .ocean:
            return Color(red: 0.0, green: 0.7, blue: 0.7)    // Cyan
        case .sunset:
            return Color(red: 1.0, green: 0.6, blue: 0.2)    // Orange
        case .forest:
            return Color(red: 0.4, green: 0.7, blue: 0.3)    // Light green
        case .classic:
            return .blue
        }
    }
    
    // Status colors (can be customized per theme or kept standard)
    func statusColor(_ status: EventStatus) -> Color {
        switch status {
        case .available: return .gray
        case .active: return accentColor
        case .paused: return .orange
        case .completed: return .blue
        }
    }
    
    // Preview icon for theme picker
    var icon: String {
        switch self {
        case .christmas: return "🎄"
        case .ocean: return "🌊"
        case .sunset: return "🌅"
        case .forest: return "🌲"
        case .classic: return "⚪️"
        }
    }
}

// MARK: - Theme Manager (SwiftUI Environment)

struct ThemeKey: EnvironmentKey {
    static let defaultValue: ColorTheme = .christmas
}

extension EnvironmentValues {
    var colorTheme: ColorTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Convenience Extensions

extension View {
    func themedBackground(_ theme: ColorTheme) -> some View {
        self.background(
            LinearGradient(
                colors: [theme.gradientStart, theme.gradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}
