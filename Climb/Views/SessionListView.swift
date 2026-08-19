import SwiftUI
import SwiftData
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
    @State private var store = Store.shared
    /// Up when the compose button was pressed with no free session left to make.
    @State private var showsPaywall = false
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
            .navigationTitle("Sessions")
            .searchable(text: $searchText, prompt: "Search")
            .toolbar {
                // The way back into onboarding, top-left, for as long as onboarding
                // is the thing being built: walking the flow should cost a tap, not a
                // reinstall or a relaunch with an argument. It moves where you are in
                // the flow and nothing else — no note, no attempt and no video is
                // touched by it, so it can never cost anything to press.
                #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Onboarding.shared.reset()
                    } label: {
                        Label("Replay onboarding", systemImage: "sparkles")
                    }
                }
                #endif
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
                    onSkip: { open(session) })
            }
            // A sheet rather than a cover: this paywall is one you are meant to be able
            // to put down.
            .sheet(isPresented: $showsPaywall) {
                PaywallView(presentation: .limitReached,
                            onPurchase: subscribed,
                            onDismiss: { showsPaywall = false })
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
            if showsUsage {
                Section {
                    usageBar
                        .plainRow()
                        .listRowInsets(EdgeInsets(top: 24, leading: 0, bottom: 8, trailing: 0))
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Whether the free tier's meter is on screen.
    ///
    /// Not while subscribed — there is no limit left to meter — and not on an empty
    /// list, where "0 of 5 used" would be the app's opening line. It appears with the
    /// first session, which is the point at which a number is worth reading: what makes
    /// running out feel fair is having watched it coming, and what makes an empty app
    /// feel unwelcoming is being shown a quota before using anything.
    ///
    /// A search that hides rows leaves it up. It counts what is kept, not what is
    /// listed, and blinking out because a query matched nothing would read as the
    /// number having changed.
    private var showsUsage: Bool {
        !store.isPro && !ownSessions.isEmpty
    }

    /// How much of the free tier is spent, said plainly and tappable. Tapping opens the
    /// paywall early — someone who reads the meter and decides now is the time to
    /// subscribe should not have to hit the wall first to be allowed to.
    private var usageBar: some View {
        let used = min(ownSessions.count, FreeTier.sessionLimit)
        let isFull = FreeTier.remaining(ownSessionCount: ownSessions.count) == 0
        return Button {
            showsPaywall = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(used) of \(FreeTier.sessionLimit) free sessions")
                    Spacer()
                    Text(isFull ? "Subscribe" : "Upgrade")
                        .foregroundStyle(.white)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                // Drawn rather than a ProgressView: this needs to be a hairline on
                // black, and the system's bar brings its own colour and thickness.
                GeometryReader { proxy in
                    let fraction = Double(used) / Double(FreeTier.sessionLimit)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.surface)
                        Capsule()
                            .fill(isFull ? Color.routeHold : Color.white.opacity(0.55))
                            .frame(width: max(3, proxy.size.width * fraction))
                    }
                }
                .frame(height: 3)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: used)
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

    /// Compose. Under the cap this is the whole of it; at the cap the paywall comes up
    /// instead and nothing is written — the session is not made and then taken away,
    /// which would leave a note on screen that the list refuses to keep.
    private func createSession() {
        guard FreeTier.allowsAnotherSession(ownSessionCount: ownSessions.count,
                                            isPro: store.isPro) else {
            showsPaywall = true
            return
        }
        let session = ClimbSession()
        modelContext.insert(session)
        try? modelContext.save()
        checkingIn = session
    }

    /// Puts the check-in away and opens the note behind it. The two are not swapped in
    /// one turn: dismissing a cover and pushing a destination in the same frame drops
    /// the push, so the note is opened once the cover has actually gone.
    private func open(_ session: ClimbSession) {
        checkingIn = nil
        DispatchQueue.main.async { newSession = session }
    }

    /// Bought, from the wall they hit on the way to a new session — so they get the
    /// session they asked for. The guard in `createSession` passes now that the
    /// entitlement has moved, and the note opens as if the wall had never been there.
    private func subscribed() {
        showsPaywall = false
        createSession()
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
