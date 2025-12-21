import SwiftUI
import SwiftData

struct ParticipantCatalogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorTheme) private var theme

    @Query(sort: \Person.displayName)
    private var people: [Person]

    @State private var showCreatePerson = false
    @State private var editingPerson: Person?

    @State private var alertTitle = "Message"
    @State private var alertMessage: String?
    @State private var showAlert = false

    var body: some View {
    ZStack {
        // Gradient background
        LinearGradient(
            colors: [theme.gradientStart, theme.gradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        // Your existing List
        List {
            ForEach(people) { person in
                Button {
                    editingPerson = person
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(person.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)

                            if let sex = person.sex {
                                Text("Gender: \(sex)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if !person.isActive {
                            Text("Inactive")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete(perform: deletePeople)
        }
        .scrollContentBackground(.hidden) // <- critical
    }
    .navigationTitle("Participant Catalog")
    .toolbarBackground(.hidden, for: .navigationBar)   // lets gradient show under title
    .toolbarColorScheme(.dark, for: .navigationBar)    // keeps title readable on gradient
    .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Add") { showCreatePerson = true }
        }
    }
    .sheet(isPresented: $showCreatePerson) {
        CreatePersonSheet()
    }
    .sheet(item: $editingPerson) { person in
        EditPersonSheet(person: person)
    }
    .alert(alertTitle, isPresented: $showAlert) {
        Button("OK", role: .cancel) { }
    } message: {
        Text(alertMessage ?? "Unknown error")
    }
}

    private func deletePeople(at offsets: IndexSet) {
        for index in offsets {
            context.delete(people[index])
        }
        try? context.save()
    }
}

#Preview {
    NavigationStack {
        ParticipantCatalogView()
    }
    .modelContainer(for: [Person.self])
}

