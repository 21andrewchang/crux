import SwiftUI
import UIKit

/// The quiz questions answered with a number rather than a tap: the three body
/// measurements, the two pull-up numbers the profile is actually built out of, and the
/// two grades — the one you're on and the one you're after.
///
/// Everything is recorded in metric whatever the screen is showing, which is why the
/// metric scales are still here with nothing calling them: reading the answer in feet
/// and pounds is a decision about the screen, and the recorded answer never moved.
enum BodyMeasure: String {
    case height, weight, apeIndex, pullUps, pullUpMax, grade, goalGrade

    /// Where the slider starts on a question that has never been answered: the middle
    /// of the range for the two sizes, and level for ape index, which is the only one
    /// with a meaningful zero.
    var start: Double {
        switch self {
        case .height: 172
        case .weight: 70
        case .apeIndex: 0
        // Both start at the honest end rather than in the middle of the range: a tape
        // parked at eight reps is the app guessing eight reps, and whoever taps
        // straight through has then been credited with a number they never gave. Zero
        // added weight is the true modal answer anyway.
        case .pullUps: 0
        case .pullUpMax: 0
        // The one number here with no honest zero: a tape parked at V0 is not modesty,
        // it is a wrong guess, the same as parking the reps tape at eight would be.
        // So this one does what the body sizes do and opens somewhere plausible, low
        // enough not to flatter anybody into agreeing with it.
        case .grade: 5
        // Only ever reached by a quiz that somehow skipped the grade question — the
        // goal tape normally opens on whatever that answer landed on.
        case .goalGrade: 5
        }
    }

    /// Whether this question is answered on the upright ladder rather than the flat
    /// tape. The grades are, and only the grades: a grade *is* a rung, and the one
    /// question in the quiz whose scale people already picture standing up is the one
    /// that shouldn't be lying on its side.
    var isLadder: Bool { self == .grade || self == .goalGrade }

    /// Every ruler reads in feet and pounds for now — the metric halves below are kept
    /// against the day the switch comes back, not because anything reaches them.
    var scale: Scale { scale(imperial: true) }

    /// What one step of the ruler is worth in metric, used to round the recorded answer
    /// to the same precision the screen was showing.
    func scale(imperial: Bool) -> Scale {
        switch self {
        case .height:
            imperial
                ? Scale(range: 47...87, majorEvery: 6, unit: "",
                        toMetric: { $0 * 2.54 }, fromMetric: { $0 / 2.54 },
                        text: { "\(Int($0) / 12)′ \(Int($0) % 12)″" })
                : Scale(range: 120...220, majorEvery: 10, unit: "cm",
                        toMetric: { $0 }, fromMetric: { $0 },
                        text: { "\(Int($0))" })
        case .weight:
            imperial
                ? Scale(range: 77...353, majorEvery: 10, unit: "lb",
                        toMetric: { $0 / 2.20462 }, fromMetric: { $0 * 2.20462 },
                        text: { "\(Int($0))" })
                : Scale(range: 35...160, majorEvery: 10, unit: "kg",
                        toMetric: { $0 }, fromMetric: { $0 },
                        text: { "\(Int($0))" })
        case .apeIndex:
            imperial
                ? Scale(range: -8...8, majorEvery: 1, unit: "in",
                        toMetric: { $0 * 2.54 }, fromMetric: { $0 / 2.54 },
                        text: Self.signed, step: 40, ticksPerUnit: 4)
                : Scale(range: -20...20, majorEvery: 5, unit: "cm",
                        toMetric: { $0 }, fromMetric: { $0 },
                        text: Self.signed)
        case .pullUps:
            // The same tape either way up, and at the same spacing as the two body
            // sizes, so the one screen with nothing to convert still reads as one of
            // the set.
            Scale(range: 0...40, majorEvery: 5, unit: "reps",
                  toMetric: { $0 }, fromMetric: { $0 },
                  text: { "\(Int($0))" })
        case .pullUpMax:
            // Added weight, so the sign is read out loud — this is what goes *on top*
            // of you, and a bare "20" beside a bodyweight question is ambiguous.
            imperial
                ? Scale(range: 0...220, majorEvery: 10, unit: "lb",
                        toMetric: { $0 / 2.20462 }, fromMetric: { $0 * 2.20462 },
                        text: Self.added)
                : Scale(range: 0...100, majorEvery: 10, unit: "kg",
                        toMetric: { $0 }, fromMetric: { $0 },
                        text: Self.added)
        case .grade, .goalGrade:
            // Nothing to convert and nothing to abbreviate: the V scale is already the
            // scale. Read on the ladder rather than the tape, so the tick fields go
            // unused and `step` is the gap between two rungs — which is also how far the
            // finger travels to cross one, since the ladder moves with the finger.
            Scale(range: 0...17, majorEvery: 1, unit: "",
                  toMetric: { $0 }, fromMetric: { $0 },
                  text: { "V\(Int($0))" }, step: 100)
        }
    }

    /// Nothing added reads as nothing, not as "+0" — the bottom of that scale is a
    /// plain bodyweight pull-up and should say so.
    private static func added(_ value: Double) -> String {
        let whole = Int(value)
        return whole > 0 ? "+\(whole)" : "0"
    }

    /// Ape index is the one number here that can be negative, and the sign is the whole
    /// point of it — a plus is never dropped just because it is the positive case.
    private static func signed(_ value: Double) -> String {
        let whole = Int(value)
        return whole > 0 ? "+\(whole)" : "\(whole)"
    }

    /// The answer as the quiz records it: always metric, always whole units, and the
    /// unit said out loud so the string can be read back without knowing which question
    /// it came from.
    func answer(metric value: Double) -> String {
        let whole = Int(value.rounded())
        switch self {
        case .height: return "\(whole) cm"
        case .weight: return "\(whole) kg"
        case .apeIndex: return whole > 0 ? "+\(whole) cm" : "\(whole) cm"
        case .pullUps: return "\(whole) reps"
        case .pullUpMax: return "+\(whole) kg"
        case .grade, .goalGrade: return "V\(whole)"
        }
    }

    /// Back off a recorded answer. The leading run of anything that isn't part of a
    /// number is stepped over first, so a grade's "V" is skipped without the sign on
    /// "+20 kg" being skipped with it. Anything unreadable falls back to the start, so a
    /// question saved by an older build never lands the screen on nothing.
    func value(from answer: String) -> Double {
        let number = answer.drop { !$0.isNumber && $0 != "-" && $0 != "+" }
        let digits = number.prefix { $0.isNumber || $0 == "-" || $0 == "+" }
        return Double(digits) ?? start
    }

    struct Scale {
        /// In display units — inches, pounds, centimetres — not metric.
        var range: ClosedRange<Double>
        /// How often the ruler grows a long tick with a number under it.
        var majorEvery: Double
        var unit: String
        var toMetric: (Double) -> Double
        var fromMetric: (Double) -> Double
        /// The big readout. Height in feet and inches is why this is a closure rather
        /// than a number formatter.
        var text: (Double) -> String
        /// Points per unit on the tape. The default is wide enough that a single step
        /// is a deliberate movement rather than something a resting thumb can do by
        /// accident; a scale with only a dozen units in it spreads out further so every
        /// one of them can be numbered.
        var step: CGFloat = 16
        /// How many ticks are drawn per unit. Above one, the extra ticks are decoration
        /// between the ones you can land on — a wide scale would otherwise be all long
        /// numbered marks and empty space between them.
        var ticksPerUnit: Double = 1
    }
}

/// The number, big, over the thing it is scrubbed on: a flat tape for the measurements,
/// an upright ladder for the grades. One question, the whole screen — the answer is the
/// only thing on it either way.
struct MeasurePicker: View {
    let measure: BodyMeasure
    /// Metric, whatever the ruler is showing.
    @Binding var value: Double

    private var scale: BodyMeasure.Scale { measure.scale }

    /// The ruler's own value, in display units, kept clamped to the range it is drawn
    /// over — switching units mid-question can otherwise land outside it.
    private var shown: Binding<Double> {
        Binding {
            min(max(scale.fromMetric(value).rounded(), scale.range.lowerBound),
                scale.range.upperBound)
        } set: {
            value = scale.toMetric($0)
        }
    }

    var body: some View {
        if measure.isLadder {
            Ladder(value: shown, scale: scale)
                .id(measure)
        } else {
            // The whole question is the ruler, readout included: one block sat under
            // the question, and a thumb anywhere on it scrubs.
            Ruler(value: shown, scale: scale) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(scale.text(shown.wrappedValue))
                        // The sharp face, the same one the ladder and the profile set
                        // a number in: the rounded one read as a toy everywhere it was
                        // used, and a measurement is not a toy.
                        .font(.system(size: 72, weight: .heavy))
                        .tracking(-1.5)
                        .monospacedDigit()
                    if !scale.unit.isEmpty {
                        Text(scale.unit)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.12), value: shown.wrappedValue)
            }
            .frame(maxWidth: .infinity)
            // One question, one ruler. Without this the next question inherits the last
            // one's scrubber — its marks parked where the old scale left them, which on
            // a narrower scale is off the end of the tape entirely, and any throw still
            // running coasting on against ends that no longer exist.
            .id(measure)
        }
    }
}

/// How long the coast lasts, near enough: speed falls off by `e` every this many
/// seconds, and the throw is over once it drops under half a unit a second. Out here
/// because a generic view can't hold a stored static.
private let tapeDecay: Double = 0.42

/// How fast the finger has to still be going at the end of a drag for the picker to
/// carry on without it, in units of predicted overshoot — and how far that drag has to
/// have covered, in units. Together they are what separates a throw from a placement.
/// Out here for the same reason `tapeDecay` is.
private let throwSpeed: Double = 3
private let throwDistance: Double = 4

/// The dragging itself, which is the same on both pickers however differently they are
/// drawn: a finger anywhere in the space moves the thing, a whole unit crossed is felt
/// as well as seen, and let go of mid-throw it keeps running and coasts to a stop — so
/// a long way up the range is one flick rather than ten drags.
///
/// The marks go with the finger, both ways round. On the tape that means pulling right
/// reads down, the way a tape does when you pull it toward you. On the ladder it means
/// pulling down reads *up*, because the hard end is at the top and bringing it to you is
/// how you get to it — which, as it happens, is also what the move is called.
private struct Scrub<Content: View>: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Points of travel under the finger per unit.
    let step: CGFloat
    /// Dragged up and down rather than side to side.
    let upright: Bool
    /// Drawn from where the thing actually is, which is not where the answer is: the
    /// number handed over here runs continuously so the marks slide, while `value` only
    /// ever holds whole units. The two are the same to within half a step.
    @ViewBuilder var content: (Double) -> Content

    @State private var position: Double = 0
    /// Where the drag started, so the whole gesture is measured from one place instead
    /// of accumulating rounding a frame at a time.
    @State private var anchor: Double?
    /// The coast, held onto so the next touch can stop it dead.
    @State private var fling: Task<Void, Never>?
    @State private var ticker = UISelectionFeedbackGenerator()

    var body: some View {
        content(position)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if anchor == nil {
                            // A finger down on a moving picker stops it, the way it
                            // would on a real one. Nothing is thrown twice.
                            fling?.cancel()
                            fling = nil
                            anchor = position
                        }
                        move(to: (anchor ?? position) + travel(drag.translation))
                    }
                    .onEnded { drag in
                        anchor = nil
                        // What the touch would have carried on to, had it not been let
                        // go of — the system's own read of the throw, in units rather
                        // than points.
                        let thrown = travel(drag.predictedEndTranslation) - travel(drag.translation)
                        // A throw has to be both: a long way covered and still moving at
                        // the end of it. Either one on its own is someone lining a number
                        // up — a short flick with the wrist, or a long drag that was
                        // slowed to a stop on the number they wanted — and both of those
                        // want the picker to stay exactly where it was let go of. Coming
                        // off a number you were holding and having it slide two more is
                        // the picker arguing with you.
                        guard abs(thrown) > throwSpeed,
                              abs(travel(drag.translation)) > throwDistance else {
                            return settle()
                        }
                        coast(from: thrown / tapeDecay)
                    }
            )
            .onAppear {
                position = value
                ticker.prepare()
            }
            // Anything that moves the answer from outside — a unit switch, a question
            // seeded off the one before it — moves the picker to where the answer now is
            // rather than the other way round.
            .onChange(of: value) {
                guard abs(value - position) > 0.51 else { return }
                // A throw belongs to the picker it was made on. If the answer is moved
                // from outside while one is still running, the throw is over — carrying
                // on would drag the marks back off wherever they have just been put.
                fling?.cancel()
                fling = nil
                position = value
            }
            .onDisappear { fling?.cancel() }
    }

    /// What a drag is worth, in units.
    private func travel(_ translation: CGSize) -> Double {
        upright ? Double(translation.height / step) : -Double(translation.width / step)
    }

    /// Puts the picker somewhere, within its ends, and reports whatever whole unit has
    /// come under the mark — with a tick under the finger for each one crossed.
    private func move(to target: Double) {
        position = min(max(target, range.lowerBound), range.upperBound)
        let whole = position.rounded()
        guard whole != value else { return }
        value = whole
        // One tick per unit crossed: the picker is felt as much as read, and a step is
        // a step whatever the units are.
        ticker.selectionChanged()
        ticker.prepare()
    }

    /// The throw: speed falling away by a fixed fraction every frame until it is not
    /// worth drawing any more, then the picker parked on the unit it stopped nearest.
    /// Running into either end is the end of it — a tape has no give at its stops.
    private func coast(from velocity: Double) {
        fling?.cancel()
        fling = Task {
            var speed = velocity
            var last = ContinuousClock.now
            while !Task.isCancelled, abs(speed) > 0.5 {
                try? await Task.sleep(for: .milliseconds(16))
                if Task.isCancelled { return }

                let now = ContinuousClock.now
                let step = last.duration(to: now)
                let dt = Double(step.components.seconds)
                    + Double(step.components.attoseconds) / 1e18
                last = now

                move(to: position + speed * dt)
                if position <= range.lowerBound || position >= range.upperBound { break }
                speed *= exp(-dt / tapeDecay)
            }
            settle()
        }
    }

    /// The picker resting on a whole unit rather than between two, however it got there.
    private func settle() {
        withAnimation(.easeOut(duration: 0.18)) {
            position = min(max(position.rounded(), range.lowerBound), range.upperBound)
        }
    }
}

/// A tape measure pulled past a fixed mark: the ticks move, the mark doesn't, and the
/// number over it is whatever is under the mark.
///
/// The tape takes the whole space it is given, readout and all, and every bit of that
/// is draggable — the ticks are where the answer is read, not the only place it can be
/// changed.
private struct Ruler<Readout: View>: View {
    @Binding var value: Double
    let scale: BodyMeasure.Scale
    /// Drawn above the ticks, and dragged on just the same.
    @ViewBuilder var readout: Readout

    var body: some View {
        Scrub(value: $value, range: scale.range, step: scale.step, upright: false) { position in
            // Sat at the top of the space rather than floating in it: the answer, then
            // the tape a fixed gap under it, and whatever room is left over goes below.
            // The gap the units switch used to sit in, kept as space: the number wants
            // air over it whether or not there is anything to put in it.
            VStack(spacing: 0) {
                readout.padding(.top, 56)
                tape(at: position).padding(.top, 28)
                Spacer()
            }
        }
    }

    private func tape(at position: Double) -> some View {
        Canvas { context, size in
            let middle = size.width / 2
            // Only the ticks that can land on screen are walked, so a range of three
            // hundred pounds costs the same as one of a hundred centimetres.
            let reach = Double(middle / scale.step) + 1
            // Walked on the tick grid rather than in whole units, so a scale carrying
            // quarter marks starts and ends on one of them.
            let grid = 1 / scale.ticksPerUnit
            let first = max(scale.range.lowerBound, ((position - reach) / grid).rounded() * grid)
            let last = min(scale.range.upperBound, ((position + reach) / grid).rounded() * grid)
            guard first <= last else { return }

            for tick in stride(from: first, through: last, by: grid) {
                let x = middle + CGFloat(tick - position) * scale.step
                let isMajor = abs(tick.truncatingRemainder(dividingBy: scale.majorEvery)) < 1e-6
                // Ticks shorten toward the edges, evenly about the centreline, so the
                // tape reads as wrapped round a drum turning past the mark rather than
                // as a flat strip sliding behind a window.
                let curve = cos(min(abs(x - middle) / middle, 1) * .pi / 2)
                let height: CGFloat = (isMajor ? 34 : 18) * (0.4 + 0.6 * curve)
                context.fill(
                    Path(roundedRect: CGRect(x: x - 1, y: 44 - height / 2,
                                             width: 2, height: height),
                         cornerRadius: 1),
                    with: .color(.white.opacity(isMajor ? 0.55 : 0.25)))

                if isMajor, abs(tick.rounded() - tick) < 1e-6 {
                    context.draw(
                        Text(scale.text(tick))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.4)),
                        at: CGPoint(x: x, y: 76))
                }
            }
        }
        .frame(height: 96)
        // The tape runs off both edges rather than stopping at them: what is far from
        // the mark fades instead of being cut.
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                     .init(color: .black, location: 0.14),
                                     .init(color: .black, location: 0.86),
                                     .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .overlay {
            Capsule()
                .fill(Color.white)
                .frame(width: 3, height: 48)
                .offset(y: -28)
        }
    }
}

/// The grades themselves, stood up: a column of them, evenly spaced, with everything
/// but the one you are on faded back.
///
/// A grade is a rung, and this is the one question in the quiz whose scale everybody
/// already pictures standing up — so it is asked on something shaped like the thing.
/// The hard end is at the top, which settles the direction: you pull the ladder down to
/// get up it, the same rule the flat tape is dragged by, and at the same rate — a rung
/// is as far under the finger as it is on the screen.
///
/// Every rung is the same size, and only how bright it is says which one is the answer.
/// Growing the middle one was the obvious thing and the wrong one: it made the column
/// bulge in the middle, put uneven gaps between numbers that are evenly spaced on the
/// scale, and left the thing looking like a fisheye rather than a ladder. Weight alone
/// is enough — nothing at full white but the answer.
///
/// There are no ticks, and no line across the middle — a rule through a column of
/// numbers cuts the answer in half. What marks the answer instead is a single arrow out
/// on the left, level with it and pointing in: it sits still while the ladder runs past,
/// which is the whole job, and it puts the mark beside the number rather than through
/// it.
private struct Ladder: View {
    @Binding var value: Double
    let scale: BodyMeasure.Scale

    /// How many rungs sit either side of the answer before the fade at the ends has
    /// finished with them.
    private static let shown = 3

    /// How hard the fade bites per rung away from the middle. Steep, because it does
    /// most of the work of separating the answer from its neighbours.
    private static let falloff = 2.6

    /// How much smaller everything that isn't the answer is drawn. Small, and it stops
    /// at one rung out rather than carrying on down the column — the point is a nudge
    /// that says which one is live, not a taper. Letting it run was what made the thing
    /// bulge in the middle the first time.
    private static let shrink = 0.12

    /// How far the mark sits from the middle of the ladder. Fixed rather than tucked
    /// against the number, because the number changes width — "V17" is half a glyph
    /// wider than "V7" — and a mark that shuffled sideways every time the answer went
    /// into double figures would be the liveliest thing on the screen.
    private static let markInset: CGFloat = 116

    var body: some View {
        Scrub(value: $value, range: scale.range, step: scale.step, upright: true) { position in
            ZStack {
                ForEach(rungs(around: position), id: \.self) { rung in
                    let delta = Double(rung) - position
                    Text(scale.text(Double(rung)))
                        // The same face the profile sets a grade in, so a rung on this
                        // ladder and the grade that comes back out of it are one thing
                        // written twice rather than two.
                        .font(.system(size: 80, weight: .heavy))
                        .tracking(-1.5)
                        .monospacedDigit()
                        // Each rung in its rank's metal, so scrubbing the ladder runs
                        // bronze to purple and the grade you stop on is already set the
                        // way the profile will hand it back to you.
                        .foregroundStyle(.metal(GradeTier.of(Double(rung)).color))
                        .scaleEffect(1 - Self.shrink * min(abs(delta), 1))
                        .opacity(1 / (1 + Self.falloff * abs(delta)))
                        // Up the screen is up the ladder, so a rung harder than the
                        // answer sits above it.
                        .offset(y: -CGFloat(delta) * scale.step)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: CGFloat(Self.shown) * 2 * scale.step + 80)
            // The ends fade rather than stopping, so a rung on its way out goes out
            // instead of being cut off at an edge.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                         .init(color: .black, location: 0.22),
                                         .init(color: .black, location: 0.78),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            // Outside the fade rather than inside it: the ladder is what moves and what
            // dims, and the mark does neither.
            .overlay { pointer.offset(x: -Self.markInset) }
        }
    }

    /// The mark: level with the middle and just off the shoulder of the number,
    /// pointing at whatever has been brought to it.
    private var pointer: some View {
        Pointer()
            // Grey, not white: the answer is the brightest thing on the screen and the
            // mark shouldn't be competing with it — it only has to say where to look.
            .fill(Color.white.opacity(0.45))
            .frame(width: 12, height: 18)
            .allowsHitTesting(false)
    }

    /// A triangle lying on its side, nose to the right. Its own shape rather than a
    /// rotated symbol so the nose lands exactly on the middle of the ladder rather than
    /// on the middle of whatever box a symbol was drawn in.
    private struct Pointer: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }

    /// The rungs worth drawing: the ones near enough the middle to have any of
    /// themselves left, and never past the ends of the scale.
    private func rungs(around position: Double) -> [Int] {
        let low = max(Int(scale.range.lowerBound), Int((position - Double(Self.shown)).rounded()))
        let high = min(Int(scale.range.upperBound), Int((position + Double(Self.shown)).rounded()))
        return low <= high ? Array(low...high) : []
    }
}
