import Foundation
import SwiftData

// MARK: - Enums

enum EventStatus: String, Codable, CaseIterable {
    case available
    case active
    case paused
    case completed
}

enum GameStatus: String, Codable, CaseIterable {
    case notStarted
    case inProgress
    case completed
}

enum TeamType: String, Codable, CaseIterable {
    case any
    case maleOnly
    case femaleOnly
    case couplesOnly
}

enum RoundResultType: String, Codable, CaseIterable {
    case win
    case tie
}

// MARK: - People

@Model
final class Person {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var sex: String?
    var spouseId: UUID?

    // Detailed (used by CSV import, FairnessEngine)
    var age: Int?
    var weight: Int?
    var athleticAbility: Int?
    var height: String?

    // Categories (used by simple UI)
    var weightCategory: String?   // "S", "M", "L"
    var heightCategory: String?   // "S", "M", "L"

    var isActive: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        sex: String? = nil,
        spouseId: UUID? = nil,
        age: Int? = nil,
        weight: Int? = nil,
        athleticAbility: Int? = nil,
        height: String? = nil,
        weightCategory: String? = nil,
        heightCategory: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.sex = sex
        self.spouseId = spouseId
        self.age = age
        self.weight = weight
        self.athleticAbility = athleticAbility
        self.height = height
        self.weightCategory = weightCategory
        self.heightCategory = heightCategory
        self.isActive = isActive
    }
}

// MARK: - Game Templates

@Model
final class GameTemplate {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var externalId: String

    var name: String
    var groupName: String?

    var defaultTeamCount: Int
    var defaultPlayersPerTeam: Int
    var defaultRoundsPerGame: Int
    var defaultTeamTypeRaw: String

    var instructions: String?

    init(
        id: UUID = UUID(),
        externalId: String,
        name: String,
        groupName: String? = nil,
        defaultTeamCount: Int,
        defaultPlayersPerTeam: Int,
        defaultRoundsPerGame: Int,
        defaultTeamType: TeamType,
        instructions: String? = nil
    ) {
        self.id = id
        self.externalId = externalId
        self.name = name
        self.groupName = groupName
        self.defaultTeamCount = defaultTeamCount
        self.defaultPlayersPerTeam = defaultPlayersPerTeam
        self.defaultRoundsPerGame = defaultRoundsPerGame
        self.defaultTeamTypeRaw = defaultTeamType.rawValue
        self.instructions = instructions
    }

    @Transient
    var defaultTeamType: TeamType {
        get { TeamType(rawValue: defaultTeamTypeRaw) ?? .any }
        set { defaultTeamTypeRaw = newValue.rawValue }
    }
}

// MARK: - RoundTeam

struct RoundTeam: Codable, Equatable, Identifiable {
    var id: UUID
    var memberPersonIds: [UUID]

    init(id: UUID = UUID(), memberPersonIds: [UUID]) {
        self.id = id
        self.memberPersonIds = memberPersonIds
    }
}

// MARK: - Event

@Model
final class Event {
    @Attribute(.unique) var id: UUID
    var name: String

    var statusRaw: String
    var participantIds: [UUID]

    var createdAt: Date
    var lastModifiedAt: Date

    var currentEventGameId: UUID?

    @Relationship(deleteRule: .cascade, inverse: \EventGame.event)
    var eventGames: [EventGame]

    init(
        id: UUID = UUID(),
        name: String,
        status: EventStatus = .available,
        participantIds: [UUID] = [],
        createdAt: Date = Date(),
        lastModifiedAt: Date = Date(),
        currentEventGameId: UUID? = nil,
        eventGames: [EventGame] = []
    ) {
        self.id = id
        self.name = name
        self.statusRaw = status.rawValue
        self.participantIds = participantIds
        self.createdAt = createdAt
        self.lastModifiedAt = lastModifiedAt
        self.currentEventGameId = currentEventGameId
        self.eventGames = eventGames
    }

    @Transient
    var status: EventStatus {
        get { EventStatus(rawValue: statusRaw) ?? .available }
        set { statusRaw = newValue.rawValue }
    }
}

// MARK: - EventGame

@Model
final class EventGame {
    @Attribute(.unique) var id: UUID

    var event: Event?

    var gameTemplateId: UUID
    var orderIndex: Int
    var statusRaw: String

    var overrideTeamCount: Int?
    var overridePlayersPerTeam: Int?
    var overrideRoundsPerGame: Int?
    var overrideTeamTypeRaw: String?
    var overrideInstructions: String?

    var overrideTeamPlayersData: Data?

    @Relationship(deleteRule: .cascade, inverse: \Round.eventGame)
    var rounds: [Round]

    init(
        id: UUID = UUID(),
        event: Event? = nil,
        gameTemplateId: UUID,
        orderIndex: Int,
        status: GameStatus = .notStarted,
        overrideTeamCount: Int? = nil,
        overridePlayersPerTeam: Int? = nil,
        overrideRoundsPerGame: Int? = nil,
        overrideTeamType: TeamType? = nil,
        overrideTeamPlayers: [[UUID]]? = nil,
        overrideInstructions: String? = nil,
        rounds: [Round] = []
    ) {
        self.id = id
        self.event = event
        self.gameTemplateId = gameTemplateId
        self.orderIndex = orderIndex
        self.statusRaw = status.rawValue
        self.overrideTeamCount = overrideTeamCount
        self.overridePlayersPerTeam = overridePlayersPerTeam
        self.overrideRoundsPerGame = overrideRoundsPerGame
        self.overrideTeamTypeRaw = overrideTeamType?.rawValue
        if let overrideTeamPlayers {
            self.overrideTeamPlayersData = try? JSONEncoder().encode(overrideTeamPlayers)
        } else {
            self.overrideTeamPlayersData = nil
        }
        self.overrideInstructions = overrideInstructions
        self.rounds = rounds
    }

    @Transient
    var status: GameStatus {
        get { GameStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    @Transient
    var overrideTeamType: TeamType? {
        get { overrideTeamTypeRaw.flatMap { TeamType(rawValue: $0) } }
        set { overrideTeamTypeRaw = newValue?.rawValue }
    }

    @Transient
    var overrideTeamPlayers: [[UUID]]? {
        get {
            guard let data = overrideTeamPlayersData else { return nil }
            return try? JSONDecoder().decode([[UUID]].self, from: data)
        }
        set {
            if let newValue {
                overrideTeamPlayersData = try? JSONEncoder().encode(newValue)
            } else {
                overrideTeamPlayersData = nil
            }
        }
    }
}

// MARK: - Round

@Model
final class Round {
    @Attribute(.unique) var id: UUID

    var eventGame: EventGame?

    var roundIndex: Int
    var createdAt: Date
    var completedAt: Date?

    var teamsData: Data
    var placementsData: Data

    var resultTypeRaw: String?
    var winningTeamId: UUID?

    init(
        id: UUID = UUID(),
        eventGame: EventGame? = nil,
        roundIndex: Int,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        teams: [RoundTeam] = [],
        placements: [UUID: Int] = [:],
        resultType: RoundResultType? = nil,
        winningTeamId: UUID? = nil
    ) {
        self.id = id
        self.eventGame = eventGame
        self.roundIndex = roundIndex
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.teamsData = (try? JSONEncoder().encode(teams)) ?? Data()
        self.placementsData = (try? JSONEncoder().encode(placements)) ?? Data()
        self.resultTypeRaw = resultType?.rawValue
        self.winningTeamId = winningTeamId
    }

    @Transient
    var teams: [RoundTeam] {
        get { (try? JSONDecoder().decode([RoundTeam].self, from: teamsData)) ?? [] }
        set { teamsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    @Transient
    var placements: [UUID: Int] {
        get { (try? JSONDecoder().decode([UUID: Int].self, from: placementsData)) ?? [:] }
        set { placementsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    @Transient
    var resultType: RoundResultType? {
        get { resultTypeRaw.flatMap { RoundResultType(rawValue: $0) } }
        set { resultTypeRaw = newValue?.rawValue }
    }

    @Transient
    var isLocked: Bool {
        completedAt != nil
    }
}
