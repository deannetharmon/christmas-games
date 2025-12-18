import Foundation
import SwiftData

enum GameCatalogCSVImporterError: LocalizedError {
    case invalidFormat(String)
    case missingRequiredColumn(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg): return msg
        case .missingRequiredColumn(let col): return "CSV is missing required column: \(col)"
        }
    }
}

@MainActor
enum GameCatalogCSVImporter {

    struct ImportResult {
        var insertedOrUpdated: Int
        var skipped: Int
        var removed: Int
    }

    /// Importer tailored for your "Minute to Win It - Head to Head" CSV:
    /// Required columns:
    /// - gameId
    /// - gameName
    /// - teamType
    ///
    /// Optional columns:
    /// - groupName
    /// - defaultTeamCount, defaultPlayersPerTeam, defaultRoundsPerGame
    /// - instructionText
    /// - Materials, Gather, Purchase, Url (ignored by default)
    /// - Check (if "x", row is skipped and counted as removed)
    static func importCSV(context: ModelContext, csvData: Data) throws -> ImportResult {

        guard let text = String(data: csvData, encoding: .utf8) else {
            throw GameCatalogCSVImporterError.invalidFormat("CSV file could not be read as UTF-8 text.")
        }

        let rawLines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !rawLines.isEmpty else {
            throw GameCatalogCSVImporterError.invalidFormat("CSV file is empty.")
        }

        // 1) Find the header row by detecting the expected columns.
        guard let headerIndex = rawLines.firstIndex(where: { line in
            let cols = parseCSVLine(line).map(normalizeHeaderKey)
            return cols.contains("gameid") && cols.contains("gamename") && cols.contains("teamtype")
        }) else {
            let firstLineCols = parseCSVLine(rawLines.first ?? "")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: ", ")
            throw GameCatalogCSVImporterError.invalidFormat(
                "Could not find a valid header row. Expected columns: gameId, gameName, teamType. " +
                "First line columns were: \(firstLineCols)"
            )
        }

        let headerCols = parseCSVLine(rawLines[headerIndex])

        // Build header map; tolerate duplicate column names by keeping first occurrence.
        var headerMap: [String: Int] = [:]
        for (idx, name) in headerCols.enumerated() {
            let key = normalizeHeaderKey(name)
            if headerMap[key] == nil {
                headerMap[key] = idx
            }
        }

        func colIndex(_ key: String, alternatives: [String] = []) -> Int? {
            if let i = headerMap[normalizeHeaderKey(key)] { return i }
            for alt in alternatives {
                if let i = headerMap[normalizeHeaderKey(alt)] { return i }
            }
            return nil
        }

        // Required
        guard let iGameId = colIndex("gameId", alternatives: ["gameid", "id"]) else {
            throw GameCatalogCSVImporterError.missingRequiredColumn("gameId")
        }
        guard let iGameName = colIndex("gameName", alternatives: ["gamename", "name"]) else {
            throw GameCatalogCSVImporterError.missingRequiredColumn("gameName")
        }
        guard let iTeamType = colIndex("teamType", alternatives: ["teamtype"]) else {
            throw GameCatalogCSVImporterError.missingRequiredColumn("teamType")
        }

        // Optional
        let iGroupName = colIndex("groupName", alternatives: ["group", "groupname"])
        let iTeamCount = colIndex("defaultTeamCount", alternatives: ["defaultteamcount"])
        let iPlayersPerTeam = colIndex("defaultPlayersPerTeam", alternatives: ["defaultplayersperteam"])
        let iRounds = colIndex("defaultRoundsPerGame", alternatives: ["defaultroundspergame"])
        let iInstructionText = colIndex("instructionText", alternatives: ["instructiontext", "instructions"])
        let iCheck = colIndex("check", alternatives: ["Check"])

        var result = ImportResult(insertedOrUpdated: 0, skipped: 0, removed: 0)

        // 2) Process rows
        for line in rawLines.dropFirst(headerIndex + 1) {
            let cols = parseCSVLine(line)

            guard iGameId < cols.count, iGameName < cols.count, iTeamType < cols.count else {
                result.skipped += 1
                continue
            }

            // Check column: if "x" -> skip/remove
            if let iCheck, iCheck < cols.count {
                let flag = cols[iCheck].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if flag == "x" {
                    result.removed += 1
                    continue
                }
            }

            let gameIdRaw = cols[iGameId].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = cols[iGameName].trimmingCharacters(in: .whitespacesAndNewlines)

            guard !gameIdRaw.isEmpty, !name.isEmpty else {
                result.skipped += 1
                continue
            }

            // Stable externalId derived from gameId
            let externalId = "mtwi_\(slug(gameIdRaw))"

            let groupName: String? = {
                guard let iGroupName, iGroupName < cols.count else { return nil }
                let g = cols[iGroupName].trimmingCharacters(in: .whitespacesAndNewlines)
                return g.isEmpty ? nil : g
            }()

            let instructions: String? = {
                guard let iInstructionText, iInstructionText < cols.count else { return nil }
                let t = cols[iInstructionText].trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }()

            let teamType = mapTeamType(cols[iTeamType])

            let defaultTeamCount = parsePositiveInt(cols, iTeamCount, defaultValue: 2)
            let defaultPlayersPerTeam = parsePositiveInt(cols, iPlayersPerTeam, defaultValue: 2)
            let defaultRoundsPerGame = parsePositiveInt(cols, iRounds, defaultValue: 1)

            let existing = try fetchTemplateByExternalId(context: context, externalId: externalId)

            if let t = existing {
                t.name = name
                t.groupName = groupName
                t.defaultTeamCount = defaultTeamCount
                t.defaultPlayersPerTeam = defaultPlayersPerTeam
                t.defaultRoundsPerGame = defaultRoundsPerGame
                t.defaultTeamTypeRaw = teamType.rawValue
                t.instructions = instructions
                result.insertedOrUpdated += 1
            } else {
                let t = GameTemplate(
                    externalId: externalId,
                    name: name,
                    groupName: groupName,
                    defaultTeamCount: defaultTeamCount,
                    defaultPlayersPerTeam: defaultPlayersPerTeam,
                    defaultRoundsPerGame: defaultRoundsPerGame,
                    defaultTeamType: teamType,
                    instructions: instructions
                )
                context.insert(t)
                result.insertedOrUpdated += 1
            }
        }

        try context.save()
        return result
    }

    // MARK: - Helpers

    private static func parsePositiveInt(_ cols: [String], _ index: Int?, defaultValue: Int) -> Int {
        guard let index, index < cols.count else { return defaultValue }
        let s = cols[index].trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return defaultValue }
        if let v = Int(s), v > 0 { return v }
        return defaultValue
    }

    private static func mapTeamType(_ raw: String) -> TeamType {
        let n = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")

        if n.isEmpty { return .any }

        switch n {
        case "any", "anygender", "mixed", "coed", "all":
            return .any
        case "maleonly", "menonly", "boysonly", "male", "men":
            return .maleOnly
        case "femaleonly", "womenonly", "girlsonly", "female", "women":
            return .femaleOnly
        case "couplesonly", "couples", "couple", "spousesonly", "spouse":
            return .couplesOnly
        default:
            return .any
        }
    }

    private static func normalizeHeaderKey(_ s: String) -> String {
        let lowered = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = lowered
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
        let allowed = compact.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(allowed))
    }

    private static func slug(_ s: String) -> String {
        let lowered = s.lowercased()
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let raw = String(mapped)
        let collapsed = raw
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? UUID().uuidString.lowercased() : collapsed
    }

    /// CSV parser with quote handling (supports commas inside quoted fields)
    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex

        while i < line.endIndex {
            let ch = line[i]

            if ch == "\"" {
                let next = line.index(after: i)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    i = line.index(after: next)
                    continue
                }
                inQuotes.toggle()
                i = line.index(after: i)
                continue
            }

            if ch == ",", !inQuotes {
                result.append(current)
                current = ""
                i = line.index(after: i)
                continue
            }

            current.append(ch)
            i = line.index(after: i)
        }

        result.append(current)
        return result
    }

    private static func fetchTemplateByExternalId(context: ModelContext, externalId: String) throws -> GameTemplate? {
        let descriptor = FetchDescriptor<GameTemplate>(
            predicate: #Predicate { $0.externalId == externalId }
        )
        return try context.fetch(descriptor).first
    }
}
