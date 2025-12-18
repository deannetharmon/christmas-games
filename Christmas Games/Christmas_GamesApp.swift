import SwiftUI
import SwiftData

@main
struct Christmas_GamesApp: App {

    private var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Person.self,
            GameTemplate.self,
            Event.self,
            EventGame.self,
            Round.self
        ])

        // Put the store in Documents/Christmas Games so it’s easy to find/remove if needed
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folder = docs.appendingPathComponent("Christmas Games", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // Bump this suffix any time you change SwiftData @Model storage in a non-migrating project
        let storeURL = folder.appendingPathComponent("ChristmasGames_v2.store")

        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
