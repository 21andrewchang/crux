import SwiftUI
import SwiftData

/// The last page of the note, and the only one that isn't a document.
///
/// The other three are places to write. This one is a place to read: it is the same
/// shape every session, it is never typed into, and everything on it is counted off
/// what was already logged rather than asked for again. That is the whole point of the
/// page — the work of a session is done on the wall, and a review that asks for more
/// typing at the end of one is a review nobody fills in.
///
/// What it counts, and why these:
///
/// - **Duration** runs from the moment the check-in was done with — or from when the
///   note was made, for one that never went through a check-in. It keeps moving until
///   the session is ended, so the number at the top of the page is the session as it
///   stands rather than as it finished.
/// - **Climbs** is how many distinct problems the note names — the climb headings, not
///   the attempts under them. A go recorded with no climb over it is a go on something
///   the note never named, and inventing a problem for it would inflate the one number
///   here that is supposed to mean "how much did I actually work on".
/// - **Attempts** is every go, named or not.
/// - **Avg rest** is the gap between goes, off the timestamps. Long gaps mean a
///   project day and short ones mean a volume day, which is the one thing on this page
///   that says something about *how* the session was run rather than how much was in it.
/// - **Notes** is the goes you wrote something on, which is never all of them.
/// - **Effort** is a count per word rather than an average. An average of four
///   unanchored words is a number with no unit; the shape of the four counts is the
///   actual reading — a session that is all Easy and a session that is all Limit both
///   average to nothing useful, and tell you completely different things. It carries no
///   heading of its own: the four words down the left say what they are.
struct SessionReviewView: View {
    @Bindable var session: ClimbSession
    /// What the header takes off the top of the screen, handed down so the page starts
    /// under it rather than behind it.
    var topInset: CGFloat
    var onChange: () -> Void
    /// The session has just been called. The note folds itself down behind this page
    /// — every climb closed, every attempt closed under it — so what is left when you
    /// swipe back is the list of what you climbed rather than the whole log of it.
    var onEnd: () -> Void = {}

    /// Everything still in the note. A deleted row keeps its record and its video, so
    /// counting the relationship raw would keep counting attempts that were taken back.
    private var attempts: [Attempt] {
        session.attempts.filter { $0.deletedAt == nil }
    }

    private var climbCount: Int { session.climbNames.count }

    private var attemptCount: Int { attempts.count }

    /// The goes you wrote something on. Not every attempt gets a note and that is the
    /// reading — an attempt with a note is one you had something to say about.
    private var noteCount: Int {
        attempts.filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    /// How long the gaps between goes ran, on average.
    ///
    /// Measured off the attempts' own timestamps rather than off `restSeconds`, which
    /// only counts the seconds the attempt page happened to be up — close the page and
    /// sit down for four minutes and that number says nothing. A gap here is from the
    /// end of one recording to the start of the next, so the climbing itself is not
    /// counted as rest.
    ///
    /// Gaps past `restCeiling` are left out. Somebody who stopped for lunch did not
    /// rest for forty minutes between goes, and one break like that drags the average
    /// far enough to make the number worse than no number.
    private var averageRest: TimeInterval? {
        let ordered = attempts.sorted { $0.createdAt < $1.createdAt }
        guard ordered.count > 1 else { return nil }
        var gaps: [TimeInterval] = []
        for (current, next) in zip(ordered, ordered.dropFirst()) {
            let gap = next.createdAt.timeIntervalSince(current.createdAt) - current.videoDuration
            if gap > 0, gap <= Self.restCeiling { gaps.append(gap) }
        }
        guard !gaps.isEmpty else { return nil }
        return gaps.reduce(0, +) / Double(gaps.count)
    }

    /// Past this, a gap is a break rather than a rest.
    private static let restCeiling: TimeInterval = 15 * 60

    private func count(of effort: Effort) -> Int {
        attempts.filter { $0.effort == effort }.count
    }

    private var unratedCount: Int {
        attempts.filter { $0.effort == nil }.count
    }

    /// The longest bar on the effort chart, so the four are drawn against each other
    /// rather than each against itself. Never zero — a chart of nothing draws flat.
    private var effortPeak: Int {
        max(1, Effort.allCases.map(count).max() ?? 1)
    }

    var body: some View {
        // No scroll view. There are four numbers and a clock on here and there always
        // will be — a page that fits is a page whose button is where you left it, and
        // the button is the one thing on here you press without reading.
        VStack(alignment: .leading, spacing: 28) {
            clock
            tiles
            effort
            ender
        }
        // Centred in the room between the pills and the bar, so the air above the
        // clock and the air under the last row match. The height is measured off the
        // screen rather than asked for with a `maxHeight: .infinity` — inside the
        // paging view that carries the four pages, an infinite frame here came back
        // the size of the content and the page stayed hung off the top.
        .frame(maxWidth: .infinity, minHeight: room, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, topInset)
        // Clear of the bar the note carries at the bottom of every page.
        .padding(.bottom, 108)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
    }

    /// What is left of the screen once the header at the top and the bar at the bottom
    /// have taken theirs.
    private var room: CGFloat {
        max(0, UIScreen.main.bounds.height - topInset - 108)
    }

    // MARK: - The clock

    /// The one number big enough to read across a room, because it is the one you look
    /// at mid-session. It redraws every second while the session is running and holds
    /// still the moment it is ended — a `TimelineView` rather than a stored ticker, so
    /// a page nobody is looking at costs nothing.
    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = session.duration(asOf: context.date)
            VStack(alignment: .leading, spacing: 6) {
                // One word whichever state it is in. The number underneath is the
                // same measurement running or stopped, and renaming it on the way past
                // reads as two different figures. The clock rides with the word rather
                // than the digits — at caption size it labels, where next to the
                // numerals it competed with them.
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.footnote.weight(.medium))
                    Text("Duration")
                        .font(.footnote.weight(.medium))
                }
                .foregroundStyle(Color.paper.opacity(0.45))

                // The number and the switch that stops it, on one line. The button is
                // beside the digits rather than under them because it is a control on
                // *this* number, and because the bottom of the page belongs to the one
                // button that ends the session.
                // Centred rather than sat on the digits' baseline: a symbol's baseline
                // is not its foot, so a mark aligned that way hangs visibly low against
                // numerals that have nothing below theirs.
                HStack(spacing: 12) {
                    Text(Self.longClock(elapsed))
                        .font(.system(size: Self.clockSize, weight: .semibold))
                        .monospacedDigit()
                        // Dimmer whenever the clock is standing still, paused or ended.
                        // Nothing is moving, and the digits saying so is what stops a
                        // frozen clock reading as a broken one.
                        .foregroundStyle(Color.paper.opacity(session.isRunning ? 1 : 0.5))
                        // The digits change width as the hour rolls over; without this the
                        // whole line jumps a pixel every time a minute does.
                        .contentTransition(.numericText())

                    Spacer(minLength: 0)

                    pauseSwitch
                }
                .animation(.easeInOut(duration: 0.2), value: session.isRunning)
            }
        }
    }

    /// Pause, continue, and the way back into a session already called — one control,
    /// because they are all the same question about the number beside it.
    ///
    /// Whenever the clock is moving it offers to stop it; whenever it is standing
    /// still — paused for lunch, or ended an hour ago and picked back up — it offers
    /// to continue, and continuing carries on from the number on screen. The stretch
    /// that was paused or ended is banked rather than climbed, so a session left at
    /// thirty minutes reads thirty minutes and one second when it comes back, not
    /// however long the phone was in a bag.
    ///
    /// It is the only way back into an ended session, which is why it stays on the page
    /// after the End button has gone.
    private var pauseSwitch: some View {
        Button {
            if session.endedAt != nil {
                session.reopen()
            } else if session.isPaused {
                session.resume()
            } else {
                session.pause()
            }
            Haptics.selection()
            onChange()
        } label: {
            // No word, no capsule: a mark drawn to the height of the digits and
            // centred on them, reading as the other half of the clock rather than as
            // a control parked next to it. The two glyphs swap in place — the same
            // switch throwing, not one button leaving and another arriving.
            Image(systemName: session.isRunning ? "pause.fill" : "play.fill")
                .font(.system(size: Self.markSize, weight: .semibold))
                .foregroundStyle(Color.paper)
                .contentTransition(.symbolEffect(.replace))
                // Invisible room around a mark that would otherwise be a thin tap
                // target at the very edge of the screen. The trailing side is wider
                // than the page's own margin, holding the mark in off the edge rather
                // than letting it sit flush with the tiles below.
                .padding(.leading, 16)
                .padding(.trailing, 10)
                .padding(.vertical, 8)
                .contentShape(.rect)
                // Centring the boxes still leaves the mark reading low beside numerals
                // whose weight all sits above the baseline. Optical, so it is a nudge
                // rather than a measurement — and it carries the tap target with it.
                .offset(y: -4)
        }
        .buttonStyle(.plain)
    }

    /// The clock's own size, and the mark's — one number apiece, because the mark is
    /// meant to read as part of the number rather than as something beside it. The mark
    /// is set well under: a symbol drawn at the digits' point size comes out taller
    /// than they do, since the digits spend theirs on the room above and below.
    private static let clockSize: CGFloat = 52
    private static let markSize: CGFloat = 33

    /// `1:04:22` past the hour, `4:22` under it — an hour of leading zero on a number
    /// that spends most of its life under sixty minutes is an hour of noise.
    private static func longClock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - The counts

    /// Four numbers in a grid rather than a list, so the page reads as a scoreboard at
    /// a glance instead of as rows to be gone through one at a time.
    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)],
                  spacing: 10) {
            tile("Climbs", "\(climbCount)")
            tile("Attempts", "\(attemptCount)")
            tile("Avg rest", averageRest?.clockString ?? "—")
            tile("Notes", "\(noteCount)")
        }
    }

    private func tile(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.paper)
                .contentTransition(.numericText())
            Text(name)
                .font(.footnote)
                .foregroundStyle(Color.paper.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface, in: .rect(cornerRadius: 16))
    }

    // MARK: - Effort

    /// No heading. The four words are down the left of it and they are the heading —
    /// a line reading "Effort" above a row that reads "Easy" is the same thing said
    /// twice, and the space it costs is space this page does not have to spare if it
    /// is going to fit without scrolling.
    private var effort: some View {
        VStack(spacing: 10) {
            ForEach(Effort.allCases) { level in
                effortRow(level.label, tint: level.color, value: count(of: level))
            }
            // Only when there are some. An "Unrated 0" row on every session is a
            // reproach for nothing, and rating is optional on purpose.
            if unratedCount > 0 {
                effortRow("Unrated", tint: Color.paper.opacity(0.3), value: unratedCount)
            }
        }
    }

    /// A word, a bar, a number. The bar is drawn against the busiest level rather than
    /// against the total, so the shape of a session is legible even when most of the
    /// goes landed on one word.
    private func effortRow(_ name: String, tint: Color, value: Int) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(Color.paper.opacity(value == 0 ? 0.35 : 0.85))
                .frame(width: 68, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surface)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(value == 0 ? 0 : 6,
                                          proxy.size.width * Double(value) / Double(effortPeak)))
                }
            }
            .frame(height: 8)

            Text("\(value)")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Color.paper.opacity(value == 0 ? 0.35 : 0.85))
                .frame(width: 24, alignment: .trailing)
        }
        .animation(.easeInOut(duration: 0.25), value: value)
    }

    // MARK: - Ending it

    /// The bottom of the page, and the end of the session: one button, and once it is
    /// pressed, nothing. The ended time is already on the clock above, and the way back
    /// into an ended session belongs somewhere other than under the button that ends it
    /// — it is Continue, up beside the number it would restart.
    @ViewBuilder
    private var ender: some View {
        if session.endedAt == nil {
            Button {
                session.end()
                Haptics.sessionEnded()
                onChange()
                onEnd()
            } label: {
                // Sized to its own words rather than to the screen. A full-width slab
                // is the shape of a button you are meant to press to get on with
                // something; this one ends the session, which is worth having to aim
                // at. It keeps the page's left edge with everything else on it.
                Text("End session")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Color.paper, in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }
}
