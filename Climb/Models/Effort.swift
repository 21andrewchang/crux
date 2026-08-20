import SwiftUI

/// How hard the attempt was, asked on the attempt page while the answer is still in
/// your forearms.
///
/// Four words rather than the usual RPE 1–10. A number only works when it is anchored
/// to something countable — in the weights room "RPE 8" is shorthand for two reps left
/// in the tank — and nothing has ever anchored the climbing version, so the scale gets
/// used as a mood ring. Words can carry the anchor themselves. Which anchor they should
/// carry is the open question; the words are the part worth shipping first.
enum Effort: Int, CaseIterable, Identifiable {
    case easy, medium, hard, limit

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Med"
        case .hard: "Hard"
        case .limit: "Limit"
        }
    }

    /// The scale runs cool to hot and then off the end of the dial: white is nothing
    /// spent, and purple is the one that means you have nothing left, so it sits apart
    /// from the reds rather than one shade further along them.
    private var rgb: (Double, Double, Double) {
        switch self {
        case .easy: (1.00, 1.00, 1.00)
        case .medium: (1.00, 0.45, 0.70)
        case .hard: (1.00, 0.27, 0.23)
        case .limit: (0.72, 0.40, 1.00)
        }
    }

    var color: Color {
        Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    /// The same colour for the inline row, which is drawn in UIKit.
    var uiColor: UIColor {
        UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    /// What an attempt nobody has rated is stored as. Rating is optional on purpose:
    /// logging a go has to stay one tap, and an unrated attempt is worth more than a
    /// guessed one.
    static let unrated = -1

    static func stored(_ raw: Int) -> Effort? { Effort(rawValue: raw) }
}
