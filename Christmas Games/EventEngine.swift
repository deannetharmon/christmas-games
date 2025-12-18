import Foundation
import SwiftData

@MainActor
final class EventEngine {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Participants

    func setParticipants(for event: Event, participantIds: [UUID]) throws {
        event.participantIds = participantIds
        touch(event)
        try context.save()
    }

    // MARK: - Event Games: Import / Add / Remove

    /// Imports all GameTemplate rows into the given Event as EventGame rows.
    /// Idempotent: re-running does NOT create duplicates.
    func importAllCatalogGames(into event: Event) throws {
        let templates = try context.fetch(FetchDescriptor<GameTemplate>())
        let existingTemplateIds = Set(event.eventGames.map { $0.gameTemplateId })

        let maxIndex = event.eventGames.map(\.orderIndex).max() ?? -1
        var nextIndex = maxIndex + 1

        for template in templates {
            guard !existingTemplateIds.contains(template.id) else { continue }

            let eg = EventGame(
                event: event,
                gameTemplateId: template.id,
                orderIndex: nextIndex
            )
            nextIndex += 1

            context.insert(eg)
            event.eventGames.append(eg)
        }

        touch(event)
        try context.save()
    }

    /// Adds a single template to the event (no duplicates).
    func addGameTemplate(_ template: GameTemplate, to event: Event) throws {
        let exists = event.eventGames.contains(where: { $0.gameTemplateId == template.id })
        guard !exists else { return }

        let maxIndex = event.eventGames.map(\.orderIndex).max() ?? -1
        let eg = EventGame(
            event: event,
            gameTemplateId: template.id,
            orderIndex: maxIndex + 1
        )

        context.insert(eg)
        event.eventGames.append(eg)

        touch(event)
        try context.save()
    }

    /// Removes an EventGame from the event.
    func removeEventGame(_ eventGame: EventGame, from event: Event) throws {
        event.eventGames.removeAll(where: { $0.id == eventGame.id })
        context.delete(eventGame)

        // If you removed the current game, clear pointer
        if event.currentEventGameId == eventGame.id {
            event.currentEventGameId = nil
        }

        touch(event)
        try context.save()
    }

    // MARK: - Start / Progression

    // MARK: - Event Lifecycle (used by ContentView)

    func startEvent(_ event: Event) throws {
        // Starting the event means: mark active and immediately start the next game.
        guard !event.participantIds.isEmpty else { throw StartError.noParticipants }

        event.status = .active

        if let next = try pickNextGameRandom(event: event) {
            try start(event: event, eventGame: next)
        }

        touch(event)
        try context.save()
    }

    func pauseEvent(_ event: Event) throws {
        event.status = .paused
        touch(event)
        try context.save()
    }

    func resumeEvent(_ event: Event) throws {
        guard !event.participantIds.isEmpty else { throw StartError.noParticipants }

        event.status = .active

        // If there is no current game (or it is completed), start the next game.
        let current = event.currentEventGameId.flatMap { id in
            event.eventGames.first(where: { $0.id == id })
        }

        if current == nil || current?.status == .completed {
            if let next = try pickNextGameRandom(event: event) {
                try start(event: event, eventGame: next)
            } else {
                event.status = .completed
                event.currentEventGameId = nil
            }
        }

        touch(event)
        try context.save()
    }

    /// Starts a specific EventGame:
    /// - sets event active
    /// - sets currentEventGameId
    /// - sets game status to inProgress
    /// - creates round 0 if missing
    func start(event: Event, eventGame: EventGame) throws {
        // Must have participants to play
        guard !event.participantIds.isEmpty else {
            throw StartError.noParticipants
        }

        // Resolve template to know defaultRoundsPerGame
        guard let template = try fetchTemplate(id: eventGame.gameTemplateId) else {
            throw StartError.missingTemplate
        }

        event.status = .active
        event.currentEventGameId = eventGame.id
        eventGame.status = .inProgress

        // Create round 0 only if none exist
        if eventGame.rounds.isEmpty {
            let r = Round(eventGame: eventGame, roundIndex: 0, teams: [])
            context.insert(r)
            eventGame.rounds.append(r)
        }

        touch(event)
        try context.save()
    }

    // MARK: - Game / Round progression (used by ContentView)

    func createNextRound(for eventGame: EventGame) throws -> Round {
        let nextIndex = eventGame.rounds.map(\.roundIndex).max().map { $0 + 1 } ?? 0
        let r = Round(eventGame: eventGame, roundIndex: nextIndex, teams: [])
        context.insert(r)
        eventGame.rounds.append(r)

        if let event = eventGame.event {
            touch(event)
        }
        try context.save()
        return r
    }

    func completeGame(_ eventGame: EventGame) throws {
        eventGame.status = .completed
        if let event = eventGame.event {
            // If the completed game was current, clear pointer (next game will set it)
            if event.currentEventGameId == eventGame.id {
                event.currentEventGameId = nil
            }
            touch(event)
        }
        try context.save()
    }

    func pickNextGameRandom(event: Event) throws -> EventGame? {
        let remaining = event.eventGames.filter { $0.status == .notStarted }
        guard !remaining.isEmpty else { return nil }

        // Simple variety heuristic: prefer a different group than the last completed game.
        let templates = try context.fetch(FetchDescriptor<GameTemplate>())
        let templateById = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })

        let lastCompleted = event.eventGames
            .filter { $0.status == .completed }
            .sorted { ($0.orderIndex) > ($1.orderIndex) }
            .first

        let lastGroup = lastCompleted.flatMap { templateById[$0.gameTemplateId]?.groupName?.trimmingCharacters(in: .whitespacesAndNewlines) }

        if let lastGroup, !lastGroup.isEmpty {
            let differentGroup = remaining.filter {
                let g = templateById[$0.gameTemplateId]?.groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (g?.isEmpty == false) ? (g != lastGroup) : true
            }
            if let pick = differentGroup.randomElement() {
                return pick
            }
        }

        return remaining.randomElement()
    }

    func pushGameToLater(_ eventGame: EventGame) throws {
        guard let event = eventGame.event else { return }
        let maxIndex = event.eventGames.map(\.orderIndex).max() ?? -1
        eventGame.orderIndex = maxIndex + 1
        touch(event)
        try context.save()
    }

    func removeGameFromEvent(_ eventGame: EventGame) throws {
        guard let event = eventGame.event else {
            context.delete(eventGame)
            try context.save()
            return
        }
        event.eventGames.removeAll(where: { $0.id == eventGame.id })
        context.delete(eventGame)
        if event.currentEventGameId == eventGame.id {
            event.currentEventGameId = nil
        }
        touch(event)
        try context.save()
    }

    // MARK: - Teams / Rounds

    func generateTeams(for round: Round) throws {
        guard let eventGame = round.eventGame, let event = eventGame.event else { return }

        let fairness = FairnessEngine(context: context)
        let teams = try fairness.generateTeams(for: round, in: event)

        round.teams = teams
        touch(event)
        try context.save()
    }

    func swapPlayer(in round: Round, from outgoing: UUID, to incoming: UUID) throws {
        var updated = round.teams
        guard let teamIndex = updated.firstIndex(where: { $0.memberPersonIds.contains(outgoing) }) else { return }

        var team = updated[teamIndex]
        team.memberPersonIds = team.memberPersonIds.map { $0 == outgoing ? incoming : $0 }
        updated[teamIndex] = team
        round.teams = updated

        if let event = round.eventGame?.event {
            touch(event)
        }
        try context.save()
    }

    func finalizeRound(_ round: Round, winnerTeamId: UUID?) throws {
        round.completedAt = Date()

        if let winnerTeamId {
            round.resultType = .win
            round.winningTeamId = winnerTeamId
        } else {
            round.resultType = .tie
            round.winningTeamId = nil
        }

        if let event = round.eventGame?.event {
            touch(event)
        }
        try context.save()
    }

    // MARK: - Helpers

    private func fetchTemplate(id: UUID) throws -> GameTemplate? {
        let d = FetchDescriptor<GameTemplate>(predicate: #Predicate { $0.id == id })
        return try context.fetch(d).first
    }

    private func touch(_ event: Event) {
        event.lastModifiedAt = Date()
    }

    enum StartError: LocalizedError {
        case noParticipants
        case missingTemplate
        case invalidRoundCount

        var errorDescription: String? {
            switch self {
            case .noParticipants:
                return "No players selected for this event. Add players before starting a game."
            case .missingTemplate:
                return "The selected game template could not be found in the catalog."
            case .invalidRoundCount:
                return "This game has an invalid number of rounds."
            }
        }
    }
}
