import SwiftUI

/// Opened by tapping an inline row: the shared attempt screen over the stored attempt.
struct AttemptDetailView: View {
    @Bindable var attempt: Attempt
    let ordinal: Int
    /// Set when a timestamp in the note was tapped: the player opens parked there.
    var startAt: TimeInterval? = nil
    var onDone: () -> Void

    @State private var controller = AttemptPlayerController()

    var body: some View {
        AttemptPlayerView(
            videoURL: attempt.videoURL,
            duration: attempt.videoDuration,
            notes: $attempt.notes,
            startAt: startAt,
            controller: controller
        ) {
            EmptyView()
        }
        .overlay(alignment: .top) {
            AttemptTopBar(
                title: attempt.climb?.name ?? "Attempt \(ordinal)",
                subtitle: attempt.climb != nil ? "Attempt \(ordinal)" : nil,
                onClose: leave
            )
        }
    }

    /// Every way out funnels through here, so a half-written note is never dropped.
    private func leave() {
        controller.commitDraft()
        onDone()
    }
}
