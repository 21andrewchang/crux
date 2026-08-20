import SwiftData
import SwiftUI
import UIKit

/// The payoff at the end of onboarding: the quiz's answers drawn as one shape.
///
/// Six pillars, because a shape you can read at a glance is the whole point — a chart
/// with nine spokes is a table wearing a costume. What each one is, and why these six:
///
/// - **Fingers** is its own pillar rather than part of strength because finger strength
///   is the single biggest predictor of what you climb, and it trains and injures
///   completely differently from everything else on here.
/// - **Strength** is slow force — max pull, lock-offs, compression, body tension.
/// - **Power** is fast force — dynos, coordination, catching. Every boulderer knows
///   someone strong who can't jump, and someone springy who can't lock anything off;
///   collapsing the two would draw them the same shape.
/// - **Endurance** is the bouldering kind: how many quality goes you get before the
///   wheels come off, not whether you can hang on for forty metres.
/// - **Technique** is footwork, positioning, efficiency.
/// - **Mind** carries tactics as well as nerve. They are genuinely different things —
///   tactics is knowledge, nerve is disposition — but tactics is the one nobody rates
///   honestly about themselves, and an axis everyone scores well on is a dead axis.
///
/// The rings are the grade ladder the quiz already asked in, so the shape is read in
/// grades rather than in points out of a hundred: how far a spoke reaches *is* what you
/// climb on that axis. A number out of 99 would have to be explained; V6–V8 doesn't.
///
/// **Your grade is the floor of the shape, not its average.** You climb at the level of
/// whatever is holding you back — so nothing on here can sit far below what you climb,
/// because if it did you wouldn't be climbing it. What sits *above* your grade is
/// headroom: strength you already have and aren't getting anything for yet.
///
/// This is the correction that matters most, and it took a wrong version of the screen
/// to see it. Averaging the six meant that measuring somebody's pull-ups as excellent
/// forced something else down to compensate — a climber with a big pull was told their
/// technique was three grades below what they climb, which is not a diagnosis, it's an
/// insult, and it isn't true. A big pull doesn't imply a matching hole somewhere. It
/// implies you could be climbing harder than you are.
///
/// So a measured spoke says what it measures, and everything unmeasured sits at your
/// grade — nudged by what you said you were good at, up more readily than down, because
/// the floor is the floor. The reading is in the overhang: a spoke well past the others
/// is capacity you haven't cashed in.
///
/// The rungs themselves go unlabelled. The grade a spoke reaches is already written at
/// the end of it, so numbering the rings as well would be the same scale printed twice —
/// and the second printing lands in the middle of the chart, where the shape is.
struct ProfileView: View {
    /// One spoke. `sources` are the quiz's own words for it — every attribute offered
    /// on the strengths and weaknesses screens has to land on exactly one pillar or the
    /// answer goes nowhere.
    struct Pillar {
        let name: String
        let sources: [String]
    }

    /// Clockwise from the top. Ordered so the three physical pillars take the right
    /// side and the skill and head ones take the left — which means a shape that leans
    /// right belongs to someone climbing on power, and one that leans left to someone
    /// climbing on craft. The lean is the first thing read, so it should mean something.
    static let pillars: [Pillar] = [
        Pillar(name: "Fingers", sources: ["Finger strength"]),
        Pillar(name: "Strength", sources: ["Body tension", "Flexibility"]),
        Pillar(name: "Power", sources: ["Power"]),
        Pillar(name: "Endurance", sources: ["Endurance", "Recovery"]),
        Pillar(name: "Technique", sources: ["Footwork", "Movement"]),
        Pillar(name: "Mind", sources: ["Mentality", "Route reading"]),
    ]

    /// The rings, innermost out. The quiz asks for a grade rather than a band, so this
    /// ladder is now the reading rather than the asking: a spoke's label is an estimate
    /// and a range is the honest shape for one, where the grade that went in was a fact
    /// and went in exact.
    static let bands = ["V0–V2", "V3–V5", "V6–V8", "V9–V11", "V12+"]

    /// How much of the gap between what you can pull once and what you can pull for
    /// reps counts as power. Load without reps behind it is a fast-force build; reps
    /// without load is the other one. Half, so that two spokes coming out of the same
    /// pair of numbers read differently rather than one being a louder copy of the other.
    private static let bias = 0.5

    /// A spoke never reaches the middle. A zero-length arm reads as a broken chart, and
    /// nobody's fingers are worth nothing.
    private static let floor = 0.7

    /// How far a measured spoke is allowed to sit from your grade, in rings.
    ///
    /// A pull-up number is real evidence and it is not *strong* evidence: plenty of V7
    /// climbers do twenty of them and plenty of V10 climbers do twelve. Left uncapped, a
    /// good set of numbers pushes two spokes to the rim, and because the six of them
    /// have to average out at your grade, everything else gets shoved into the middle —
    /// which is how somebody who climbs V7 ends up being told their technique is V0.
    /// Capping what one measurement is worth is what keeps the shape a reading of you
    /// rather than a reading of your pull-ups.
    private static let reach = 1.25

    /// Whether the card of answers is in the screen at all. Off, the chart and the two
    /// grades have it to themselves — the card, everything that builds it and its beat
    /// in the reveal are all still here, just not on.
    private static let showsInfo = false

    /// Whether Continue starts the whole run over from the first question rather than
    /// buying anything. On while onboarding is what is being worked on — walking the
    /// flow end to end is the only way to see it, and it shouldn't cost a relaunch.
    /// It puts back only where you are in the flow: whatever the last pass left in the
    /// practice note is still there at the start of the next.
#if DEBUG
    // Flip to true to make the wall's button replay the flow instead of buying.
    private static let restartsForDevelopment = false
    #else
    // Release — TestFlight and the App Store — can never carry a development switch,
    // whatever the line above happens to say when a build is cut.
    private static let restartsForDevelopment = false
    #endif

    /// Opened from the app rather than walked into at the end of the first run: the
    /// same chart and the same numbers, settled rather than played, with nothing asked
    /// for underneath. Somebody coming back to read their profile has already sat
    /// through the animation once, and once is what it is worth.
    var isReview = false

    /// Which side of the card is being drawn. The profile reads as one object with two
    /// faces — the shape and what it comes to on the front, the answers it was built
    /// from on the back — so the two are the same view rather than two screens.
    enum Face { case front, back }
    var face: Face = .front

    var onFinish: () -> Void = {}

    @State private var onboarding = Onboarding.shared
    @Query private var allSessions: [ClimbSession]
    @Query private var allClimbs: [Climb]
    @Query private var allAttempts: [Attempt]
    /// Whether the empty chart — rings, spokes, and the green core that is about to be
    /// pushed out into a shape — has come up yet.
    @State private var chartIn = false
    /// How far out each corner has been pushed, as a fraction of the radius. One entry
    /// per pillar, animated one at a time.
    @State private var reaches: [Double] = []
    /// Which corners have landed. Drives the dot and the label at each one, so a
    /// pillar's name arrives with its corner rather than on a timer of its own.
    @State private var landed: [Bool] = Array(repeating: false, count: pillars.count)
    /// Whether the whole thing has played out — the dream included. Until it has, a
    /// tap does nothing: there is no skipping to the end of a screen this short.
    @State private var finished = false
    /// How far through the screen's three placings it is: 0 the chart on its own in
    /// the middle, 1 the chart and the grades centred as a block, 2 the block at the
    /// top with the chart a size down and the price under it.
    @State private var stage = 0
    /// How tall the grades are, measured rather than guessed, so centring the block
    /// they are half of is exact at whatever size the numbers came out.
    @State private var gradesHeight: CGFloat = 140
    /// The height of the column, so the chart's starting place can be the middle of the
    /// screen measured rather than guessed at.
    @State private var columnHeight: CGFloat = 800
    /// Whether what the chart was built from has arrived. It comes up between the last
    /// corner and the grade: the evidence, and then what it comes to.
    @State private var infoIn = false
    /// Whether the grade under the chart has arrived. It waits for the whole shape:
    /// six corners are six things being said, and the grade is what they come to.
    @State private var gradeIn = false
    /// Whether the dream shape is on the chart at all. It comes up as a dot in the
    /// middle before it opens, and this is what puts the dot there.
    @State private var dreamIn = false
    /// Whether the goal grade itself has arrived — a beat behind the room being made
    /// for it, which is what the move to the left is.
    @State private var goalIn = false
    /// Which of the two beats is up: the profile on its own, or the profile against the
    /// one your goal grade would need. Continue is what moves between them.
    @State private var slide = 0
    /// How far the grade already on screen is thrown off its place by the shudder, in
    /// points. Nothing at rest; a few points either side of nothing while the screen is
    /// working up to what it is about to say.
    @State private var shake: CGFloat = 0
    /// The dream shape's corners. Empty until the second beat, when it opens out of the
    /// middle of the same chart — even all the way round, because a goal grade is not a
    /// shape you have to guess at: it is what all six of these have to reach.
    @State private var dreamReaches: [Double] = []
    /// Which plan the footer has selected. It lives here rather than in the footer so
    /// the screen owns the choice, the same way the paywall does.
    @State private var plan: Store.Plan = .yearly

    private var answers: [String: String] { onboarding.answers }

    /// The line over the plans. It says nothing about the trial, because the row under
    /// it already does and the button under that says it a third time; what it is for
    /// is the one thing neither of them says — that what is being bought is the tool,
    /// and not the grade the chart just gave you.
    private static let headline = "Unlock Crux to start improving"

    /// Where the chart-and-grades block sits, as a drop from the top of the column.
    ///
    /// Centred on the chart alone while the chart is all there is to look at, then
    /// centred on the pair once the grade is under it — which is the small rise the
    /// grade's arrival is paid for with — and flush to the top once the price is due.
    private var blockOffset: CGFloat {
        switch stage {
        case 0: max(0, (columnHeight - Self.chartHeight) / 2 - 8)
        case 1: max(0, (columnHeight - Self.chartHeight - gradesHeight) / 2 - 8)
        default: 0
        }
    }

    var body: some View {
        // The screen builds itself: the chart alone in the middle, then up to the top,
        // then what it was read out of under it, and the grade last of all at the
        // bottom — which is the order the three of them were arrived at.
        if isReview { reviewColumn } else { salesColumn }
    }

    /// The card's front: the shape at full size with what it comes to under it.
    ///
    /// Nothing is shared with the wall's copy of this screen but the drawing. There the
    /// chart is a thing being revealed and then sold against; here it is a thing being
    /// looked up, so it arrives whole and stays put.
    private var reviewColumn: some View {
        Group {
            switch face {
            case .front: reviewFront
            case .back: reviewBack
            }
        }
        .foregroundStyle(Color.paper)
        .task { await settle() }
    }

    private var reviewFront: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The grade first and hard into the corner, the way a card carries its
            // value: it is the one thing on here read at a glance and from across a
            // room, and centring it under the chart made it a caption on the drawing
            // rather than the headline the drawing explains.
            grades
                .frame(maxWidth: .infinity, alignment: .leading)

            chart
                .frame(height: Self.chartHeight)

            Spacer(minLength: 0)
        }
        // Up alongside the disc rather than below it: the grade is short enough to sit
        // level with the turn button instead of starting a row of its own under it.
        .padding(.top, -30)
    }

    private var reviewBack: some View {
        VStack(spacing: 14) {
            info
            tally
        }
        .padding(.vertical, 6)
    }

    /// What the account has in it, as four numbers.
    ///
    /// On the back with the quiz's answers rather than on the front with the shape,
    /// because these are the only things on the card that move: the shape is what you
    /// said you were when you arrived, and this is what you have done since. Two rows
    /// of two, so the pairs read across — what you logged, and what you filmed.
    private var tally: some View {
        // The seeded goal note is a page of the app rather than a session, and a
        // deleted attempt is not one either.
        let sessions = allSessions.filter { $0.id != Goals.id && $0.id != Tutorial.id }.count
        let live = allAttempts.filter { $0.deletedAt == nil }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11))
                Text("Logged")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Color.paper.opacity(0.4))

            HStack(alignment: .top, spacing: 16) {
                column([Stat(label: "Sessions", value: "\(sessions)"),
                        Stat(label: "Climbs", value: "\(allClimbs.count)")])
                column([Stat(label: "Clips", value: "\(live.filter { $0.videoFilename != nil }.count)"),
                        Stat(label: "Attempts", value: "\(live.count)")])
            }
        }
        // No panel of its own. On the card these sit on glass, and a grey box inside
        // a glass one is a second card where there is only one thing — the glass is
        // already the edge, so drawing another inside it just makes the page busier.
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var salesColumn: some View {
        VStack(spacing: 0) {
            // The chart and the grades under it travel together. On the first beat the
            // chart alone is centred, with the grades' room already held below it and
            // empty; when the grade arrives the pair centres as one, which is a small
            // rise rather than a jump; and only when the price is due does the block go
            // to the top and the chart take a size down with it.
            VStack(spacing: 0) {
                chart
                    .padding(.top, 8)
                    // The labels come down with the rings because the whole chart is
                    // scaled rather than redrawn smaller.
                    .scaleEffect(stage >= 2 ? Self.movedScale : 1, anchor: .top)
                    // What the scaling leaves behind at the bottom, given back to the
                    // column: a view scaled down still lays out at its full height.
                    .padding(.bottom, stage >= 2 ? -Self.chartHeight * (1 - Self.movedScale) : 0)

                if Self.showsInfo {
                    info
                        .padding(.top, 24)
                        .opacity(infoIn ? 1 : 0)
                        .offset(y: infoIn ? 0 : 12)
                }

                grades
                    // Tucked up under the chart rather than set below it: the labels
                    // around the rings leave a margin of their own, and the gap read as
                    // a gap on top of that.
                    .padding(.top, -12)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        gradesHeight = $0
                    }
            }
            .offset(y: blockOffset)

            Spacer(minLength: 8)

            // The one sentence on the screen, and it is about the tool rather than the
            // grade. Two enormous numbers sat straight on top of a price implies the
            // price is what moves you from one to the other; naming what is actually
            // being bought — the record, and getting there quicker for having kept it —
            // is both the honest framing and the one that sells.
            Text(Self.headline)
                .font(.system(size: 21, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
                .opacity(finished ? 1 : 0)
                .animation(.easeInOut(duration: 0.45), value: finished)

            // The asking, on the same screen as the thing being asked for. It arrives
            // last, under a gap that has just been drawn twice over — once as a shape
            // and once as two numbers — so the price is read against that rather than
            // against a page break. Nothing is written over it: a line of copy between
            // the grades and the plans was saying what the chart had just said better.
            PurchaseFooter(plan: $plan, onPurchase: onFinish,
                           replay: Self.restartsForDevelopment ? onboarding.reset : nil)
                .opacity(finished ? 1 : 0)
                .offset(y: finished ? 0 : 16)
                .animation(.spring(response: 0.6, dampingFraction: 0.88), value: finished)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { columnHeight = $0 }
        // Nothing to tap through: the screen plays itself, and what is under it when it
        // has finished playing is the one decision on it.
        .foregroundStyle(Color.paper)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task(run)
    }

    // MARK: - The chart

    /// One chart, both shapes. The dream doesn't get a chart of its own — it opens out
    /// of the middle of this one, under the profile and past it, so the gap between the
    /// two is a distance on a single set of rings rather than something to be worked out
    /// by looking from one picture to another.
    private var chart: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            // The labels live outside the rings, so the rings only get what is left of
            // the box after the widest of them has been allowed for on both sides.
            let radius = side / 2 - Self.labelRoom
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                rings(radius: radius)
                // Behind the profile, because it is the bigger of the two and encloses
                // it — but drawn at full strength, because it is the one the screen is
                // about. Its outline carries a small glow that rises and falls on a slow
                // count: enough that the eye keeps coming back to it, not so much that
                // the chart is a light show.
                TimelineView(.animation) { timeline in
                    shape(radius: radius, reaches: dreamReaches, tint: dreamTint,
                          glow: Self.pulse(at: timeline.date))
                }
                .opacity(dreamIn ? 1 : 0)
                // And the profile taken back the moment the goal is up. On its own it is
                // the only shape on the chart and is drawn like it; next to what it is
                // being read against it is the smaller, dimmer of the two, which is the
                // whole point being made.
                shape(radius: radius, reaches: reaches, tint: tint)
                    .opacity(dreamIn ? 0.45 : 1)
                labels(radius: radius, center: center)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: Self.chartHeight)
    }

    /// How tall the chart's box is — one size for the whole screen, whatever else is on
    /// it. It was shrinking to make room for the plans, and a chart that resizes under
    /// you reads as the screen giving way rather than as room being made: better to
    /// draw it at the size it will end up at and leave it there.
    private static let chartHeight: CGFloat = 320

    /// How much of itself the chart keeps once it is up at the top. One, as it turns
    /// out: with the price sat on the bottom of the screen rather than floating above
    /// its own empty strip, the room was already there — and a chart that shrinks to
    /// make room it didn't need is a chart that flinches. Kept as a number rather than
    /// taken out, because it is the first thing to reach for on a shorter phone.
    private static let movedScale: CGFloat = 1

    /// What the shapes come to, in grades. On its own the number is the size it is
    /// because it is the only writing on the screen; once the dream is up it steps down
    /// to make room for the one it is being read against.
    private var grades: some View {
        HStack(spacing: 16) {
            // Full strength when the profile is being read rather than sold. Dimming
            // is only ever relative — it is what makes this number recede next to the
            // goal grade arriving beside it — and on a sheet where no goal ever comes,
            // a number mixed halfway to black is just a grade drawn wrong. The wall's
            // copy of this screen is untouched: it still has something to recede for.
            grade(grade(for: "grade"), tint: tint, dim: !isReview)
                // Last of all, and on the same spring the corners land on, so it reads
                // as the seventh beat of the same reveal rather than as a caption.
                .scaleEffect(gradeIn ? 1 : 0.6)
                .opacity(gradeIn ? 1 : 0)
                // And then it starts to go. The shudder is on this number alone —
                // nothing else on the screen moves — so what is coming reads as
                // something happening to it rather than to the phone.
                .offset(x: shake)
            // Taken into the row before it can be seen: the space it needs is what
            // carries the grade already there over to the left, and only once that has
            // happened does the goal itself turn up in it.
            if slide == 1 {
                // Between the two, so the pair reads as a distance rather than as two
                // facts stood next to each other. Faint, and much smaller than what it
                // joins: it is punctuation, not a third thing on the line.
                //
                // Drawn rather than set. Both the SF Symbol and the font's own arrow
                // glyph round their ends and their point, and that softness next to two
                // heavy, flat-cut numbers reads as a second typeface on the line.
                SharpArrow()
                    .stroke(Color.paper.opacity(0.3),
                            style: StrokeStyle(lineWidth: 3, lineCap: .butt,
                                               lineJoin: .miter, miterLimit: 12))
                    .frame(width: 30, height: 18)
                    .opacity(goalIn ? 1 : 0)
                    // Put into the row with no transition of its own: the fade is the
                    // one above, and SwiftUI's default insert fading underneath it was
                    // the hitch on the way in.
                    .transition(.identity)
                grade(grade(for: "goalGrade"), tint: dreamTint, shining: true)
                    .scaleEffect(goalIn ? 1 : 0.7)
                    .opacity(goalIn ? 1 : 0)
                    .transition(.identity)
            }
        }
        // The row is as tall as the taller number from the start, whether or not that
        // number is in it yet. Without it the row grew when the goal arrived and the
        // grade already there was re-centred in the new height — so what should have
        // been a step to the left was a step down and to the left.
        .frame(height: gradeSize * 1.24)
    }

    /// Heavy, tight, and the system face rather than the rounded one — a grade is a
    /// hard number and the soft face was reading as a toy. The negative tracking is what
    /// keeps two characters at this size looking set rather than spaced.
    ///
    /// The two of them are not drawn the same way, because they are not the same kind of
    /// fact. What you climb now is set smaller and duller — it is the thing being left
    /// behind, and it should look like it. What you're after is the size it is and lit
    /// besides: a band of light crosses it, over and over.
    private func grade(_ text: String, tint: Color,
                       dim: Bool = false, shining: Bool = false) -> some View {
        let label = Text(text)
            .font(.system(size: dim ? gradeSize * 0.7 : gradeSize, weight: .heavy))
            .tracking(-2)
        return label
            // Shaded rather than plated: the colour itself at the top, a little of it
            // taken away by the bottom. The chrome ramp that was here first — highlight,
            // shadow, second highlight — read as a sticker, which is what happens when
            // type at this size pretends to be metal.
            .foregroundStyle(.metal(dim ? tint.mix(with: .black, by: 0.45) : tint))
            .overlay { if shining { sheen(label) } }
            // One soft shadow under it, black rather than coloured, so the number sits
            // above the screen instead of glowing on it. Lighter on the card: that
            // shadow was set to carry the number off a black screen, and the same
            // weight on a grey panel a few inches across reads as smudge under it
            // rather than as height above it.
            .shadow(color: .black.opacity(isReview ? 0.32 : 0.6),
                    radius: isReview ? 9 : 16,
                    y: isReview ? 4 : 8)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// The sweep across the goal grade: a slanted band of light that crosses it and
    /// comes round again. Masked to the glyphs, so what shines is the number rather than
    /// a strip of light passing over the screen behind it.
    ///
    /// Slanted, faint, and soft at both edges — the three things that separate a sheen
    /// from a highlighter. A band with hard sides at full strength doesn't read as light
    /// on a surface, it reads as a white rectangle sliding past.
    ///
    /// Driven off the clock rather than off a repeating animation started on appear:
    /// this number arrives in the middle of two other animations, and a `repeatForever`
    /// kicked off inside that was landing on its end value with nothing in between —
    /// which is a sheen that never crosses.
    private func sheen(_ label: Text) -> some View {
        TimelineView(.animation) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let travel = Self.sheenTravel(at: seconds)
            GeometryReader { geometry in
                let size = geometry.size
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: Color.paper.opacity(0.03), location: 0.3),
                                       .init(color: Color.paper.opacity(0.22), location: 0.5),
                                       .init(color: Color.paper.opacity(0.03), location: 0.7),
                                       .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    // Wider than the number, not narrower: a band you can see the ends
                    // of is a bar sliding past, however soft its edges are. At close to
                    // twice the width there are no ends to see — what crosses the glyphs
                    // is the bright middle of the gradient and nothing else. Taller than
                    // the number too, and turned off the vertical, so the light meets it
                    // at an angle and still covers it at both ends of the turn.
                    .frame(width: size.width * 1.9, height: size.height * 2.6)
                    .rotationEffect(.degrees(20))
                    .offset(x: travel * size.width)
                    .frame(width: size.width, height: size.height)
                    .blendMode(.plusLighter)
            }
        }
        .mask(label)
        .allowsHitTesting(false)
    }

    /// The breath the goal shape's glow is on, as a number between nothing and full.
    /// A cosine rather than a sawtooth, so it swells and settles instead of snapping
    /// back to dark at the end of every count.
    private static func pulse(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: pulseCycle) / pulseCycle
        return 0.5 - cos(phase * 2 * .pi) / 2
    }

    /// How long that breath takes. Slow — a pulse you can count is a heartbeat, and a
    /// pulse you can't is a flicker.
    private static let pulseCycle: Double = 2.2

    /// Where the sheen is, as a share of the number's width either side of it.
    ///
    /// Not a constant speed. A stripe crossing at one rate is a stripe; light glancing
    /// off something is slowest at the edges of the turn and quickest through the middle
    /// of it, which is what the quintic ease here does — it is at its fastest exactly
    /// where it is over the glyphs. And the sweep is only the first part of the count:
    /// the rest of it is spent parked off the far side, so what you see is a thing that
    /// goes past rather than a thing that is always going past.
    private static func sheenTravel(at seconds: Double) -> Double {
        let phase = seconds.truncatingRemainder(dividingBy: sheenCycle) / sheenCycle
        guard phase < sheenCrossing else { return sheenReach }
        let step = phase / sheenCrossing
        let eased = step * step * step * (step * (step * 6 - 15) + 10)
        return (eased * 2 - 1) * sheenReach
    }

    /// How long the whole count takes, sweep and wait together.
    private static let sheenCycle: Double = 1.6

    /// How much of that count the sweep itself gets. The rest is the wait.
    private static let sheenCrossing: Double = 0.58

    /// How far past the number each end of the sweep sits, as a share of its width —
    /// far enough that the bright middle of the band is clear of the glyphs before it
    /// stops, which takes more room now the band itself is wider than they are.
    private static let sheenReach: Double = 1.5

    /// One size for both grades, picked off the longer of the two and picked before
    /// either is on screen — so a V5 next to a V11 is set at the V11's size rather than
    /// scaled down to fit when the V11 turns up, and nothing on the line changes size
    /// once it is up. "V11" is half again as wide as "V5"; letting each find its own
    /// size was what made the pair look like two different fonts.
    private var gradeSize: CGFloat {
        max(grade(for: "grade").count, grade(for: "goalGrade").count) > 2 ? 84 : 116
    }

    /// How much room outside the rings the axis labels need — two lines of text either
    /// side of the widest spoke, and enough of it that the widest word on the chart
    /// clears the outermost ring rather than sitting on it.
    private static let labelRoom: CGFloat = 62

    /// The ladder itself: five hexagons, the outermost one brighter because it is the
    /// end of the scale rather than another rung.
    private func rings(radius: CGFloat) -> some View {
        ZStack {
            ForEach(1...Self.bands.count, id: \.self) { ring in
                let outermost = ring == Self.bands.count
                Hexagon(fraction: Double(ring) / Double(Self.bands.count))
                    .stroke(Color.paper.opacity(outermost ? 0.22 : 0.11),
                            lineWidth: outermost ? 1.5 : 1)
                    .frame(width: radius * 2, height: radius * 2)
            }
            // The spokes, drawn faintly enough to guide the eye to a label without
            // turning the middle of the chart into a star.
            Spokes()
                .stroke(Color.paper.opacity(0.07), lineWidth: 1)
                .frame(width: radius * 2, height: radius * 2)
        }
        .opacity(chartIn ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: chartIn)
    }

    /// The profile's colour is the tier its grade sits in — so the shape a V4 climber
    /// is shown is blue and the one a V10 climber is shown is red, and the colour is
    /// already telling them where they are before a single label is read.
    private var tint: Color { GradeTier.of(number(for: "grade")).color }

    /// The same rank colour, off the answers on file rather than off an instance — so
    /// anything drawing around the profile can be lit in it without building the view.
    static var rankTint: Color {
        let measure = BodyMeasure.grade
        let answer = Onboarding.shared.answers["grade"] ?? measure.answer(metric: measure.start)
        return GradeTier.of(measure.value(from: answer)).color
    }

    /// The dream's, likewise — which is what makes the goal grade's own tier the thing
    /// the second shape is drawn in rather than one aspirational purple for everybody.
    private var dreamTint: Color { GradeTier.of(number(for: "goalGrade")).color }

    /// A ladder answer as the number it is. The quiz writes both grades as "V6".
    private func number(for key: String) -> Double {
        let measure: BodyMeasure = key == "goalGrade" ? .goalGrade : .grade
        return measure.value(from: grade(for: key))
    }


    /// The profile. It arrives as a small hexagon and is then pushed out one corner at
    /// a time — which is why the corners are animated separately rather than the whole
    /// path being scaled up: a shape that grows uniformly says nothing about the six
    /// things it is made of, and this screen's whole job is that it is made of six
    /// things.
    private func shape(radius: CGFloat, reaches: [Double], tint: Color,
                       glow: Double = 0) -> some View {
        Radar(reaches: AnimatableVector(reaches))
            .fill(LinearGradient(colors: [tint.opacity(0.42), tint.opacity(0.16)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                ZStack {
                    if glow > 0 {
                        // The glow: the same line again, laid down thicker, blurred, and
                        // kept faint — a shadow in the shape's own colour rather than a
                        // second edge. It is under the real line and nothing else, so
                        // what rises and falls is the light off the outline and not the
                        // whole chart swelling.
                        Radar(reaches: AnimatableVector(reaches))
                            .stroke(tint, style: StrokeStyle(lineWidth: 6, lineJoin: .round))
                            .blur(radius: 7 + 4 * glow)
                            .opacity(0.3 + 0.3 * glow)
                    }
                    Radar(reaches: AnimatableVector(reaches))
                        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
            }
            .frame(width: radius * 2, height: radius * 2)
            .opacity(chartIn ? 1 : 0)
            .animation(.easeInOut(duration: 0.4), value: chartIn)
    }

    /// The name of each pillar and the grade its spoke reaches, sat outside the rings on
    /// its own axis. Aligned by which side of the chart it is on, so nothing leans in
    /// over the shape.
    private func labels(radius: CGFloat, center: CGPoint) -> some View {
        ForEach(Array(Self.pillars.enumerated()), id: \.offset) { index, pillar in
            let angle = Self.angle(index)
            let out = radius + 30
            // Pushed further out sideways than up and down. A label is centred on its
            // point and is much wider than it is tall, so on the four corner axes the
            // inner half of a long word — the back end of TECHNIQUE — was landing on the
            // ring while the two upright labels had room to spare. The extra only
            // applies where there is width to clear: it goes with the cosine, which is
            // nothing at the top and bottom of the chart and most at the corners.
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * (out + 22),
                                y: center.y + CGFloat(sin(angle)) * out)
            VStack(spacing: 2) {
                Text(pillar.name.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.paper.opacity(0.5))
                Text(band(at: index))
                    .font(.system(size: 15, weight: .bold))
            }
            .fixedSize()
            .position(point)
            // Each name comes up with its own corner rather than on a stagger of its
            // own, so the two are one event however the cadence below is retimed.
            .opacity(landed[index] ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: landed[index])
        }
    }

    /// What the quiz was told, printed back under the chart — small, in a grid, and
    /// only the answers the shape is actually built out of.
    ///
    /// It was a list of every question at full size first, and that was a page of its
    /// own under a screen that is meant to be one glance. A receipt is worth having and
    /// it is worth nothing at the size of the thing it is a receipt for: this is the
    /// numbers, three to a row, close enough to the chart to be read with it.
    private var info: some View {
        // Two columns read down rather than across: the body's three numbers on the
        // left, the three that were measured on the right, so what you are sits beside
        // what you can do instead of interleaved with it.
        let half = (stats.count + 1) / 2
        return VStack(alignment: .leading, spacing: 14) {
            // What the card is, said once and quietly — without it the block reads as
            // six loose numbers under a chart rather than as the thing they were all
            // given for.
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 11))
                Text("Profile")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Color.paper.opacity(0.4))

            HStack(alignment: .top, spacing: 16) {
                column(Array(stats.prefix(half)))
                column(Array(stats.dropFirst(half)))
            }
        }
        // No panel of its own. On the card these sit on glass, and a grey box inside
        // a glass one is a second card where there is only one thing — the glass is
        // already the edge, so drawing another inside it just makes the page busier.
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column(_ stats: [Stat]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(stats, id: \.label) { stat in
                // One line, not two: the label greyed and the number after it, the way
                // it would be said out loud. Set as one string rather than a label
                // stacked over a value — a caption in small capitals over every number
                // was more type than the numbers themselves.
                // One size down the whole card, and barely any room left for shrinking:
                // the longest answer here is "One arm, easily", and a line that scaled
                // itself to fit was setting half the card in a different size from the
                // other half.
                (Text("\(stat.label): ").foregroundStyle(Color.paper.opacity(0.4))
                    + Text(stat.value).fontWeight(.semibold))
                    .font(.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One cell of the receipt.
    private struct Stat {
        let label: String
        let value: String
        /// White for everything except a grade, which is already coloured by the tier
        /// it lands in everywhere else in the app.
        var tint: Color = .white
    }

    /// The answers the chart is built out of, and nothing else — the body's three
    /// numbers and the three that were measured. The grades are already up in full size,
    /// the screens of opinion feed nothing here, and how long somebody has climbed and
    /// how often are facts about their week rather than about the shape. A question that was skipped — the
    /// added-weight one, for anybody who can't do a pull-up — leaves no cell behind
    /// rather than a cell saying nothing.
    private var stats: [Stat] {
        var rows: [Stat] = []

        // Read back in the units the ruler was showing rather than the metric they were
        // recorded in: what somebody set in feet should come back in feet.
        func ruler(_ key: String, _ label: String, _ measure: BodyMeasure) {
            guard let saved = answers[key] else { return }
            let scale = measure.scale
            let shown = scale.text(scale.fromMetric(measure.value(from: saved)))
            rows.append(Stat(label: label,
                             value: scale.unit.isEmpty ? shown : "\(shown) \(scale.unit)"))
        }

        func tapped(_ key: String, _ label: String) {
            guard let saved = answers[key], !saved.isEmpty else { return }
            rows.append(Stat(label: label, value: saved))
        }

        ruler("height", "Height", .height)
        ruler("weight", "Weight", .weight)
        ruler("apeIndex", "Ape index", .apeIndex)
        ruler("pullUps", "Pull-ups", .pullUps)
        // What goes on top of a bodyweight pull-up, which is the most anybody pulls —
        // "added" said what it was and "max" says what it means.
        ruler("pullUpMax", "Max", .pullUpMax)
        tapped("hang", "Hang")
        return rows
    }


    // MARK: - Scoring

    /// Where the quiz's grade answer sits on the ladder, as a ring number. This is the
    /// mean the six spokes have to come out at, not a starting point they each sit near.
    /// Unanswered reads as the middle rung rather than as nothing: a chart drawn at zero
    /// is not a profile.
    ///
    /// It lands between rings as readily as on one. V6 and V8 sit in the same band and
    /// are not the same climber — flooring the whole chart at the same ring for both was
    /// throwing away the most precise answer the quiz gets. Each ring is pinned at the
    /// middle grade of its band — V1, V4, V7, V10, V13 — and anything between two of
    /// them is read straight across, the same way a measured spoke is.
    private var base: Double {
        guard let answer = answers["grade"] else { return 3 }
        return Self.ring(BodyMeasure.grade.value(from: answer),
                         through: [(1, 1), (4, 2), (7, 3), (10, 4), (13, 5)])
    }

    /// What the quiz was told, printed back: the grade itself, exact, however wide the
    /// band its spoke lands in. The two ladder answers are already written as "V6" —
    /// there is nothing to convert, and converting is how a fact becomes an estimate.
    private func grade(for key: String) -> String {
        let measure: BodyMeasure = key == "goalGrade" ? .goalGrade : .grade
        return answers[key] ?? measure.answer(metric: measure.start)
    }

    /// The ring the goal grade sits on — the whole dream shape, since every corner of it
    /// is the same. A goal that isn't past what you already climb is drawn at what you
    /// climb rather than inside it: the second chart is never smaller than the first.
    private var dreamBase: Double {
        let goal = Self.ring(BodyMeasure.goalGrade.value(from: grade(for: "goalGrade")),
                             through: [(1, 1), (4, 2), (7, 3), (10, 4), (13, 5)])
        return min(Double(Self.bands.count), max(base, goal))
    }

    /// The leading number off an answer the quiz wrote as "12 reps" or "+20 kg".
    private func number(_ key: String) -> Double? {
        guard let answer = answers[key] else { return nil }
        let digits = answer.prefix { $0.isNumber || $0 == "-" || $0 == "+" }
        return Double(digits)
    }

    /// What they weigh, which both weighted answers are read against. A quiz that
    /// somehow skipped the question falls back to the ruler's own starting point rather
    /// than dividing by nothing.
    private var bodyWeight: Double {
        let weight = number("weight") ?? 0
        return weight > 20 ? weight : BodyMeasure.weight.start
    }

    // MARK: The measured spokes

    /// Reps against the ladder. Rung by rung: a couple is where everyone starts, five is
    /// the first real set, and past twenty the number stops discriminating — which is
    /// exactly why the same movement is asked about twice, once for reps and once for
    /// load.
    private var enduranceRing: Double? {
        guard let reps = number("pullUps") else { return nil }
        return Self.ring(reps, through: [(0, 1), (5, 2), (11, 3), (17, 4), (25, 5)])
    }

    /// Load, as a share of what they weigh — which is the only way the number means
    /// anything, and the reason the weight screen is now load-bearing. Nobody who can't
    /// do a single rep is asked the question at all, so that case takes the bottom rung
    /// straight from the reps answer.
    private var strengthRing: Double? {
        guard let reps = number("pullUps") else { return nil }
        guard reps >= 1 else { return 1 }
        guard let added = number("pullUpMax") else { return nil }
        let share = added / bodyWeight * 100
        return Self.ring(share, through: [(0, 2), (10, 3), (25, 4), (50, 5)])
    }

    /// A measurement laid on the ring ladder, read straight between the anchors rather
    /// than bucketed into them: twelve reps and fourteen are not the same answer, and a
    /// chart that draws them identically is throwing away the only hard numbers it has.
    private static func ring(_ value: Double, through anchors: [(Double, Double)]) -> Double {
        if let first = anchors.first, value <= first.0 { return first.1 }
        for (low, high) in zip(anchors, anchors.dropFirst()) where value <= high.0 {
            let across = (value - low.0) / (high.0 - low.0)
            return low.1 + across * (high.1 - low.1)
        }
        return anchors.last?.1 ?? 1
    }

    /// The edge. Read by where the answer sits in the quiz's own list rather than by
    /// its words, because that list was written as the rings in order — five rungs, five
    /// rings, and a ladder that never has to be converted into anything.
    private var fingersRing: Double? {
        guard let answer = answers["hang"],
              let rungs = QuizView.questions.first(where: { $0.id == "hang" })?.options,
              let rung = rungs.firstIndex(of: answer) else { return nil }
        return Double(rung + 1)
    }

    /// Fast force, out of the same two pull-up answers Strength and Endurance come
    /// from — read for their *balance* rather than their size. A big single with few
    /// reps behind it is the shape of a powerful climber; twenty reps and nothing added
    /// is the shape of an enduring one, and they deserve different spokes even though
    /// there is only one movement being asked about.
    ///
    /// A proxy, and not a good one — nothing here has watched anybody jump. Still better
    /// than what it replaced, which was a tick box.
    private var powerRing: Double? {
        guard let load = strengthRing, let reps = enduranceRing else { return nil }
        return load + (load - reps) * Self.bias
    }

    /// Your head sits at your limit grade, and time never pushes it past that. Years on
    /// the wall don't make anyone's nerve V12 — if it were, they'd be on V12 — so this
    /// axis only ever reads down.
    ///
    /// What it reads down for is a mismatch: each answer carries the grade it plausibly
    /// gets you to, and somebody climbing well past it has gone up faster than the
    /// tactics and the head have had time to follow. A V7 in their first month is
    /// climbing on athleticism, and this is the one spoke that can say so. The `reach`
    /// cap keeps that a push rather than a shove — the drop is never more than a band
    /// and a quarter however far apart the two answers are.
    private var mindRing: Double? {
        let ceilings = ["Just started": 1.0, "Under a year": 2.0,
                        "1–3 years": 3.0, "3+ years": Double(Self.bands.count)]
        guard let answer = answers["experience"], let ceiling = ceilings[answer] else { return nil }
        return min(base, ceiling)
    }

    /// Which spokes are measurements rather than inferences, each held within `reach`
    /// of the grade. Four of the six now; Power is the one with no honest question
    /// behind it, and Technique the one whose question hasn't been asked yet.
    private func measured(_ pillar: Pillar) -> Double? {
        let raw: Double? = switch pillar.name {
        case "Fingers": fingersRing
        case "Strength": strengthRing
        case "Power": powerRing
        case "Endurance": enduranceRing
        case "Mind": mindRing
        default: nil
        }
        return raw.map { max(base - Self.reach, min(base + Self.reach, $0)) }
    }

    // MARK: The shape

    /// All six spokes, in rings.
    ///
    /// A measured spoke says what it measures. Anything unmeasured sits at your grade,
    /// full stop — no opinion moves it. What was ticked on the strengths and weaknesses
    /// screens deliberately does nothing here: a chart built out of numbers and a chart
    /// built out of self-assessment are two different products, and mixing them gets you
    /// the credibility of the second one.
    ///
    /// Nothing is conserved and nothing trades off. A spoke reaching past the rest isn't
    /// taken out of another one; it's headroom, and headroom is what this chart is for.
    private var spokes: [Double] {
        Self.pillars.map { pillar in
            max(Self.floor, min(Double(Self.bands.count), measured(pillar) ?? base))
        }
    }

    /// The grade a spoke reaches, for the label under its name.
    private func band(at index: Int) -> String { label(spokes[index]) }

    private func label(_ ring: Double) -> String {
        let rung = Int(ring.rounded()) - 1
        return Self.bands[max(0, min(Self.bands.count - 1, rung))]
    }

    // MARK: - Geometry

    /// Where the *n*th spoke points. Straight up for the first, then clockwise — a
    /// pointed top rather than a flat one, so the chart has a spoke where the eye lands.
    static func angle(_ index: Int) -> Double {
        -.pi / 2 + 2 * .pi * Double(index) / Double(pillars.count)
    }

    // MARK: - The reveal

    /// Where a corner sits before it is pushed out — the small green hexagon the shape
    /// grows from. `floor` rather than nothing, because a polygon with corners at the
    /// centre is a path with no area, and the first two would draw as a sliver rather
    /// than as a shape being built.
    private static var seed: Double { floor / Double(bands.count) }

    /// The dot the dream opens out of: far enough off zero to be drawn, small enough
    /// that what is drawn is a point rather than a shape.
    private static let dot = 0.018

    /// The wait between one corner landing and the next. Even, and slow enough that no
    /// two are ever on screen at once — six corners is six things being said, and the
    /// screen is only worth having if each of them is read.
    private static let cadence: Double = 0.48

    /// The number already on screen, coming apart at the seams. A dozen quick throws
    /// either side of its place, each one further than the last and each with a knock
    /// under the finger, so the screen is plainly winding up to something by the time it
    /// happens.
    ///
    /// The knocks ramp in strength along with the throws. A rumble at one level is a
    /// phone buzzing; a rumble that is getting worse is a warning.
    private func shudder() async {
        let rumble = UIImpactFeedbackGenerator(style: .soft)
        rumble.prepare()
        let steps = 12
        for step in 0..<steps {
            let share = Double(step) / Double(steps - 1)
            withAnimation(.linear(duration: 0.042)) {
                shake = (step.isMultiple(of: 2) ? -1 : 1) * (1.5 + 7 * share)
            }
            rumble.impactOccurred(intensity: 0.25 + 0.6 * share)
            try? await Task.sleep(for: .milliseconds(42))
            if Task.isCancelled { return }
        }
        withAnimation(.linear(duration: 0.04)) { shake = 0 }
    }

    /// Continue, twice over: the first press brings the dream up beside the profile,
    /// the second leaves the screen. One button rather than two, because the second
    /// chart is the rest of this screen and not the next one.
    private func next() {
        guard slide == 0 else {
            onFinish()
            return
        }
        // A dot in the middle of the chart, which is what it opens out of. The profile
        // grows from a small hexagon because it is being built corner by corner and has
        // to be a shape the whole way; this one arrives all at once and shouldn't
        // announce its six sides before it has any.
        dreamReaches = Array(repeating: Self.dot, count: Self.pillars.count)
        // The hit the shudder was building to, and the number is thrown off the middle
        // of the screen by it. Heavy at full strength — the one time the phone is asked
        // for everything it has — and the spring is quick and loose so the grade is
        // knocked left rather than carried there.
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.68)) { slide = 1 }
        Task { @MainActor in
            let tap = UIImpactFeedbackGenerator(style: .rigid)
            tap.prepare()
            // Then the number that room was made for — and with it, in the middle of
            // the chart, the dot it is about to open out of. They arrive together
            // because they are the same thing said twice: the grade, and the shape it
            // asks for.
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.spring(response: 0.44, dampingFraction: 0.78)) { goalIn = true }
            withAnimation(.easeOut(duration: 0.2)) { dreamIn = true }
            tap.impactOccurred()
            tap.prepare()
            // And then what the dot opens into, behind the shape already there.
            try? await Task.sleep(for: .milliseconds(320))
            // Every corner at once, unlike the profile's: the dream isn't six things
            // being said, it's one — this, evenly, all the way round.
            withAnimation(.spring(response: 0.75, dampingFraction: 0.78)) {
                dreamReaches = Array(repeating: dreamBase / Double(Self.bands.count),
                                     count: Self.pillars.count)
            }
            tap.impactOccurred()

            // The gap is drawn and read; now the block gives up the middle of the
            // screen, and what it makes room for is the only thing left to do here.
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.spring(response: 0.62, dampingFraction: 0.9)) { stage = 2 }
            try? await Task.sleep(for: .milliseconds(220))
            finished = true
        }
    }

    /// Rings first, then the corners one at a time, each with a tap under the finger.
    @Sendable
    /// The end of `run`'s first beat, arrived at without walking through it — except
    /// for the shape itself, which still opens.
    ///
    /// The rings, the spokes and the labels are furniture: they say what the chart is,
    /// and animating furniture in is a loading screen wearing a costume. The coloured
    /// shape is the only thing on here that is *about* the person reading it, so it is
    /// the only thing worth watching arrive — out of the middle in one movement rather
    /// than a corner at a time, because on a second reading the drama is not in the
    /// order the six were measured.
    private func settle() async {
        chartIn = true
        landed = Array(repeating: true, count: Self.pillars.count)
        stage = 1
        infoIn = true
        gradeIn = true
        finished = true
        guard reaches.isEmpty || reaches.allSatisfy({ $0 <= Self.seed }) else { return }
        reaches = Array(repeating: Self.seed, count: Self.pillars.count)
        // One frame with the dot on screen, so the shape has somewhere to open from.
        try? await Task.sleep(for: .milliseconds(32))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
            reaches = spokes.map { $0 / Double(Self.bands.count) }
        }
    }

    private func run() async {
        reaches = Array(repeating: Self.seed, count: Self.pillars.count)
        let tap = UIImpactFeedbackGenerator(style: .rigid)
        tap.prepare()

        withAnimation { chartIn = true }
        try? await Task.sleep(for: .milliseconds(420))
        if Task.isCancelled { return }

        let values = spokes.map { $0 / Double(Self.bands.count) }
        for index in Self.pillars.indices {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                reaches[index] = values[index]
                landed[index] = true
            }
            tap.impactOccurred()
            tap.prepare()
            guard index < Self.pillars.count - 1 else { break }
            try? await Task.sleep(for: .seconds(Self.cadence))
            if Task.isCancelled { return }
        }

        try? await Task.sleep(for: .milliseconds(320))
        if Task.isCancelled { return }
        // Up by half the height of what is about to appear under it — the chart stays
        // full size, and the pair ends up centred where the chart alone just was.
        withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) { stage = 1 }

        if Self.showsInfo {
            try? await Task.sleep(for: .milliseconds(280))
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { infoIn = true }
        }

        try? await Task.sleep(for: .milliseconds(300))
        if Task.isCancelled { return }
        withAnimation(.spring(response: 0.46, dampingFraction: 0.66)) { gradeIn = true }
        tap.impactOccurred()

        // Long enough to read what you climb, and no longer — then the number starts
        // to shake, which is the screen saying this isn't the end of it before a word
        // of it has been read.
        try? await Task.sleep(for: .milliseconds(650))
        if Task.isCancelled { return }
        await shudder()
        if Task.isCancelled { return }
        next()
    }
}

/// A list of numbers SwiftUI can interpolate, so a `Shape` can animate every corner at
/// once and each on its own timing. Without it a shape animates as one path, and the
/// corners could only ever grow together.
struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    init(_ values: [Double]) { self.values = values }

    static var zero: AnimatableVector { AnimatableVector([]) }

    /// Paired up to the longer of the two, with the shorter read as zeros — the arrays
    /// are always the same length in practice, and padding is cheaper than trusting it.
    private static func zip(_ left: AnimatableVector, _ right: AnimatableVector,
                            _ combine: (Double, Double) -> Double) -> AnimatableVector {
        let count = max(left.values.count, right.values.count)
        return AnimatableVector((0..<count).map { index in
            combine(index < left.values.count ? left.values[index] : 0,
                    index < right.values.count ? right.values[index] : 0)
        })
    }

    static func + (left: AnimatableVector, right: AnimatableVector) -> AnimatableVector {
        zip(left, right, +)
    }

    static func - (left: AnimatableVector, right: AnimatableVector) -> AnimatableVector {
        zip(left, right, -)
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }
}

// MARK: - Shapes

/// One ring of the ladder, at `fraction` of the way out.
/// The arrow between the two grades: three straight strokes, butt-cut at every end and
/// mitred at the point. Nothing here is a curve, which is the whole reason it exists —
/// the drawn arrows in the system face are rounded off at the tip and the tails, and at
/// this size, beside type that is cut flat, that reads as soft rather than as neutral.
private struct SharpArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.midY
        // The head is as deep as it is tall, so the two barbs meet the shaft at right
        // angles to each other — the plainest arrowhead there is, and the one that keeps
        // its point once the stroke is mitred.
        let head = rect.height / 2
        path.move(to: CGPoint(x: rect.minX, y: mid))
        path.addLine(to: CGPoint(x: rect.maxX, y: mid))
        path.move(to: CGPoint(x: rect.maxX - head, y: mid - head))
        path.addLine(to: CGPoint(x: rect.maxX, y: mid))
        path.addLine(to: CGPoint(x: rect.maxX - head, y: mid + head))
        return path
    }
}

private struct Hexagon: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 * fraction
        var path = Path()
        for index in ProfileView.pillars.indices {
            let angle = ProfileView.angle(index)
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                                y: center.y + CGFloat(sin(angle)) * radius)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

/// The lines from the middle out to each corner.
private struct Spokes: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for index in ProfileView.pillars.indices {
            let angle = ProfileView.angle(index)
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                                     y: center.y + CGFloat(sin(angle)) * radius))
        }
        return path
    }
}

/// The profile itself: one corner per pillar, each at its own distance out — and each
/// animating independently, which is what `AnimatableVector` is here for.
private struct Radar: Shape {
    var reaches: AnimatableVector

    var animatableData: AnimatableVector {
        get { reaches }
        set { reaches = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for (index, value) in reaches.values.enumerated() {
            let angle = ProfileView.angle(index)
            let reach = radius * CGFloat(value)
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * reach,
                                y: center.y + CGFloat(sin(angle)) * reach)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
