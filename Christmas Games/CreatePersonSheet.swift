import SwiftUI
import SwiftData

struct CreatePersonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \Person.displayName)
    private var allPeople: [Person]

    @State private var displayName = ""
    @State private var sex = "M"
    @State private var weightCategory = "M"
    @State private var heightCategory = "M"
    @State private var spouseId: UUID?
    @State private var isActive = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Name", text: $displayName)
                }

                Section("Details") {
                    HStack {
                        Text("Gender:")
                        Spacer()
                        Picker("Gender", selection: $sex) {
                            Text("M").tag("M")
                            Text("F").tag("F")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    HStack {
                        Text("Weight:")
                        Spacer()
                        Picker("Weight", selection: $weightCategory) {
                            Text("S").tag("S")
                            Text("M").tag("M")
                            Text("L").tag("L")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    HStack {
                        Text("Height:")
                        Spacer()
                        Picker("Height", selection: $heightCategory) {
                            Text("S").tag("S")
                            Text("M").tag("M")
                            Text("L").tag("L")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }

                Section("Spouse (Optional)") {
                    Picker("Spouse", selection: $spouseId) {
                        Text("None").tag(nil as UUID?)
                        ForEach(allPeople.filter { $0.isActive }) { person in
                            Text(person.displayName).tag(person.id as UUID?)
                        }
                    }
                }

                Section {
                    Toggle("Active", isOn: $isActive)
                }
            }
            .navigationTitle("Add Participant")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Save & Add Another") { saveAndContinue() }
                        .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button("Done") { saveAndDismiss() }
                }
            }
        }
    }

    private func saveAndContinue() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let person = Person(
            displayName: trimmedName,
            sex: sex,
            spouseId: spouseId,
            isActive: isActive
        )
        person.weightCategory = weightCategory
        person.heightCategory = heightCategory

        context.insert(person)
        try? context.save()
        
        // Reset form for next entry
        displayName = ""
        sex = "M"
        weightCategory = "M"
        heightCategory = "M"
        spouseId = nil
        isActive = true
    }
    
    private func saveAndDismiss() {
        // Only save if there's a name entered
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            let person = Person(
                displayName: trimmedName,
                sex: sex,
                spouseId: spouseId,
                isActive: isActive
            )
            person.weightCategory = weightCategory
            person.heightCategory = heightCategory

            context.insert(person)
            try? context.save()
        }
        
        dismiss()
    }
}

struct EditPersonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \Person.displayName)
    private var allPeople: [Person]

    let person: Person

    @State private var displayName = ""
    @State private var sex = "M"
    @State private var weightCategory = "M"
    @State private var heightCategory = "M"
    @State private var spouseId: UUID?
    @State private var isActive = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Name", text: $displayName)
                }

                Section("Details") {
                    HStack {
                        Text("Gender:")
                        Spacer()
                        Picker("Gender", selection: $sex) {
                            Text("M").tag("M")
                            Text("F").tag("F")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    HStack {
                        Text("Weight:")
                        Spacer()
                        Picker("Weight", selection: $weightCategory) {
                            Text("S").tag("S")
                            Text("M").tag("M")
                            Text("L").tag("L")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    HStack {
                        Text("Height:")
                        Spacer()
                        Picker("Height", selection: $heightCategory) {
                            Text("S").tag("S")
                            Text("M").tag("M")
                            Text("L").tag("L")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }

                Section("Spouse (Optional)") {
                    Picker("Spouse", selection: $spouseId) {
                        Text("None").tag(nil as UUID?)
                        ForEach(allPeople.filter { $0.id != person.id && $0.isActive }) { p in
                            Text(p.displayName).tag(p.id as UUID?)
                        }
                    }
                }

                Section {
                    Toggle("Active", isOn: $isActive)
                }
            }
            .navigationTitle("Edit Participant")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                displayName = person.displayName
                sex = person.sex ?? "M"
                weightCategory = person.weightCategory ?? "M"
                heightCategory = person.heightCategory ?? "M"
                spouseId = person.spouseId
                isActive = person.isActive
            }
        }
    }

    private func save() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        person.displayName = trimmedName
        person.sex = sex
        person.weightCategory = weightCategory
        person.heightCategory = heightCategory
        person.spouseId = spouseId
        person.isActive = isActive

        try? context.save()
        dismiss()
    }
}

#Preview {
    CreatePersonSheet()
        .modelContainer(for: [Person.self])
}
