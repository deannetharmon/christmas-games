import XCTest

final class MainMenuUITests: XCTestCase {
    
    func testNavigateToGameCatalog() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Tap Game Catalog button
        app.buttons["Game Catalog"].tap()
        
        // Verify we're on the Game Catalog screen
        XCTAssertTrue(app.navigationBars["Game Catalog"].exists)
    }
    
    func testCreateNewEvent() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Navigate to Events
        let eventsButton = app.buttons["Events"]
        XCTAssertTrue(eventsButton.exists)
        eventsButton.tap()
        
        // Tap Add Event
        app.buttons["Add Event"].tap()
        
        // Enter event name
        let eventNameField = app.textFields["Event Name"]
        eventNameField.tap()
        eventNameField.typeText("Test Event 2025")
        
        // Save
        app.buttons["Save"].tap()
        
        // Verify event appears in list
        XCTAssertTrue(app.staticTexts["Test Event 2025"].exists)
    }
}
