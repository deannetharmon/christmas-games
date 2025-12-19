import Foundation
import SwiftData

enum SeedData {

    @MainActor
    static func seedOrUpdateRoster(context: ModelContext) throws {

        let existing = try context.fetch(FetchDescriptor<Person>())
        var byName: [String: Person] =
            Dictionary(uniqueKeysWithValues: existing.map { ($0.displayName, $0) })

        let legacyNamesToDelete: Set<String> = ["Couple2-A", "Couple2-B"]
        for person in existing where legacyNamesToDelete.contains(person.displayName) {
            context.delete(person)
            byName[person.displayName] = nil
        }

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
                p.sex = sex
                p.age = age
                p.weight = weight
                p.athleticAbility = athleticAbility
                p.height = height
                p.isActive = true
                
                // Set categories from detailed values
                p.weightCategory = categoryForWeight(weight)
                p.heightCategory = categoryForHeight(height)
                
                return p
            } else {
                let p = Person(
                    displayName: name,
                    sex: sex,
                    age: age,
                    weight: weight,
                    athleticAbility: athleticAbility,
                    height: height,
                    weightCategory: categoryForWeight(weight),
                    heightCategory: categoryForHeight(height),
                    isActive: true
                )
                context.insert(p)
                byName[name] = p
                return p
            }
        }

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
    
    // MARK: - Category Mapping
    
    private static func categoryForWeight(_ weight: Int) -> String {
        switch weight {
        case ..<160: return "S"
        case 160..<220: return "M"
        default: return "L"
        }
    }
    
    private static func categoryForHeight(_ height: String) -> String {
        // Parse height like "6'3"" → inches
        let components = height.replacingOccurrences(of: "\"", with: "").split(separator: "'")
        guard components.count == 2,
              let feet = Int(components[0]),
              let inches = Int(components[1]) else {
            return "M" // Default
        }
        
        let totalInches = (feet * 12) + inches
        
        switch totalInches {
        case ..<67: return "S"  // < 5'7"
        case 67..<73: return "M" // 5'7" - 6'0"
        default: return "L"      // > 6'0"
        }
    }
}
