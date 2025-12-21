import Foundation
import SwiftData

@MainActor
enum GameCatalogImporter {

    // MARK: - Public API (matches your BootstrapView calls)

    /// Imports games.json from Documents *if present*.
    /// Returns the number of templates imported/updated, or nil if the file doesn't exist.
    static func importFromDocumentsIfPresent(
        context: ModelContext,
        filename: String,
        fileExtension: String
    ) throws -> Int? {
        let url = documentsURL(filename: filename, fileExtension: fileExtension)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let count = try importFromData(context: context, jsonData: data)
        return count
    }

    /// Imports games.json from the app bundle.
    /// Returns the number of templates imported/updated.
    static func importFromBundle(
        context: ModelContext,
        filename: String,
        fileExtension: String
    ) throws -> Int {
        guard let url = Bundle.main.url(forResource: filename, withExtension: fileExtension) else {
            return 0 // treat missing bundled json as "no seed"
        }

        let data = try Data(contentsOf: url)
        let count = try importFromData(context: context, jsonData: data)
        return count
    }

    // MARK: - Backward-compatible helpers (optional; safe to keep)

    static func importFromBundle(context: ModelContext) throws {
        _ = try importFromBundle(context: context, filename: "games", fileExtension: "json")
    }

    static func importFromDocuments(context: ModelContext) throws {
        _ = try importFromDocumentsIfPresent(context: context, filename: "games", fileExtension: "json")
    }

    // MARK: - Core import

    private static func importFromData(context: ModelContext, jsonData: Data) throws -> Int {
        let decoder = JSONDecoder()
        let catalog = try decoder.decode(GameCatalog.self, from: jsonData)

        var count = 0
        for game in catalog.games {
            try upsert(game: game, context: context)
            count += 1
        }

        try context.save()
        return count
    }

    private static func upsert(game: GameCatalogGame, context: ModelContext) throws {
        let descriptor = FetchDescriptor<GameTemplate>(
            predicate: #Predicate { $0.externalId == game.externalId }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.name = game.name
            existing.groupName = game.groupName
            existing.defaultTeamCount = game.defaultTeamCount
            existing.defaultPlayersPerTeam = game.defaultPlayersPerTeam
            existing.defaultRoundsPerGame = game.defaultRoundsPerGame
            existing.defaultTeamTypeRaw = game.teamType.rawValue
            existing.playInstructions = game.playInstructions
            existing.setupInstructions = game.setupInstructions
        } else {
            let template = GameTemplate(
                externalId: game.externalId,
                name: game.name,
                groupName: game.groupName,
                defaultTeamCount: game.defaultTeamCount,
                defaultPlayersPerTeam: game.defaultPlayersPerTeam,
                defaultRoundsPerGame: game.defaultRoundsPerGame,
                defaultTeamType: game.teamType,
                playInstructions: game.playInstructions,
                setupInstructions: game.setupInstructions
            )
            context.insert(template)
        }
    }

    // MARK: - Paths

    private static func documentsURL(filename: String, fileExtension: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(filename).\(fileExtension)")
    }
}

// MARK: - Private JSON DTOs (avoid redeclaration collisions)

private struct GameCatalog: Codable {
    let games: [GameCatalogGame]
}

private struct GameCatalogGame: Codable {
    let externalId: String
    let name: String
    let groupName: String?
    let defaultTeamCount: Int
    let defaultPlayersPerTeam: Int
    let defaultRoundsPerGame: Int
    let teamType: TeamType
    let playInstructions: String?
    let setupInstructions: String?
}
