import SwiftUI
import UIKit

/// The beat between the quiz and the walkthrough: the answers being turned into
/// something, said out loud one line at a time, over a boulder problem going up the
/// screen a hold at a time. The route is the progress bar — how far up the wall it has
/// got is how far through this the app is.
struct LoadingView: View {
    /// Said in the order they happen, and named for what the app is doing with what was
    /// just answered rather than for what the code is doing.
    private static let stages = ["Creating climbing profile",
                                 "Personalizing journal"]

    /// How long each line holds. Long enough to read, short enough that it never feels
    /// like waiting.
    private static let stageDuration: TimeInterval = 1.8

    /// Where the room's light hangs. The wall is painted by it and the holds are lit by
    /// it, so it is settled once here and handed to both.
    private static let light = CGVector(dx: -0.48, dy: -0.62)

    var onFinish: () -> Void

    @State private var stage = 0
    @State private var progress: CGFloat = 0

    var body: some View {
        // The wall first, then the route on it, then the line being read over the middle.
        // Two shadows under the words — a tight one to hold the letters off any hold they
        // land on, a wide one to sink the wall behind them.
        ZStack {
            GymWall(light: Self.light)

            // The light swings a few degrees across the whole run. Almost nothing moves,
            // but the gloss crawls over the holds as it goes, and a highlight that moves
            // is the one thing a picture of a hold can never do.
            TimelineView(.animation) { context in
                RouteProgress(progress: progress, light: Self.light(at: context.date))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 40)
            }

            Text(Self.stages[min(stage, Self.stages.count - 1)])
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                // Only the band the words themselves take is darkened, blurred out to
                // nothing at its edges — the wall keeps its middle, the letters keep
                // their contrast.
                .background {
                    Capsule()
                        .fill(.black.opacity(0.62))
                        .blur(radius: 30)
                        .padding(.horizontal, -48)
                        .padding(.vertical, -22)
                }
                .shadow(color: .black.opacity(0.9), radius: 5)
                .id(stage)
                .transition(.opacity)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .animation(.easeInOut(duration: 0.3), value: stage)
        .task(run)
    }

    /// The light, swung a little either side of where it hangs. Slow enough that it is
    /// never the thing being watched, wide enough that no two holds catch it at once.
    private static func light(at date: Date) -> CGVector {
        let sweep = sin(date.timeIntervalSinceReferenceDate * 0.55) * 0.16
        return CGVector(dx: light.dx * cos(sweep) - light.dy * sin(sweep),
                        dy: light.dx * sin(sweep) + light.dy * cos(sweep))
    }

    /// The run, one stage per half of the wall: the bottom half goes up under the first
    /// line, everything stops, the line changes, and the top half goes up under the
    /// second. Each half is a run of its own — slow at the start, quick through the
    /// middle, slow again at the top — so the pause reads as the halfway rest it is.
    @Sendable
    private func run() async {
        let holds = RouteProgress.holds.count
        guard holds > 1 else { onFinish(); return }

        let tap = UIImpactFeedbackGenerator(style: .medium)
        tap.prepare()

        let half = holds / 2
        guard await place(0..<half, tapping: tap) else { return }

        // The rest between halves: hands off, read the next line, carry on.
        try? await Task.sleep(for: .seconds(0.45))
        if Task.isCancelled { return }
        stage = 1
        try? await Task.sleep(for: .seconds(0.5))
        if Task.isCancelled { return }

        guard await place(half..<holds, tapping: tap) else { return }

        try? await Task.sleep(for: .seconds(0.45))
        if Task.isCancelled { return }
        onFinish()
    }

    /// Puts one stretch of the route on the wall over `stageDuration`, a hold at a time.
    /// The gaps come off a cosine — widest at either end of the stretch, tightest
    /// through its middle — which is a progress bar's speeding up and slowing down, felt
    /// in the taps as much as seen in the holds. False if the screen went away.
    private func place(_ range: Range<Int>, tapping tap: UIImpactFeedbackGenerator) async -> Bool {
        let count = range.count
        guard count > 0 else { return true }
        let gaps = (0..<max(count - 1, 1)).map { index -> Double in
            let along = count > 2 ? Double(index) / Double(count - 2) : 0.5
            return 1 + 0.8 * cos(2 * .pi * along)
        }
        let scale = Self.stageDuration / max(gaps.reduce(0, +), 0.001)

        for (step, index) in range.enumerated() {
            withAnimation(.easeOut(duration: 0.22)) {
                progress = CGFloat(index + 1) / CGFloat(RouteProgress.holds.count)
            }
            // The same tap every time: a hold going on the wall is one event, not a
            // measurement of the hold.
            tap.impactOccurred()
            tap.prepare()

            guard step < count - 1 else { break }
            try? await Task.sleep(for: .seconds(gaps[step] * scale))
            // Cancelled means the screen went away underneath us — nothing to finish.
            if Task.isCancelled { return false }
        }
        return true
    }
}
