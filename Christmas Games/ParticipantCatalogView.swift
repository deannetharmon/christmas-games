import SwiftUI
import SwiftData

struct ParticipantCatalogView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var themeManager: ThemeManager

    @Query(sort: \Person.displayName)
    private var people: [Person]

    @State private var showCreatePerson = false
    @State private var editingPerson: Person?

    @State private var alertTitle = "Message"
    @State private var alertMessage: String?
    @State private var showAlert = false

    var body: some View {
        ZStack {
            // Solid background
            themeManager.background
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
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Participant Catalog")
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add") { showCreatePerson = true }
                    .foregroundColor(themeManager.text)
            }
        }
        .sheet(isPresented: $showCreatePerson) {
            CreatePersonSheet()
                .environmentObject(themeManager)
        }
        .sheet(item: $editingPerson) { person in
            EditPersonSheet(person: person)
                .environmentObject(themeManager)
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
    .environmentObject(ThemeManager())
}
