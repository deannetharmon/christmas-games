import SwiftUI
import Combine

// MARK: - Color Extension for Luminance
extension Color {
    // Initialize from Hex
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String? {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)
        
        if components.count >= 4 { a = Float(components[3]) }
        
        if a != 1.0 {
            return String(format: "%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }

    var isLight: Bool {
        let uiColor = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        
        if !uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return true
        }
        
        let brightness = ((red * 299) + (green * 587) + (blue * 114)) / 1000
        return brightness > 0.5
    }
}

// MARK: - Dynamic Theme Model
struct Theme: Identifiable, Equatable {
    let id: String
    
    let primary: Color
    let secondary: Color
    let background: Color
    let card: Color
    let text: Color
    let divider: Color
    let onPrimary: Color
    
    /// Create a theme from a single base color and intensity
    init(hex: String, intensity: Double) {
        self.id = hex
        
        let base = Color(hex: hex)
        
        self.primary = base
        self.secondary = base.opacity(0.6)
        
        // Get base color RGB components
        let uiBase = UIColor(base)
        var baseR: CGFloat = 0, baseG: CGFloat = 0, baseB: CGFloat = 0, baseA: CGFloat = 0
        uiBase.getRed(&baseR, green: &baseG, blue: &baseB, alpha: &baseA)
        
        // Clamp intensity to valid range (allow full 0-1 range now)
        let clampedIntensity = max(0.0, min(1.0, intensity))
        
        // Calculate the EFFECTIVE color after alpha-blending with white background
        // Formula: effectiveColor = baseColor * alpha + white * (1 - alpha)
        let effectiveR = baseR * clampedIntensity + 1.0 * (1.0 - clampedIntensity)
        let effectiveG = baseG * clampedIntensity + 1.0 * (1.0 - clampedIntensity)
        let effectiveB = baseB * clampedIntensity + 1.0 * (1.0 - clampedIntensity)
        
        // Create the light mode background using the blended color (opaque)
        let lightModeBackground = UIColor(red: effectiveR, green: effectiveG, blue: effectiveB, alpha: 1.0)
        
        self.background = Color(UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return .systemGroupedBackground
            } else {
                return lightModeBackground
            }
        })
        
        self.card = Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? .secondarySystemGroupedBackground : .white
        })
        
        self.divider = Color.gray.opacity(0.2)
        
        // Text on Primary: High contrast
        self.onPrimary = base.isLight ? Color.black : Color.white
        
        // Calculate luminance of the effective blended background
        let effectiveLuminance = (effectiveR * 0.299) + (effectiveG * 0.587) + (effectiveB * 0.114)
        // Raised threshold from 0.5 to 0.75 so text flips to white earlier
        let effectiveBgIsLight = effectiveLuminance > 0.75
        
        // For dynamic text that adapts to light/dark mode
        self.text = Color(UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return .label
            } else {
                // Light mode: flip based on effective background luminance
                return effectiveBgIsLight ? .label : .white
            }
        })
    }
}

// MARK: - Theme Manager
@MainActor
final class ThemeManager: ObservableObject {
    private let storageKeyHex = "selectedThemeHex"
    private let storageKeyIntensity = "selectedThemeIntensity"
    private let defaultHex = "B22222" // Christmas red as default
    
    @Published var selectedThemeId: String {
        didSet { updateTheme() }
    }
    
    @Published var currentIntensity: Double {
        didSet { updateTheme() }
    }
    
    @Published private(set) var currentTheme: Theme
    
    init() {
        let savedHex = UserDefaults.standard.string(forKey: storageKeyHex) ?? defaultHex
        let savedIntensityDouble = UserDefaults.standard.double(forKey: storageKeyIntensity)
        let resolvedIntensity = savedIntensityDouble == 0 ? 0.15 : savedIntensityDouble
        
        self.selectedThemeId = savedHex
        self.currentIntensity = resolvedIntensity
        self.currentTheme = Theme(hex: savedHex, intensity: resolvedIntensity)
    }
    
    private func updateTheme() {
        UserDefaults.standard.set(selectedThemeId, forKey: storageKeyHex)
        UserDefaults.standard.set(currentIntensity, forKey: storageKeyIntensity)
        self.currentTheme = Theme(hex: selectedThemeId, intensity: currentIntensity)
    }
    
    // Convenience Proxies
    var primary: Color { currentTheme.primary }
    var secondary: Color { currentTheme.secondary }
    var background: Color { currentTheme.background }
    var card: Color { currentTheme.card }
    var text: Color { currentTheme.text }
    var divider: Color { currentTheme.divider }
    var onPrimary: Color { currentTheme.onPrimary }
}

// MARK: - Team Colors for Gameplay
extension ThemeManager {
    /// Get team colors that work well with the current theme
    /// Returns a set of 6 distinct colors suitable for team identification
    var teamColors: [Color] {
        // Use classic, high-contrast team colors that work with any theme
        return [
            .red,
            .blue,
            .green,
            .orange,
            .purple,
            Color(red: 0.0, green: 0.7, blue: 0.7)  // Teal
        ]
    }
    
    /// Get status color for events
    func statusColor(_ status: EventStatus) -> Color {
        switch status {
        case .available: return .gray
        case .active: return primary
        case .paused: return .orange
        case .completed: return .blue
        }
    }
}
