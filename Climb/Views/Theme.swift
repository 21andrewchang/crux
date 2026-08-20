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

/// The grade ladder as ranks: bronze, silver, gold, platinum, diamond, and then elite
/// past the top of it. Two grades to a rank the whole way up, which puts V0–V1 in
/// bronze and everything from V10 in elite.
///
/// Ranks rather than words like "intermediate" because a rank is a thing you are and a
/// description is a thing someone says about you — and because the ladder is read at a
/// glance, in colour, far more often than it is read as a name. The metals run in the
/// order everyone already knows them in, so the order needs no explaining; purple sits
/// past the last of them and nothing else in the app is allowed to be purple, which is
/// what makes a purple V12 mean something.
enum GradeTier: Int, CaseIterable {
    case bronze, silver, gold, platinum, diamond, elite

    /// Which rank a V-grade falls in. Anything past V10 is elite — the ranks stop
    /// because the ladder stops mattering up there, not because the grades do.
    static func of(_ grade: Double) -> GradeTier {
        GradeTier(rawValue: max(0, min(allCases.count - 1, Int(grade) / 2))) ?? .bronze
    }

    var name: String {
        switch self {
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .platinum: "Platinum"
        case .diamond: "Diamond"
        case .elite: "Elite"
        }
    }

    /// The two grades it covers, written the way the profile labels a spoke.
    var band: String {
        self == .elite ? "V10+" : "V\(rawValue * 2)–V\(rawValue * 2 + 1)"
    }

    /// Each metal as the thing itself rather than as a hue: bronze warm and dark enough
    /// to read as metal, silver neutral, gold the yellow already in the app, platinum a
    /// pale steel with the cold in it, diamond the ice blue past that, and elite purple.
    var color: Color {
        switch self {
        case .bronze: Color(red: 0.80, green: 0.51, blue: 0.28)
        case .silver: Color(red: 0.76, green: 0.79, blue: 0.83)
        case .gold: Color(red: 1, green: 0.78, blue: 0.26)
        case .platinum: Color(red: 0.55, green: 0.88, blue: 0.83)
        case .diamond: Color(red: 0.36, green: 0.71, blue: 1)
        case .elite: Color(red: 0.66, green: 0.44, blue: 1)
        }
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
