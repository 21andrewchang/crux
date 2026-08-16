import Combine
import SwiftUI
import SwiftData
import UIKit

/// The note. Type freely; "Start Attempt" drops a recorded go into the document.
struct SessionDetailView: View {
    @Bindable var session: ClimbSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Only consulted for notes saved before climbs became plain text: an old stored
    /// climb's marker resolves to its name and comes back as an inline bubble.
    @Query private var climbs: [Climb]

    @State private var editorController = NoteEditorController()
    @State private var stopwatch = StopwatchModel()
    @State private var pendingAttemptID: UUID?
    @State private var openedAttemptID: UUID?
    /// Outlives `openedAttemptID`, which is already nil by the time the sheet's dismissal
    /// handler runs.
    @State private var editedAttemptID: UUID?
    /// Where the opened attempt's player starts — set by tapping a timestamp in the note.
    @State private var openedAttemptStart: TimeInterval?
    @State private var isEditing = false
    /// Times the swap between the parked system bar and the keyboard bar.
    @State private var barPark = BarParkModel()
    /// Tracked so the floating duration menu can sit just above the keyboard bar.
    @State private var keyboardHeight: CGFloat = 0
    @State private var isConfirmingDelete = false
    @State private var isConfirmingRowDelete = false
    @State private var doomedRowCount = 0
    /// Attempts whose rows have been removed but whose deletion is still undoable.
    @State private var detached: [DetachedAttempt] = []

    var body: some View {
        NoteEditor(
            session: session,
            controller: editorController,
            onStartAttempt: startAttempt,
            onAddClimb: { editorController.insertClimbHeader() },
            onAddSection: { editorController.insertSectionHeader() },
            stopwatch: stopwatch,
            barPark: barPark,
            onOpenAttempt: {
                openedAttemptStart = nil
                openedAttemptID = $0
                editedAttemptID = $0
            },
            onSeekAttempt: { id, seconds in
                openedAttemptStart = seconds
                openedAttemptID = id
                editedAttemptID = id
            },
            legacyClimbName: { id in climbs.first { $0.id == id }?.name },
            onConfirmDelete: { count in
                doomedRowCount = count
                isConfirmingRowDelete = true
            },
            onChange: saveChanges,
            onFocusChange: { focused in
                isEditing = focused
                // The keyboard can come back without the will-change notification
                // arriving in a useful order — dismissing the attempt sheet hands
                // focus straight back — so the bar swap keys off focus too.
                if focused { barPark.lift() }
            }
        )
        .background(Color.black)
        .background(BarParkAnchor(model: barPark))
        .ignoresSafeArea(.container, edges: .vertical)
        // The note runs edge to edge under the bars; a black fade at each end
        // keeps the status bar and the bottom bar legible over the text.
        .overlay {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
                Spacer(minLength: 0)
                LinearGradient(colors: [.black.opacity(0), .black],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        // The timer's duration menu floats here, over the note, rather than inside
        // the toolbar: the keyboard accessory's frame is fixed, and growing it to
        // fit the menu made the whole bar jump. A full-screen catcher behind it
        // dismisses on a tap anywhere outside. Sits under the toolbar in the
        // chain, so the bar's own buttons still get their taps first.
        .overlay(alignment: .bottomTrailing) {
            if stopwatch.isChoosing {
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture {
                            withAnimation(.smooth(duration: 0.35)) { stopwatch.isChoosing = false }
                        }
                    TimerDurationMenu { duration in
                        withAnimation(.smooth(duration: 0.35)) { stopwatch.start(duration) }
                    }
                    .padding(.trailing, 16)
                    // 8pt above the timer capsule, measured from the true screen
                    // bottom. Parked: the capsule lives in the system bottom bar,
                    // top near 86 (34 safe area + 48 capsule + 4). Editing: the
                    // keyboard frame includes the 64pt accessory, whose capsule
                    // top sits 8 below its top edge — so the keyboard height
                    // itself lands the menu 8pt clear.
                    .padding(.bottom, isEditing ? keyboardHeight : 94)
                }
                // Full screen regardless of any inherited safe-area context, so
                // the paddings above mean distance from the physical bottom edge.
                .ignoresSafeArea()
            }
        }
        .animation(.smooth(duration: 0.35), value: stopwatch.isChoosing)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboardHeight = max(0, UIScreen.main.bounds.maxY - frame.minY)
            // The bar swap: rising (only for the note's own keyboard, not a
            // sheet's) hides the parked items this instant and starts tracking
            // the clone's position; the swap back fires off where the clone
            // actually is mid-slide, with the duration only as a backstop.
            let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
            if keyboardHeight > 0 {
                if isEditing { barPark.lift() }
            } else {
                barPark.parkBy(duration)
            }
        }
        // Without this, the bottom bar would dodge the keyboard and briefly float
        // over it during focus transitions; the accessory already covers that case.
        .ignoresSafeArea(.keyboard)
        .onDisappear {
            barPark.restore()
            discardDetachedAttempts()
        }
        // No date in the top bar — it lives in the note itself, above the title.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", systemImage: "checkmark") { editorController.endEditing() }
                        .labelStyle(.iconOnly)
                        .fontWeight(.semibold)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }

            // Parked bar: real system bottom bar items, which is what buys the
            // Notes push transition — the search field morphs into these. The
            // system bar cannot ride the keyboard (SwiftUI re-pins its chrome
            // every frame), so while editing the keyboard accessory clone in
            // NoteEditor takes over at the same metrics. The items stay in the
            // toolbar permanently; `barPark` snaps the bar's chrome view
            // invisible/visible in step with the keyboard, because removing
            // items would replay the system's insertion animation every time.
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Add Climb", systemImage: "plus") { editorController.insertClimbHeader() }
                    .dampedToolbarMorph()
                Button("Add Section", systemImage: "list.dash.header.rectangle") {
                    editorController.insertSectionHeader()
                }
                .dampedToolbarMorph()
                Button("Record Attempt", systemImage: "video.fill", action: startAttempt)
                    .dampedToolbarMorph()
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItemGroup(placement: .bottomBar) {
                if !stopwatch.hasStarted {
                    // Tapping the idle disc offers the three durations in the
                    // floating menu — the system menu is far too wide for them.
                    Button("Timer", systemImage: "timer") {
                        withAnimation(.smooth(duration: 0.35)) { stopwatch.isChoosing.toggle() }
                    }
                    .dampedToolbarMorph()
                } else {
                    Button {
                        withAnimation(.smooth(duration: 0.35)) { stopwatch.toggle() }
                    } label: {
                        StopwatchFace(stopwatch: stopwatch)
                    }
                    .dampedToolbarMorph()
                    Button("Reset", systemImage: "xmark") {
                        withAnimation(.smooth(duration: 0.35)) { stopwatch.reset() }
                    }
                    // xmark fills its bounds edge to edge, so at the bar's default
                    // size it reads bigger than the transport glyphs; a few points
                    // down looks optically matched to the 19pt pause/play.
                    .font(.system(size: 14, weight: .semibold))
                    .dampedToolbarMorph()
                }
            }
        }
        .confirmationDialog("Delete this session?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Session", role: .destructive, action: deleteSession)
        } message: {
            Text("This deletes the note and every attempt recorded in it.")
        }
        // An alert, not a sheet: it lands in the middle of the note with the keyboard
        // still up, where the row being deleted is.
        .alert(doomedRowCount == 1 ? "Delete this attempt?" : "Delete \(doomedRowCount) attempts?",
               isPresented: $isConfirmingRowDelete) {
            Button("Cancel", role: .cancel) { editorController.cancelPendingDeletion() }
            Button("Delete", role: .destructive) { editorController.confirmPendingDeletion() }
        } message: {
            Text(doomedRowCount == 1
                 ? "The video will not be deleted."
                 : "Their videos will not be deleted.")
        }
        // A sheet, same as the replay page, so recording and replaying an attempt are
        // one shape on screen. The flow decides for itself when swipe-to-dismiss is
        // allowed — free before recording starts, off once a take is on the line.
        .sheet(item: $pendingAttemptID) { id in
            AttemptFlowView(
                attemptID: id,
                ordinal: editorController.nextAttemptOrdinal(),
                // The heading this attempt will land under, so the recording page is
                // headed like the replay page.
                climbName: editorController.currentClimbName(),
                onFinish: { finishAttempt(id: id, captured: $0) },
                onCancel: { pendingAttemptID = nil }
            )
        }
        // A native sheet, so dragging the page around comes from the system. On dismiss
        // rather than on Done: the note has to come back showing what the page ended up
        // saying.
        .sheet(item: $openedAttemptID, onDismiss: syncEditedAttempt) { id in
            if let attempt = session.attempt(with: id) {
                AttemptDetailView(
                    attempt: attempt,
                    ordinal: editorController.groupOrdinal(of: id) ?? session.ordinal(of: id),
                    startAt: openedAttemptStart,
                    onDone: { openedAttemptID = nil }
                )
            }
        }
    }

    // MARK: Attempt lifecycle

    private func startAttempt() {
        pendingAttemptID = UUID()
    }

    /// The attempt joins the session first, then the row is inserted — the inline view
    /// reads its data straight out of the session as it lays out.
    private func finishAttempt(id: UUID, captured: CapturedAttempt) {
        let attempt = Attempt(id: id)
        attempt.videoFilename = captured.videoFilename
        attempt.thumbnailFilename = captured.thumbnailFilename
        attempt.videoDuration = captured.duration
        attempt.restSeconds = captured.restSeconds
        attempt.notes = captured.notes
        attempt.session = session
        session.attempts.append(attempt)
        modelContext.insert(attempt)

        pendingAttemptID = nil
        // Inserting rebuilds the rows, which also refreshes the heading's now-stale
        // "7 attempts · 3 sessions" line and renumbers the group.
        editorController.insertAttempt(id: id)
        // Land the user typing on the new line under the row, keyboard and bar up,
        // as the sheet slides away. UIKit only restores the keyboard by itself when
        // the note was being edited at present time — asking makes it every time.
        editorController.focus()
        saveChanges()

        // The rest began when the recording stopped, so the 2-minute countdown is
        // backdated by the rest already spent on the review screen. If the whole
        // window went to reviewing, there's nothing left to count down.
        if captured.restSeconds < 120 {
            withAnimation(.smooth(duration: 0.35)) {
                stopwatch.start(120, from: Date(timeIntervalSinceNow: -captured.restSeconds))
            }
        }
    }

    /// Notes written in the sheet are on the attempt already; this is what puts them
    /// into the note's own text. A deleted attempt has nothing to sync.
    private func syncEditedAttempt() {
        guard let id = editedAttemptID else { return }
        editedAttemptID = nil
        openedAttemptStart = nil
        guard let attempt = session.attempt(with: id) else { return }

        editorController.setNotes(attempt.notes, for: id)
        saveChanges()
        editorController.refreshRows()
    }

    /// The note *is* the session, so deleting it takes every attempt and video with it.
    /// Pop first and delete once the push animation is over: the editor is still bound to
    /// the session on the way out, and laying out against a deleted model traps.
    private func deleteSession() {
        let session = session
        let context = modelContext
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            session.attempts.forEach(VideoStore.delete)
            context.delete(session)
            try? context.save()
        }
    }

    private func saveChanges() {
        reconcileAttempts()
        try? modelContext.save()
    }

    /// The document decides which attempts exist. A row that is gone from it detaches
    /// its attempt — unlinked so it stops counting, but not destroyed, because undo can
    /// put the row back and the attempt has to come back whole. A marker that reappears
    /// re-links the attempt it stands for, climb and all.
    private func reconcileAttempts() {
        let referenced = Set(session.attachmentIDs)

        for orphan in session.attempts where !referenced.contains(orphan.id) {
            detached.append(DetachedAttempt(attempt: orphan, climb: orphan.climb))
            orphan.climb = nil
            orphan.session = nil
        }
        session.attempts.removeAll { !referenced.contains($0.id) }

        for entry in detached where referenced.contains(entry.attempt.id) {
            entry.attempt.session = session
            entry.attempt.climb = entry.climb
            session.attempts.append(entry.attempt)
        }
        detached.removeAll { referenced.contains($0.attempt.id) }
    }

    /// Leaving the note ends the undo window, so anything still detached is now deleted
    /// as far as the app is concerned. The record and the video file stay on disk: a
    /// recording is the one thing here that cannot be made again.
    private func discardDetachedAttempts() {
        guard !detached.isEmpty else { return }
        for entry in detached {
            entry.attempt.deletedAt = Date()
        }
        detached.removeAll()
        try? modelContext.save()
    }
}

/// An attempt whose row is out of the document but whose deletion is still undoable.
/// The climb is held alongside it because detaching has to clear the link — otherwise
/// the climb keeps counting a go the note no longer shows.
private struct DetachedAttempt {
    let attempt: Attempt
    let climb: Climb?
}

/// Lets `UUID` drive `sheet(item:)` / `fullScreenCover(item:)`.
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
