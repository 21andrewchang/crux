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
    ///
    /// `from` backdates the start: the rest countdown after an attempt runs from the
    /// moment the recording stopped, not the moment Finish was tapped. A backdated
    /// start is already mid-flight, so it keeps the full duration — the X:59 trim
    /// only applies to fresh menu picks.
    func start(_ duration: TimeInterval, from startDate: Date? = nil) {
        isChoosing = false
        self.duration = startDate == nil ? duration - 1 : duration
        accumulated = 0
        startedAt = startDate ?? Date()
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
/// keyboard bar, and never a timer. The keyboard bar slides down with the
/// keyboard, and the swap is keyed to where that bar actually is on screen: a
/// display link reads its live (presentation-layer) position every frame, and a
/// few points before it would land on the parked capsule both flips happen at
/// once — clone off, system bar on — so the sliding bar can never quite reach
/// the parked position, which is exactly how Notes does it.
///
/// The flips are UIKit `isHidden` toggles, not SwiftUI state changes:
/// removing/reinserting the toolbar items makes the system play its own
/// insertion animation no matter what the transaction says, but a hidden view
/// is simply not drawn — instant both ways. The items themselves stay in the
/// toolbar permanently.
@MainActor
final class BarParkModel: NSObject {
    /// Anchor into the view hierarchy; the chrome is re-found through its
    /// window on every flip, so pushes and pops can rebuild it freely.
    weak var anchor: UIView?
    /// The accessory clone riding the keyboard, registered by the note editor
    /// when it builds its input accessory view.
    weak var keyboardBar: UIView?

    /// Swap this many points of travel before the clone would land on the
    /// parked capsule — late enough to read as one bar arriving, early enough
    /// that the clone visibly never gets there.
    private static let lead: CGFloat = 10

    private var watcher: CADisplayLink?
    private var deadline: Task<Void, Never>?
    /// Cached for the per-frame tick; the flips themselves re-find the chrome.
    private weak var watchedChrome: UIView?
    /// The trigger only arms once the clone has been seen *above* the parked
    /// spot. On its way up it starts below (rising from offscreen with the
    /// keyboard), and an unarmed trigger must not read that as "arrived".
    private var armed = false
    private var tickCount = 0

    // MARK: Diagnostics — Documents/barpark.log, pulled off the device with
    // devicectl. Rip out once the handoff is signed off.
    private static let debugLogging = true
    private var logHandle: FileHandle?

    private func log(_ line: String) {
        guard Self.debugLogging else { return }
        if logHandle == nil {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("barpark.log")
            FileManager.default.createFile(atPath: url.path, contents: Data())
            logHandle = try? FileHandle(forWritingTo: url)
        }
        logHandle?.write(Data((line + "\n").utf8))
    }

    /// Keyboard is rising — the accessory clone takes over this instant, and
    /// the watcher starts following it so any way down (animated dismiss,
    /// interactive drag) trips the swap at the same spot.
    func lift() {
        deadline?.cancel()
        armed = false
        keyboardBar?.isHidden = false
        watchedChrome = chrome
        watchedChrome?.isHidden = true
        log("lift: bar=\(keyboardBar.map(String.init(describing:)) ?? "nil") chrome=\(watchedChrome.map(String.init(describing:)) ?? "nil")")
        startWatching()
    }

    /// Keyboard is dismissing over `duration`. The watcher does the real swap
    /// off the bar's position; this is only a backstop for when the position
    /// can't be read, so the chrome can never get stuck hidden.
    func parkBy(_ duration: TimeInterval) {
        deadline?.cancel()
        deadline = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.05) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // The keyboard can be back up by the time this fires — finishing an
            // attempt dismisses its sheet and hands focus straight back to the
            // note — and parking then would hide the bar the user is looking at.
            // A live keyboard is the one thing that keeps the accessory in a
            // window, so that's the test.
            if self?.keyboardBar?.window != nil {
                self?.log("park deadline skipped: keyboard up")
                return
            }
            self?.log("park via deadline")
            self?.park()
        }
    }

    /// Leaving the screen: whatever state the swap was in, the bar chrome is
    /// shared navigation furniture and must come back.
    func restore() {
        stopWatching()
        deadline?.cancel()
        keyboardBar?.isHidden = false
        chrome?.isHidden = false
    }

    private func park() {
        stopWatching()
        deadline?.cancel()
        armed = false
        keyboardBar?.isHidden = true
        chrome?.isHidden = false
    }

    private func startWatching() {
        guard watcher == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        watcher = link
    }

    private func stopWatching() {
        watcher?.invalidate()
        watcher = nil
    }

    @objc private func tick() {
        guard let bar = keyboardBar, let window = bar.window,
              let barTop = Self.liveScreenTop(of: bar)
        else { return }
        // Where the clone's top sits when its capsule lines up with the parked
        // one, measured off the live system bar: capsule bottom 28pt above the
        // screen bottom + 48pt capsule + the clone's own 8pt top padding. The
        // chrome view can't anchor this — it reports a full-window frame.
        let arrivalTop = window.bounds.height - 76 - 8
        tickCount += 1
        if tickCount % 10 == 0 {
            let chromeTop = (watchedChrome ?? chrome).map { $0.convert($0.bounds, to: nil).minY }
            log("tick bar=\(barTop) arrival=\(arrivalTop) chrome=\(String(describing: chromeTop)) armed=\(armed)")
        }
        // Swap `lead` points before alignment — but only descending: crossing
        // the line on the way down, having first been above it.
        if barTop < arrivalTop - Self.lead {
            armed = true
        } else if armed {
            log("park via position: bar=\(barTop) arrival=\(arrivalTop)")
            park()
        }
    }

    /// Where `view` is drawn *right now*. Model frames jump to the animation's
    /// end value the moment it starts, so the mid-slide position only exists in
    /// the presentation tree — and it's an ancestor the keyboard animates, not
    /// the accessory itself, so the offsets are summed up the whole layer chain.
    private static func liveScreenTop(of view: UIView) -> CGFloat? {
        var y: CGFloat = 0
        var node: CALayer? = view.layer
        while let layer = node {
            let live = layer.presentation() ?? layer
            y += live.frame.minY - live.bounds.minY
            node = layer.superlayer
        }
        return y
    }

    private var chrome: UIView? {
        anchor?.window.flatMap(Self.findFloatingBar(in:))
    }

    private static func findFloatingBar(in view: UIView) -> UIView? {
        if String(describing: type(of: view)) == "FloatingBarContainerView" { return view }
        for subview in view.subviews {
            if let found = findFloatingBar(in: subview) { return found }
        }
        return nil
    }
}

/// Invisible; its only job is giving `BarParkModel` a live window to search.
struct BarParkAnchor: UIViewRepresentable {
    let model: BarParkModel

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        model.anchor = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        model.anchor = view
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
    var onAddSection: () -> Void
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
                    Button(action: onAddSection) {
                        // A boxier glyph than the transport marks; a couple of points
                        // down reads optically matched beside the 27pt plus.
                        barGlyph("list.dash.header.rectangle", pointSize: 24)
                            .frame(width: 58, height: 48)
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
