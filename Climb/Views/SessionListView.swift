import PostHog
import SwiftData
import SwiftUI
import UIKit

/// The notes list: one row per session, newest first.
struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClimbSession.createdAt, order: .reverse) private var sessions: [ClimbSession]
    @State private var newSession: ClimbSession?
    /// The session made but not yet opened: the check-in is over it, and it opens when
    /// the check-in is done with — answered or backed out of.
    @State private var checkingIn: ClimbSession?
    @State private var searchText = ""
    /// The global bottom bar's state; the bar itself floats over the whole
    /// navigation stack below, so it never re-enters or resets across pushes.
    @State private var barModel = BottomBarModel()
    /// Whether the profile is up — the quiz's answers drawn as one shape, read rather
    /// than walked into.
    @State private var showingProfile = false
    /// Whether the list itself is what is on screen. The card and the button that opens
    /// it belong to this page, and the overlay carrying them sits outside the
    /// navigation stack so it can cover the bars — which also means nothing takes it
    /// away on a push unless this does.
    @State private var isAtRoot = true

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
        return ownSessions.filter { $0.searchText.localizedCaseInsensitiveContains(query) }
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
            .onAppear { isAtRoot = true }
            .onDisappear { isAtRoot = false }
            // Straight off the paywall into a session. Paying is somebody saying they
            // want to use this, and the honest answer to that is the check-in, not a
            // list with one button on it: the first thing the app does with the money
            // is start the thing it was bought for.
            .task { startFirstSessionIfNeeded() }
            .navigationTitle("Sessions")
            .searchable(text: $searchText, prompt: "Search")
            // PostHog: track when a search query is submitted
            .onChange(of: isSearching) { _, nowSearching in
                if nowSearching {
                    PostHogSDK.shared.capture("session_searched")
                }
            }
            .toolbar {
                // The profile opposite compose: the two things this page offers that
                // are not a session — read where you are, or start one.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingProfile = true
                    } label: {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                }
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
            // Over everything, and before the note exists on screen: a session begins
            // with the check-in or it does not begin. A cover rather than a sheet —
            // there is nothing behind it worth seeing, and it is not something to put
            // half down.
            .fullScreenCover(item: $checkingIn) { session in
                CheckInFlow(
                    answers: session.checkIn,
                    onFinish: { answers in
                        session.checkIn = answers
                        session.updatedAt = Date()
                        try? modelContext.save()
                        open(session)
                    },
                    onSkip: { open(session) },
                    // Answered, not climbing. The check-in is kept and the cover comes
                    // down onto the list — the session is there, waiting, rather than
                    // pushed open in front of somebody who has just said not yet.
                    onLater: { answers in
                        session.checkIn = answers
                        session.updatedAt = Date()
                        try? modelContext.save()
                        checkingIn = nil
                    })
            }
        }
        .bottomBarHost(barModel)
        // The page goes soft under the card rather than only dark. Ramped rather than
        // switched: the blur comes up with the card and goes with it, so the list reads
        // as falling out of focus behind something arriving in front of it instead of
        // being replaced by a blurred copy of itself.
        .blur(radius: showingProfile ? 18 : 0)
        .animation(.easeOut(duration: 0.28), value: showingProfile)
        // Over the whole page, bars included: the card is a thing held up in front of
        // the list, not a panel inside it.
        .overlay {
            if isAtRoot {
                ProfileCard(isPresented: showingProfile) { showingProfile = false }
            }
        }
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

    /// What the page says with nothing on it. The first session opens itself now — off
    /// the wall, straight into the check-in — so this is no longer the front door it was
    /// written as: it is what is left after Later, or after the last session is deleted.
    /// Which makes it a prompt rather than a landing, and it is set as one.
    private var emptyState: some View {
        Button(action: createSession) {
            ContentUnavailableView {
                Label {
                    // Big, because there is nothing else here. The line was sized down
                    // to a caption when it sat above a white capsule that was the only
                    // thing worth pressing — with the capsule gone it is the thing being
                    // pressed, and a title is what a page with one thing on it says.
                    Text("Start Your First Session")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.paper)
                } icon: {
                    // Still faint. The mark says what the screen is; the words say what
                    // to do about it.
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(Color.paper.opacity(0.3))
                }
            } description: {
                // The whole block is the button, so the instruction is the affordance:
                // dimmed rather than lightened, because it is the footnote under the
                // title and not a second thing to decide between.
                Text("Tap to continue")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.paper.opacity(0.35))
            }
            // Nothing is drawn between the words and the touch, so the gaps between
            // them have to take the tap along with the glyphs.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Up off the centre line. Dead centre puts the words in the middle of the
        // glass, which is where a thumb rests rather than where the eye lands first.
        .offset(y: -56)
    }

    private var noResultsState: some View {
        ContentUnavailableView.search(text: searchText)
    }

    /// The one session nobody asks for. Onboarding sets the flag as it hands over off
    /// the first-run wall, and this is the only place that reads it — so it fires once,
    /// on the launch that just came through the flow, and never again. Whether the list
    /// is empty is not asked here: the flag already means first run, and a debug pass
    /// through the flow with last week's sessions still on file should behave like the
    /// real thing rather than quietly skip the part being tested.
    private func startFirstSessionIfNeeded() {
        let onboarding = Onboarding.shared
        guard onboarding.startsFirstSession else { return }
        onboarding.startsFirstSession = false
        createSession()
    }

    /// Compose.
    private func createSession() {
        let session = ClimbSession()
        modelContext.insert(session)
        try? modelContext.save()
        // PostHog: track new session creation
        PostHogSDK.shared.capture("session_created", properties: [
            "total_sessions": ownSessions.count + 1,
        ])
        checkingIn = session
    }

    /// Fires once when a search query is first entered, so we know search is being used.
    private var searchQueryForTracking: String { searchText.trimmingCharacters(in: .whitespaces) }

    /// Puts the check-in away and opens the note behind it. The two are not swapped in
    /// one turn: dismissing a cover and pushing a destination in the same frame drops
    /// the push, so the note is opened once the cover has actually gone.
    private func open(_ session: ClimbSession) {
        // The check-in is the door into the session, so leaving it is the session
        // starting — whether the four questions were answered or walked past.
        session.startIfNeeded()
        try? modelContext.save()
        checkingIn = nil
        DispatchQueue.main.async { newSession = session }
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
