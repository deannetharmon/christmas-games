# Christmas Games App - Update Summary

## Files Modified:

### 1. RunGameView.swift
- **Fixed Team D display issue** by adding team colors
- Added `teamColor(for:)` function that assigns distinct colors to teams (red, green, yellow, blue, orange, purple)
- Updated `header()` function to use `playInstructions` instead of `instructions`

### 2. GameCatalogView.swift  
- **Added rounds display** to game catalog rows
- Updated `gameRow()` to show "Rounds: X" alongside team information
- Updated Edit Template sheet to handle both `playInstructions` and `setupInstructions`

### 3. Models.swift
- **Renamed `instructions` to `playInstructions`** in GameTemplate model
- **Added `setupInstructions`** field to GameTemplate
- Updated EventGame to use `overridePlayInstructions` and `overrideSetupInstructions`
- Updated all initializers to handle new fields

### 4. GameCatalogCSVImporter.swift
- Updated to handle both `playInstructions` and `setupInstructions` columns
- Added fallback column name detection for new fields
- Updated template creation/update logic

### 5. GameTemplateSheet.swift
- Added separate text fields for Setup Instructions and Playing Instructions
- Updated save logic for both instruction types

### 6. GameCatalogImporter.swift
- Updated JSON import to handle `playInstructions` and `setupInstructions`
- Modified GameCatalogGame struct for new fields

### 7. GameCatalogExporter.swift
- Updated export to include both instruction fields
- Modified ExportGameCatalogGame struct

### 8. games.json
- Updated sample data structure with `playInstructions` and `setupInstructions`
- Set `setupInstructions` to null for existing games

### 9. CreatePersonSheet.swift (renamed from CreatPersonSheet.swift)
- **Added labels** to Details section: "Gender:", "Weight:", "Height:"  
- Used HStack layout with labels on left and segmented pickers on right
- Applied same changes to EditPersonSheet

## Important Notes:

1. **Database Schema Changed**: You'll need to reload your CSV data after these updates since the schema has changed (instructions → playInstructions + setupInstructions)

2. **CSV Format Update**: Your CSV files should now have columns:
   - `playInstructions` (or `playinstructions`)
   - `setupInstructions` (or `setupinstructions`)
   - The old `instructions` column will no longer be recognized

3. **Team Colors**: Teams are now color-coded:
   - Team A: Red
   - Team B: Green
   - Team C: Yellow
   - Team D: Blue
   - Team E: Orange
   - Team F: Purple
   - Additional teams: Default color

4. **File Renamed**: CreatPersonSheet.swift → CreatePersonSheet.swift (fixed typo)

## Color Theme Issue (Not Fixed):
Issue #5 regarding color themes across views was not addressed as the theme system code was not provided. If you have a custom theme implementation, please share it so this can be fixed.
