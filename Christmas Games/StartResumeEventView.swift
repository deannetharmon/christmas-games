import SwiftUI
import SwiftData

struct StartResumeEventView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Event.createdAt, order: .reverse)
    private var allEvents: [Event]

    @State private var message: String?
    @State private var showMessage = false

    var body: some View {
        List {
            ForEach(eligibleEvents) { event in
                NavigationLink {
                    RunGameView(event: event)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.name)
                                .font(.headline)

                            Text(event.statusRaw.capitalized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        actionButton(for: event)
                    }
                }
            }
        }
        .navigationTitle("Start/Resume Event")
        .alert("Message", isPresented: $showMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(message ?? "Unknown error")
        }
    }

    private var eligibleEvents: [Event] {
        allEvents.filter { $0.status != .completed }
    }

    @ViewBuilder
    private func actionButton(for event: Event) -> some View {
        let engine = EventEngine(context: context)

        switch event.status {
        case .available:
            Button("Start") {
                do { try engine.startEvent(event) }
                catch { show(error) }
            }
            .buttonStyle(.bordered)
            .disabled(event.eventGames.isEmpty || event.participantIds.isEmpty)

        case .active, .paused:
            Button("Resume") {
                do {
                    if event.status == .paused {
                        try engine.resumeEvent(event)
                    }
                }
                catch { show(error) }
            }
            .buttonStyle(.bordered)

        case .completed:
            EmptyView()
        }
    }

    private func show(_ error: Error) {
        message = error.localizedDescription
        showMessage = true
    }
}

#Preview {
    NavigationStack {
        StartResumeEventView()
    }
    .modelContainer(for: [Event.self, Person.self, GameTemplate.self])
}
