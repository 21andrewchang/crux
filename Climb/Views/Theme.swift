import SwiftUI

/// One surface for the whole app: pure black, no separators, no card fills. Anything
/// that needs to read as a distinct block lifts off the background by a few percent
/// rather than by a line around it.
extension Color {
    static let surface = Color.white.opacity(0.07)
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
