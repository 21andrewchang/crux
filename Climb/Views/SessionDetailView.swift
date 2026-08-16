import Combine
import SwiftUI
import SwiftData
import UIKit

/// The note. Type freely; "Start Attempt" drops a recorded go into the document.
struct SessionDetailView: View {
    @Bindable var session: ClimbSession
    /// Raise the keyboard as the note opens — true only for a note just created.
    var startsEditing = false
    /// The note is standing in for the whole app during onboarding. Its own top-bar
    /// actions — the ellipsis, and Delete under it — are not part of the walkthrough,
    /// so the corner is left to whoever is hosting it (see `RootView`).
    var isOnboarding = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Only consulted for notes saved before climbs became plain text: an old stored
    /// climb's marker resolves to its name and comes back as an inline bubble.
    @Query private var climbs: [Climb]

    @State private var editorController = NoteEditorController()
    /// The global bar's model — the bar and the timer live above the whole
    /// navigation stack (see SessionListView); this page just registers its
    /// actions with it while on screen.
    @Environment(BottomBarModel.self) private var barModel
    private var stopwatch: StopwatchModel { barModel.stopwatch }
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
    /// Tracked off the keyboard notifications to tell rises from dismissals.
    @State private var keyboardHeight: CGFloat = 0
    @State private var isConfirmingDelete = false
    @State private var isConfirmingRowDelete = false
    /// Camera tapped while the rest countdown is still running.
    @State private var isConfirmingEarlyAttempt = false
    @State private var doomedRowCount = 0
    /// Attempts whose rows have been removed but whose deletion is still undoable.
    @State private var detached: [DetachedAttempt] = []
    /// The tutorial's walkthrough. Built with the session rather than started on
    /// appearance, so the very first bar this page draws is already the right one.
    @State private var guide: TutorialGuide

    init(session: ClimbSession, startsEditing: Bool = false, isOnboarding: Bool = false) {
        self.session = session
        self.startsEditing = startsEditing
        self.isOnboarding = isOnboarding
        _guide = State(initialValue: TutorialGuide(session: session))
    }

    var body: some View {
        NoteEditor(
            session: session,
            controller: editorController,
            onStartAttempt: startAttempt,
            onAddClimb: { editorController.insertClimbHeader() },
            onAddSection: { editorController.insertSectionHeader() },
            stopwatch: stopwatch,
            guide: guide,
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
                barModel.isEditing = focused
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
        // The timer renders globally, above the navigation stack
        // (SessionListView); this page mirrors the state it positions itself
        // off, and wires the keyboard swap: the global capsule gets the same
        // flip the bar chrome does — hidden the instant the keyboard bar
        // lifts, back when the clone lands or the screen exits.
        // The rest capsule is drawn globally, over the whole stack, so the walkthrough
        // reaches it through the bar's model rather than directly.
        .onChange(of: guide.isRestUnlocked, initial: true) {
            barModel.isRestLocked = !guide.isRestUnlocked
        }
        .onAppear {
            barPark.onParkedVisibilityChange = { barModel.parkedVisible = $0 }
            // A note opened by the new-note button lands typing at its title, the way
            // Notes does — the caret sits at the top of an empty document already.
            if startsEditing { editorController.focus() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboardHeight = max(0, UIScreen.main.bounds.maxY - frame.minY)
            barModel.keyboardHeight = keyboardHeight
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
            barModel.isEditing = false
            barModel.isRestLocked = false
            discardDetachedAttempts()
        }
        // No date in the top bar — it lives in the note itself, above the title.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar { toolbarContent }
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
        .alert("Still Resting", isPresented: $isConfirmingEarlyAttempt) {
            Button("Cancel", role: .cancel) {}
            Button("Yes", role: .destructive) { pendingAttemptID = UUID() }
        } message: {
            Text("Are you sure you start an attempt?")
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

    // MARK: Toolbar

    /// Split out of `body` purely for the type-checker: inlined, the toolbar's
    /// branches plus the sized glyphs push the one-expression body past what it
    /// will solve in reasonable time.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Onboarding owns both corners itself — back to the quiz, and Skip/Done — so
        // the note contributes nothing up top while it is the walkthrough.
        if isOnboarding {
            ToolbarItem(placement: .topBarTrailing) { EmptyView() }
        } else if isEditing {
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

        // The leading pill: real system bottom-bar items, which is what
        // buys the Notes push transition — the search field morphs into
        // these. Only the timer stays out of the system bar (rendered
        // globally over the stack; it could never be chromed right here);
        // the trailing stand-in below holds its slot open and relays its
        // taps, since the bar band swallows touches aimed at overlays.
        // While editing, the keyboard accessory clone in NoteEditor takes
        // over at the same metrics; `barPark` snaps the bar's chrome and
        // the global capsule in step with the keyboard.
        //
        // Left alone, these draw at the system's own ~27pt bar metric, and a
        // `.font` on the item does NOT move them — the bar re-applies its own
        // metric to a `systemImage` label. So the mark is handed over as a
        // finished raster from `barGlyph` instead, the very same call the
        // keyboard clone makes: not an SF Symbol as far as the bar is
        // concerned, so nothing downstream can resize it. Both bars therefore
        // draw one identical image, and the icons hold their size through the
        // keyboard swap.
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                editorController.insertSectionHeader()
            } label: {
                Label { Text("Add Section") } icon: {
                    systemBarGlyph("textformat.size", opacity: lockedFade(guide.isSectionUnlocked))
                }
            }
            .labelStyle(.iconOnly)
            .dampedToolbarMorph()
            .allowsHitTesting(guide.isSectionUnlocked)
            // Darkened out while the tutorial's walkthrough is still working up to
            // them — see `TutorialGuide`. Both bars dim the same buttons, so the
            // keyboard swap lands on the same pill either way. Held back by hit
            // testing rather than `disabled`, which the system dims a second time
            // on top of ours and would leave this bar darker than the clone.
            Button {
                editorController.insertClimbHeader()
            } label: {
                Label { Text("Add Climb") } icon: {
                    systemBarGlyph("plus", opacity: lockedFade(guide.isClimbUnlocked))
                }
            }
            .labelStyle(.iconOnly)
            .dampedToolbarMorph()
            .allowsHitTesting(guide.isClimbUnlocked)
            Button(action: startAttempt) {
                Label { Text("Record Attempt") } icon: {
                    systemBarGlyph("video.fill", opacity: lockedFade(guide.isAttemptUnlocked))
                }
            }
            .labelStyle(.iconOnly)
            .dampedToolbarMorph()
            .allowsHitTesting(guide.isAttemptUnlocked)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button {
                stopwatch.toggleMenu()
            } label: {
                // Under-sized by the system's ~14-per-side label padding so
                // the slot matches the capsule; hit area grown back out.
                // No measuring here — the capsule's position is pinned once
                // off the settled list, and tracking it across transitions
                // made it jump.
                Color.clear
                    .frame(width: max(20, barModel.capsuleWidth - 28 + 16), height: 48)
                    .contentShape(Rectangle().inset(by: -14))
            }
            .buttonStyle(.plain)
            // The capsule it stands in for is dark and deaf during the walkthrough;
            // the relay has to be too, or the panel opens from behind it.
            .disabled(!guide.isRestUnlocked)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    /// How far down a bar glyph is drawn for a step the walkthrough has not reached.
    private func lockedFade(_ isUnlocked: Bool) -> Double {
        isUnlocked ? 1 : TutorialGuide.lockedOpacity
    }

    // MARK: Attempt lifecycle

    private func startAttempt() {
        // Mid-countdown, recording means cutting the rest short — check first.
        if stopwatch.hasStarted, stopwatch.remaining(at: Date()) > 0 {
            isConfirmingEarlyAttempt = true
        } else {
            pendingAttemptID = UUID()
        }
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
