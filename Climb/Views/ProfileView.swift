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

    var onFinish: () -> Void

    @State private var onboarding = Onboarding.shared
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
    /// Whether the chart has been carried up to the top of the screen, which is what
    /// opens the space the other two land in.
    @State private var moved = false
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
    /// The dream shape's corners. Empty until the second beat, when it opens out of the
    /// middle of the same chart — even all the way round, because a goal grade is not a
    /// shape you have to guess at: it is what all six of these have to reach.
    @State private var dreamReaches: [Double] = []

    private var answers: [String: String] { onboarding.answers }

    /// How far down the chart sits before it is moved: the drop from its place at the
    /// top of the column to the middle of the screen.
    private var centering: CGFloat {
        max(0, columnHeight / 2 - (Self.chartHeight / 2 + 8))
    }

    var body: some View {
        // The screen builds itself: the chart alone in the middle, then up to the top,
        // then what it was read out of under it, and the grade last of all at the
        // bottom — which is the order the three of them were arrived at.
        VStack(spacing: 0) {
            chart
                .padding(.top, 8)
                // Drawn in the middle of the screen to start with, where there is
                // nothing else, and carried up to the top once the shape is finished —
                // the move is what opens the room the profile and the grade land in,
                // rather than the two of them appearing around something that never
                // moved.
                .offset(y: moved ? 0 : centering)

            if Self.showsInfo {
                info
                    .padding(.top, 24)
                    .opacity(infoIn ? 1 : 0)
                    .offset(y: infoIn ? 0 : 12)
            }

            grades
                .padding(.top, 4)

            Spacer(minLength: 16)

            // The way out, said once and quietly, and only once there is somewhere to
            // go. It sits on its own at the bottom rather than under the grade, so the
            // grade keeps the company of the profile it came out of.
            Text("Tap to continue")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.35))
                .opacity(finished ? 1 : 0)
                .animation(.easeInOut(duration: 0.5), value: finished)
                .padding(.bottom, 8)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { columnHeight = $0 }
        // No button. The screen plays itself — the shape, the profile, the grade, and
        // then the grade you're after — and once it has finished playing a tap anywhere
        // takes it. A button under all of this would have been asking for a decision
        // where there isn't one.
        .contentShape(.rect)
        .onTapGesture { if finished { onFinish() } }
        .foregroundStyle(.white)
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
                // Behind the profile, because it is the bigger of the two and the one
                // that hasn't happened yet — and drawn back a little, so what you climb
                // stays the solid thing on the chart and what you're after reads as the
                // shape it hasn't been filled into.
                shape(radius: radius, reaches: dreamReaches, tint: dreamTint)
                    .opacity(dreamIn ? 0.4 : 0)
                shape(radius: radius, reaches: reaches, tint: tint)
                labels(radius: radius, center: center)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: Self.chartHeight)
    }

    /// How tall the chart's box is, wherever on the screen it currently sits.
    private static let chartHeight: CGFloat = 320

    /// What the shapes come to, in grades. On its own the number is the size it is
    /// because it is the only writing on the screen; once the dream is up it steps down
    /// to make room for the one it is being read against.
    private var grades: some View {
        HStack(spacing: 16) {
            grade(grade(for: "grade"), tint: tint)
                // Last of all, and on the same spring the corners land on, so it reads
                // as the seventh beat of the same reveal rather than as a caption.
                .scaleEffect(gradeIn ? 1 : 0.6)
                .opacity(gradeIn ? 1 : 0)
            // Taken into the row before it can be seen: the space it needs is what
            // carries the grade already there over to the left, and only once that has
            // happened does the goal itself turn up in it. Neither number ever changes
            // size — what you climb doesn't get smaller because you said what you're
            // after.
            if slide == 1 {
                // Between the two, so the pair reads as a distance rather than as two
                // facts stood next to each other. Faint, and much smaller than what it
                // joins: it is punctuation, not a third thing on the line.
                Image(systemName: "arrow.right")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                    .opacity(goalIn ? 1 : 0)
                    // Put into the row with no transition of its own: the fade is the
                    // one above, and SwiftUI's default insert fading underneath it was
                    // the hitch on the way in.
                    .transition(.identity)
                grade(grade(for: "goalGrade"), tint: dreamTint)
                    .scaleEffect(goalIn ? 1 : 0.7)
                    .opacity(goalIn ? 1 : 0)
                    .transition(.identity)
            }
        }
    }

    /// Heavy, tight, and the system face rather than the rounded one — a grade is a
    /// hard number and the soft face was reading as a toy. The negative tracking is what
    /// keeps two characters at this size looking set rather than spaced.
    private func grade(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: gradeSize, weight: .heavy))
            .tracking(-2)
            // Shaded rather than plated: the colour itself at the top, a little of it
            // taken away by the bottom. The chrome ramp that was here first — highlight,
            // shadow, second highlight — read as a sticker, which is what happens when
            // type at this size pretends to be metal.
            .foregroundStyle(Self.shaded(tint))
            // One soft shadow under it, black rather than coloured, so the number sits
            // above the screen instead of glowing on it.
            .shadow(color: .black.opacity(0.6), radius: 16, y: 8)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// One size for both grades, picked off the longer of the two and picked before
    /// either is on screen — so a V5 next to a V11 is set at the V11's size rather than
    /// scaled down to fit when the V11 turns up, and nothing on the line changes size
    /// once it is up. "V11" is half again as wide as "V5"; letting each find its own
    /// size was what made the pair look like two different fonts.
    private var gradeSize: CGFloat {
        max(grade(for: "grade").count, grade(for: "goalGrade").count) > 2 ? 84 : 116
    }

    /// The shading: the tier's colour, lifted a touch at the top and let down at the
    /// bottom. Two stops and a small range — enough that the glyph has a direction to
    /// it, not enough to be a second colour.
    private static func shaded(_ tint: Color) -> LinearGradient {
        LinearGradient(colors: [tint.mix(with: .white, by: 0.14),
                                tint.mix(with: .black, by: 0.24)],
                       startPoint: .top, endPoint: .bottom)
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
                    .stroke(Color.white.opacity(outermost ? 0.22 : 0.11),
                            lineWidth: outermost ? 1.5 : 1)
                    .frame(width: radius * 2, height: radius * 2)
            }
            // The spokes, drawn faintly enough to guide the eye to a label without
            // turning the middle of the chart into a star.
            Spokes()
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                .frame(width: radius * 2, height: radius * 2)
        }
        .opacity(chartIn ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: chartIn)
    }

    /// The profile's colour is the tier its grade sits in — so the shape a V4 climber
    /// is shown is blue and the one a V10 climber is shown is red, and the colour is
    /// already telling them where they are before a single label is read.
    private var tint: Color { GradeTier.of(number(for: "grade")).color }

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
    private func shape(radius: CGFloat, reaches: [Double], tint: Color) -> some View {
        Radar(reaches: AnimatableVector(reaches))
            .fill(LinearGradient(colors: [tint.opacity(0.42), tint.opacity(0.16)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                Radar(reaches: AnimatableVector(reaches))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
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
                    .foregroundStyle(.white.opacity(0.5))
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
            .foregroundStyle(.white.opacity(0.4))

            HStack(alignment: .top, spacing: 16) {
                column(Array(stats.prefix(half)))
                column(Array(stats.dropFirst(half)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: .rect(cornerRadius: 18))
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
                (Text("\(stat.label): ").foregroundStyle(.white.opacity(0.4))
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
        // First the room, which moves the grade already on screen over to the left.
        withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) { slide = 1 }
        Task { @MainActor in
            let tap = UIImpactFeedbackGenerator(style: .rigid)
            tap.prepare()
            // Then the number that room was made for.
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.spring(response: 0.44, dampingFraction: 0.78)) { goalIn = true }
            tap.impactOccurred()
            tap.prepare()
            // The dot, put down in the middle of the chart on its own.
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.easeOut(duration: 0.2)) { dreamIn = true }
            // And then what it opens into, behind the shape already there.
            try? await Task.sleep(for: .milliseconds(220))
            // Every corner at once, unlike the profile's: the dream isn't six things
            // being said, it's one — this, evenly, all the way round.
            withAnimation(.spring(response: 0.75, dampingFraction: 0.78)) {
                dreamReaches = Array(repeating: dreamBase / Double(Self.bands.count),
                                     count: Self.pillars.count)
            }
            tap.impactOccurred()
            try? await Task.sleep(for: .milliseconds(500))
            finished = true
        }
    }

    /// Rings first, then the corners one at a time, each with a tap under the finger.
    @Sendable
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
        withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) { moved = true }

        if Self.showsInfo {
            try? await Task.sleep(for: .milliseconds(280))
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { infoIn = true }
        }

        try? await Task.sleep(for: .milliseconds(300))
        if Task.isCancelled { return }
        withAnimation(.spring(response: 0.46, dampingFraction: 0.66)) { gradeIn = true }
        tap.impactOccurred()

        // Long enough to read what you climb, and no longer: the second beat is the
        // point of the screen and waiting on a tap for it would have most people
        // leaving before it happened.
        try? await Task.sleep(for: .seconds(1))
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
