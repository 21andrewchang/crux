import SwiftUI
import UIKit

/// The beat between the quiz and the walkthrough: a ring filling while the answers are
/// turned into something, with the list of what is being made ticking off under it.
///
/// The copy names only what the app actually does with what was just answered — a
/// profile, a pair of grades, the focus areas, and the goal page they all land on.
/// Nothing here claims work that isn't happening.
struct LoadingView: View {
    /// Ticked in order, one per quarter of the ring. Named for the thing being made
    /// rather than for the code making it.
    private static let steps = ["Climbing profile",
                                "Grade targets",
                                "Focus areas",
                                "Your goal page"]

    /// Long enough that the ring reads as a fill rather than a jump, short enough that
    /// it never becomes waiting. Nothing is actually being computed behind it — the
    /// screen is the beat, so this is the whole of the wait.
    private static let duration: TimeInterval = 2

    var onFinish: () -> Void

    /// Driven by hand rather than by `withAnimation`, because the number in the middle
    /// has to be the same value the ring is drawn from — an implicit animation would
    /// move the arc and leave the digits behind.
    @State private var progress: Double = 0

    private var done: Int { Int(progress * Double(Self.steps.count)) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ring

            Text("Setting up your journal")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 40)

            card
                .padding(.top, 36)

            Spacer()
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task(run)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.surface, lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                // From the top, clockwise — a ring that starts anywhere else reads as a
                // dial being turned rather than as something filling up.
                .rotationEffect(.degrees(-90))

            Text("\(Int(progress * 100))%")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 180, height: 180)
    }

    /// The list of what is being made, lifted off the black by a few percent rather than
    /// boxed in by a line — the same way every other block in the app stands apart.
    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("From your answers")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.45))

            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                let isDone = index < done
                HStack(spacing: 12) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isDone ? Color.white : Color.white.opacity(0.25))
                        .contentTransition(.symbolEffect(.replace))
                    Text(step)
                        .foregroundStyle(isDone ? Color.white : Color.white.opacity(0.4))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.surface, in: .rect(cornerRadius: 18))
        .animation(.easeInOut(duration: 0.25), value: done)
    }

    /// The fill, stepped by hand at screen rate. Eased at both ends so it leaves and
    /// arrives slowly, which is what makes the couple of seconds read as work rather
    /// than as a timer, with a tap under the finger every time a line is ticked.
    @Sendable
    private func run() async {
        let tap = UIImpactFeedbackGenerator(style: .medium)
        tap.prepare()

        let start = ContinuousClock.now
        var ticked = 0
        while true {
            let since = start.duration(to: .now)
            let elapsed = Double(since.components.seconds)
                + Double(since.components.attoseconds) / 1e18
            let t = min(elapsed / Self.duration, 1)
            progress = t * t * (3 - 2 * t)

            if done > ticked {
                ticked = done
                tap.impactOccurred()
                tap.prepare()
            }
            if t >= 1 { break }

            try? await Task.sleep(for: .milliseconds(33))
            // Cancelled means the screen went away underneath us — nothing to finish.
            if Task.isCancelled { return }
        }

        try? await Task.sleep(for: .seconds(0.3))
        if Task.isCancelled { return }
        onFinish()
    }
}
