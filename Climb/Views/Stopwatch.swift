import SwiftUI
import UIKit

/// A glyph rendered through UIKit's symbol configuration, so the raster matches
/// the system bottom bar pixel for pixel. The point sizes below were measured
/// off the live system bar (its icons are ~27pt, not the 17–20pt you'd guess):
/// plus 26.71 → 28.7×26.7, video/timer 26.96 → 38.7×26.7 / 32×32, all medium.
private func barGlyph(_ name: String, pointSize: CGFloat) -> Image {
    let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    let image = UIImage(systemName: name, withConfiguration: config) ?? UIImage()
    return Image(uiImage: image.withRenderingMode(.alwaysTemplate))
}

/// Countdown state behind the stopwatch item in the note's bottom bar.
@Observable
final class StopwatchModel {
    private(set) var isRunning = false
    /// Countdown target; nil until a duration is picked from the menu.
    private(set) var duration: TimeInterval?
    /// Time banked across earlier run stretches; the live stretch adds on top.
    private var accumulated: TimeInterval = 0
    private var startedAt: Date?

    /// Once started, the button shows time (running or paused) instead of the icon.
    var hasStarted: Bool { duration != nil }

    /// Idle disc tapped; the floating menu is showing the duration choices.
    var isChoosing = false

    /// Kick off a fresh countdown with the picked duration, less one second so a
    /// round-minute pick opens on X:59 — showing 10:00 for a beat and then dropping
    /// to 9:59 shrinks the capsule mid-flight.
    func start(_ duration: TimeInterval) {
        isChoosing = false
        self.duration = duration - 1
        accumulated = 0
        startedAt = Date()
        isRunning = true
    }

    /// Pause → resume, one tap each.
    func toggle() {
        if let startedAt {
            accumulated += Date().timeIntervalSince(startedAt)
            self.startedAt = nil
            isRunning = false
        } else {
            startedAt = Date()
            isRunning = true
        }
    }

    func remaining(at date: Date) -> TimeInterval {
        let elapsed = accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
        return max(0, (duration ?? 0) - elapsed)
    }

    /// Back to the bare icon: nothing banked, nothing running. `isRunning` is left
    /// alone on purpose — the face is animating out when this runs, and flipping it
    /// would swap the glyph to play mid-exit. `start` sets it fresh anyway.
    func reset() {
        duration = nil
        accumulated = 0
        startedAt = nil
    }
}

/// When the parked system bar shows, Notes-style: never a crossfade with the
/// keyboard bar. The keyboard bar slides down with the keyboard and, just before
/// it lands on the parked position, the system items snap on in place (and snap
/// off the instant the keyboard starts to rise). Both flips run with animations
/// disabled — the motion on screen is only ever the keyboard bar travelling.
@Observable
final class BarParkModel {
    private(set) var parked = true
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// Keyboard is rising — the accessory clone takes over this instant.
    func lift() {
        pending?.cancel()
        setParkedInstantly(false)
    }

    /// Keyboard is dismissing over `duration` — snap the parked bar on just
    /// before the sliding bar reaches it.
    func parkAfter(_ duration: TimeInterval) {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 0.85 * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.setParkedInstantly(true)
        }
    }

    private func setParkedInstantly(_ value: Bool) {
        guard parked != value else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { parked = value }
    }
}

extension View {
    /// The system animates bottom bar items across a push/pop with a fairly bouncy
    /// spring. Overriding the transaction flattens whatever animation reaches these
    /// items into the app's standard smooth curve, taking the overshoot out of the
    /// toolbar morph. Only reaches content we own — the search field animates itself.
    func dampedToolbarMorph() -> some View {
        transaction { t in
            guard t.animation != nil else { return }
            t.animation = .smooth(duration: 0.35)
        }
    }
}

/// The started stopwatch's face — transport glyph beside the live countdown. The
/// system bottom bar supplies the capsule around it and stretches as this resizes.
struct StopwatchFace: View {
    var stopwatch: StopwatchModel

    var body: some View {
        HStack(spacing: 6) {
            // Once running the face is a plain transport control —
            // pause while running, play while paused.
            let symbol = stopwatch.isRunning ? "pause.fill" : "play.fill"
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(stopwatch.isRunning ? AnyShapeStyle(.secondary) : AnyShapeStyle(.green))
                // The glyph swaps instantly — only the capsule stretch animates.
                .contentTransition(.identity)
                .animation(nil, value: symbol)
            // Half-second ticks keep whole-second digits honest without
            // a per-frame timeline. Paused, the value freezes and dims.
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(stopwatch.remaining(at: context.date).clockString)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
            }
            // TimelineView greedily fills the width it's offered;
            // pin it to the text's own size so the capsule hugs.
            .fixedSize()
            .opacity(stopwatch.isRunning ? 1 : 0.5)
            .transition(.opacity)
        }
    }
}

/// The bar that rides the keyboard while the note is being edited. The parked bar
/// is the real system bottom bar (which cannot be moved — SwiftUI re-pins its
/// chrome every frame), so this clone takes over the moment the keyboard rises,
/// attached as the text view's input accessory so UIKit moves it with the
/// keyboard for free. Its metrics are measured off the live system bar so the
/// swap reads as the same bar travelling up: 48pt capsules, 28pt side margins,
/// 4pt between the pill's buttons.
struct EditingToolbar: View {
    var stopwatch: StopwatchModel
    var onAddClimb: () -> Void
    var onStartAttempt: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Button(action: onAddClimb) {
                        barGlyph("plus", pointSize: 26.7083)
                            .frame(width: 54.6667, height: 48)
                            .contentShape(.rect)
                    }
                    Button(action: onStartAttempt) {
                        barGlyph("video.fill", pointSize: 26.9583)
                            .frame(width: 64.6667, height: 48)
                            .contentShape(.rect)
                    }
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)

                Spacer()

                stopwatchCapsule
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    /// Same states as the parked stopwatch item: idle disc, or the running face
    /// with a reset target on its trailing edge.
    private var stopwatchCapsule: some View {
        HStack(spacing: 0) {
            if !stopwatch.hasStarted {
                Button {
                    withAnimation(.smooth(duration: 0.35)) { stopwatch.isChoosing.toggle() }
                } label: {
                    barGlyph("timer", pointSize: 26.9583)
                        .frame(width: 48, height: 48)
                        .contentShape(.rect)
                }
            } else {
                Button {
                    withAnimation(.smooth(duration: 0.35)) { stopwatch.toggle() }
                } label: {
                    StopwatchFace(stopwatch: stopwatch)
                        .padding(.leading, 12)
                        .frame(minWidth: 48)
                        .frame(height: 48)
                        .contentShape(.rect)
                }
                Button {
                    withAnimation(.smooth(duration: 0.35)) { stopwatch.reset() }
                } label: {
                    // Mirrors the parked bar's reset, which is declared at
                    // 14pt semibold against the same 19pt transport glyphs.
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 48)
                        .contentShape(.rect)
                }
                .transition(.opacity)
            }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .animation(.smooth(duration: 0.35), value: stopwatch.hasStarted)
        .animation(.smooth(duration: 0.35), value: stopwatch.isChoosing)
    }
}

/// Narrow vertical list of the three durations — a stand-in for the system menu,
/// which imposes a huge minimum width. Hosted by the session view, floating over
/// everything, so the bottom bar never has to make room for it.
struct TimerDurationMenu: View {
    var start: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach([10, 5, 2], id: \.self) { minutes in
                Button {
                    start(TimeInterval(minutes * 60))
                } label: {
                    Text("\(minutes):00")
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
            }
        }
        .frame(width: 110)
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        .transition(.scale(scale: 0.1, anchor: .bottomTrailing).combined(with: .opacity))
    }
}
