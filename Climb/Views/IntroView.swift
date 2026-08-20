import SwiftUI

/// The cold open: three screens of the app before anything is asked of anyone.
///
/// It sits ahead of the quiz rather than inside it, and ahead of everything else on a
/// first launch — the one place a demo costs nothing, because nothing has been spent
/// yet. What it shows is the loop rather than a feature list: check in, log, review,
/// in the order a session actually happens. Three screens is the whole argument, and
/// three taps is the whole cost of it — short enough that there is nothing to skip.
struct IntroView: View {
    /// Done with it — skipped or walked through, the same thing either way.
    let onFinish: () -> Void

    @State private var index = 0
    /// The page's own width, for deciding which half of it was tapped.
    @State private var pageWidth: CGFloat = 0

    private struct Slide {
        let headline: String
        let art: Art
    }

    /// What sits under a headline: a crop of the app, or something drawn for the
    /// occasion. The last slide is a claim about the next six months, and there is no
    /// screenshot of that — it has to be drawn.
    private enum Art {
        case shot(String)
        case curve
    }

    /// Four slides, and the order is the argument: the journal, what it shows you, what
    /// you learn off it, and the grade that was the point of all of it. It opens on
    /// what the app *is* and closes on what it is *for* — the promise is the last thing
    /// on screen before the questions start, which is where a promise is worth most.
    ///
    /// Verb-first, the way the ones worth copying are: reach, analyze, learn. The verb
    /// is what the user does, not what the app does — nobody wants a feature, they want
    /// the thing on the other side of it.
    private static let slides = [
        // "The", not "a": a positioning line that concedes it is one of many is not a
        // positioning line. And the sport is named because that is the differentiator
        // doing the work — a journal that knows your goals could be any notes app.
        Slide(headline: "The bouldering journal that knows your goals", art: .shot("introLog")),
        Slide(headline: "Analyze your training load and track progress", art: .shot("introReview")),
        Slide(headline: "Learn technique faster by reviewing your clips", art: .shot("introClip")),
        // No "with Crux" on the end. Slide one already said whose journal this is, and
        // the closer is the one line that should be about them and not about us — the
        // shortest and hardest of the four, with the chart under it doing the arguing.
        Slide(headline: "Reach your dream grade with consistent growth", art: .curve),
    ]

    private var isLast: Bool { index == Self.slides.count - 1 }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $index) {
                ForEach(Array(Self.slides.enumerated()), id: \.offset) { position, slide in
                    page(slide, active: position == index).tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
            // Tap the left of the page to go back, anywhere else to go on — the way a
            // story works, and the way people already hold a phone: the swipe stays,
            // this is just the shorter version of it for a thumb that is already
            // resting on the glass. `simultaneousGesture` rather than an overlay, so
            // nothing sits on top of the pager stealing the swipe from it.
            .simultaneousGesture(
                SpatialTapGesture().onEnded { tap in
                    // A third, not a half. Forward is the direction nearly every tap
                    // means, so back gets the smaller target and the accidental tap
                    // costs nothing.
                    if tap.location.x < pageWidth * 0.3 {
                        back()
                    } else {
                        advance()
                    }
                }
            )

            progress
        }
        .background(Color.black)
        .overlay(alignment: .bottom) { footer }
        .animation(.easeInOut(duration: 0.25), value: index)
    }

    // MARK: - A slide

    private func page(_ slide: Slide, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(slide.headline)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.paper)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 36)
                // Held open to the tallest headline — three lines at 34 point, plus the
                // padding above them — so the shot under it starts at the same height
                // on all four and the page does not jump as it turns. Two-line slides
                // pay for the third line in white space rather than in movement.
                .frame(height: 180, alignment: .topLeading)

            Spacer(minLength: 0)

            art(slide, active: active)
        }
    }

    @ViewBuilder
    private func art(_ slide: Slide, active: Bool) -> some View {
        switch slide.art {
        case .shot(let name): shot(name)
        case .curve:
            GradeCurve(active: active)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                // Lifted past the even gap the screenshots get. They are tall enough to
                // fill their space; the chart is a short block, and a short block
                // centred in a tall gap reads as having sunk to the bottom of it.
                .padding(.bottom, Self.footerRoom + 150)
        }
    }

    /// The crop as it is, fitted to whatever the headline leaves it.
    ///
    /// No phone around it and no bezel: these are cut to the content rather than to the
    /// device, and a partial screen inside a phone frame reads as a broken phone. Black
    /// crop on a black page against a black app means the shot is simply the app, which
    /// is the whole idea — the slide is not a picture of the screen, it is the screen.
    ///
    /// Fitted rather than filled, because the three are cut to three different shapes:
    /// fitting is what lets a square one and a tall one sit in the same space without
    /// either being cropped a second time on the way in.
    ///
    /// Cornered, which shows on exactly one of them. Two of these crops are black UI on
    /// a black page and have no visible edge to round; the clip is a photograph, and a
    /// photograph with square corners reads as pasted on rather than placed. Rounding
    /// all of them costs nothing on the ones with nothing to show.
    ///
    /// Nothing else — no outline, no glow. Both were tried to give the black crops an
    /// edge, and both made it worse: an outline reads as a wireframe on a page with
    /// nothing else ruled on it, and a halo needs air around it to be a halo, which
    /// would have cost the spacing the slides are laid out on. The two black shots
    /// having no edge is not a fault to be fixed — it is what black UI on a black page
    /// looks like, and the app is that page.
    private func shot(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .clipShape(.rect(cornerRadius: 20))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            // Exactly what the footer stands in — its 20 of padding and the button's
            // 56 — and not a point more. The shot centres in what is left, so the gap
            // over it and the gap under it come out the same; anything rounded up here
            // is added to the bottom gap alone and the shot reads as riding high.
            .padding(.bottom, Self.footerRoom)
    }

    /// What the button and its padding take off the bottom of the page.
    private static let footerRoom: CGFloat = 76

    // MARK: - Chrome

    /// One pill a slide, the one you are on lit. A bar that filled up would be a
    /// promise about how much is left; three pills say it outright.
    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(Self.slides.indices, id: \.self) { position in
                Capsule()
                    .fill(position == index ? Color.paper : Color.surface)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: advance) {
                // The same word on all three. A button that renames itself on the last
                // slide is telling you where you are, which the pills already do.
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.paper, in: .capsule)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        // The phone is running underneath this, so the buttons get ground to sit on:
        // clear where the screenshot is still being read, solid by the time it reaches
        // the words.
        .background {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black, location: 0.45),
                                   .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .padding(.top, -80)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func back() {
        guard index > 0 else { return }
        index -= 1
    }

    private func advance() {
        guard !isLast else {
            onFinish()
            return
        }
        index += 1
    }
}

/// The comparison both of the onboardings worth copying end on: the next six months
/// with the thing, and the next six months without it.
///
/// Drawn the way they draw it — no panel around it. Cal AI can afford a card because
/// their page is white and the card is a shade off it; the same card on black is a grey
/// box with a chart trapped in it. Here the chart sits on the page, like Liftoff's.
///
/// The claim is deliberately about *shape* rather than about numbers, and there were two
/// reasons to keep it that way. Liftoff can put "TOP 500 by Oct 18" on theirs because
/// theirs runs after their quiz; this one is a cold open and knows nothing about who is
/// reading it. Grades on the ends made that worse rather than better — V8 is a fantasy
/// to a V2 and an insult to a V9, and either way the slide stops being about them. The
/// real numbers belong on the profile, which has asked.
///
/// What is left is what the chart was always actually arguing: the difference a
/// written-down year makes. One line goes up, one spends twelve months finding out the
/// hard way. The second is not a worse climber — it is the same climber guessing, and
/// every boulderer has had that year.
private struct GradeCurve: View {
    /// Whether this is the slide on screen. The chart draws itself on arrival and winds
    /// back when the page leaves, so coming back to it plays again rather than finding
    /// it already finished.
    let active: Bool

    /// How much of each line has been laid down, left to right, and whether what sits
    /// at the end of it has landed yet.
    @State private var missDrawn: CGFloat = 0
    @State private var cruxDrawn: CGFloat = 0
    @State private var missLanded = false
    @State private var cruxLanded = false
    /// The run in progress, so leaving the slide stops the knocks as well as the lines.
    @State private var runner: Task<Void, Never>?

    private static let missDraw: TimeInterval = 0.85
    private static let cruxDraw: TimeInterval = 1.05

    /// Normalised: 0 to 1 left to right, 0 the bottom of the plot and 1 the top.
    ///
    /// Both finish level rather than still climbing — a hill for the grade to stand on.
    /// A number hung over a line that is still going up reads as a point it passes
    /// through; the same number over a flat top reads as where it got to.
    ///
    /// The white one is a staircase and not a ramp: up, a small step back, up again.
    /// That is what a grade actually does — you sit at one for a month, it goes
    /// backwards for a fortnight, and then a session comes along where it does not.
    /// A clean diagonal would be the honest shape of a lie; the steps are the same
    /// promise told truthfully, and they still end four grades higher.
    private static let withCrux: [CGPoint] = [
        CGPoint(x: 0, y: 0.16), CGPoint(x: 0.09, y: 0.26), CGPoint(x: 0.17, y: 0.30),
        CGPoint(x: 0.25, y: 0.285), CGPoint(x: 0.33, y: 0.39), CGPoint(x: 0.42, y: 0.45),
        CGPoint(x: 0.50, y: 0.435), CGPoint(x: 0.58, y: 0.53), CGPoint(x: 0.66, y: 0.60),
        CGPoint(x: 0.73, y: 0.585), CGPoint(x: 0.81, y: 0.68), CGPoint(x: 0.87, y: 0.72),
        CGPoint(x: 0.93, y: 0.726), CGPoint(x: 1, y: 0.726),
    ]

    /// Up, down, up, down, and out barely above where it came in. The plateau is the
    /// point:
    /// the good weeks are real, and with nothing writing them down they do not add to
    /// anything.
    private static let without: [CGPoint] = [
        CGPoint(x: 0, y: 0.16), CGPoint(x: 0.10, y: 0.30), CGPoint(x: 0.20, y: 0.17),
        CGPoint(x: 0.31, y: 0.32), CGPoint(x: 0.42, y: 0.18), CGPoint(x: 0.53, y: 0.31),
        CGPoint(x: 0.64, y: 0.21), CGPoint(x: 0.74, y: 0.29), CGPoint(x: 0.84, y: 0.313),
        CGPoint(x: 0.92, y: 0.315), CGPoint(x: 1, y: 0.315),
    ]

    private static let missTint = Effort.hard.color

    /// Where the dot sits — short of the right edge, with the line carrying on past it
    /// to run off the page. The reference does this and it is worth copying: a line
    /// that stops at its own marker reads as data that ran out, and one that keeps
    /// going reads as a season that is still going.
    ///
    /// Both plateaus are level well before this, so each marker stands on flat ground.
    private static let markerX: CGFloat = 0.90
    private static let cruxTop: CGFloat = 0.724
    private static let missTop: CGFloat = 0.315

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            plot
            // A set height rather than whatever is going spare. The chart is one
            // sentence — two lines and where they end — and stretching it to the full
            // page does not make the sentence any longer, only emptier.
            .frame(height: 250)

            tape
                // Negative, on purpose. The lines never come nearer the floor than
                // their first dip, so the bottom of the plot box is empty air and the
                // tape can be lifted into it — measured off the lines rather than off
                // the box they happen to be drawn in.
                .padding(.top, -14)

            HStack {
                Text("Month 1")
                Spacer()
                Text("Month 12")
            }
            .font(.caption)
            .foregroundStyle(Color.paper.opacity(0.35))
            .padding(.top, 5)
        }
    }

    private var plot: some View {
        GeometryReader { geometry in
            // Inset before anything is placed, not after: the rings and the grades are
            // positioned in the same space the lines are drawn in.
            let size = CGSize(width: geometry.size.width - 14, height: geometry.size.height)
            ZStack {
                // Dashed, and barely there. The shape of the pair is the whole message;
                // a grid that can be read is a grid competing with it.
                ForEach(1..<4) { row in
                    Path { path in
                        let y = size.height * CGFloat(row) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    .stroke(Color.paper.opacity(0.09),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                }

                // Revealed by a moving edge rather than by `trim`. Trim walks a path by
                // its own length, so the wobbly line and the steady one would arrive at
                // any given month at different times; a wipe puts both at the same date
                // at the same moment, which is the only way a race between them reads.
                Self.area(Self.withCrux, in: size)
                    .fill(LinearGradient(colors: [Color.paper.opacity(0.18), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .mask(alignment: .leading) { wipe(cruxDrawn, in: size) }

                Self.line(Self.without, in: size)
                    .stroke(Self.missTint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .mask(alignment: .leading) { wipe(missDrawn, in: size) }

                Self.line(Self.withCrux, in: size)
                    .stroke(Color.paper, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .mask(alignment: .leading) { wipe(cruxDrawn, in: size) }

                // Where each of them ends up, which is the sentence the chart is making.
                // Landing rather than arriving: scaled up from almost nothing on a
                // loose spring, so each one overshoots and settles on its line instead
                // of fading up in place.
                ring(CGPoint(x: Self.markerX, y: Self.missTop), in: size, tint: Self.missTint)
                    .scaleEffect(missLanded ? 1 : 0.2)
                    .opacity(missLanded ? 1 : 0)
                ring(CGPoint(x: Self.markerX, y: Self.cruxTop), in: size, tint: Color.paper)
                    .scaleEffect(cruxLanded ? 1 : 0.2)
                    .opacity(cruxLanded ? 1 : 0)

                Text("Without Crux")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Self.missTint)
                    .position(x: Self.markerX * size.width,
                              y: (1 - Self.missTop) * size.height - 20)
                    // Rises out of the dot into its place above it, and does nothing
                    // else. Scaling a word makes it arrive from the front, which reads
                    // as a second event competing with the dot's; travelling straight up
                    // makes it the dot's own label getting out of the way of the line.
                    .offset(y: missLanded ? 0 : 20)
                    .opacity(missLanded ? 1 : 0)
            }
            // The mark back in the corner. Over the white plateau it was competing with
            // the label on the line under it for the same end of the chart; up here it
            // signs the picture instead of pointing at part of it.
            .overlay(alignment: .topLeading) {
                cruxTag
                    .padding(.top, 16)
                    .scaleEffect(cruxLanded ? 1 : 0.2, anchor: .leading)
                    .opacity(cruxLanded ? 1 : 0)
            }
        .onChange(of: active, initial: true) { _, isOn in
            if isOn { play() } else { rewind() }
        }
            // Room for the rings to be rings rather than half-circles against the edge.
            .padding(.horizontal, 7)
        }
    }

    /// The moving edge that lets a line through.
    private func wipe(_ progress: CGFloat, in size: CGSize) -> some View {
        Rectangle().frame(width: size.width * progress)
    }

    /// The red line first and alone, so the up-and-down year is the one you read before
    /// anything is offered against it. The white one then covers the same twelve months
    /// and leaves it behind — the argument made as a motion rather than as a shape you
    /// have to compare two halves of.
    ///
    /// Each line is felt as well as drawn, out of the train of knocks the profile's
    /// shudder is built from rather than out of Core Haptics: the red one light, the
    /// white one half again as strong and on a firmer generator, so the second reads as
    /// a rumble against the first's buzz. Then the landing, and the two are told apart by force — the red end is a
    /// soft tap because arriving where you started is not an event, and the Crux end is
    /// everything the phone has.
    private func play() {
        runner?.cancel()
        rewind()
        runner = Task { @MainActor in
            // Both generators built and woken before a line is drawn. A generator asked
            // to knock in the same breath it was made in gets missed — which is what
            // swallowed the whole of the first line's buzz, since it was the one with
            // nothing before it to have warmed the engine up.
            let soft = UIImpactFeedbackGenerator(style: .light)
            let firm = UIImpactFeedbackGenerator(style: .medium)
            soft.prepare()
            firm.prepare()
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: Self.missDraw)) { missDrawn = 1 }
            await rumble(soft, for: Self.missDraw, strength: 0.45)
            guard !Task.isCancelled else { return }

            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.48)) { missLanded = true }

            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: Self.cruxDraw)) { cruxDrawn = 1 }
            await rumble(firm, for: Self.cruxDraw, strength: 0.85)
            guard !Task.isCancelled else { return }

            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.46)) { cruxLanded = true }
        }
    }

    /// A held buzz made the only way the app makes one: knocks close enough together to
    /// stop being knocks.
    private func rumble(_ knock: UIImpactFeedbackGenerator,
                        for duration: TimeInterval,
                        strength: CGFloat) async {
        let beat = 40
        for _ in 0..<max(1, Int(duration * 1000) / beat) {
            knock.impactOccurred(intensity: strength)
            knock.prepare()
            try? await Task.sleep(for: .milliseconds(beat))
            if Task.isCancelled { return }
        }
    }

    private func rewind() {
        runner?.cancel()
        missDrawn = 0
        cruxDrawn = 0
        missLanded = false
        cruxLanded = false
    }

    /// A short run of the app's own tape under the chart: a tick a month, a taller one
    /// each quarter. Same two-point rounded ticks at the same two weights the measure
    /// picker draws its ruler in, just cut down — a second ruler with manners of its own
    /// would be a second ruler.
    private var tape: some View {
        Canvas { context, size in
            let months = 12
            // Inset by the half-width of a tick so the first and last are whole.
            let span = size.width - 2
            for month in 0...months {
                let x = 1 + span * CGFloat(month) / CGFloat(months)
                let major = month % 3 == 0
                context.fill(
                    Path(roundedRect: CGRect(x: x - 1, y: 0, width: 2,
                                             height: major ? 11 : 6),
                         cornerRadius: 1),
                    // Down at the gridlines' level. The picker's tape is the thing you
                    // are reading; this one is the paper under a chart, and at the
                    // weight it was borrowed at it was louder than the dashes it sits
                    // beneath.
                    with: .color(Color.paper.opacity(major ? 0.15 : 0.08)))
            }
        }
        .frame(height: 11)
        // The same inset the lines are drawn in, so month twelve on the tape is under
        // where the lines run off the page.
        .padding(.horizontal, 7)
    }

    /// The mark, given a face rather than a flat fill — the app already has this in
    /// `metal`, which is what the rank badges are drawn in, so the logo picks up the
    /// same light everything else in the app is lit by.
    private var cruxTag: some View {
        HStack(spacing: 7) {
            CruxMark()
                .fill(.metal(Color.paper))
                .overlay {
                    CruxMark()
                        .stroke(Color.white.opacity(0.5), lineWidth: 0.75)
                }
                .frame(width: 21, height: 21)
                .shadow(color: .black.opacity(0.55), radius: 5, y: 2)
            Text("Crux")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.paper)
        }
    }

    private func ring(_ point: CGPoint, in size: CGSize, tint: Color) -> some View {
        Circle()
            .fill(tint)
            .frame(width: 9, height: 9)
            .position(Self.place(point, in: size))
    }

    private static func place(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
    }

    /// A Catmull-Rom spline through the points, converted to the cubics `Path` draws.
    ///
    /// This used to hold the tangent flat at every point, which is easy and wrong: it
    /// makes each segment an S that arrives and leaves horizontally, so a steady rise
    /// comes out as a staircase of little waves and a plateau arrives at a corner. A
    /// Catmull-Rom takes each point's direction from its neighbours instead, which is
    /// what rounds the shoulder where the climb levels off — the shape the reference
    /// has and the reason its line looks drawn rather than plotted.
    private static func line(_ points: [CGPoint], in size: CGSize) -> Path {
        let mapped = points.map { place($0, in: size) }
        var path = Path()
        guard let first = mapped.first, mapped.count > 1 else { return path }
        path.move(to: first)
        for index in 0..<(mapped.count - 1) {
            // The ends have no neighbour beyond them, so they stand in for their own.
            let before = mapped[max(index - 1, 0)]
            let start = mapped[index]
            let end = mapped[index + 1]
            let after = mapped[min(index + 2, mapped.count - 1)]
            path.addCurve(
                to: end,
                control1: CGPoint(x: start.x + (end.x - before.x) / 6,
                                  y: start.y + (end.y - before.y) / 6),
                control2: CGPoint(x: end.x - (after.x - start.x) / 6,
                                  y: end.y - (after.y - start.y) / 6))
        }
        return path
    }

    private static func area(_ points: [CGPoint], in size: CGSize) -> Path {
        var path = line(points, in: size)
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}

/// The Crux mark: the open C, traced straight off the logo's own path so it is the
/// logo rather than an impression of it.
struct CruxMark: Shape {
    func path(in rect: CGRect) -> Path {
        // The artwork's own box, so the numbers below are the ones in the file.
        let scale = min(rect.width / 1409, rect.height / 1421)
        let originX = rect.midX - 1409 * scale / 2
        let originY = rect.midY - 1421 * scale / 2
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }

        var path = Path()
        path.move(to: at(0, 710.5))
        path.addCurve(to: at(710.5, 0), control1: at(0, 318.102), control2: at(318.102, 0))
        path.addLine(to: at(1409, 0))
        path.addLine(to: at(1080.99, 376.824))
        path.addLine(to: at(749.193, 376.824))
        path.addCurve(to: at(399.696, 726.321),
                      control1: at(556.171, 376.824), control2: at(399.696, 533.299))
        path.addCurve(to: at(749.193, 1075.82),
                      control1: at(399.696, 919.343), control2: at(556.171, 1075.82))
        path.addLine(to: at(1080.99, 1075.82))
        path.addLine(to: at(1409, 1421))
        path.addLine(to: at(710.5, 1421))
        path.addCurve(to: at(0, 710.5), control1: at(318.102, 1421), control2: at(0, 1102.9))
        path.closeSubpath()
        return path
    }
}
