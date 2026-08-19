import SwiftUI

/// How far the open page has been scrolled from its top. Observed rather than held as
/// view state so that following a finger up the page redraws the header and nothing
/// else — the four editors under it have no interest in the number.
@Observable
final class HeaderScroll {
    var travel: CGFloat = 0
}

/// The parts of a note that belong to the session rather than to any one page: the
/// name and the pills.
///
/// Nothing behind any of it — no fade, no backing — so the page runs the whole height
/// of the screen and you can watch a line travel from the chin to the forehead the way
/// Notes lets you.
///
/// All of it scrolls away with the page — the pills as much as the name. Nothing
/// sticks: the page is what you came to read, and once you are into it the whole head
/// of the note gets out of the way. Coming back to the top brings it all back.
///
/// No date on it. The list is already ordered by day and says so on every row — the
/// note itself only ever needed a name.
///
/// Its own view, not a slice of the note's, so that a scroll redraws this and not the
/// four editors underneath.
struct NoteHeader: View {
    @Bindable var session: ClimbSession
    /// How far the open page is scrolled, which is how far the head of the note has
    /// been carried up with it.
    let scroll: HeaderScroll
    @Binding var tab: NoteTab
    /// What the name says while it is unwritten — the walkthrough asks for one
    /// particular name, so during it the field shows that name.
    let placeholder: String
    @FocusState.Binding var isTitleFocused: Bool
    /// What the header comes to, handed back so every page can hold that much room
    /// open at its top.
    let onHeight: (CGFloat) -> Void

    /// How tall the whole head of the note is — how far it travels before it is gone.
    @State private var height: CGFloat = 0

    /// The last of the travel, over which the header fades out rather than sliding on
    /// up behind the top bar's own buttons.
    private static let fade: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            titleField
                .padding(.top, 2)
                .padding(.bottom, 10)
            NoteTabBar(selection: $tab)
                .padding(.bottom, 10)
        }
        .opacity(opacity)
        .offset(y: -min(scroll.travel, height))
        // Measured rather than assumed: a name that wraps to two lines pushes the
        // pills — and the text under them — down.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            height = $0
            onHeight($0)
        }
    }

    /// Whole until the last stretch of the way up, then out — so the pills are still
    /// there for as long as they are usefully on screen, and gone before they reach
    /// the buttons in the corner.
    private var opacity: Double {
        guard height > 0 else { return 1 }
        return min(1, max(0, (height - scroll.travel) / Self.fade))
    }

    /// The session's name. Wraps rather than scrolling sideways — a workout can be
    /// called whatever it is called, and the header grows to hold it.
    private var titleField: some View {
        TextField(text: $session.title, axis: .vertical) {
            Text(placeholder)
        }
        .font(.system(size: 34, weight: .bold))
        .textInputAutocapitalization(.words)
        .submitLabel(.done)
        .focused($isTitleFocused)
        .tint(.white)
        .padding(.horizontal, 16)
    }
}
