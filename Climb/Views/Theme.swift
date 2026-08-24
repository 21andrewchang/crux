import CoreGraphics
import SwiftUI

/// One surface for the whole app: pure black, no separators, no card fills. Anything
/// that needs to read as a distinct block lifts off the background by a few percent
/// rather than by a line around it.
extension Color {
    static let surface = Color.white.opacity(0.07)

    /// White, a few percent off. Pure white on pure black is a harder edge than any
    /// screen needs — text glares and a filled button reads as a light source rather
    /// than as a surface. Everything that would have been `.white` is this instead.
    static let paper = Color(white: 0.92)

    /// The yellow the hold detector paints a route in — the loading screen's wall is
    /// set in it, and anything else that stands for a route should be too.
    static let routeHold = Color(red: 0.925, green: 0.835, blue: 0.31)
}

/// The grade ladder as ranks: bronze, silver, gold, platinum, diamond, elite, ruby, and
/// pearl at the very top. Two grades to a rank up to elite, which puts V0–V1 in bronze
/// and V10–V11 in elite; ruby takes three on its own and pearl finishes the scale.
///
/// Ranks rather than words like "intermediate" because a rank is a thing you are and a
/// description is a thing someone says about you — and because the ladder is read at a
/// glance, in colour, far more often than it is read as a name. The metals run in the
/// order everyone already knows them in, so the order needs no explaining; purple sits
/// past the last of them and nothing else in the app is allowed to be purple, which is
/// what makes a purple V11 mean something.
///
/// Above purple the steps get wider rather than finer, because the grades do: V12 to
/// V14 is a decade of climbing for anyone who gets there, so it is one rank — red, the
/// only red in the app — and V15 and up, which perhaps a few dozen people alive have
/// touched, is pearl.
enum GradeTier: Int, CaseIterable {
    case bronze, silver, gold, platinum, diamond, elite, ruby, pearl

    /// Which rank a V-grade falls in. Two to a rank up to V11, then ruby holds V12–V14
    /// whole and pearl takes everything past it — the top of the ladder is scarcer, so
    /// its ranks are wider.
    static func of(_ grade: Double) -> GradeTier {
        switch Int(grade) {
        case ..<12: GradeTier(rawValue: max(0, Int(grade) / 2)) ?? .bronze
        case 12...14: .ruby
        default: .pearl
        }
    }

    var name: String {
        switch self {
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .platinum: "Platinum"
        case .diamond: "Diamond"
        case .elite: "Elite"
        case .ruby: "Ruby"
        case .pearl: "Pearl"
        }
    }

    /// The grades it covers, written the way the profile labels a spoke.
    var band: String {
        switch self {
        case .ruby: "V12–V14"
        case .pearl: "V15+"
        default: "V\(rawValue * 2)–V\(rawValue * 2 + 1)"
        }
    }

    /// Each metal as the thing itself rather than as a hue: bronze warm and dark enough
    /// to read as metal, silver a grey steel, gold the yellow already in the app,
    /// platinum a pale steel with the cold in it, diamond the ice blue past that, elite
    /// purple, ruby the one red in the app, and pearl an off-white with the warmth left
    /// in it.
    ///
    /// Silver is grey and a good way down from white rather than the bright near-white
    /// it started as, because pearl is the near-white now and two ranks cannot both be
    /// that. It costs silver nothing — a real silver is a dark metal that happens to be
    /// a mirror, and the light one was only ever reading as "light grey".
    ///
    /// Pearl is the only one of them that is a poor flat colour — a pearl is what light
    /// does to a surface, not a value — so anything drawing a grade at size should take
    /// `fill` instead and let the nacre ramp do the work.
    var color: Color {
        switch self {
        case .bronze: Color(red: 0.80, green: 0.51, blue: 0.28)
        case .silver: Color(red: 0.61, green: 0.63, blue: 0.66)
        case .gold: Color(red: 1, green: 0.78, blue: 0.26)
        case .platinum: Color(red: 0.55, green: 0.88, blue: 0.83)
        case .diamond: Color(red: 0.36, green: 0.71, blue: 1)
        case .elite: Color(red: 0.66, green: 0.44, blue: 1)
        case .ruby: Color(red: 0.94, green: 0.24, blue: 0.31)
        case .pearl: Color(red: 0.93, green: 0.90, blue: 0.92)
        }
    }

    /// The rank as a face: every rank but pearl is its colour shaded, and pearl is
    /// nacre, which no single colour can stand in for.
    var fill: LinearGradient {
        self == .pearl ? .nacre : .metal(color)
    }
}

extension ShapeStyle where Self == LinearGradient {
    /// A rank's colour as a face rather than a flat fill: the colour itself lifted a
    /// touch towards white at the top and let down towards black at the bottom.
    ///
    /// Two stops and a small range — enough that a glyph set in it has a direction to
    /// the light, not enough to be a second colour. The full chrome ramp — highlight,
    /// shadow, second highlight — reads as a sticker at any size worth using it at.
    static func metal(_ tint: Color) -> LinearGradient {
        LinearGradient(colors: [tint.mix(with: .white, by: 0.14),
                                tint.mix(with: .black, by: 0.24)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Pearl, which is not a colour but an interference: cream where the light lands,
    /// a rose blush under it, a green flash through the middle and lilac in the shade.
    ///
    /// Getting this wrong is easy in both directions and it was got wrong both ways
    /// before it was got right. Too much colour and too few stops and it reads as
    /// sherbet — you see the stripes and the edges between them. Back the colour off
    /// far enough for the edges to disappear and what is left is silver, because a
    /// near-neutral ramp from white to grey *is* silver, whatever it is called.
    ///
    /// So the colour is kept — the green flash especially, which is the thing people
    /// actually recognise a pearl by — and the edges are dealt with instead. The ramp
    /// is a smooth curve through eight control points, sampled at nineteen stops, so no
    /// two neighbouring stops are far apart even where the hue is turning hardest.
    /// That is what a gradient can't do with four stops and big steps between them: the
    /// eye finds a straight line where two of them meet, and once it has found one it
    /// finds all of them.
    ///
    /// The flake on top of this matters as much as the ramp does — grain breaks up
    /// whatever banding is left the way dithering does, and no flat gradient of any
    /// smoothness reads as paint without it.
    ///
    /// It is lit top-down like `metal`, so a pearl grade sits in the same light as
    /// every other rank on the ladder and the shift between them is the surface, not
    /// the direction the light comes from.
    static var nacre: LinearGradient {
        LinearGradient(stops: [.init(color: Color(red: 0.990, green: 0.978, blue: 0.950), location: 0.0000),
                               .init(color: Color(red: 0.985, green: 0.967, blue: 0.949), location: 0.0556),
                               .init(color: Color(red: 0.976, green: 0.947, blue: 0.948), location: 0.1111),
                               .init(color: Color(red: 0.972, green: 0.938, blue: 0.948), location: 0.1667),
                               .init(color: Color(red: 0.967, green: 0.927, blue: 0.943), location: 0.2222),
                               .init(color: Color(red: 0.959, green: 0.910, blue: 0.936), location: 0.2778),
                               .init(color: Color(red: 0.955, green: 0.904, blue: 0.933), location: 0.3333),
                               .init(color: Color(red: 0.934, green: 0.903, blue: 0.918), location: 0.3889),
                               .init(color: Color(red: 0.913, green: 0.901, blue: 0.902), location: 0.4444),
                               .init(color: Color(red: 0.897, green: 0.901, blue: 0.894), location: 0.5000),
                               .init(color: Color(red: 0.857, green: 0.900, blue: 0.873), location: 0.5556),
                               .init(color: Color(red: 0.840, green: 0.899, blue: 0.864), location: 0.6111),
                               .init(color: Color(red: 0.831, green: 0.878, blue: 0.862), location: 0.6667),
                               .init(color: Color(red: 0.824, green: 0.862, blue: 0.860), location: 0.7222),
                               .init(color: Color(red: 0.817, green: 0.836, blue: 0.857), location: 0.7778),
                               .init(color: Color(red: 0.806, green: 0.799, blue: 0.853), location: 0.8333),
                               .init(color: Color(red: 0.799, green: 0.786, blue: 0.848), location: 0.8889),
                               .init(color: Color(red: 0.777, green: 0.754, blue: 0.831), location: 0.9444),
                               .init(color: Color(red: 0.762, green: 0.734, blue: 0.820), location: 1.0000)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// The flake in a metallic paint: a fixed field of fine noise, tiled and laid over a
/// colour so the surface has a grain to it instead of being a clean ramp. A pearl or a
/// candy is a coat of flake under a clear coat — take the flake out and what is left is
/// a gradient, which is what every flat "silver" on a screen is and why none of them
/// read as paint.
///
/// One image, built once and reused everywhere: it is a texture, not a state, and a
/// grain that changed between two numbers on the same screen would read as movement.
enum Flake {
    /// A square of grey noise, mid-grey on average so that laying it over a colour in
    /// `.overlay` blend lightens and darkens the surface in equal measure and leaves
    /// the hue where it was.
    ///
    /// Deterministic rather than random: the same field every launch, off a fixed seed,
    /// so nothing about the app's surface depends on the order things were drawn in.
    static let texture: Image = {
        let side = 96
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for i in 0..<(side * side) {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            // The top bits of the state rather than the bottom ones — the low bits of a
            // linear congruential generator cycle short enough to see as a pattern.
            let raw = Int(truncatingIfNeeded: seed >> 33) & 0xFF
            // Pulled halfway back to mid-grey: full-range noise over type reads as
            // dirt on the screen, and the flake in a paint is a glint, not a speckle.
            let value = UInt8(128 + (raw - 128) / 2)
            pixels[i * 4] = value
            pixels[i * 4 + 1] = value
            pixels[i * 4 + 2] = value
        }
        let context = CGContext(data: &pixels, width: side, height: side,
                                bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let image = context?.makeImage() else { return Image(systemName: "circle") }
        return Image(decorative: image, scale: 2)
    }()
}

extension View {
    /// Flake laid over whatever this is, kept inside its own shape.
    ///
    /// The overlay is masked by the view itself rather than clipped to its frame, so on
    /// a number the grain sits in the glyphs and not in the box around them. That costs
    /// drawing the thing twice, which is why this is on the pearl grade and not on
    /// every rank: the grain is the top of the ladder saying it is a different material,
    /// and a grain on all of them would just be a filter over the app.
    func flake(_ strength: Double = 0.5) -> some View {
        overlay {
            Flake.texture
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(strength)
                .allowsHitTesting(false)
        }
        .compositingGroup()
        .mask(self)
    }

    /// The surface a rank is made of: pearl is flake under a clear coat, and every
    /// other rank is its own ramp and nothing else. Written as one modifier so a call
    /// site can hand it a tier and not carry the exception around itself.
    @ViewBuilder
    func flaked(_ tier: GradeTier) -> some View {
        if tier == .pearl { flake(0.55) } else { self }
    }
}

extension View {
    /// Black behind a `List`/`ScrollView`, with the system's own background suppressed.
    func blackBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.black)
    }

    /// Rows that carry no fill and no separator — the list becomes plain text on black.
    func plainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
