import Foundation

/// The four pages a session note is written across.
///
/// A session runs in the same order every time — how you turned up, what you warmed
/// up on, the climbing itself, what you make of it afterwards — so the note is four
/// documents rather than one long scroll. Each tab holds its own text and its own
/// attachments; the title above them belongs to the session, not to any one page.
///
/// The order is the order of the session, and `rawValue` is what the paging view
/// swipes through, so cases are appended and never reordered.
enum NoteTab: Int, CaseIterable, Identifiable, Hashable {
    case checkIn, warmUp, main, review

    var id: Int { rawValue }

    /// What the tab says on its pill.
    var title: String {
        switch self {
        case .checkIn: "Check-in"
        case .warmUp: "Warm-up"
        case .main: "Main"
        case .review: "Review"
        }
    }

    /// Whether the readiness card opens this page. Only the check-in's — the card is
    /// the reason that tab exists.
    var showsCheckIn: Bool { self == .checkIn }

    /// Whether an empty page here says what the bar's buttons do. Only the main page:
    /// the hints are about recording climbs, which is what that page is for.
    var showsHints: Bool { self == .main }

    /// What an empty page says behind its first line — the tab's own job, in the
    /// voice of a placeholder. Nothing on the check-in page: the card is already
    /// sitting on its first line, and a placeholder would be drawn straight over it.
    var placeholder: String? {
        switch self {
        case .checkIn: nil
        case .warmUp: "What you warmed up on"
        case .main: "The session"
        case .review: "What you make of it"
        }
    }
}
