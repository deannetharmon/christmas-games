import XCTest
import SwiftData
@testable import Christmas_Games

final class EventEngineTests: XCTestCase {
    var context: ModelContext!
    var engine: EventEngine!
    
    @MainActor
    override func setUp() {
        super.setUp()
        // Create in-memory database for testing
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Event.self, Person.self, GameTemplate.self, EventGame.self, Round.self,
            configurations: config
        )
        context = container.mainContext
        engine = EventEngine(context: context)
    }
    
    @MainActor
    func testStartEvent_WithNoParticipants_ThrowsError() throws {
        // Given: an event with no participants
        let event = Event(name: "Test Event")
        let template = GameTemplate(
            externalId: "test",
            name: "Test Game",
            defaultTeamCount: 2,
            defaultPlayersPerTeam: 2,
            defaultRoundsPerGame: 1,
            defaultTeamType: .any
        )
        context.insert(event)
        context.insert(template)
        
        let eventGame = EventGame(
            event: event,
            gameTemplateId: template.id,
            orderIndex: 0
        )
        context.insert(eventGame)
        event.eventGames.append(eventGame)
        
        // When/Then: starting should throw noParticipants error
        XCTAssertThrowsError(try engine.startEvent(event)) { error in
            XCTAssertEqual(error as? EventEngine.StartError, .noParticipants)
        }
    }
    
    @MainActor
    func testStartEvent_CreatesActiveRound() throws {
        // Given: an event with participants and a game
        let event = Event(name: "Test Event")
        let person1 = Person(displayName: "Test Person 1")
        let person2 = Person(displayName: "Test Person 2")
        
        context.insert(event)
        context.insert(person1)
        context.insert(person2)
        
        event.participantIds = [person1.id, person2.id]
        
        let template = GameTemplate(
            externalId: "test",
            name: "Test Game",
            defaultTeamCount: 2,
            defaultPlayersPerTeam: 1,
            defaultRoundsPerGame: 1,
            defaultTeamType: .any
        )
        context.insert(template)
        
        let eventGame = EventGame(
            event: event,
            gameTemplateId: template.id,
            orderIndex: 0
        )
        context.insert(eventGame)
        event.eventGames.append(eventGame)
        
        // When: starting the event
        try engine.startEvent(event)
        
        // Then: event should be active with a current game and an active round
        XCTAssertEqual(event.status, .active)
        XCTAssertNotNil(event.currentEventGameId)
        XCTAssertEqual(eventGame.status, .inProgress)
        XCTAssertEqual(eventGame.rounds.count, 1)
        
        let round = eventGame.rounds.first!
        XCTAssertNil(round.completedAt, "Round should not be completed")
    }
    
    @MainActor
    func testFinalizeRound_AssignsCorrectPlacements() throws {
        // Given: a round with teams
        let event = Event(name: "Test Event")
        let person1 = Person(displayName: "Person 1")
        let person2 = Person(displayName: "Person 2")
        
        context.insert(event)
        context.insert(person1)
        context.insert(person2)
        
        let template = GameTemplate(
            externalId: "test",
            name: "Test Game",
            defaultTeamCount: 2,
            defaultPlayersPerTeam: 1,
            defaultRoundsPerGame: 1,
            defaultTeamType: .any
        )
        context.insert(template)
        
        let eventGame = EventGame(
            event: event,
            gameTemplateId: template.id,
            orderIndex: 0
        )
        context.insert(eventGame)
        
        let round = Round(eventGame: eventGame, roundIndex: 0)
        context.insert(round)
        eventGame.rounds.append(round)
        
        let team1 = RoundTeam(memberPersonIds: [person1.id])
        let team2 = RoundTeam(memberPersonIds: [person2.id])
        round.teams = [team1, team2]
        
        // When: finalizing round with team1 as winner
        try engine.finalizeRound(round, winnerTeamId: team1.id)
        
        // Then: placements should be assigned correctly
        XCTAssertNotNil(round.completedAt)
        XCTAssertEqual(round.placements[person1.id], 1, "Winner should get 1st place")
        XCTAssertEqual(round.placements[person2.id], 2, "Loser should get 2nd place")
    }
    
    @MainActor
    func testResetEvent_ClearsAllGamesAndRounds() throws {
        // Given: an event with completed games and rounds
        let event = Event(name: "Test Event", status: .completed)
        context.insert(event)
        
        let template = GameTemplate(
            externalId: "test",
            name: "Test Game",
            defaultTeamCount: 2,
            defaultPlayersPerTeam: 1,
            defaultRoundsPerGame: 1,
            defaultTeamType: .any
        )
        context.insert(template)
        
        let eventGame = EventGame(
            event: event,
            gameTemplateId: template.id,
            orderIndex: 0,
            status: .completed
        )
        context.insert(eventGame)
        event.eventGames.append(eventGame)
        
        let round = Round(eventGame: eventGame, roundIndex: 0, completedAt: Date())
        context.insert(round)
        eventGame.rounds.append(round)
        
        // When: resetting the event
        try engine.resetEvent(event)
        
        // Then: event should be reset
        XCTAssertEqual(event.status, .available)
        XCTAssertNil(event.currentEventGameId)
        XCTAssertEqual(eventGame.status, .notStarted)
        XCTAssertTrue(eventGame.rounds.isEmpty, "All rounds should be deleted")
    }
}
