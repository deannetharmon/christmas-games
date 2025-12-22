# Theme System Implementation Guide

## Files to Add/Replace

### 1. **ColorTheme.swift** (NEW FILE - Add to Xcode)
- Add this as a new file to your Xcode project
- Contains the complete theme system with 5 color schemes:
  - 🎄 Christmas (red → green)
  - 🌊 Ocean (blue → teal)
  - 🌅 Sunset (orange → golden)
  - 🌲 Forest (dark green → light green)
  - ⚪️ Classic (neutral gray)

### 2. **MainMenuView.swift** (REPLACE)
- Replace your existing MainMenuView.swift
- Adds paint palette button in top-right
- Tap to open theme picker
- Selected theme persists across app launches

### 3. **RunGameView.swift** (REPLACE)
- Replace your existing RunGameView.swift
- Team colors now automatically match selected theme
- No code changes needed - just uses theme

---

## How It Works

### User Experience
1. **Open app** → See main menu with current theme gradient
2. **Tap paint palette icon** (top-right) → Theme picker opens
3. **See 5 themes** with:
   - Preview gradient box
   - Theme name
   - 6 colored dots showing team colors
   - Checkmark on selected theme
4. **Tap any theme** → Instantly applies and saves
5. **Close picker** → Theme persists forever (saved in UserDefaults)

### Theme Applied To:
✅ Main menu background gradient
✅ Team A, B, C, D, E, F colors in RunGameView
✅ Accent colors (ready for future use)
✅ Status colors (ready for future use)

---

## Theme Details

### Christmas 🎄
- Gradient: Deep red → Forest green
- Teams: Red, Green, Gold, White, Brown, Blue
- Accent: Gold

### Ocean 🌊
- Gradient: Deep blue → Teal
- Teams: Deep blue, Cyan, Light blue, Teal, Sky blue, Navy
- Accent: Cyan

### Sunset 🌅
- Gradient: Orange-red → Golden
- Teams: Red-orange, Orange, Yellow, Pink, Purple, Peach
- Accent: Orange

### Forest 🌲
- Gradient: Dark green → Light green
- Teams: Green, Olive, Brown, Light green, Yellow-green, Teal
- Accent: Light green

### Classic ⚪️
- Gradient: Neutral gray
- Teams: Red, Blue, Green, Orange, Purple, Teal
- Accent: Blue

---

## Adding Theme to Other Views (Future)

To use theme in any other view:

```swift
struct MyView: View {
    @Environment(\.colorTheme) private var theme
    
    var body: some View {
        Text("Hello")
            .foregroundColor(theme.accentColor)
    }
}
```

Theme is automatically passed down through SwiftUI's environment!

---

## Persistence

Theme choice is saved using `@AppStorage("selectedTheme")` which uses UserDefaults.
This means:
- Selection survives app restarts
- No database needed
- Instant load on launch
- User never has to pick again

---

## Next Steps (Optional)

You could extend this to:
- Add more themes
- Apply theme to EventsListView status colors
- Theme the stats view
- Add animated theme transitions
- Let users create custom themes
