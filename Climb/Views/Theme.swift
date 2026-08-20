import SwiftUI

/// One surface for the whole app: pure black, no separators, no card fills. Anything
/// that needs to read as a distinct block lifts off the background by a few percent
/// rather than by a line around it.
extension Color {
    static let surface = Color.white.opacity(0.07)

    /// The yellow the hold detector paints a route in — the loading screen's wall is
    /// set in it, and anything else that stands for a route should be too.
    static let routeHold = Color(red: 0.925, green: 0.835, blue: 0.31)
}

/// The grade ladder in colour: five tiers, each three grades wide, the same rungs the
/// profile draws its rings on and the quiz asks its two grades in.
///
/// It runs white, blue, gold, red, purple — cool at the bottom, hot at the top, and
/// purple past where hot goes. White is the bottom rung rather
/// than a colour of its own: nothing has been earned yet, and a first grade reading in
/// plain white is the honest version of that. Purple is elite and nothing else in the
/// app is allowed to be, which is what makes a purple V12 mean something.
enum GradeTier: Int, CaseIterable {
    case novice, intermediate, advanced, expert, elite

    /// Which tier a V-grade falls in. Anything past V12 is elite — the tiers stop
    /// because the ladder stops mattering up there, not because the grades do.
    static func of(_ grade: Double) -> GradeTier {
        GradeTier(rawValue: max(0, min(allCases.count - 1, Int(grade) / 3))) ?? .novice
    }

    var name: String {
        switch self {
        case .novice: "Novice"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        case .expert: "Expert"
        case .elite: "Elite"
        }
    }

    /// The three grades it covers, written the way the profile labels a spoke.
    var band: String {
        self == .elite ? "V12+" : "V\(rawValue * 3)–V\(rawValue * 3 + 2)"
    }

    var color: Color {
        switch self {
        case .novice: .white
        case .intermediate: Color(red: 0.29, green: 0.66, blue: 1)
        case .advanced: Color(red: 1, green: 0.78, blue: 0.26)
        case .expert: Color(red: 1, green: 0.29, blue: 0.29)
        case .elite: Color(red: 0.66, green: 0.44, blue: 1)
        }
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
