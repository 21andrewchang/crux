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
    /// Where the head of the note comes to when it is resting, in screen coordinates,
    /// so every page can start its text on that exact line. Handed back as a position
    /// rather than a height because the page has its own idea of where the safe area
    /// begins — and the keyboard moves it out from under the header.
    let onBottom: (CGFloat) -> Void

    /// How tall the whole head of the note is — how far it travels before it is gone.
    @State private var height: CGFloat = 0
    /// Where the head of the note sits when nothing has been scrolled.
    @State private var top: CGFloat = 0

    /// The last of the travel, over which the header fades out rather than sliding on
    /// up behind the top bar's own buttons.
    private static let fade: CGFloat = 40

    var body: some View {
        ZStack(alignment: .top) {
            // The head of the note travels with the page, so it cannot be asked where
            // it rests — this can. Nothing is drawn: it is a mark at the line the
            // header starts on, held still while the header itself slides past it.
            Color.clear
                .frame(height: 0)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                    top = $0
                    reportBottom()
                }
            head
        }
    }

    /// The name and the pills, moving as the one piece they read as: the same offset
    /// and the same fade carry both, and the page below starts exactly where they end.
    private var head: some View {
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
            reportBottom()
        }
    }

    /// The line the pages start their text on: the bottom edge of the head of the note
    /// where it rests, whatever the page under it is doing.
    private func reportBottom() { onBottom(top + height) }

    /// Whole until the last stretch of the way up, then out — so the pills are still
    /// there for as long as they are usefully on screen, and gone before they reach
    /// the buttons in the corner.
    private var opacity: Double {
        guard height > 0 else { return 1 }
        return min(1, max(0, (height - scroll.travel) / Self.fade))
    }

    /// The session's name. Wraps rather than scrolling sideways — a workout can be
    /// called whatever it is called, and the header grows to hold it.
    ///
    /// Title-cased on the way in, the same as the headings under it: the keyboard's own
    /// autocapitalization only ever catches what is typed, and a name pasted in or
    /// written before the rule existed reads as a name too.
    private var title: Binding<String> {
        Binding { session.title } set: { session.title = NoteDocument.capitalizedName($0) }
    }

    private var titleField: some View {
        TextField(text: title, axis: .vertical) {
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
