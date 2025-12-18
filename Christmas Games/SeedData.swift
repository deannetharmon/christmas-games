import Foundation
import SwiftData

enum SeedData {

    /// Upserts the full roster and removes legacy placeholders.
    /// Safe to run multiple times.
    @MainActor
    static func seedOrUpdateRoster(context: ModelContext) throws {

        // Fetch all existing people
        let existing = try context.fetch(FetchDescriptor<Person>())
        var byName: [String: Person] =
            Dictionary(uniqueKeysWithValues: existing.map { ($0.displayName, $0) })

        // MARK: - Remove legacy placeholder people
        let legacyNamesToDelete: Set<String> = ["Couple2-A", "Couple2-B"]
        for person in existing where legacyNamesToDelete.contains(person.displayName) {
            context.delete(person)
            byName[person.displayName] = nil
        }

        // MARK: - Upsert helper
        @discardableResult
        func upsert(
            _ name: String,
            sex: String,
            age: Int,
            weight: Int,
            athleticAbility: Int,
            height: String
        ) -> Person {

            if let p = byName[name] {
                // Update existing record
                p.sex = sex
                p.age = age
                p.weight = weight
                p.athleticAbility = athleticAbility
                p.height = height
                p.isActive = true
                return p
            } else {
                // Insert new record
                let p = Person(
                    displayName: name,
                    sex: sex,
                    age: age,
                    weight: weight,
                    athleticAbility: athleticAbility,
                    height: height,
                    isActive: true
                )
                context.insert(p)
                byName[name] = p
                return p
            }
        }

        // MARK: - Roster (from your sheet)

        let dean     = upsert("Dean",     sex: "M", age: 60, weight: 250, athleticAbility: 3, height: #"6'3""#)
        let shannon  = upsert("Shannon",  sex: "F", age: 57, weight: 150, athleticAbility: 4, height: #"6'"#)

        let michael  = upsert("Michael",  sex: "M", age: 34, weight: 250, athleticAbility: 3, height: #"6'"#)
        let brittany = upsert("Brittany", sex: "F", age: 33, weight: 190, athleticAbility: 1, height: #"5'10""#)

        let blake    = upsert("Blake",    sex: "M", age: 30, weight: 250, athleticAbility: 5, height: #"6'2""#)
        let brooklin = upsert("Brooklin", sex: "F", age: 30, weight: 140, athleticAbility: 4, height: #"5'2""#)

        let brandon  = upsert("Brandon",  sex: "M", age: 27, weight: 260, athleticAbility: 5, height: #"6'6""#)
        let jenna    = upsert("Jenna",    sex: "F", age: 27, weight: 140, athleticAbility: 4, height: #"5'8""#)

        let hunter   = upsert("Hunter",   sex: "M", age: 27, weight: 260, athleticAbility: 5, height: #"6'5""#)
        let brooke   = upsert("Brooke",   sex: "F", age: 24, weight: 140, athleticAbility: 5, height: #"5'10""#)

        // MARK: - Spouse linking (bidirectional)

        func linkSpouses(_ a: Person, _ b: Person) {
            a.spouseId = b.id
            b.spouseId = a.id
        }

        linkSpouses(dean, shannon)
        linkSpouses(michael, brittany)
        linkSpouses(blake, brooklin)
        linkSpouses(brandon, jenna)
        linkSpouses(hunter, brooke)

        try context.save()
    }
}
