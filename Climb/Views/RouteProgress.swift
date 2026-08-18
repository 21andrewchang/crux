import SwiftUI

/// The route the loading screen draws: the boulder problem off the hold-detection
/// render, going up the wall one hold at a time from the ground.
///
/// Every hold is its own image, cut out of that render pixel for pixel, and placed back
/// at the spot it was cut from. The cut-out only carries a shape, so the shape is what
/// gets lit: `climbingHold` reads each mask's own coverage as a height, sculpts a top, a
/// shoulder and a side out of it, and puts a key light, a gloss and a rim on the result.
/// `progress` is how much of the line is up: they land in order from the bottom, and how
/// fast they land is whatever curve the caller animates that number along.
struct RouteProgress: View, Animatable {
    var progress: Double

    /// Which way the room is lit, in screen space — screen y runs down, so this points
    /// up and to the left. The holds, their shadows and the wall all agree on it.
    var light: CGVector = .init(dx: -0.48, dy: -0.62)

    /// The paint on the route. The cut-outs carry the shape and this carries the colour,
    /// so the wall can be set to any route's colour.
    var tint: Color = .routeHold

    /// Makes SwiftUI interpolate the number itself, so the holds land across the whole
    /// of the caller's animation rather than all at once at either end of it.
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// A bolt through a hold: where it is drilled, as a fraction of the cut-out, and how
    /// big, against the width of the route's box.
    ///
    /// It sits where the hold is thickest — the middle of the biggest circle that fits
    /// inside it — so a crescent takes its bolt through the meat rather than out in the
    /// gap it curls around. A hold that is really two holds touching gets one each: the
    /// picture is left whole, and only the bolts know they came apart.
    struct Bolt {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
    }

    /// One hold: the cut-out, where it sits in the route's own 0...1 box, and whatever
    /// it is drilled with. Small holds carry none.
    struct Hold {
        let name: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let bolts: [Bolt]
    }

    /// The box the holds were cut from, as height over width.
    private static let aspect: CGFloat = 1108.0 / 487.0

    /// Every bolt is the same bolt — a drill bit is one size whatever it goes through —
    /// so the stored radius only decides *whether* a hold is drilled, never how big the
    /// hole is. Against the width of the route's box.
    private static let boltRadius: CGFloat = 0.017

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width, geometry.size.height / Self.aspect)
            let box = CGSize(width: scale, height: scale * Self.aspect)
            ZStack(alignment: .topLeading) {
                ForEach(Array(Self.holds.enumerated()), id: \.offset) { index, hold in
                    body(for: hold, landed: landing(index), in: box)
                }
            }
            .frame(width: box.width, height: box.height, alignment: .topLeading)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    /// One hold on the wall: the sculpted cut-out, whatever it is bolted through, and
    /// the shadow it throws.
    ///
    /// A hold arrives a little proud of the wall — larger, softer, its shadow thrown wide
    /// — and is pressed on, the shadow drawing in under it as it goes. Holds are set on a
    /// wall rather than switched on, and a shadow closing up is the only part of setting
    /// one that can be seen from the ground.
    @ViewBuilder
    private func body(for hold: Hold, landed: Double, in box: CGSize) -> some View {
        let size = CGSize(width: hold.width * box.width, height: hold.height * box.height)
        // How thick the shoulder is before the top of the hold flattens out. Small holds
        // are all shoulder, which is what a foot chip is.
        let bevel = min(max(min(size.width, size.height) * 0.27, 2.2), 10)
        let proud = 1 - landed

        Image("RouteHolds/" + hold.name)
            .renderingMode(.template)
            .resizable()
            .foregroundStyle(.white)
            .frame(width: size.width, height: size.height)
            .layerEffect(
                ShaderLibrary.climbingHold(
                    .float(Float(bevel)),
                    .float2(Float(light.dx), Float(light.dy)),
                    .float(0.72),
                    .float(0.85),  // how broad the colour swirl in the moulding runs
                    .color(tint)
                ),
                maxSampleOffset: CGSize(width: bevel, height: bevel)
            )
            .overlay {
                ForEach(Array(hold.bolts.enumerated()), id: \.offset) { _, bolt in
                    BoltHole(diameter: Self.boltRadius * box.width, light: light)
                        .position(x: bolt.x * size.width, y: bolt.y * size.height)
                }
            }
            // Tight and dark, right under the hold: the line that says it is touching.
            .shadow(color: .black.opacity(0.72),
                    radius: 1.5 + 5 * proud,
                    x: -light.dx * (1.5 + 7 * proud),
                    y: -light.dy * (1.5 + 7 * proud))
            // Wide and weak: the room's own light closing in around it.
            .shadow(color: .black.opacity(0.40),
                    radius: 7 + 16 * proud,
                    x: -light.dx * (4 + 14 * proud),
                    y: -light.dy * (4 + 14 * proud))
            .scaleEffect(1 + 0.17 * proud)
            .opacity(landed)
            .offset(x: hold.x * box.width, y: hold.y * box.height)
    }

    /// How far into its own arrival this hold is. The holds have the run divided evenly
    /// between them, so `progress` reads as how many are up: at `n / count` the first
    /// `n` are on the wall and the next one is just starting to land.
    private func landing(_ index: Int) -> Double {
        let count = Double(Self.holds.count)
        let raw = min(max((progress - Double(index) / count) * count, 0), 1)
        return 1 - pow(1 - raw, 3)
    }

    /// Cut from the render, bottom hold first — the order they are set in.
    static let holds: [Hold] = [
        .init(name: "hold00", x: 0.5257, y: 0.9657, width: 0.0390, height: 0.0171, bolts: []),
        .init(name: "hold01", x: 0.5154, y: 0.9179, width: 0.0431, height: 0.0190, bolts: []),
        .init(name: "hold02", x: 0.3778, y: 0.9016, width: 0.0431, height: 0.0190, bolts: []),
        .init(name: "hold03", x: 0.3696, y: 0.8619, width: 0.0390, height: 0.0171, bolts: []),
        .init(name: "hold04", x: 0.3593, y: 0.8222, width: 0.0411, height: 0.0181, bolts: []),
        .init(name: "hold05", x: 0.3470, y: 0.7843, width: 0.0390, height: 0.0171, bolts: []),
        .init(name: "hold06", x: 0.5359, y: 0.7563, width: 0.0637, height: 0.0298, bolts: []),
        .init(name: "hold07", x: 0.3265, y: 0.6805, width: 0.1910, height: 0.0551, bolts: [.init(x: 0.495, y: 0.459, radius: 0.0077)]),
        .init(name: "hold08", x: 0.7741, y: 0.6715, width: 0.0534, height: 0.0298, bolts: []),
        .init(name: "hold09", x: 0.2772, y: 0.6227, width: 0.0965, height: 0.0379, bolts: [.init(x: 0.532, y: 0.476, radius: 0.0072)]),
        .init(name: "hold10", x: 0.5708, y: 0.6029, width: 0.0513, height: 0.0226, bolts: []),
        .init(name: "hold11", x: 0.1006, y: 0.3827, width: 0.1068, height: 0.0505, bolts: [.init(x: 0.519, y: 0.411, radius: 0.0081)]),
        .init(name: "hold12", x: 0.3614, y: 0.5009, width: 0.0472, height: 0.0217, bolts: []),
        .init(name: "hold13", x: 0.3121, y: 0.4883, width: 0.0472, height: 0.0208, bolts: []),
        .init(name: "hold14", x: 0.1540, y: 0.3231, width: 0.1088, height: 0.0695, bolts: [.init(x: 0.566, y: 0.481, radius: 0.0090)]),
        .init(name: "hold15", x: 0.5400, y: 0.4206, width: 0.0595, height: 0.0262, bolts: []),
        .init(name: "hold16", x: 0.6324, y: 0.2969, width: 0.2608, height: 0.0659, bolts: [.init(x: 0.465, y: 0.562, radius: 0.0108)]),
        .init(name: "hold17", x: 0.4497, y: 0.1218, width: 0.1992, height: 0.1282, bolts: [.init(x: 0.485, y: 0.331, radius: 0.0117), .init(x: 0.577, y: 0.725, radius: 0.0086)]),
        .init(name: "hold18", x: 0.1951, y: 0.0848, width: 0.1211, height: 0.0560, bolts: [.init(x: 0.508, y: 0.452, radius: 0.0090)]),
        .init(name: "hold19", x: 0.1088, y: 0.0181, width: 0.1581, height: 0.0551, bolts: [.init(x: 0.506, y: 0.410, radius: 0.0099)]),
    ]
}

/// The bolt a hold is set with: a counter-sunk hole and the head sitting down in it.
///
/// A hole is lit backwards from everything around it. The light comes in over the near
/// rim and lands on the far inside wall, so the side of the hole nearest the light is the
/// dark one — that inversion is the whole reason it reads as going in rather than as a
/// dot painted on. The countersink around it is lit the ordinary way, and having the two
/// disagree across a few points is what sells the depth at this size.
private struct BoltHole: View {
    var diameter: CGFloat
    var light: CGVector

    /// Where the light is coming from, as a unit point across the hole.
    private var lit: UnitPoint {
        let length = max(sqrt(light.dx * light.dx + light.dy * light.dy), 0.0001)
        return UnitPoint(x: 0.5 - light.dx / length * 0.5, y: 0.5 - light.dy / length * 0.5)
    }

    private var shaded: UnitPoint {
        UnitPoint(x: 1 - lit.x, y: 1 - lit.y)
    }

    var body: some View {
        ZStack {
            // The dish the bolt is sunk into, cut down out of the hold's own surface:
            // dark where it turns away from the light, catching it on the far side.
            Circle()
                .fill(
                    LinearGradient(colors: [.black.opacity(0.55), .white.opacity(0.32)],
                                   startPoint: lit, endPoint: shaded)
                )
                .frame(width: diameter * 1.45, height: diameter * 1.45)
                .blur(radius: diameter * 0.16)
                .blendMode(.overlay)

            // The bore. Near black under the near lip, opening onto the lit far wall.
            Circle()
                .fill(
                    LinearGradient(colors: [.black, Color(white: 0.30)],
                                   startPoint: shaded, endPoint: lit)
                )
                .overlay {
                    Circle()
                        .strokeBorder(.black.opacity(0.9), lineWidth: diameter * 0.13)
                        .blur(radius: diameter * 0.09)
                }

            // The head, down far enough that only its top face catches anything.
            Circle()
                .fill(
                    LinearGradient(colors: [Color(white: 0.46), Color(white: 0.05)],
                                   startPoint: lit, endPoint: shaded)
                )
                .frame(width: diameter * 0.58, height: diameter * 0.58)
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.7), .clear],
                                           startPoint: lit, endPoint: shaded),
                            lineWidth: diameter * 0.075
                        )
                }
                .shadow(color: .black.opacity(0.8),
                        radius: diameter * 0.08,
                        x: -light.dx * diameter * 0.09,
                        y: -light.dy * diameter * 0.09)
                .offset(x: -light.dx * diameter * 0.04, y: -light.dy * diameter * 0.04)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// The wall the route is set on: painted ply, lit from the same corner the holds are.
///
/// Black is not a wall — it is the absence of one, and a hold in front of it has nothing
/// to be in front of. This gives the light something to fall on and the shadows something
/// to land on, dark enough that the route is still the only thing with a colour.
struct GymWall: View {
    var light: CGVector = .init(dx: -0.48, dy: -0.62)

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.black)
                .colorEffect(
                    ShaderLibrary.gymWall(
                        .float2(Float(geometry.size.width), Float(geometry.size.height)),
                        .float2(Float(light.dx), Float(light.dy))
                    )
                )
        }
        .ignoresSafeArea()
    }
}
