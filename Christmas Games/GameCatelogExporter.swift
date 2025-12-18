import Foundation
import SwiftData

@MainActor
enum GameCatalogExporter {

    static func exportToDocuments(
        context: ModelContext,
        filename: String = "games",
        fileExtension: String = "json"
    ) throws -> URL {

        let templates = try context.fetch(FetchDescriptor<GameTemplate>())

        let games: [ExportGameCatalogGame] = templates
            .map { t in
                ExportGameCatalogGame(
                    externalId: t.externalId,
                    name: t.name,
                    groupName: t.groupName,
                    defaultTeamCount: t.defaultTeamCount,
                    defaultPlayersPerTeam: t.defaultPlayersPerTeam,
                    defaultRoundsPerGame: t.defaultRoundsPerGame,
                    teamType: t.defaultTeamType,
                    instructions: t.instructions
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let catalog = ExportGameCatalog(games: games)

        let data = try JSONEncoder().encode(catalog)

        let url = try documentsURL(filename: filename, fileExtension: fileExtension)
        try data.write(to: url, options: [.atomic])

        return url
    }

    private static func documentsURL(filename: String, fileExtension: String) throws -> URL {
        let dir = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return dir.appendingPathComponent("\(filename).\(fileExtension)")
    }
}

// MARK: - Private JSON DTOs (scoped to exporter)

private struct ExportGameCatalog: Codable {
    let games: [ExportGameCatalogGame]
}

private struct ExportGameCatalogGame: Codable {
    let externalId: String
    let name: String
    let groupName: String?
    let defaultTeamCount: Int
    let defaultPlayersPerTeam: Int
    let defaultRoundsPerGame: Int
    let teamType: TeamType
    let instructions: String?
}
