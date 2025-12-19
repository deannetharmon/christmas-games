import SwiftUI
import SwiftData

/// Main Menu matching the PDF wireframe (vertical menu buttons).
/// Order (per wireframe): Events → Game Catalog → Participant Catalog → Start/Resume Event → Event Stats
struct MainMenuView: View {
    @Query(sort: \Event.createdAt, order: .reverse)
    private var events: [Event]

    @Query(sort: \Person.displayName)
    private var people: [Person]

    @Query(sort: \GameTemplate.name)
    private var games: [GameTemplate]

    private var activeOrPausedEvent: Event? {
        events.first(where: { $0.status == .active || $0.status == .paused })
    }

    private var startResumeTitle: String {
        guard let e = activeOrPausedEvent else { return "Start/Resume Event" }
        return e.status == .paused ? "Resume Event" : "Start Event"
    }

    private var startResumeSubtitle: String {
        guard let e = activeOrPausedEvent else { return "No active event" }
        return e.name
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 14) {
                        NavigationLink {
                            EventsListView()
                        } label: {
                            MenuRow(
                                title: "Events",
                                subtitle: "\(events.count) total",
                                systemImage: "calendar"
                            )
                        }

                        NavigationLink {
                            GameCatalogView()
                        } label: {
                            MenuRow(
                                title: "Game Catalog",
                                subtitle: "\(games.count) games",
                                systemImage: "list.bullet.rectangle"
                            )
                        }

                        NavigationLink {
                            ParticipantCatalogView()
                        } label: {
                            MenuRow(
                                title: "Participant Catalog",
                                subtitle: "\(people.count) participants",
                                systemImage: "person.3"
                            )
                        }

                        NavigationLink {
                            StartResumeEventView()
                        } label: {
                            MenuRow(
                                title: startResumeTitle,
                                subtitle: startResumeSubtitle,
                                systemImage: "play.circle"
                            )
                        }
                        .disabled(activeOrPausedEvent == nil)
                        .opacity(activeOrPausedEvent == nil ? 0.5 : 1.0)

                        NavigationLink {
                            EventStatsView()
                        } label: {
                            MenuRow(
                                title: "Event Stats",
                                subtitle: "Results grid",
                                systemImage: "chart.bar"
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Harmon Family Games")
                .font(.title2)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

private struct MenuRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
