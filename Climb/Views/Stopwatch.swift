import SwiftUI
import UIKit

/// The one size every bottom-bar glyph is drawn at, in both bars. The system's
/// own bar icons measure ~27pt (not the 17–20pt you'd guess) and that's what
/// these were originally matched to — plus 26.71, video/timer 26.96, section a
/// couple down for its wider mark. Deliberately smaller than the system's now,
/// and deliberately ONE number: the marks read as a set rather than each being
/// optically balanced against the others.
let barGlyphPointSize: CGFloat = 22

/// The size the navigation bar's own marks are drawn at. The bar will not take a
/// `.font` on a `systemImage` item — it re-applies its own metric on top — so the
/// corner's marks are handed over as finished rasters at this size instead, the same
/// trick `barGlyph` plays on the bottom bar.
let topBarGlyphPointSize: CGFloat = 15

func topBarGlyph(_ name: String) -> Image {
    Image(uiImage: topBarGlyphImage(name))
}

/// The raster behind it — what `UINavigationBar`'s back indicator needs, since that
/// one is set as an image rather than built as a button.
func topBarGlyphImage(_ name: String) -> UIImage {
    barGlyphImage(name, pointSize: topBarGlyphPointSize)
}

/// A glyph rendered through UIKit's symbol configuration, so the raster matches
/// the system bottom bar pixel for pixel — and so the real bar and the keyboard
/// clone draw from the identical raster, which is what keeps the swap seamless.
func barGlyph(_ name: String, pointSize: CGFloat = barGlyphPointSize) -> Image {
    Image(uiImage: barGlyphImage(name, pointSize: pointSize))
}

/// The raster behind `barGlyph`, before SwiftUI gets hold of it — the system bar
/// needs the `UIImage` itself so it can fade the mark into it (see `systemBarGlyph`).
func barGlyphImage(_ name: String, pointSize: CGFloat) -> UIImage {
    let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    let image = UIImage(systemName: name, withConfiguration: config) ?? UIImage()
    return image.withRenderingMode(.alwaysTemplate)
}

/// The width the system bottom bar gives one of its buttons: the mark itself plus
/// 13pt of the bar's own label padding a side. The clone's slots used to be hard
/// numbers (58, 54.6667, 64.6667) measured off the live bar — but measured when the
/// marks were still the system's ~27pt, and `barGlyphPointSize` has come down to 22
/// since, which took the real bar's slots down with it and left the clone's pill the
/// wider of the two. Derived from the raster, they move together.
///
/// Checked against the live bar's own layout at 22pt: it lays its three items out at
/// 57.0, 49.3333 and 57.6667, four points apart, for a 172pt capsule — which is this
/// number, this spacing, and the same 28pt bar margin, exactly.
func barSlotWidth(_ name: String) -> CGFloat {
    barGlyphImage(name, pointSize: barGlyphPointSize).size.width + 26
}

/// The system bottom bar does not draw a handed-in raster at its own size — it
/// blows it up to the bar's icon box. Measured off the live bar: one 22pt
/// raster came out 23.0pt tall as a toolbar item and 18.0pt tall in the
/// keyboard clone's plain HStack, a consistent ~1.28× across all three marks.
/// So the real bar is handed a pre-shrunk raster and both bars land on the same
/// rendered mark. Re-measure this if the marks ever drift apart again: screenshot
/// both bars and compare glyph heights in pixels ÷ 3.
private let systemBarGlyphScale: CGFloat = 18.0 / 23.0

/// `barGlyph` for the real system bottom bar, pre-shrunk by `systemBarGlyphScale`
/// so it renders at the same size the keyboard clone draws it.
///
/// `opacity` is drawn INTO the raster rather than layered on with the modifier,
/// for the same reason the size is: the bar re-renders a toolbar item's label its
/// own way, and an `.opacity` on the button — like a `.font` — never reaches the
/// mark. Only `.disabled` dimmed these, by an amount of the system's choosing that
/// left this bar darker than the keyboard clone. Baked in, both bars fade the same
/// glyph by the same 12% (a template image keeps nothing but its alpha, so a mark
/// drawn at 12% tints to a mark at 12%).
///
/// Which is also why the faded one skips the pre-shrink: redrawing the mark costs
/// it its symbol-ness, and the bar's blow-up is something it does to SYMBOLS. A
/// plain raster is drawn at the size it arrives — the size the keyboard clone draws
/// it at — so pre-shrinking a faded glyph would leave it the smaller of the two.
func systemBarGlyph(_ name: String, opacity: Double = 1) -> Image {
    let isFaded = opacity < 1
    let image = barGlyphImage(
        name,
        pointSize: isFaded ? barGlyphPointSize : barGlyphPointSize * systemBarGlyphScale
    )
    guard isFaded else { return Image(uiImage: image) }

    let format = UIGraphicsImageRendererFormat.preferred()
    format.scale = image.scale
    let faded = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
        image.draw(at: .zero, blendMode: .normal, alpha: opacity)
    }
    return Image(uiImage: faded.withRenderingMode(.alwaysTemplate))
}

/// The hybrid bottom bar's shared state. The leading pill is ordinary system
/// bottom-bar items on each page — which is what buys the native search-field
/// → pill morph on push — but the TIMER is global: one capsule (and its
/// duration panel) floating above the whole navigation stack, always there,
/// because the system toolbar could never render it right (content lagged its
/// capsule, glass lost its rim, it entered pushes late). The stopwatch living
/// here means a running rest countdown survives navigation. Each page's system
/// bar holds an invisible same-width slot open under the capsule and relays
/// its taps — the bar band swallows touches aimed at overlays.
@Observable
@MainActor
final class BottomBarModel {
    let stopwatch = StopwatchModel()
    /// False while the keyboard clone owns the bar (flipped by BarParkModel).
    var parkedVisible = true
    /// Mirrored from the session page so the timer panel can sit on the
    /// capsule in either bar position.
    var isEditing = false
    /// Mirrored from the session page's `TutorialGuide`: the capsule is rendered
    /// globally, above the navigation stack, so this is how the note being walked
    /// through tells it to sit dark. Cleared as that page leaves.
    var isRestLocked = false
    var keyboardHeight: CGFloat = 0
    /// The timer capsule's live width, measured off the global overlay so the
    /// pages' system bars can hold a same-sized slot open under it.
    var capsuleWidth: CGFloat = 48
    /// Distance from the screen's trailing edge to the capsule's trailing
    /// edge: the system bar's own side margin, per the live-bar measurements
    /// the keyboard clone was built from. A constant on purpose — deriving it
    /// from placeholder geometry meant chasing animating (and sometimes
    /// pre-layout) bar frames, which flung the capsule around.
    var capsuleTrailingInset: CGFloat = 28

    /// Physical-bottom inset up to the timer capsule's bottom edge: parked,
    /// the capsule bottom lands at 28 (the system bar's own metric); editing,
    /// it hangs off the reported keyboard frame.
    ///
    /// The accessory's own box says 56 (a 64pt bar whose capsule bottom sits 8
    /// above it), but the frame the keyboard reports runs a further capsule-height
    /// past the bar it carries, and anything hung off 56 floats 48pt high — which
    /// is exactly the gap the duration panel used to show here while the parked one
    /// sat flush. 84 is what the live keyboard actually needs — landed by eye
    /// between 104 (panel tucked under the capsule) and 80 (floating off it).
    var timerBottomInset: CGFloat {
        isEditing ? max(28, keyboardHeight - 84) : 28
    }
}

/// Countdown state behind the stopwatch item in the note's bottom bar.
@Observable
final class StopwatchModel {
    /// Countdown target; nil until a duration is picked from the menu.
    private(set) var duration: TimeInterval?
    private var startedAt: Date?

    /// Once started, the button shows the live countdown beside the icon.
    var hasStarted: Bool { duration != nil }

    /// The duration choices are showing: idle, the detached popup; running,
    /// the panel grown out from behind the countdown capsule.
    var isChoosing = false
    /// The running panel's rows' visibility, split from `isChoosing` because a
    /// close must yank the row content the instant it starts — watching the
    /// options ride the collapsing panel down read badly — while the rows
    /// themselves animate out of the layout to give the shrink its height.
    var showsOptions = false

    func openMenu() {
        showsOptions = true
        withAnimation(.smooth(duration: 0.35)) { isChoosing = true }
    }

    /// Every close path funnels here: capsule re-tap, outside tap, or picking
    /// a duration.
    func closeMenu() {
        showsOptions = false
        withAnimation(.smooth(duration: 0.35)) { isChoosing = false }
    }

    func toggleMenu() {
        isChoosing ? closeMenu() : openMenu()
    }

    /// Kick off a fresh countdown with the picked duration, less one second so a
    /// round-minute pick opens on X:59 rather than sitting on 10:00 for a beat —
    /// the countdown reads as already running. (It cost nothing in layout once the
    /// capsule went fixed-width; originally it was there to stop the drop from
    /// 10:00 to 9:59 shrinking the capsule mid-flight.) Picking while one is
    /// already running simply overrides it.
    ///
    /// `from` backdates the start: the rest countdown after an attempt runs from the
    /// moment the recording stopped, not the moment Finish was tapped. A backdated
    /// start is already mid-flight, so it keeps the full duration — the X:59 trim
    /// only applies to fresh menu picks.
    func start(_ duration: TimeInterval, from startDate: Date? = nil) {
        self.duration = startDate == nil ? duration - 1 : duration
        startedAt = startDate ?? Date()
    }

    func remaining(at date: Date) -> TimeInterval {
        let elapsed = startedAt.map { date.timeIntervalSince($0) } ?? 0
        return max(0, (duration ?? 0) - elapsed)
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
    /// Mirrors the chrome flips for SwiftUI content that must swap in step —
    /// the overlay-drawn timer capsule hides and shows exactly when the parked
    /// chrome does. Called with `true` when the parked bar is showing.
    var onParkedVisibilityChange: ((Bool) -> Void)?

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
#if DEBUG
    // Flip to true to write Documents/barpark.log while chasing a timer bug.
    private static let debugLogging = false
    #else
    // Release — TestFlight and the App Store — can never carry a development switch,
    // whatever the line above happens to say when a build is cut.
    private static let debugLogging = false
    #endif
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
        onParkedVisibilityChange?(false)
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
        onParkedVisibilityChange?(true)
    }

    private func park() {
        stopWatching()
        deadline?.cancel()
        armed = false
        keyboardBar?.isHidden = true
        chrome?.isHidden = false
        onParkedVisibilityChange?(true)
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

/// The stopwatch's face in BOTH states — timer glyph beside a label that reads
/// "Rest" until a duration is picked and the live countdown after. Deliberately
/// ONE layout holding ONE Text rather than a branch per state: swapping subtrees
/// gave the new one its natural width in a single frame, so starting a countdown
/// snapped the capsule's width and read as a flash. And the label sits in a box
/// held open by an invisible twin of the widest string it can ever show, so the
/// capsule is ONE size forever: picking a duration doesn't grow it, ticking down
/// past a digit doesn't shrink it, and the search field the bar sizes against
/// this thing never moves. The glyph keeps its own 48pt slot for the same reason.
struct StopwatchFace: View {
    var stopwatch: StopwatchModel

    /// Monospaced so every digit is interchangeable — that plus the sizing twin
    /// is what makes one width fit every countdown.
    private let labelFont = Font.system(size: 19, weight: .semibold).monospacedDigit()

    var body: some View {
        HStack(spacing: 0) {
            // The same raster the idle disc shows, so starting a countdown
            // never resizes, restyles, or shifts the icon.
            barGlyph("timer")
                .frame(width: 48)
            ZStack {
                // The sizing twin: the longest label the capsule can ever show
                // (5 monospaced characters, wider than "Rest"). Invisible, but
                // it's what holds the box — and so the capsule — at one width.
                Text("10:00")
                    .font(labelFont)
                    .hidden()
                // Half-second ticks keep whole-second digits honest without
                // a per-frame timeline; idle it just re-renders the same word.
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text(stopwatch.hasStarted
                         ? stopwatch.remaining(at: context.date).clockString
                         : "Rest")
                        .font(labelFont)
                }
                // TimelineView greedily fills the width it's offered;
                // pin it to the text's own size so the twin sets the box.
                .fixedSize()
            }
            .padding(.trailing, 14)
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
    /// While the tutorial's walkthrough is running the bar holds back every button it
    /// has not asked for yet, so the one thing to press is the only thing there.
    var guide: TutorialGuide
    var onAddClimb: () -> Void
    var onAddSection: () -> Void
    var onStartAttempt: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    // One point size for all three (see `barGlyphPointSize`), and
                    // slots sized the way the system bar sizes its own (see
                    // `barSlotWidth`), so the pill keeps its footprint and the swap
                    // doesn't shift.
                    Button(action: onAddSection) {
                        barGlyph("textformat.size")
                            .frame(width: barSlotWidth("textformat.size"), height: 48)
                            .contentShape(.rect)
                    }
                    .opacity(guide.isSectionUnlocked ? 1 : TutorialGuide.lockedOpacity)
                    .allowsHitTesting(guide.isSectionUnlocked)
                    Button(action: onAddClimb) {
                        barGlyph("plus")
                            .frame(width: barSlotWidth("plus"), height: 48)
                            .contentShape(.rect)
                    }
                    .opacity(guide.isClimbUnlocked ? 1 : TutorialGuide.lockedOpacity)
                    .allowsHitTesting(guide.isClimbUnlocked)
                    Button(action: onStartAttempt) {
                        barGlyph("video.fill")
                            .frame(width: barSlotWidth("video.fill"), height: 48)
                            .contentShape(.rect)
                    }
                    .opacity(guide.isAttemptUnlocked ? 1 : TutorialGuide.lockedOpacity)
                    .allowsHitTesting(guide.isAttemptUnlocked)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .animation(.smooth(duration: 0.35), value: guide.step)

                Spacer()

                stopwatchCapsule
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private var stopwatchCapsule: some View {
        TimerCapsule(stopwatch: stopwatch, isLocked: !guide.isRestUnlocked)
    }
}

/// The timer button, whole — our glass, our content, one SwiftUI tree — used
/// verbatim by BOTH bars: the keyboard accessory drops it in directly, and the
/// parked bar hosts it as a toolbar item with the system's shared capsule
/// hidden (`sharedBackgroundVisibility(.hidden)`), because content animating
/// inside the system's own capsule lagged its chrome. "Rest" idle or the
/// running countdown, at ONE unchanging width either way (see `StopwatchFace`);
/// a tap toggles the duration panel, and picking a duration swaps the label
/// underneath without the capsule — or the search field sized against it —
/// moving at all.
struct TimerCapsule: View {
    var stopwatch: StopwatchModel
    /// Darkened out and deaf to taps while the tutorial's walkthrough is running —
    /// the same treatment the bar's other buttons get before their step arrives.
    var isLocked = false
    /// False where the capsule is a pure readout: the attempt sheet shows the same
    /// clock, but its duration panel is hosted by the page underneath, so a tap
    /// there would grow the panel behind the sheet.
    var isInteractive = true

    var body: some View {
        Button {
            stopwatch.toggleMenu()
        } label: {
            // "Rest" sits permanently where the countdown will once a
            // duration is picked, in a box sized for the countdown, so
            // neither opening the drawer nor starting a rest moves a thing.
            StopwatchFace(stopwatch: stopwatch)
                .frame(height: 48)
                .contentShape(.rect)
                // Inside the glass, exactly like the pill's glyphs: the bar's other
                // buttons dim their mark on top of a capsule that stays at full
                // strength, so dimming this capsule's glass along with its face read
                // as a different amount of dark.
                .opacity(isLocked ? TutorialGuide.lockedOpacity : 1)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .animation(.smooth(duration: 0.35), value: stopwatch.hasStarted)
        .allowsHitTesting(isInteractive && !isLocked)
        .animation(.smooth(duration: 0.35), value: isLocked)
    }
}

/// The timer capsule's duration panel, grown upward out of the real bar button's
/// top edge — idle (where the capsule first stretches leftward to say "Rest") and
/// running alike. The capsule in the bar keeps receiving every tap (open and
/// close both) while this panel is pure backdrop: its own glass card sitting
/// clear ABOVE the capsule rather than behind it, sized by an invisible twin of
/// the capsule's current face so the two line up in width. Opening therefore
/// reads as the choices rising out of the button, with nothing swapped, nothing
/// restyled, and nothing drawn over the button itself. Hosted full-screen and
/// permanently by the session view, so the grow always animates and the
/// tap-anywhere-outside catcher comes with it; hit-testing is off entirely
/// while closed.
struct TimerBubble: View {
    var stopwatch: StopwatchModel
    /// Distance from the physical screen bottom up to the capsule's bottom edge.
    var bottomInset: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { stopwatch.closeMenu() }
                .allowsHitTesting(stopwatch.isChoosing)
            panel
                // Both bars park the capsule 28pt from the trailing edge.
                .padding(.trailing, 28)
                // Above the capsule, not behind it: its bottom inset, plus the
                // 48pt capsule itself and 8pt of daylight between the two glasses
                // — enough to read as two pieces, close enough to read as one
                // control. Wherever the capsule is — parked, or riding the
                // keyboard — the panel follows it and clears it by the same gap.
                .padding(.bottom, bottomInset + 56)
        }
        .ignoresSafeArea()
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if stopwatch.isChoosing {
                ForEach([10, 5, 2], id: \.self) { minutes in
                    Button {
                        withAnimation(.smooth(duration: 0.35)) {
                            stopwatch.start(TimeInterval(minutes * 60))
                        }
                        stopwatch.closeMenu()
                    } label: {
                        Text("\(minutes):00")
                            .font(.system(size: 17, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Tighter than a list row: three of these is the
                            // whole panel, and at 44 apiece it stood taller
                            // than it had anything to say.
                            .frame(height: 36)
                            .contentShape(.rect)
                    }
                }
                // Yanked invisible the instant a close starts (`showsOptions`
                // flips with no animation), so the shrink animates over empty
                // glass instead of sliding the options down through it.
                .opacity(stopwatch.showsOptions ? 1 : 0)
                .transition(.identity)
            }
            // Invisible twin of the capsule's content, at the capsule's own
            // insets, flattened to nothing: width is all it is here for — the
            // panel matching the button it rises out of — now that the capsule's
            // own 48pt is no longer part of this card.
            StopwatchFace(stopwatch: stopwatch)
                .frame(height: 0)
                .hidden()
        }
        // The rows are flush to each other; the glass gets its breath at the two
        // ends, so the top and bottom choices aren't sitting in the corner curves.
        .padding(.vertical, 8)
        .fixedSize(horizontal: true, vertical: false)
        .buttonStyle(.plain)
        // The capsule's own radius, so the card above reads as the same family
        // of glass as the button below it.
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .opacity(stopwatch.isChoosing ? 1 : 0)
        .allowsHitTesting(stopwatch.isChoosing)
    }
}

