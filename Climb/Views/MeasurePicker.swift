import SwiftUI
import UIKit

/// The three quiz questions answered with a number rather than a tap: height, weight,
/// ape index.
///
/// Everything is recorded in metric whatever the screen is showing, so switching units
/// is a way of reading the answer and never a change to it.
enum BodyMeasure: String {
    case height, weight, apeIndex

    /// Where the slider starts on a question that has never been answered: the middle
    /// of the range for the two sizes, and level for ape index, which is the only one
    /// with a meaningful zero.
    var start: Double {
        switch self {
        case .height: 172
        case .weight: 70
        case .apeIndex: 0
        }
    }

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
        }
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
        }
    }

    /// Back off a recorded answer. Anything unreadable falls back to the start, so a
    /// question saved by an older build never lands the screen on nothing.
    func value(from answer: String) -> Double {
        let digits = answer.prefix { $0.isNumber || $0 == "-" || $0 == "+" }
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

/// The number, big, over a ruler that scrubs under the thumb. One question, the whole
/// screen: the answer is the only thing on it.
struct MeasurePicker: View {
    let measure: BodyMeasure
    /// Metric, whatever the ruler is showing.
    @Binding var value: Double
    @Binding var imperial: Bool

    private var scale: BodyMeasure.Scale { measure.scale(imperial: imperial) }

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
        // The whole question is the ruler, switch and readout included: one block sat
        // in the middle of the space under the question, and a thumb anywhere on it
        // scrubs.
        Ruler(value: shown, scale: scale) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(scale.text(shown.wrappedValue))
                    .font(.system(size: 72, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if !scale.unit.isEmpty {
                    Text(scale.unit)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.12), value: shown.wrappedValue)
        } header: {
            units
        }
        .frame(maxWidth: .infinity)
    }

    /// Which units the question is being read in. A preference rather than an answer —
    /// it follows you across all three screens and is never what gets recorded.
    private var units: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { isImperial in
                Button {
                    imperial = isImperial
                } label: {
                    Text(isImperial ? "ft / lb" : "cm / kg")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(imperial == isImperial ? .black : .white.opacity(0.5))
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(imperial == isImperial ? Color.white : .clear,
                                    in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.surface, in: .capsule)
        .animation(.easeInOut(duration: 0.15), value: imperial)
    }
}

/// A tape measure pulled past a fixed mark: the ticks move, the mark doesn't, and the
/// number over it is whatever is under the mark. Dragged right reads down, the way a
/// tape does when you pull it toward you — and let go of mid-throw it keeps running and
/// coasts to a stop, so a long way up the range is one flick rather than ten drags.
///
/// The tape takes the whole space it is given, readout and all, and every bit of that
/// is draggable — the ticks are where the answer is read, not the only place it can be
/// changed.
/// How long the coast lasts, near enough: speed falls off by `e` every this many
/// seconds, and the throw is over once it drops under half a unit a second. Out here
/// because a generic view can't hold a stored static.
private let tapeDecay: Double = 0.42

private struct Ruler<Readout: View, Header: View>: View {
    @Binding var value: Double
    let scale: BodyMeasure.Scale
    /// Drawn above the ticks, and dragged on just the same.
    @ViewBuilder var readout: Readout
    /// Drawn at the top of the space, up near the question: which units the answer is
    /// being read in is a setting for the screen, not part of the answer, so it sits
    /// with the question rather than in among the tape.
    @ViewBuilder var header: Header

    /// Where the tape actually is, which is not where the answer is: this runs
    /// continuously so the ticks slide, while `value` only ever holds whole units. The
    /// two are the same number to within half a step.
    @State private var position: Double = 0
    /// Where the drag started, so the whole gesture is measured from one place instead
    /// of accumulating rounding a frame at a time.
    @State private var anchor: Double?
    /// The coast, held onto so the next touch can stop it dead.
    @State private var fling: Task<Void, Never>?
    @State private var ticker = UISelectionFeedbackGenerator()

    var body: some View {
        VStack(spacing: 0) {
            // Twice as much room left under the block as over it, so it reads as
            // sitting high on the screen rather than adrift in the middle of it.
            // Sat at the top of the space rather than floating in it: switch, then
            // answer, then tape, each a fixed gap under the last, and whatever room is
            // left over goes below.
            header
            readout.padding(.top, 40)
            tape.padding(.top, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if anchor == nil {
                        // A finger down on a moving tape stops it, the way it would on
                        // a real one. Nothing is thrown twice.
                        fling?.cancel()
                        fling = nil
                        anchor = position
                    }
                    move(to: (anchor ?? position) - Double(drag.translation.width / scale.step))
                }
                .onEnded { drag in
                    anchor = nil
                    // What the touch would have carried on to, had it not been let go
                    // of — the system's own read of the throw, in units rather than
                    // points. Anything under a couple of units is a nudge, not a flick.
                    let thrown = -Double((drag.predictedEndTranslation.width
                                          - drag.translation.width) / scale.step)
                    guard abs(thrown) > 1 else { return settle() }
                    coast(from: thrown / tapeDecay)
                }
        )
        .onAppear {
            position = value
            ticker.prepare()
        }
        // The unit switch moves the answer under the tape rather than the other way
        // round, so the tape is put where the answer now is.
        .onChange(of: value) {
            guard abs(value - position) > 0.51 else { return }
            position = value
        }
        .onDisappear { fling?.cancel() }
    }

    private var tape: some View {
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

    /// Puts the tape somewhere, within its ends, and reports whatever whole unit has
    /// come under the mark — with a tick under the finger for each one crossed.
    private func move(to target: Double) {
        position = min(max(target, scale.range.lowerBound), scale.range.upperBound)
        let whole = position.rounded()
        guard whole != value else { return }
        value = whole
        // One tick per unit crossed: the ruler is felt as much as read, and a step is
        // a step whatever the units are.
        ticker.selectionChanged()
        ticker.prepare()
    }

    /// The throw: speed falling away by a fixed fraction every frame until it is not
    /// worth drawing any more, then the tape parked on the unit it stopped nearest.
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
                if position <= scale.range.lowerBound || position >= scale.range.upperBound {
                    break
                }
                speed *= exp(-dt / tapeDecay)
            }
            settle()
        }
    }

    /// The tape resting on a whole unit rather than between two, however it got there.
    private func settle() {
        withAnimation(.easeOut(duration: 0.18)) {
            position = min(max(position.rounded(), scale.range.lowerBound),
                           scale.range.upperBound)
        }
    }
}
