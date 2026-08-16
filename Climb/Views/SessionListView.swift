import SwiftUI
import SwiftData
import UIKit

/// The notes list: one row per session, newest first.
struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClimbSession.createdAt, order: .reverse) private var sessions: [ClimbSession]
    @State private var newSession: ClimbSession?
    @State private var searchText = ""
    /// The global bottom bar's state; the bar itself floats over the whole
    /// navigation stack below, so it never re-enters or resets across pushes.
    @State private var barModel = BottomBarModel()

    /// The user's own sessions. The seeded walkthrough is not one of them — it belongs
    /// to onboarding, which opens it on its own and is the only place it is ever read —
    /// so the list never carries it, pinned or otherwise. Nor is the goal note: it is a
    /// page of the app, pinned above the weeks on its own terms rather than filed under
    /// the week it happened to be written in.
    private var ownSessions: [ClimbSession] {
        sessions.filter { $0.id != Tutorial.id && $0.id != Goals.id }
    }

    /// The pinned goal note, absent only for the frame before the seed lands.
    private var goal: ClimbSession? { Goals.note(in: sessions) }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Title and body both match, so searching finds a session by anything written in it.
    private var visibleSessions: [ClimbSession] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return ownSessions }
        return ownSessions.filter { $0.bodyText.localizedCaseInsensitiveContains(query) }
    }

    /// One card per calendar week, newest first. Sessions keep the query's newest-first
    /// order inside each week because `Dictionary(grouping:)` preserves input order.
    private var weeks: [SessionWeek] {
        let calendar = Calendar.current
        let byWeek = Dictionary(grouping: visibleSessions) { session in
            calendar.dateInterval(of: .weekOfYear, for: session.createdAt)?.start ?? session.createdAt
        }
        return byWeek.keys.sorted(by: >).map { start in
            SessionWeek(id: start,
                        title: Self.weekTitle(startingAt: start, calendar: calendar),
                        sessions: byWeek[start] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                // The goal card is pinned whatever else the list has in it, so an empty
                // list is still a list — with the emptiness said inside it, under the
                // card, rather than in place of the whole page. A search that finds
                // nothing is the one thing that replaces it: the card is not a result.
                if isSearching, visibleSessions.isEmpty {
                    noResultsState
                } else if ownSessions.isEmpty, !Goals.isPinned {
                    // Nothing pinned above them, so an empty list is an empty page.
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Sessions")
            .searchable(text: $searchText, prompt: "Search")
            .toolbar {
                // Compose lives top-right — the same corner the ellipsis holds
                // inside a session — leaving the bottom bar to the search field
                // and the (globally rendered) timer capsule.
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createSession) {
                        Label("New Session", systemImage: "square.and.pencil")
                    }
                }
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                // Invisible stand-in holding the timer capsule's slot open, so
                // the search field doesn't stretch under the capsule floating
                // above in the global overlay; it also takes the capsule's taps
                // here, since the bar band swallows touches aimed at overlays.
                // No spacer before it: the system's default item gap is the
                // same one it puts before the search field's cancel button.
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        barModel.stopwatch.toggleMenu()
                    } label: {
                        // The system pads item labels ~14 per side inside the
                        // slot, so the label under-sizes by 28 to make the SLOT
                        // come out at the capsule's width — otherwise the
                        // search field runs shorter than it does against its
                        // own cancel button. The hit area is grown back out to
                        // cover the full slot.
                        // The extra 16 shortens the search field a touch
                        // beyond the slot-width match.
                        Color.clear
                            .frame(width: max(20, barModel.capsuleWidth - 28 + 16), height: 48)
                            .contentShape(Rectangle().inset(by: -14))
                    }
                    .buttonStyle(.plain)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .navigationDestination(item: $newSession) { session in
                SessionDetailView(session: session, startsEditing: true)
            }
        }
        .bottomBarHost(barModel)
    }

    /// Notes' list: rows sit in rounded cards on a grouped background, no separators —
    /// one card per week, newest week first.
    /// `.insetGrouped` already supplies Notes' exact fills — `systemGroupedBackground`
    /// behind, `secondarySystemGroupedBackground` for the card.
    private var list: some View {
        List {
            // Above every week, headerless: the goal is not something that happened in
            // a week, it is what the weeks are for.
            if Goals.isPinned, !isSearching, let goal {
                Section {
                    NavigationLink {
                        SessionDetailView(session: goal)
                    } label: {
                        goalRow(for: goal)
                    }
                    .listRowSeparator(.hidden)
                }
            }
            if Goals.isPinned, !isSearching, ownSessions.isEmpty {
                Section {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            ForEach(weeks) { week in
                Section {
                    ForEach(week.sessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            row(for: session)
                        }
                    }
                    .onDelete { delete($0, from: week.sessions) }
                    .listRowSeparator(.hidden)
                } header: {
                    Text(week.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                        // Insets are relative to the card, so zero leading lines the
                        // header up with the card's edge and the navigation title.
                        .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 8, trailing: 0))
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(for session: ClimbSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(session.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(session.createdAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.subheadline)
                    .foregroundStyle(.quaternary)
            }
            Text(session.previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    /// The pinned card. A session row with a mark in front of it: the same two lines,
    /// minus the date, since a goal is not dated the way a session is.
    private func goalRow(for goal: ClimbSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "target")
                .font(.headline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(goalPreview(for: goal))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    /// What is written under the title, or what the page is for while nothing is —
    /// `previewText`'s own fallback counts attempts, which a goal note has none of.
    private func goalPreview(for goal: ClimbSession) -> String {
        goal.bodyPreview ?? Goals.placeholder
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Sessions", systemImage: "figure.climbing")
        } description: {
            Text("Start a new note when you get to the wall.")
        }
    }

    private var noResultsState: some View {
        ContentUnavailableView.search(text: searchText)
    }

    private func createSession() {
        let session = ClimbSession()
        modelContext.insert(session)
        try? modelContext.save()
        newSession = session
    }

    /// Indexes are into the rows of one week's card, not the whole list.
    private func delete(_ offsets: IndexSet, from rows: [ClimbSession]) {
        for index in offsets {
            let session = rows[index]
            session.attempts.forEach(VideoStore.delete)
            modelContext.delete(session)
        }
        try? modelContext.save()
    }
}

/// A week's worth of sessions, keyed by the day the week starts on.
private struct SessionWeek: Identifiable {
    let id: Date
    let title: String
    let sessions: [ClimbSession]
}

private extension SessionListView {
    /// "This Week" / "Last Week", then a date range — "Aug 3 – 9", carrying the year once
    /// the week falls outside this one.
    static func weekTitle(startingAt start: Date, calendar: Calendar) -> String {
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start
        if start == currentWeek { return "This Week" }
        if let previous = currentWeek.flatMap({ calendar.date(byAdding: .weekOfYear, value: -1, to: $0) }),
           start == previous {
            return "Last Week"
        }

        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let sameYear = calendar.isDate(start, equalTo: Date(), toGranularity: .year)
        let style = sameYear
            ? Date.IntervalFormatStyle().month(.abbreviated).day()
            : Date.IntervalFormatStyle().year().month(.abbreviated).day()
        return (start..<end).formatted(style)
    }
}
