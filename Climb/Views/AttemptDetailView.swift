import SwiftUI

/// The two ways to take an attempt back. Both screens the player appears on offer
/// both: a recording saves itself the moment it lands, so this page is never a "do you
/// want to keep it" — it is the attempt, already in the note, with an undo either side,
/// and a stored one is the same attempt a while later.
struct AttemptActions {
    /// Throws this take away and opens the camera for another.
    var onRetake: () -> Void
    /// Throws it away.
    var onDelete: () -> Void
    /// A take that has never been anywhere but this page. Deleting it is the end of
    /// the recording; deleting a stored one only takes its row out of the note.
    var isFreshTake = false
}

/// The attempt screen, in both places it appears: opened from an inline row in the
/// note, and straight off the camera (see `AttemptFlowView`). `review` is the only
/// difference between the two.
struct AttemptDetailView: View {
    @Bindable var attempt: Attempt
    let ordinal: Int
    /// The heading the attempt sits under. Falls back to the stored link, which only
    /// notes saved before climbs became plain text carry.
    var climbName: String? = nil
    /// Set when a timestamp in the note was tapped: the player opens parked there.
    var startAt: TimeInterval? = nil
    var autoplays = false
    /// The app's one rest clock, shown here as it is in the note's bar — a go just
    /// recorded starts it, and the page it opens onto is where you sit out the rest.
    var stopwatch: StopwatchModel
    var actions: AttemptActions? = nil
    var onDone: () -> Void

    @State private var controller = AttemptPlayerController()
    @State private var isPickingEffort = false
    @State private var isConfirmingRetake = false
    @State private var isConfirmingDelete = false

    private var heading: String? { climbName ?? attempt.climb?.name }
    private var fresh: Bool { actions?.isFreshTake ?? false }

    var body: some View {
        AttemptPlayerView(
            videoURL: attempt.videoURL,
            duration: attempt.videoDuration,
            notes: $attempt.notes,
            startAt: startAt,
            autoplays: autoplays,
            controller: controller
        ) {
            controls
        }
        .overlay(alignment: .top) {
            AttemptTopBar(
                title: heading ?? "Attempt \(ordinal)",
                subtitle: heading != nil ? "Attempt \(ordinal)" : nil,
                onClose: leave
            ) {
                if actions != nil { moreMenu }
            }
        }
        // Always mounted, so the ground and the card can arrive on their own beats.
        .overlay {
            EffortMenu(
                isPresented: isPickingEffort,
                selection: attempt.effort,
                onPick: { effort in
                    attempt.effort = effort
                    isPickingEffort = false
                },
                onDismiss: { isPickingEffort = false }
            )
        }
        .alert("Retake this attempt?", isPresented: $isConfirmingRetake) {
            Button("Cancel", role: .cancel) { }
            Button("Retake", role: .destructive) { actions?.onRetake() }
        } message: {
            // Retaking is not "keep the notes, swap the video": the clips are cut
            // out of this take's frames and mean nothing against another one, so they
            // go with it. Worth saying before the camera opens, not after.
            Text(fresh ? "The video and every clip on it will be deleted."
                       : "The video and every clip on it leave the note, and the camera opens for another.")
        }
        .alert("Delete this attempt?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { actions?.onDelete() }
        } message: {
            // A fresh take was never anywhere but here, so deleting it is the end of
            // it. A stored one is a row in a note, and that note's undo still applies.
            Text(fresh ? "The video and every clip on it will be deleted."
                       : "The video and every clip on it leave the note.")
        }
    }

    /// The ways to take an attempt back, folded into the corner the way every other
    /// screen's destructive actions are — an ellipsis, and the choices under it. Out
    /// here as a pair of capsules they were the loudest thing on a page whose point is
    /// the video.
    private var moreMenu: some View {
        Menu {
            Button("Retake", systemImage: "arrow.trianglehead.counterclockwise") {
                isConfirmingRetake = true
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                isConfirmingDelete = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .frame(width: 48, height: 48)
                .glassEffect(.regular, in: .circle)
                .contentShape(.circle)
        }
        .foregroundStyle(.white)
    }

    /// Effort at the leading edge, the rest capsule at the trailing one. The corner
    /// before this row belongs to the player's own pencil.
    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                EffortButton(effort: attempt.effort) {
                    isPickingEffort = true
                }

                Spacer(minLength: 0)

                // A readout here, not a button: its duration panel is hosted by the
                // note under this sheet, so a tap would open it out of sight.
                TimerCapsule(stopwatch: stopwatch, isInteractive: false)
            }
        }
    }

    /// Every way out funnels through here, so a half-written note is never dropped.
    private func leave() {
        controller.commitDraft()
        onDone()
    }
}
