import SwiftUI

/// The profile as a card you turn over, rather than a screen you go to.
///
/// A card because that is what the thing already is: one object, small enough to hold,
/// with the shape you climb on the front and the numbers behind it on the back. A sheet
/// would have made it a place — somewhere you navigate to and come back from — and the
/// profile is not a destination, it is something you glance at and put down.
///
/// The ground and the card answer to `isPresented` separately, the same way `EffortMenu`
/// does it: one transition over the pair scales the darkened page in along with the
/// card, which reads as the whole screen arriving rather than a card arriving on it.
struct ProfileCard: View {
    let isPresented: Bool
    /// Tapping the page around the card puts it down. There is no close mark on the
    /// card itself: the corner disc is the turn, and a card this size with a way out
    /// in every corner is more chrome than card.
    var onDismiss: () -> Void

    /// The arrival: almost all of the distance covered in the first third of the time,
    /// then a long settle. An ease-out curve rather than a spring — a spring's speed is
    /// a consequence of its stiffness, so making one arrive fast makes it overshoot,
    /// and every attempt to damp that out slows the start again. A curve lets the start
    /// be quick and the end be soft without the two arguing.
    /// Quintic ease-out. Fast, and with a start you can actually see: the previous
    /// curve put most of the distance into the first few frames, which the eye reads as
    /// a cut rather than a move — a thing that fast has no beginning, it is simply
    /// somewhere else. Pulling the first handle out gives the launch a moment to exist
    /// while leaving the long smooth stop alone.
    private static let entrance = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.46)

    /// How far below its resting place the card starts.
    ///
    /// Set as a distance rather than left to `.move(edge:)`, which travels the whole
    /// height of the screen. Over that distance almost all of an ease-out is spent in
    /// the tail, so what you actually see is the slow end of the curve and the card
    /// reads as drifting up and stopping. Travelling only its own height puts the fast
    /// part of the curve inside the visible run: it arrives quickly and the deceleration
    /// is something that happens on screen rather than off it.
    private static let travel: CGFloat = 480

    /// Putting it down is not an event. An exit that takes as long as the arrival makes
    /// the page you asked for wait on an animation you have already stopped watching,
    /// so this is roughly a third of it and out of the way.
    private static let exit = Animation.easeOut(duration: 0.12)

    /// How far off square the card starts, in degrees. Turned away to the left and
    /// swinging flat as it rises — enough to have a face that catches the light on the
    /// way in, not so much that it reads as a flip.
    private static let entranceTilt: Double = 26

    /// How far through the turn the card is, in degrees. One value drives everything:
    /// the rotation of both faces and which of them can be seen. The earlier version
    /// swapped the faces on a timer set to roughly half the animation, which is what
    /// put the front face on screen mirrored — a spring has no reliable midpoint in
    /// time, so the only thing that knows where the card actually is, is the angle.
    @State private var angle: Double = 0
    /// How far the finger currently on the card has turned it, on top of `angle`. Kept
    /// apart from it so letting go can settle from wherever the drag left off without
    /// the two having to be reconciled first.
    @State private var dragAngle: Double = 0

    /// The card is one size whichever way up it is. Sized here rather than by whichever
    /// face happens to be taller, or the panel resizes mid-turn — which is the stretch.
    private static let cardHeight: CGFloat = 468

    /// Shallow. A strong perspective foreshortens hard at the quarter turn, and on a
    /// panel this tall that reads as the card being squeezed rather than turned.
    private static let perspective: CGFloat = 0.22

    private static let turn = Animation.spring(response: 0.6, dampingFraction: 0.86)

    /// The arrival: quick off the mark and slow to settle. A spring with the damping up
    /// near one has no bounce left in it, which is what makes a fast start read as the
    /// card being thrown rather than sprung.


    /// How long the page takes to go down — slower than the card's arrival, so the card
    /// is what the eye follows.
    private static let dim: TimeInterval = 0.12

    var body: some View {
        ZStack {
            scrim

            // Between the dark and the card: over the blurred page rather than in it,
            // so it stays sharp while everything behind it softens, and it comes and
            // goes on the card's own clock rather than the page's.
            rankGlow

            ZStack {
                if isPresented { card }
            }
            .animation(isPresented ? Self.entrance : Self.exit, value: isPresented)
        }
        .ignoresSafeArea()
        .allowsHitTesting(isPresented)
        // In on the turn, out flat.
        //
        // Found by accident: reopening a card left face-down animated the angle back to
        // zero at the same time as the rise, and the card came up spinning. Worth
        // keeping and worth doing on purpose — it arrives as an object being flipped
        // into your hand rather than a panel being shown, and it lands square whichever
        // way up it was put down.
        .onChange(of: isPresented) { _, up in
            guard up else { angle = 0; return }
            angle = -Self.entranceTilt
            withAnimation(Self.entrance) { angle = 0 }
        }
    }

    /// The rank light, across the very bottom of the glass — home indicator and all,
    /// since the parent ignores the safe area and this is aligned to the bottom of that
    /// rather than of the content.
    ///
    /// Only up while the card is. It is the light the card was brought out under, not a
    /// permanent feature of the app, and a coloured wash sitting at the foot of the
    /// session list all day would be decoration that has to be explained.
    private var rankGlow: some View {
        EllipticalGradient(
            colors: [ProfileView.rankTint.opacity(0.34),
                     ProfileView.rankTint.opacity(0.10),
                     .clear],
            center: .bottom,
            startRadiusFraction: 0,
            endRadiusFraction: 0.85)
            .frame(height: 320)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .blendMode(.plusLighter)
            .opacity(isPresented ? 1 : 0)
            .animation(isPresented ? Self.entrance : Self.exit, value: isPresented)
            .allowsHitTesting(false)
    }

    private var scrim: some View {
        // Lighter than it was: the blur under it is now doing most of the work of
        // separating the card from the page, and the two stacked read as pitch.
        Color.black.opacity(isPresented ? 0.5 : 0)
            .ignoresSafeArea()
            .contentShape(.rect)
            .onTapGesture(perform: onDismiss)
            .animation(.easeInOut(duration: Self.dim), value: isPresented)
    }

    /// The whole object turns, not the picture on it.
    ///
    /// Both sides are mounted at all times and the pair is rotated together, so the
    /// glass, the corners and the shadow travel with the contents — a card whose panel
    /// stayed still while its face swapped over would be a screen with a transition on
    /// it, which is the thing this is not. The back is pre-rotated half a turn so that
    /// when the pair is upside down it is the side reading the right way up, and each
    /// face is hidden past the quarter turn so neither is ever seen mirrored.
    private var card: some View {
        ZStack {
            face(.front)
                .modifier(Flip(angle: angle + dragAngle, isBack: false))

            face(.back)
                .modifier(Flip(angle: angle + dragAngle, isBack: true))
        }
        .gesture(spin)
        .padding(.horizontal, 24)
        // Slid in from off the bottom of the screen, at full opacity the whole way.
        //
        // The fade was the thing that made it look conjured: a card that is already
        // half-transparent in the middle of the screen never came from anywhere. Coming
        // in off the edge solid means the eye reads a real object entering the frame —
        // it was always there, it was just further down the table than you could see.
        .transition(.asymmetric(
            insertion: .offset(y: Self.travel),
            // Not the way it came. Sliding back down would say it went somewhere and
            // could be fetched again from there; shrinking away where it stands says it
            // was only ever being held up, and puts nothing on screen on the way out to
            // watch instead of the page coming back.
            removal: .scale(scale: 0.8).combined(with: .opacity)))
    }

    /// Turning the card by hand.
    ///
    /// The angle follows the finger while it is down, and on release the card carries on
    /// from wherever the flick was heading — `predictedEndTranslation` is what makes a
    /// hard swipe spin through several turns rather than stopping dead where it was let
    /// go. Whatever that comes to is rounded to the nearest half turn, so the card
    /// always settles with a face out and never edge-on.
    private static let degreesPerPoint: Double = 0.9

    private var spin: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragAngle = value.translation.width * Self.degreesPerPoint
            }
            .onEnded { value in
                let dragged = value.translation.width * Self.degreesPerPoint
                let predicted = value.predictedEndTranslation.width * Self.degreesPerPoint
                let target = ((angle + predicted) / 180).rounded() * 180
                // Fold the drag into the settled angle before animating. Zeroing
                // `dragAngle` on its own puts the card back where the finger picked it
                // up, and the animation then has to travel the whole way from there —
                // which is the full spin you get after letting go a degree short of
                // the turn. Moving the same amount out of one and into the other leaves
                // the card exactly where it is, with nothing left to undo.
                angle += dragged
                dragAngle = 0
                withAnimation(Self.turn) { angle = target }
            }
    }

    private func flip() {
        withAnimation(Self.turn) { angle += 180 }
    }

    /// One half-turn of the card, with each face's own rotation and its own visibility
    /// read off the same interpolated angle.
    ///
    /// `Animatable` is the whole point: without it SwiftUI hands this the start and end
    /// angles only, and any opacity worked out from them switches on a schedule of its
    /// own rather than at the moment the card is actually edge-on. With it, `body` runs
    /// on every frame of the turn with the angle the card is really at.
    private struct Flip: ViewModifier, Animatable {
        var angle: Double
        /// The back is the same card half a turn round, so it faces out exactly when
        /// the front does not.
        let isBack: Bool

        var animatableData: Double {
            get { angle }
            set { angle = newValue }
        }

        func body(content: Content) -> some View {
            content
                .opacity(opacity)
                .rotation3DEffect(.degrees(isBack ? angle + 180 : angle),
                                  axis: (x: 0, y: 1, z: 0),
                                  perspective: ProfileCard.perspective)
        }

        /// Out before the card is edge-on rather than at the instant it is.
        ///
        /// A hard cut exactly at the quarter turn is correct and still reads as a
        /// flicker: the last few degrees before it are a bright sliver of type that
        /// vanishes rather than turns away. Fading it over the last thirty degrees
        /// means the face is already gone by the time the card is side-on, and what
        /// comes round is the other side arriving rather than this one leaving.
        private var opacity: Double {
            let turned = ((angle.truncatingRemainder(dividingBy: 360)) + 360)
                .truncatingRemainder(dividingBy: 360)
            // How far this face is from square-on to the viewer, 0…180.
            let away = isBack ? abs(180 - turned) : min(turned, 360 - turned)
            return max(0, min(1, (90 - away) / 30))
        }
    }

    private func face(_ side: ProfileView.Face) -> some View {
        VStack(spacing: 0) {
            header
            ProfileView(isReview: true, face: side)
                .padding(.horizontal, 18)

            Spacer(minLength: 0)
        }
        // No top inset of its own: the mark in the corner sets its own distance from
        // both edges, and a padding here on top of that would only be measured from
        // one of them.
        .padding(.top, 0)
        .padding(.bottom, 18)
        .frame(maxWidth: 360)
        .frame(height: Self.cardHeight, alignment: .top)
        .background { panel }
        .shadow(color: .black.opacity(0.6), radius: 34, y: 16)
    }

    /// The card stock: dark grey lit the same way the grade is.
    ///
    /// The same `Theme.metal` ramp the numbers are set in, just run over a grey instead
    /// of a rank colour — lifted towards white at the top, let down towards black at the
    /// bottom — so the card and the grade on it are lit from the same direction. Glass
    /// was the other option and it is the wrong one here: a lens takes its colour from
    /// whatever is behind it, and a card wants to be an object in its own right.
    /// Near black, and lit like a solid.
    ///
    /// Two parts, and the second is what does the work. The fill is a very subtle
    /// gradient — a shade lighter at the top-left corner than the bottom-right, small
    /// enough that it never reads as a colour, only as the face not being flat. The
    /// edge is a hairline whose brightness runs *along the diagonal*: bright where the
    /// light catches at the top-left, almost gone across the middle, bright again at
    /// the bottom-right where it wraps. That is the difference between a border and a
    /// bevel — a stroke of one opacity all the way round reads as a drawn outline, and
    /// a stroke that brightens at two opposite corners reads as an edge with thickness.
    private static let radius: CGFloat = 30

    private static let fill = LinearGradient(
        colors: [Color(white: 0.105), Color(white: 0.062)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Light on two corners and nowhere else.
    ///
    /// Angular rather than linear, and that is the whole difference. A linear gradient
    /// brightens everything it crosses — run it corner to corner and the long vertical
    /// sides come up with it, which reads as an outline drawn round the card. Sweeping
    /// the brightness *around* the centre instead means it can be placed at an angle:
    /// a short arc at the top-left where the light lands, another at the bottom-right
    /// where it wraps off the far edge, and the sides left as dark as the fill.
    ///
    /// In SwiftUI's angles zero points right and they run clockwise, so the bottom-right
    /// corner sits at 45° (0.125 of the way round) and the top-left at 225° (0.625).
    /// The bands either side of those are deliberately tight — a wide one is just the
    /// linear version again, and the effect only reads as a reflection while most of
    /// the edge has none.
    private static let unlit = Color.white.opacity(0.03)
    private static let lit = Color.white.opacity(0.26)
    /// The bottom-right peak, kept under the top-left one. It is the corner turning
    /// away from the light rather than into it, and it already carries a tail along the
    /// bottom — matched in brightness the pair read as two lights instead of one.
    private static let litLow = Color.white.opacity(0.17)

    /// Two short glints, rolled clockwise off the corners.
    ///
    /// `roll` moves where the brightest point sits; `arc` decides how much of the edge
    /// is lit at all. They are separate on purpose — the previous version widened the
    /// band to get the light leaning the right way, which walked it down the vertical
    /// sides and turned a glint into an outline. Kept this short, the left and right
    /// edges carry nothing: the light exists at two points and dies within a few
    /// degrees of them, which is what a hard surface actually does.
    private static let roll = 0.033
    private static let arc = 0.028
    /// How far the bottom-right glint carries on along the bottom edge before it dies.
    private static let tail = 0.155
    /// What is left of the light along that tail — well under the glint itself, so the
    /// bottom reads as lit rather than as a second highlight.
    private static let glow = Color.white.opacity(0.085)

    private static let bottomRight = 0.125 + roll
    private static let topLeft = 0.625 + roll

    /// Two glints, one of which runs on.
    ///
    /// The top-left is a point and nothing more. The bottom-right is a point with a
    /// tail: the light carries left along the whole bottom edge and fades out before
    /// the corner, which is what gives the card a bottom to sit on. Only that edge gets
    /// it — a tail on both would be an outline again, and the asymmetry is the thing
    /// that reads as one light source rather than a stroke that happens to vary.
    private static let edge = AngularGradient(
        stops: [.init(color: unlit, location: 0.000),
                .init(color: unlit, location: bottomRight - arc),
                .init(color: litLow, location: bottomRight),
                .init(color: glow, location: bottomRight + tail * 0.42),
                .init(color: unlit, location: bottomRight + tail),
                .init(color: unlit, location: topLeft - arc),
                .init(color: lit, location: topLeft),
                .init(color: unlit, location: topLeft + arc),
                .init(color: unlit, location: 1.000)],
        center: .center)

    /// Whether the card carries the rank light itself. Off: the glow lives at the foot
    /// of the page instead, where it lights everything rather than one object, and two
    /// of them at once would be two light sources in one room. Kept here because the
    /// card version is the better one if the page ever loses its own.
    private static let showsGlow = true

    /// The rank colour washed down the card from its top edge.
    ///
    /// Off the top rather than the foot, so it runs the same way the light on the card
    /// does — the bright corner is up there, and a glow rising from the bottom would be
    /// a second source arguing with it. It also puts the colour behind the grade, which
    /// is the thing the colour is about.
    private var glow: some View {
        EllipticalGradient(
            colors: [ProfileView.rankTint.opacity(0.34),
                     ProfileView.rankTint.opacity(0.11),
                     .clear],
            center: .top,
            startRadiusFraction: 0,
            endRadiusFraction: 0.78)
            // Stretched a little wide and pulled in vertically, anchored to the top.
            // An ellipse fitted to the card is taller than it is broad, so it comes off
            // the top as a narrow cone down the middle — a spotlight pointed at the card
            // rather than light lying on it. Only a little wider, though: stretched far
            // enough that the curve leaves the frame, the taper goes with it and what is
            // left is a rectangle of colour with a soft bottom edge.
            .scaleEffect(x: 1.35, y: 0.82, anchor: .top)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .fill(Self.fill)
            .overlay {
                if Self.showsGlow {
                    glow.clipShape(.rect(cornerRadius: Self.radius, style: .continuous))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .strokeBorder(Self.edge, lineWidth: 1)
            }
    }

    /// Just the turn: the mark on its own, no disc under it.
    ///
    /// A filled disc is a button asking to be found. This one does not need to be —
    /// there is one other thing on the card and turning it over is the only thing to
    /// do with it — so the mark is set light grey and left to sit in the corner at the
    /// same distance from the top as from the side, which is what stops it reading as
    /// hung off either edge.
    private static let corner: CGFloat = 14

    private var header: some View {
        HStack {
            Spacer(minLength: 0)

            Button(action: flip) {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.paper.opacity(0.45))
                    .frame(width: 32, height: 32)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Self.corner)
        .padding(.trailing, Self.corner)
    }
}
