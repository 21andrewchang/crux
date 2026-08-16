import SwiftUI

extension View {
    /// The global timer: its duration panel, and the capsule itself — Rest, or the
    /// running countdown — floating above every page of the stack below, simply always
    /// there. Each page's leading items stay ordinary system bottom-bar chrome (that's
    /// what buys the native search-field → pill morph on push); only the timer lives up
    /// here. The capsule steps aside while the keyboard clone is riding. Sheets and
    /// alerts still present above it.
    ///
    /// Applied by whatever is holding a navigation stack — the notes list normally, the
    /// tutorial note on its own during onboarding — so the bar never re-enters or resets
    /// across pushes within it.
    func bottomBarHost(_ barModel: BottomBarModel) -> some View {
        self
            .overlay {
                TimerBubble(
                    stopwatch: barModel.stopwatch,
                    bottomInset: barModel.timerBottomInset
                )
            }
            .overlay {
                if barModel.parkedVisible {
                    ZStack(alignment: .bottomTrailing) {
                        Color.clear
                        TimerCapsule(stopwatch: barModel.stopwatch, isLocked: barModel.isRestLocked)
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) {
                                barModel.capsuleWidth = $0
                            }
                            // Pinned to the slot the system actually allocated for the
                            // placeholder item; bottom is the bar's own 28.
                            .padding(.trailing, barModel.capsuleTrailingInset)
                            .padding(.bottom, 28)
                    }
                    .ignoresSafeArea()
                }
            }
            .environment(barModel)
    }
}
