import SwiftUI
import SwiftData

/// The notes list: one row per session, newest first.
struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClimbSession.createdAt, order: .reverse) private var sessions: [ClimbSession]
    @State private var newSession: ClimbSession?
    @State private var searchText = ""

    /// Title and body both match, so searching finds a session by anything written in it.
    private var visibleSessions: [ClimbSession] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sessions }
        return sessions.filter { $0.bodyText.localizedCaseInsensitiveContains(query) }
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
                if sessions.isEmpty {
                    emptyState
                } else if visibleSessions.isEmpty {
                    noResultsState
                } else {
                    list
                }
            }
            .navigationTitle("Sessions")
            .searchable(text: $searchText, prompt: "Search")
            .toolbar {
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button(action: createSession) {
                        Label("New Session", systemImage: "square.and.pencil")
                    }
                    .dampedToolbarMorph()
                }
            }
            .navigationDestination(item: $newSession) { session in
                SessionDetailView(session: session)
            }
        }
    }

    /// Notes' list: rows sit in rounded cards on a grouped background, no separators —
    /// one card per week, newest week first.
    /// `.insetGrouped` already supplies Notes' exact fills — `systemGroupedBackground`
    /// behind, `secondarySystemGroupedBackground` for the card.
    private var list: some View {
        List {
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
            Text(session.displayTitle)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(session.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
                Text(session.previewText)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
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
