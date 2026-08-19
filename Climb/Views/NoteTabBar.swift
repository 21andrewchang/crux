import SwiftUI

/// The four pills under a session's title: the note's pages, in the order a session
/// runs. Tapping one turns to it; the pages themselves can be swiped through, and the
/// bar follows whichever is on screen.
///
/// A row rather than a segmented control: the pills read as places to go, and the one
/// you are on is simply lit. The row scrolls sideways so the names never have to be
/// shortened on a narrow phone.
struct NoteTabBar: View {
    @Binding var selection: NoteTab

    /// Ties the lit pill to the tab it is under, so turning a page slides it across
    /// rather than blinking it out and in.
    @Namespace private var pill

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(NoteTab.allCases) { tab in
                        Button {
                            guard tab != selection else { return }
                            // No tap of its own: the page turning is what is felt, and
                            // that is answered in one place for both ways of asking
                            // for it — see `SessionDetailView`.
                            withAnimation(.snappy(duration: 0.28)) { selection = tab }
                        } label: {
                            label(for: tab)
                        }
                        .buttonStyle(.plain)
                        .id(tab)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            // Nothing to scroll on a phone wide enough for all four: the row shouldn't
            // rubber-band under a finger that was aiming at a pill.
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: selection) {
                withAnimation(.snappy(duration: 0.28)) {
                    proxy.scrollTo(selection, anchor: .center)
                }
            }
        }
    }

    /// Dark grey at rest, lighter once picked, and the word goes from dim to plain
    /// white with it — the pill is never the only thing saying which page you are on.
    ///
    /// Solid greys rather than a few percent of white: the row sticks at the top of
    /// the screen with the note scrolling underneath it, and a translucent pill would
    /// have the text of the note running through the middle of the word on it. Only
    /// the pills are opaque; between them the page shows through, which is the point.
    private func label(for tab: NoteTab) -> some View {
        let isCurrent = tab == selection
        return Text(tab.title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.45))
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background {
                ZStack {
                    Capsule(style: .continuous).fill(Color(white: 0.11))
                    if isCurrent {
                        Capsule(style: .continuous)
                            .fill(Color(white: 0.26))
                            .matchedGeometryEffect(id: "selected", in: pill)
                    }
                }
            }
            .contentShape(Capsule(style: .continuous))
    }
}
