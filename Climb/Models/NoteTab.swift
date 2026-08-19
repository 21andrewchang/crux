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

    /// Whether the page scrolls at all.
    ///
    /// Every page but the check-in's. The other three are written into and grow past
    /// the screen. The check-in is not a document — it is one card, sized to fit,
    /// and it holds still: drag it and nothing moves.
    ///
    /// That is not only about feel. A row you answer by dragging cannot live on a
    /// page that scrolls, because the two want the same gesture and the scroll wins
    /// every ambiguous one. Holding the page still is what buys the rows their drag.
    var scrolls: Bool { self != .checkIn }

    /// Whether the page can be written into.
    ///
    /// Every page but the check-in's. That one is a form, not a document — there is
    /// nothing on it you would want to type next to, and a caret landing between the
    /// boxes with the keyboard coming up over them is the whole page getting in its
    /// own way. Tapping it should answer a question or do nothing.
    var editable: Bool { self != .checkIn }

    /// Whether text on the page can be selected.
    ///
    /// Every page but the check-in's, for the same reason it cannot be typed into.
    /// There is one line of text on that page and it is invisible — the card sits on
    /// it — so the only thing a long press there can do is throw a selection highlight
    /// across the card and put a menu over it, which is a way of copying nothing.
    ///
    /// Turning it off leaves the boxes working: the card is a real subview of the text
    /// view, and hit-testing reaches it through the view hierarchy rather than through
    /// any of the gesture recognisers this switches off.
    var selectsText: Bool { self != .checkIn }

    /// Whether the page's content sits in the middle of the screen rather than at the
    /// top of it. Only the check-in's: it is one card of a known size on a page that
    /// does not scroll, so there is no reason for it to hang off the top edge with the
    /// rest of the screen empty under it.
    var centersContent: Bool { self == .checkIn }

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
