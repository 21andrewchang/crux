import AVFoundation
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

    @State private var index = 1 // TEMP
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
        /// The note itself, rebuilt and played rather than photographed.
        case log
        /// The review page itself, rebuilt and played rather than photographed.
        case review
        /// The attempt's own player, running a real clip.
        case clip
        case curve
    }

    /// Four slides, and the order is the argument: the journal, what you learn off one
    /// go of it, what you learn off a whole session of it, and the grade that was the
    /// point of all of it. It opens on what the app *is* and closes on what it is
    /// *for* — the promise is the last thing on screen before the questions start,
    /// which is where a promise is worth most.
    ///
    /// The clip runs second rather than third because it is the one slide that moves
    /// on its own, and a page that moves is worth spending early: it comes while
    /// somebody is still deciding whether to keep tapping, not after they have decided.
    ///
    /// Verb-first, the way the ones worth copying are: reach, analyze, learn. The verb
    /// is what the user does, not what the app does — nobody wants a feature, they want
    /// the thing on the other side of it.
    private static let slides = [
        // "The", not "a": a positioning line that concedes it is one of many is not a
        // positioning line. And the sport is named because that is the differentiator
        // doing the work — a journal that knows your goals could be any notes app.
        Slide(headline: "The bouldering journal that knows your goals", art: .log),
        Slide(headline: "Learn technique faster by reviewing your clips", art: .clip),
        Slide(headline: "Analyze your training load and track progress", art: .review),
        // No "with Crux" on the end. Slide one already said whose journal this is, and
        // the closer is the one line that should be about them and not about us — the
        // shortest and hardest of the four, with the chart under it doing the arguing.
        Slide(headline: "Reach your dream grade with consistent growth", art: .curve),
    ]

    private var isLast: Bool { index == Self.slides.count - 1 }

    /// Whether the slide on screen is the one that runs edge to edge.
    private var isClip: Bool {
        if case .clip = Self.slides[index].art { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $index) {
                ForEach(Array(Self.slides.enumerated()), id: \.offset) { position, slide in
                    page(slide, active: position == index).tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Down to the glass — the pager's own frame only. A page view controller
            // clips its pages, so a slide cannot reach past the box it is handed
            // however loudly it ignores the inset; the box itself has to be the whole
            // screen first. Nothing else on any slide moves for it, because the pages
            // inside are still laid out with the bar's room set aside: what changes
            // is only that a page which does ignore it now has somewhere to go.
            .ignoresSafeArea(edges: .bottom)
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
                // Over the art, not under it. The clip runs up into this block on
                // purpose and is fully black where it does; the words have to be the
                // thing drawn on that black rather than the thing behind it.
                .zIndex(1)
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
        case .log: fitted(LogSlide.crop) { LogSlide(active: active) }
        case .review: fitted(ReviewSlide.crop) { ReviewSlide(active: active) }
        // The only slide that takes the whole page: no side padding, no room held for
        // the footer, and the bottom safe area given back to the footage.
        case .clip:
            ClipSlide(active: active)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// A rebuilt slide, laid into the very box its crop used to take.
    ///
    /// The component is built at the screenshot's own dimensions and then scaled to
    /// fit, rather than laid out against whatever the phone hands it. That is the whole
    /// trick, and it is what keeps a live slide landing where the picture did: every
    /// gap on it is a fixed number of points in the shot's own coordinates, so a wider
    /// phone gets a larger copy of the same picture instead of a differently spaced
    /// one — which is exactly what `scaledToFit` was already doing to the JPEG.
    private func fitted<Content: View>(_ crop: CGSize,
                                       @ViewBuilder content: () -> Content) -> some View {
        // Built before the reader rather than inside it: a non-escaping builder cannot
        // be carried into one.
        let slide = content()
        return GeometryReader { proxy in
            let scale = min(proxy.size.width / crop.width, proxy.size.height / crop.height)
            slide
                .frame(width: crop.width, height: crop.height, alignment: .topLeading)
                .scaleEffect(scale)
                // Scaling does not change what the view is laid out as, so it is put
                // back into the full box afterwards to centre the way the shot does.
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, Self.footerRoom)
    }

    /// What the button and its padding take off the bottom of the page.
    static let footerRoom: CGFloat = 76

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
                    .font(.headline.weight(.bold))
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
                // Off over the clip. The ground under the button exists to keep words
                // readable over a screenshot that runs behind them; the clip slide has
                // no screenshot to read — it has footage that is supposed to reach the
                // bottom of the phone, and painting it black to seat a button that is
                // already an opaque white capsule would be spending the whole idea to
                // buy something that was never needed.
                .opacity(isClip ? 0 : 1)
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

/// The clip page, playing.
///
/// The other two slides are the app's own layout rebuilt to the point; this one is the
/// app's own player, running the real thing — `PlayerSurface` over `FilmstripScrubber`,
/// the same two views the attempt page is made of, with a bar copied off its playbar.
/// There was never a version of this worth faking: the argument the headline makes is
/// that a note is worth more when it is pinned to the second it is about, and the only
/// way to make that argument is to let someone watch the playhead walk into one.
///
/// Full-bleed rather than boxed, unlike the crop it replaces. A clip in a rounded card
/// is a picture of a video; a clip running to all three edges is the video, and the
/// page it is on becomes the player rather than a page with a player on it. The top
/// edge is the only one that needs handling, and it is handled by having no edge: the
/// footage fades up into the same black the headline sits on, so there is no line for
/// the eye to catch on and nothing to say where the crop stops.
private struct ClipSlide: View {
    let active: Bool

    /// Where the clip starts and stops — the back half of the take, which is the half
    /// with the catch in it. It runs to the last frame on purpose: a note is on screen
    /// for exactly the stretch its clip covers, so ending on the clip is what leaves
    /// the words up rather than blinking them off two frames before the video stops.
    private static let words = "caught with bent arms"

    /// The catch, to the second: he swings into frame at two, latches at two and a
    /// half, and the take runs on for another five and a half after that. Which is
    /// what a real clip is — a stretch somebody marked out of a video that was longer
    /// than the thing worth marking, and the reason the words are worth pinning to a
    /// second rather than to a video. Written down rather than worked out of the
    /// duration, because it is a moment in the footage and not a fraction of it.
    private static let clip = ClipMark(start: 2.15, end: 3.6)

    /// A note is on screen for exactly the stretch its clip covers — that is what a
    /// clip *is*, and the reason the words are worth pinning to a second rather than
    /// to a video. So it closes with the clip, well before the take runs out.
    private var showsNote: Bool { time >= Self.clip.start - 0.02 && time <= Self.clip.end }

    /// How far the footage fades up into the page, and how far it is pushed up under
    /// the headline to have that far to fade over. The fade runs most of the way to the
    /// words: what it is hiding is not an edge but the fact that there is one, and the
    /// shorter the run, the more the top of the video reads as a horizon.
    private static let fade: CGFloat = 350
    private static let lift: CGFloat = 150

    private static let url = Bundle.main.url(forResource: "introClip", withExtension: "mp4")

    @State private var player = AVPlayer()
    @State private var time: TimeInterval = 0
    /// The file's own length, and what the strip is laid out against until it has been
    /// asked for it.
    @State private var duration: TimeInterval = 5
    @State private var isPlaying = false
    @State private var ticker: Any?

    /// Up for exactly the stretch its clip covers, which is what the attempt page does
    /// with a note and the whole reason a note is worth pinning to a second.
    ///
    /// Read off the clock rather than latched, so the last frame takes it away with it
    /// and the next lap brings it back: the arrival is the thing being shown, and a
    /// note that stayed up through the replay would leave nothing to arrive.

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .top) {
                PlayerSurface(player: player)
                fade
            }
            // Down to the physical bottom of the phone, past the home indicator: the
            // footage is the page here, and a strip of black under it would read as
            // the video having been laid on top of one.
            //
            // Both halves are needed. The pager had to be given the whole screen
            // first, because a page view controller clips its pages and nothing
            // inside one can reach past that however loudly it ignores the inset;
            // and then the inset still has to be ignored here, because a page that
            // covers the glass is still laid out with the bar's room set aside.
            // And up past the top of the space the page left it, in under the
            // headline. The lift costs nothing, because everything it takes is
            // covered by the black end of the fade — what it buys is a longer run to
            // fade over, which is the only thing that decides whether the footage
            // arrives out of the page or against it.
            .ignoresSafeArea(edges: .bottom)
            .padding(.top, -Self.lift)
            .allowsHitTesting(false)

            playbar
                .padding(.horizontal, 16)
                // Clear of the Continue button by the same gap the button keeps from
                // the foot of the page. Measured from the page's own bottom, which is
                // still the safe one — the footage goes under the bar, the bar's
                // furniture does not.
                .padding(.bottom, IntroView.footerRoom + 20)
        }
        .animation(.smooth(duration: 0.3), value: showsNote)
        // The note landing is the moment the whole slide is built around, and it is
        // the one thing on it the phone can say out loud. Everything the generator
        // has: the intro's other knocks are taps and rumbles, so the hardest one in
        // it belongs to the only event that is a hit.
        .onChange(of: showsNote) { _, isUp in
            guard isUp else { return }
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
        }
        .task { await load() }
        .onChange(of: active, initial: true) { _, isOn in
            if isOn { play() } else { rewind() }
        }
        .onReceive(player.publisher(for: \.timeControlStatus)) { isPlaying = $0 == .playing }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            guard active else { return }
            // The clock is put back by hand rather than waited for: the observer's
            // next tick is a thirtieth of a second away, and the note would otherwise
            // still be on screen over the first frame of the replay.
            time = 0
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player.play()
        }
    }

    /// Black to nothing, eased rather than ruled.
    ///
    /// A two-stop linear gradient is linear in alpha, and alpha is not what the eye
    /// reads: a straight ramp gives up its black too fast at the top and then crawls,
    /// which shows as a soft band across the middle of the fade and a visible line
    /// where it finally lets go. These stops hold the black longer and let the last of
    /// it off gently, which is the same curve a lens falls off with.
    private var fade: some View {
        LinearGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black.opacity(0.985), location: 0.30),
            .init(color: .black.opacity(0.92), location: 0.44),
            .init(color: .black.opacity(0.80), location: 0.56),
            .init(color: .black.opacity(0.62), location: 0.66),
            .init(color: .black.opacity(0.42), location: 0.76),
            .init(color: .black.opacity(0.24), location: 0.85),
            .init(color: .black.opacity(0.10), location: 0.93),
            .init(color: .black.opacity(0.03), location: 0.97),
            .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .frame(height: Self.fade)
    }

    // MARK: - The bar

    /// The attempt page's own playbar: the note the playhead is passing, the strip of
    /// frames under it, and the line. Nothing on it takes a touch — this is the bar
    /// being demonstrated, and a filmstrip that scrubbed under the thumb would fight
    /// the page turn it is sitting in the middle of.
    private var playbar: some View {
        VStack(spacing: 8) {
            if showsNote {
                HStack(spacing: 10) {
                    Text(NoteTimestamp.display(for: Self.clip.start))
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(Self.words)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            }

            FilmstripScrubber(videoURL: Self.url,
                              duration: duration,
                              time: time,
                              isPlaying: isPlaying,
                              bookmarks: [Self.clip])
                .frame(height: 32)

            HStack(spacing: 12) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 24, height: 30)
                line
            }
            .frame(height: 48)
        }
        .foregroundStyle(.white)
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .allowsHitTesting(false)
    }

    /// The white line walking into the clip: filled to the playhead, faint past it,
    /// with the note's bubble sitting over the middle of the stretch it covers. It is
    /// the one thing on the slide that says what is about to happen before it happens.
    private var line: some View {
        GeometryReader { geo in
            let span = max(duration, 0.01)
            let progress = min(max(time / span, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.35))
                    .frame(height: 8)
                Capsule().fill(.white)
                    .frame(width: max(8, progress * geo.size.width), height: 8)
                let centre = min(max(min(max(Self.clip.centre / span, 0), 1) * geo.size.width, 5.5),
                                 geo.size.width - 5.5)
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.systemYellow))
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                    .frame(width: 26, height: 34)
                    .offset(x: centre - 13)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .frame(height: 34)
    }

    // MARK: - Running it

    private func load() async {
        guard let url = Self.url, player.currentItem == nil else { return }
        let asset = AVURLAsset(url: url)
        if let length = try? await asset.load(.duration).seconds, length.isFinite, length > 0 {
            duration = length
        }
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        // Silent, and silent the way a video with no soundtrack is silent: the file
        // carries no audio at all, so nothing here can duck what the phone is already
        // playing.
        player.isMuted = true
        // Round and round. A take is three seconds long and the whole point of having
        // it on a page is that it is watchable more than once — that is what reviewing
        // a clip *is*, and a video frozen on its last frame is the one thing on this
        // slide that would say otherwise. The note it wrote does not go round with it.
        player.actionAtItemEnd = .none
        if active { play() }
    }

    private func play() {
        guard player.currentItem != nil else { return }
        // Woken here rather than at the moment it is needed: a generator asked to
        // knock in the same breath it was made in gets missed, and this is the one
        // knock on the slide that cannot be.
        UIImpactFeedbackGenerator(style: .heavy).prepare()
        if ticker == nil {
            ticker = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1.0 / 30, preferredTimescale: 600),
                queue: .main
            ) { stamp in time = stamp.seconds }
        }
        time = 0
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    private func rewind() {
        player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        time = 0
    }
}

/// The note itself, rebuilt and played rather than photographed.
///
/// The crop this replaces was a real session's note, and it is reproduced here in the
/// shot's own coordinates: 3× off a 402-point phone with ten points trimmed from each
/// side, which is why the text column starts at 6 rather than at the note's own 16.
/// Every metric under it is the app's own — `AttemptRowView`'s 64-point row, its
/// 12-point card padding, the 46-point video squared off the two lines beside it — so
/// this is the note's layout run again rather than a drawing of it.
///
/// What it plays is the loop the headline is claiming: the session filling up. One
/// attempt is already there when the slide arrives, because a page that starts empty
/// reads as an app with nothing in it; the second and third land one at a time, the
/// count in the heading keeping up with them; and then the second opens to show what
/// was written under it, which is the part a screenshot can never argue — that the
/// notes are the point and the video is only where they hang.
private struct LogSlide: View {
    let active: Bool

    /// The crop's own size in points, which is the canvas everything below is placed on.
    static let crop = CGSize(width: 1146.0 / 3, height: 1433.0 / 3)

    /// The note's text column, once the crop has taken ten points off each side.
    private static let inset: CGFloat = 6

    /// The app's own row metrics, borrowed rather than re-guessed.
    private static let cardFill = Color(white: 0.06)
    private static let cardRadius: CGFloat = 14
    private static let cardPadding = AttemptRowView.cardPadding
    private static let rowHeight = AttemptAttachment.rowHeight
    /// The video is squared off the name and the rating beside it: one line of 16-point
    /// semibold, the 6-point gap under it, and the tag's own height.
    private static let thumbSide: CGFloat = 46

    /// Where the three cards sit, measured off the shot: the heading's name, the climb
    /// line under it, and the top of the first card.
    private static let titleTop: CGFloat = 10.1
    private static let climbTop: CGFloat = 11.67
    private static let cardsTop: CGFloat = 8.97
    private static let cardGap: CGFloat = 8.5
    /// What the bottom bar clears the foot of the crop by.
    private static let barBottom: CGFloat = 13

    /// One attempt as the slide tells it.
    private struct Take {
        let ordinal: Int
        let effort: Effort
        let thumbnail: String
        /// What is written under it — shown once the row opens, counted behind the
        /// length until then.
        let notes: [(text: String, stamp: String)]
    }

    private static let takes: [Take] = [
        Take(ordinal: 1, effort: .hard, thumbnail: "introThumb1", notes: []),
        Take(ordinal: 2, effort: .limit, thumbnail: "introThumb2",
             notes: [("left knee hit wall", "0:03"), ("left hand still holding on", "0:04")]),
        Take(ordinal: 3, effort: .limit, thumbnail: "introThumb3", notes: []),
    ]

    /// How many of the three have landed, and whether the second has opened.
    @State private var landed = 1
    @State private var opened = false
    /// When the rest on the bar runs out. Set when the slide arrives, so the countdown
    /// is running by the time it is looked at.
    @State private var restEnds = Date()
    @State private var runner: Task<Void, Never>?

    /// A rest the app itself offers, rather than the four seconds the shot happened to
    /// catch: a countdown that would hit zero halfway through the slide would need
    /// somewhere to go afterwards, and there is nothing on a slide for it to go to.
    private static let rest: TimeInterval = 120

    private static let landing: TimeInterval = 0.62
    private static let opening: TimeInterval = 0.8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
                .padding(.top, Self.titleTop)
            climb
                .padding(.top, Self.climbTop)
            cards
                .padding(.top, Self.cardsTop)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.inset)
        .frame(width: Self.crop.width, height: Self.crop.height, alignment: .topLeading)
        .overlay(alignment: .bottom) { bar.padding(.bottom, Self.barBottom) }
        .onChange(of: active, initial: true) { _, isOn in
            if isOn { play() } else { rewind() }
        }
    }

    // MARK: - The two headings

    /// The section the climb is filed under, with its own fold arrow a step past the
    /// name — the section heading's chevron sits with the words rather than out at the
    /// margin, because a section has nothing else on its line.
    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: SectionChevron.gap) {
            Text("Project")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(Color(uiColor: .label))
            Image(systemName: "chevron.down")
                .font(.system(size: SectionChevron.pointSize, weight: .semibold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                // Centred on the name's capitals rather than on its baseline, which is
                // where the note draws it.
                .alignmentGuide(.firstTextBaseline) { $0.height * 0.72 }
        }
        .frame(height: 25)
    }

    /// The climb: its hold colour as a dot and as the name's own ink, with the tally of
    /// what is filed under it out at the trailing edge. The count is the one word on
    /// the slide that keeps up with the animation — a heading reading "3 attempts" over
    /// one card would give the game away before the other two arrive.
    private var climb: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color(uiColor: .systemBlue).opacity(NoteDocument.headerTintAlpha))
                .frame(width: ClimbHeaderLayoutFragment.dotSide,
                       height: ClimbHeaderLayoutFragment.dotSide)
                .padding(.leading, ClimbHeaderLayoutFragment.dotLead)
                .padding(.trailing, 6)

            Text("Blue V8")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(uiColor: .systemBlue).opacity(NoteDocument.headerTintAlpha))

            Spacer(minLength: 8)

            Text(landed == 1 ? "1 attempt" : "\(landed) attempts")
                .font(.system(size: 13))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .contentTransition(.numericText())
                .padding(.trailing, 8)
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .frame(width: HeadingChevron.side)
        }
        .frame(height: 18)
    }

    // MARK: - The cards

    /// The three of them, appearing in the order they were climbed in. Held together by
    /// `if` rather than by opacity, so the stack is genuinely shorter before the third
    /// arrives and genuinely taller once the second opens — the card below being pushed
    /// down is what makes the opening read as the note growing rather than as a panel
    /// being swapped in.
    private var cards: some View {
        VStack(spacing: Self.cardGap) {
            ForEach(Array(Self.takes.enumerated()), id: \.offset) { position, take in
                if position < landed {
                    card(take, open: position == 1 && opened)
                        .transition(.offset(y: 14).combined(with: .opacity))
                }
            }
        }
    }

    private func card(_ take: Take, open: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            row(take, open: open)
            if open {
                notes(take)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.cardFill, in: .rect(cornerRadius: Self.cardRadius, style: .continuous))
    }

    private func row(_ take: Take, open: Bool) -> some View {
        HStack(spacing: AttemptRowView.labelGap) {
            VStack(alignment: .leading, spacing: AttemptRowView.lineGap) {
                Text("Attempt \(take.ordinal)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .label))

                HStack(spacing: 8) {
                    pill(take.effort)
                    meta("play.fill", "0:08", glyph: 10, tint: Color(uiColor: .secondaryLabel))
                    if !take.notes.isEmpty || take.ordinal != 2 {
                        meta("bubble.left.fill", "\(max(1, take.notes.count))",
                             glyph: 11, tint: Color.yellow.opacity(0.55))
                            // Written out below, the count has nothing left to stand
                            // for: it slides back behind the length it came out from
                            // rather than blinking off the line.
                            .opacity(open ? 0 : 1)
                            .offset(x: open ? -26 : 0)
                    }
                }
                .frame(height: TagPillLabel.height)
            }

            Spacer(minLength: 0)

            Image(take.thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: Self.thumbSide, height: Self.thumbSide)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                }
        }
        .padding(.horizontal, Self.cardPadding)
        .frame(height: Self.rowHeight)
    }

    /// The rating, and then the run of details after it, each behind the mark that says
    /// what it is — the row's own way of writing a number down.
    private func pill(_ effort: Effort) -> some View {
        Text(effort.label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(effort.color)
            .padding(.horizontal, 9)
            .frame(height: TagPillLabel.height)
            .background(effort.color.opacity(0.22), in: .capsule)
    }

    private func meta(_ symbol: String, _ text: String,
                      glyph: CGFloat, tint: Color) -> some View {
        HStack(spacing: 3.5) {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
    }

    /// What was written under the row, on the row's own ground so the two read as one
    /// card. Each line arrives after the card has finished opening for it, in the order
    /// they were written.
    private func notes(_ take: Take) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(take.notes.enumerated()), id: \.offset) { position, note in
                HStack(spacing: 0) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(uiColor: .systemYellow))
                        .frame(width: 30.2, alignment: .leading)
                    Text(note.text)
                        .font(.system(size: Self.quote))
                        .foregroundStyle(Color(uiColor: .label))
                    Spacer(minLength: 8)
                    Text(note.stamp)
                        .font(.system(size: Self.quote))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                .frame(height: 33)
            }
        }
        // Where the shot has them: the mark stands a little inside the name above it,
        // since the note's own bookmarks are laid out in the text container rather
        // than in the card.
        .padding(.leading, 17.2)
        .padding(.trailing, Self.cardPadding)
        .padding(.top, 2.7)
        .padding(.bottom, 3)
    }

    /// The note's quote size, pinned for the same reason the review slide pins its own.
    private static let quote: CGFloat = 17

    // MARK: - The bar

    /// The real bottom bar, at the real bar's own metrics: 28 points in from the screen
    /// edge — 18 once the crop has taken its ten — 48-point capsules, and the three
    /// marks in slots the system sizes for it.
    private var bar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(["textformat.size", "plus", "video.fill"], id: \.self) { name in
                    barGlyph(name)
                        .frame(width: barSlotWidth(name), height: 48)
                }
            }
            .glassEffect(.regular, in: .capsule)

            Spacer(minLength: 0)

            rest
        }
        .padding(.horizontal, 18)
    }

    /// The rest, running. It is the one thing on the page the app is doing rather than
    /// showing — the reason the bar has a clock on it at all is that the minutes between
    /// goes are part of the session, and a still of a stopped clock says the opposite.
    private var rest: some View {
        HStack(spacing: 0) {
            barGlyph("timer")
                .frame(width: 48)
            ZStack {
                // The same sizing twin the real face carries: the longest label it can
                // ever show, holding the capsule at one width so no digit moves it.
                Text("10:00")
                    .font(Self.faceFont)
                    .hidden()
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text(max(0, restEnds.timeIntervalSince(context.date)).clockString)
                        .font(Self.faceFont)
                }
                .fixedSize()
            }
            .padding(.trailing, 14)
        }
        .frame(height: 48)
        .glassEffect(.regular, in: .capsule)
    }

    private static let faceFont = Font.system(size: 19, weight: .semibold).monospacedDigit()

    // MARK: - Playing it

    /// One attempt, then the next, then the next, and then the second one opens.
    ///
    /// The order is the argument: two goes go by before anything is read back, which is
    /// how a session actually runs — you climb, you climb again, and the note is what
    /// you have afterwards. Each landing knocks lightly, the way the app knocks when a
    /// go is saved; the opening does not, because nothing was logged by it.
    private func play() {
        rewind()
        restEnds = Date().addingTimeInterval(Self.rest)
        runner = Task { @MainActor in
            let knock = UIImpactFeedbackGenerator(style: .light)
            knock.prepare()

            for step in 2...3 {
                try? await Task.sleep(for: .seconds(Self.landing))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { landed = step }
                knock.impactOccurred(intensity: 0.5)
                knock.prepare()
            }

            try? await Task.sleep(for: .seconds(Self.opening))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) { opened = true }
        }
    }

    private func rewind() {
        runner?.cancel()
        landed = 1
        opened = false
    }
}

/// The review page, rebuilt and played rather than photographed.
///
/// The crop this replaces was a real session's review, and every number on it is kept
/// to the digit: an hour and a half, twelve problems, twenty-four goes, and the four
/// effort words underneath in the shape that session actually had. It is laid out in
/// the crop's own coordinates — the shot was taken at 3× off a 402-point phone with six
/// points trimmed from each side, which is why the page padding here reads 14 rather
/// than the 20 the real page uses. The slide then scales that whole picture to fit, so
/// it lands where the JPEG landed on any phone.
///
/// The bars are the reason to have bothered. A screenshot of a bar chart is a fact you
/// are asked to take; a bar running out to its number in front of you is the session
/// being counted, which is the thing the headline is claiming the app does. They fill
/// left to right and one after another down the four words, so it reads as a tally
/// being added up rather than as four things going off at once — and the count on the
/// right climbs with its own bar, because a number that was already final would give
/// away the end of a sentence still being spoken.
private struct ReviewSlide: View {
    /// Whether this is the slide on screen. Same contract as the chart's: it plays on
    /// arrival and winds back on the way out, so coming back to it plays again rather
    /// than finding it already counted.
    let active: Bool

    /// The crop's own size in points, which is the canvas everything below is placed on.
    static let crop = CGSize(width: 1169.0 / 3, height: 1462.0 / 3)

    /// What the real page's 20 points of padding comes to once the crop has taken six
    /// off each side.
    private static let inset: CGFloat = 14

    /// The two text styles the real page uses, pinned to points instead of asked for by
    /// name. Everything here is laid out on a canvas of a fixed size and then scaled
    /// into the page, so a reader who has turned their text up would otherwise get the
    /// same picture with the words grown inside it — cards a different height, bars a
    /// different length, and a slide that no longer matches the three around it. The
    /// sizes are the ones the shot was taken at, which was a phone set two steps up;
    /// scaled down into the slide they land back at about the size they read as here.
    private static let footnote: CGFloat = 17
    private static let subheadline: CGFloat = 19

    /// The session on the slide. The peak is Easy's ten, and every bar is drawn against
    /// it rather than against its own maximum — the same way the real page does it, and
    /// the reason the shape of a session is legible at a glance.
    private static let counts: [(level: Effort, value: Int)] = [
        (.easy, 10), (.medium, 6), (.hard, 4), (.limit, 4),
    ]
    private static let peak = 10

    private static let draw: TimeInterval = 0.55
    /// The gap between one bar setting off and the next. Long enough to read as an
    /// order, short enough that all four are done inside a second and a half — the
    /// slide has to finish before a thumb that is already moving gets to it.
    private static let stagger: TimeInterval = 0.12

    /// How far along each bar is, and what its count has climbed to so far.
    @State private var filled: [Double] = [0, 0, 0, 0]
    @State private var shown: [Int] = [0, 0, 0, 0]
    /// The run in progress, so leaving the slide stops the counting as well as the bars.
    @State private var runner: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            clock
            tiles
            effort
        }
        .padding(.horizontal, Self.inset)
        // Where the crop's top edge fell relative to the "Duration" line above it,
        // measured off the shot rather than guessed: it puts every band on the page
        // within a pixel of where the picture had it.
        .padding(.top, 14.3)
        .frame(width: Self.crop.width, height: Self.crop.height, alignment: .topLeading)
        .onChange(of: active, initial: true) { _, isOn in
            if isOn { play() } else { rewind() }
        }
    }

    // MARK: - The clock

    /// Held rather than running. The real one ticks, and a clock ticking up on the
    /// slide would be the only thing on the page moving on its own after the bars have
    /// settled — a second animation with nothing to say, pulling the eye off the four
    /// lines that do.
    private var clock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: Self.footnote, weight: .medium))
                Text("Duration")
                    .font(.system(size: Self.footnote, weight: .medium))
            }
            .foregroundStyle(Color.paper.opacity(0.45))

            Text("1:28:30")
                .font(.system(size: 52, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.paper)
        }
    }

    // MARK: - The counts

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)],
                  spacing: 10) {
            tile("Climbs", "12")
            tile("Attempts", "24")
            tile("Avg rest", "4:31")
            tile("Notes", "30")
        }
    }

    private func tile(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.paper)
            Text(name)
                .font(.system(size: Self.footnote))
                .foregroundStyle(Color.paper.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface, in: .rect(cornerRadius: 16))
    }

    // MARK: - Effort

    private var effort: some View {
        VStack(spacing: 10) {
            ForEach(Array(Self.counts.enumerated()), id: \.offset) { position, row in
                effortRow(row.level, value: row.value, position: position)
            }
        }
    }

    /// A word, a bar, a number — the real row, with the bar's width run through the
    /// progress of its own arrival.
    private func effortRow(_ level: Effort, value: Int, position: Int) -> some View {
        HStack(spacing: 12) {
            Text(level.label)
                .font(.system(size: Self.subheadline))
                .foregroundStyle(Color.paper.opacity(0.85))
                .frame(width: 68, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surface)
                    Capsule()
                        .fill(level.color)
                        .frame(width: proxy.size.width
                               * Double(value) / Double(Self.peak)
                               * filled[position])
                }
            }
            .frame(height: 8)

            Text("\(shown[position])")
                .font(.system(size: Self.subheadline, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.paper.opacity(0.85))
                // The digits change width on the way up to ten; without this the count
                // would shuffle sideways under its own bar.
                .contentTransition(.numericText())
                .frame(width: 24, alignment: .trailing)
        }
    }

    // MARK: - Playing it

    /// The four bars set off down the page, each carrying its own count up with it and
    /// knocking once as it lands. Light knocks, and four of them: this is a tally being
    /// read out, not the chart's argument, and the last slide's landing has to stay the
    /// hardest thing the intro does.
    private func play() {
        rewind()
        runner = Task { @MainActor in
            let knock = UIImpactFeedbackGenerator(style: .light)
            knock.prepare()

            await withTaskGroup(of: Void.self) { group in
                for (position, row) in Self.counts.enumerated() {
                    group.addTask { @MainActor in
                        try? await Task.sleep(for: .seconds(Double(position) * Self.stagger))
                        guard !Task.isCancelled else { return }

                        withAnimation(.easeOut(duration: Self.draw)) { filled[position] = 1 }

                        // The count is stepped rather than animated, because a number
                        // is not a length: it has to land on every whole one it passes
                        // through on the way, and the bar's own easing would have it
                        // skipping some and dwelling on others.
                        let beat = Self.draw / Double(row.value)
                        for tally in 1...row.value {
                            try? await Task.sleep(for: .seconds(beat))
                            guard !Task.isCancelled else { return }
                            shown[position] = tally
                        }

                        knock.impactOccurred(intensity: 0.45)
                        knock.prepare()
                    }
                }
            }
        }
    }

    private func rewind() {
        runner?.cancel()
        filled = [0, 0, 0, 0]
        shown = [0, 0, 0, 0]
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
                ring(CGPoint(x: Self.markerX, y: Self.missTop), in: size,
                     tint: Self.missTint, landed: missLanded)
                ring(CGPoint(x: Self.markerX, y: Self.cruxTop), in: size,
                     tint: Color.paper, landed: cruxLanded)

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

    /// The scale goes on the circle, before it is placed. Put after `position` it
    /// scales the full-size box the dot is positioned *within*, and a box scaled about
    /// its own centre drags whatever is in it towards the middle of the chart — which is
    /// where the bounce across x and y was coming from. Scaled first, the dot never
    /// leaves the line it sits on; it only grows there.
    private func ring(_ point: CGPoint, in size: CGSize,
                      tint: Color, landed: Bool) -> some View {
        Circle()
            .fill(tint)
            .frame(width: 9, height: 9)
            .scaleEffect(landed ? 1 : 0.2)
            .opacity(landed ? 1 : 0)
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
