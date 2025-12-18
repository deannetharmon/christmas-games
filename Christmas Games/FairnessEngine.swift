import Foundation
import SwiftData

final class FairnessEngine {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func generateTeams(for round: Round, in event: Event) throws -> [RoundTeam] {

        guard let eventGame = round.eventGame else {
            throw FairnessError.missingEventGame
        }

        let settings = try effectiveSettings(for: eventGame)

        let eligiblePeople = try fetchEligiblePeople(for: event)
        let required = settings.teamCount * settings.playersPerTeam

        guard eligiblePeople.count >= required else {
            throw FairnessError.notEnoughPlayers(required: required, available: eligiblePeople.count)
        }

        // Choose participants for this round based on "equal playing time" = rounds played (completed rounds)
        let chosen = chooseParticipants(
            eligible: eligiblePeople,
            required: required,
            event: event
        )

        if settings.teamType == .couplesOnly {
            return try generateCouplesOnlyTeams(teamCount: settings.teamCount, eligible: chosen)
        }

        // Generate candidate partitions and pick best by score
        let historySignatures = matchupSignaturesForGame(eventGame: eventGame)

        let candidates = 600
        var best: [RoundTeam] = []
        var bestScore = Double.greatestFiniteMagnitude

        for _ in 0..<candidates {
            let shuffled = chosen.shuffled().map { $0.id }
            let teams = partition(ids: shuffled, teamCount: settings.teamCount, playersPerTeam: settings.playersPerTeam)

            let score = scoreTeams(
                teams: teams,
                peopleById: Dictionary(uniqueKeysWithValues: chosen.map { ($0.id, $0) }),
                historySignatures: historySignatures,
                allowSpousesSameTeam: false // unless couplesOnly
            )

            if score < bestScore {
                bestScore = score
                best = teams
                if score == 0 { break }
            }
        }

        return best
    }

    // MARK: - Settings

    private struct Settings {
        let teamCount: Int
        let playersPerTeam: Int
        let teamType: TeamType
    }

    private func effectiveSettings(for eventGame: EventGame) throws -> Settings {
        // Resolve template to get defaults
        let t = try fetchTemplate(id: eventGame.gameTemplateId)

        let teamCount = eventGame.overrideTeamCount ?? t?.defaultTeamCount ?? 2
        let playersPerTeam = eventGame.overridePlayersPerTeam ?? t?.defaultPlayersPerTeam ?? 2
        let teamType = eventGame.overrideTeamType ?? t?.defaultTeamType ?? .any

        return Settings(teamCount: max(1, teamCount), playersPerTeam: max(1, playersPerTeam), teamType: teamType)
    }

    // MARK: - Participant choice (equal playing time by rounds played)

    private func chooseParticipants(eligible: [Person], required: Int, event: Event) -> [Person] {
        let playedCounts = roundsPlayedCounts(event: event)
        return eligible
            .sorted {
                let a = playedCounts[$0.id, default: 0]
                let b = playedCounts[$1.id, default: 0]
                if a != b { return a < b }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            .prefix(required)
            .map { $0 }
    }

    private func roundsPlayedCounts(event: Event) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for eg in event.eventGames {
            for r in eg.rounds where r.completedAt != nil {
                for team in r.teams {
                    for pid in team.memberPersonIds {
                        counts[pid, default: 0] += 1
                    }
                }
            }
        }
        return counts
    }

    // MARK: - Matchup signature (head-to-head)

    private func matchupSignaturesForGame(eventGame: EventGame) -> Set<String> {
        var s = Set<String>()
        for r in eventGame.rounds where r.completedAt != nil {
            let sig = matchupSignature(teams: r.teams)
            s.insert(sig)
        }
        return s
    }

    private func matchupSignature(teams: [RoundTeam]) -> String {
        let normalizedTeams = teams
            .map { $0.memberPersonIds.sorted(by: { $0.uuidString < $1.uuidString }) }
            .sorted { left, right in
                left.map(\.uuidString).joined(separator: ",") < right.map(\.uuidString).joined(separator: ",")
            }
        return normalizedTeams
            .map { $0.map(\.uuidString).joined(separator: ",") }
            .joined(separator: "||")
    }

    // MARK: - Scoring

    private func scoreTeams(
        teams: [RoundTeam],
        peopleById: [UUID: Person],
        historySignatures: Set<String>,
        allowSpousesSameTeam: Bool
    ) -> Double {

        var score: Double = 0

        // 1) Prevent repeating the exact head-to-head matchup (B)
        let sig = matchupSignature(teams: teams)
        if historySignatures.contains(sig) {
            score += 10_000
        }

        // 2) Spouse constraint (unless couplesOnly)
        if !allowSpousesSameTeam {
            for team in teams {
                let ids = Set(team.memberPersonIds)
                for pid in ids {
                    if let spouseId = peopleById[pid]?.spouseId, ids.contains(spouseId) {
                        score += 5_000
                    }
                }
            }
        }

        // 3) Balance by athleticAbility / weight / age (if available)
        // Penalty based on variance between team totals.
        func teamStat(_ team: RoundTeam, get: (Person) -> Int?) -> Double {
            let vals = team.memberPersonIds.compactMap { peopleById[$0] }.compactMap(get)
            if vals.isEmpty { return 0 }
            return Double(vals.reduce(0, +))
        }

        let athletic = teams.map { teamStat($0) { $0.athleticAbility } }
        let weight = teams.map { teamStat($0) { $0.weight } }
        let age = teams.map { teamStat($0) { $0.age } }

        score += variancePenalty(athletic) * 2.0
        score += variancePenalty(weight) * 0.25
        score += variancePenalty(age) * 0.5

        return score
    }

    private func variancePenalty(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let varSum = values.reduce(0) { $0 + pow($1 - mean, 2) }
        return varSum
    }

    // MARK: - Couples-only teams

    private func generateCouplesOnlyTeams(teamCount: Int, eligible: [Person]) throws -> [RoundTeam] {

        let byId = Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, $0) })

        var used = Set<UUID>()
        var pairs: [[UUID]] = []

        for person in eligible {
            guard !used.contains(person.id),
                  let spouseId = person.spouseId,
                  let spouse = byId[spouseId],
                  spouse.spouseId == person.id,
                  !used.contains(spouse.id)
            else { continue }

            used.insert(person.id)
            used.insert(spouse.id)
            pairs.append([person.id, spouse.id])
        }

        guard pairs.count >= teamCount else {
            throw FairnessError.notEnoughCouples(required: teamCount, available: pairs.count)
        }

        return pairs.prefix(teamCount).map { RoundTeam(memberPersonIds: $0) }
    }

    // MARK: - Utilities

    private func partition(ids: [UUID], teamCount: Int, playersPerTeam: Int) -> [RoundTeam] {
        var result: [RoundTeam] = []
        var index = 0
        for _ in 0..<teamCount {
            let slice = ids[index..<(index + playersPerTeam)]
            result.append(RoundTeam(memberPersonIds: Array(slice)))
            index += playersPerTeam
        }
        return result
    }

    private func fetchEligiblePeople(for event: Event) throws -> [Person] {
        let all = try context.fetch(FetchDescriptor<Person>())
        let idSet = Set(event.participantIds)
        return all.filter { $0.isActive && idSet.contains($0.id) }
    }

    private func fetchTemplate(id: UUID) throws -> GameTemplate? {
        let d = FetchDescriptor<GameTemplate>(predicate: #Predicate { $0.id == id })
        return try context.fetch(d).first
    }
}

// MARK: - Errors

enum FairnessError: LocalizedError {
    case missingEventGame
    case notEnoughPlayers(required: Int, available: Int)
    case notEnoughCouples(required: Int, available: Int)

    var errorDescription: String? {
        switch self {
        case .missingEventGame:
            return "Round is not attached to an EventGame."
        case .notEnoughPlayers(let r, let a):
            return "Not enough players. Required \(r), available \(a)."
        case .notEnoughCouples(let r, let a):
            return "Not enough couples. Required \(r), available \(a)."
        }
    }
}
