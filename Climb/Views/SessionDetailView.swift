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

    /// One handle per page — each tab is its own editor, with its own cursor and its
    /// own undo stack, and the bar's buttons act on whichever is open.
    @State private var controllers = NoteTab.allCases.map { _ in NoteEditorController() }
    /// The page on screen. Turned by the pills above or by swiping the page itself.
    @State private var tab: NoteTab
    /// Which page holds the keyboard, if any. A page turn hands focus from one editor
    /// to the next, so this is the pair of them rather than a single flag.
    @State private var focusedTab: NoteTab?
    /// The name in the header, which is the session's rather than any page's.
    @FocusState private var isTitleFocused: Bool
    /// How far the open page is scrolled, which is how far the head of the note has
    /// been carried up with it. Its own object rather than a `@State` number so a
    /// scroll redraws the header alone and not the four editors under it.
    @State private var headerScroll = HeaderScroll()
    /// What the header comes to — the room every page holds open at its top.
    @State private var headerHeight: CGFloat = 0

    /// The global bar's model — the bar and the timer live above the whole
    /// navigation stack (see SessionListView); this page just registers its
    /// actions with it while on screen.
    @Environment(BottomBarModel.self) private var barModel
    private var stopwatch: StopwatchModel { barModel.stopwatch }
    @State private var pendingAttemptID: UUID?
    /// A retake asked for from the replay page, waiting for that sheet to close.
    @State private var retakeAfterClose = false
    /// When the attempt being reviewed stopped recording — what its rest is measured
    /// from once the page closes.
    @State private var attemptRestStart: Date?
    @State private var openedAttemptID: UUID?
    /// Outlives `openedAttemptID`, which is already nil by the time the sheet's dismissal
    /// handler runs.
    @State private var editedAttemptID: UUID?
    /// Where the opened attempt's player starts — set by tapping a timestamp in the note.
    @State private var openedAttemptStart: TimeInterval?
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
        // Before anything reads a page: a note written before the tabs kept its name
        // as its first line, and the header has to be handed it rather than the main
        // page opening with the title still sitting in it. Does nothing the second
        // time, which is every time after this one.
        session.splitTitleIfNeeded()
        // The walkthrough is taught on the main page, and a session already checked in
        // has no reason to open on the card again.
        let opening: NoteTab = session.id == Tutorial.id || session.readiness != nil ? .main : .checkIn
        _tab = State(initialValue: opening)
    }

    /// The page holding the keyboard, if the note is being typed in at all.
    private var isEditing: Bool { focusedTab != nil }

    /// The handle for the page on screen — what the bar's buttons and the attempt
    /// sheets act through.
    private var editorController: NoteEditorController { controllers[tab.rawValue] }

    var body: some View {
        ZStack(alignment: .top) {
            // The pages run the whole height of the screen, under the bars at both
            // ends and under the header itself — they hold the room open with their
            // own content inset, so what is chrome is chrome and what is page is the
            // whole screen.
            pages
            NoteHeader(session: session,
                       scroll: headerScroll,
                       tab: $tab,
                       placeholder: guide.isRunning ? NoteDocument.workoutName : NoteDocument.titlePlaceholder,
                       isTitleFocused: $isTitleFocused,
                       onHeight: { headerHeight = $0 })
        }
        .background(Color.black)
        .background(BarParkAnchor(model: barPark))
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
        // Every ask answered is worth feeling — the button pressed and the name given
        // both count, which is what `reached` counts. Only going forward: walking the
        // walkthrough back is a correction, not an achievement.
        .onChange(of: guide.reached) { was, now in
            guard now > was else { return }
            Haptics.stepDone()
        }
        // The walkthrough's last step, and the only one that leaves nothing behind in
        // the note: opening the rest panel is a tap and nothing else, so it is watched
        // here rather than read back out of the document.
        .onChange(of: stopwatch.isChoosing) { _, isChoosing in
            if isChoosing { guide.restOpened() }
        }
        .onAppear {
            if guide.isRunning { Haptics.warmUp() }
            barPark.onParkedVisibilityChange = { barModel.parkedVisible = $0 }
            // A note opened by the new-note button lands typing at its name, the way
            // Notes does — except the name is in the header now, not the first line.
            if startsEditing { isTitleFocused = true }
        }
        // The name is the one thing above the tabs, so it saves on its own rather than
        // through a page's editor.
        .onChange(of: session.title) {
            // A title is one line. `axis: .vertical` lets it wrap, which also lets
            // Return put a break in it — so the break is taken as the Done it meant.
            if session.title.contains("\n") {
                session.title = session.title.replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                isTitleFocused = false
            }
            session.updatedAt = Date()
            saveChanges()
        }
        // Turning a page with the keyboard up would leave it up over a page nobody
        // asked to type in.
        // Felt here rather than on the pills, so a page turned by swiping lands the
        // same as one turned by tapping — it is the page arriving that is worth a tap
        // of the phone, not the gesture that asked for it.
        .onChange(of: tab) { left, arrived in
            Haptics.selection()
            // The page being left is the one holding the keyboard, so it is the one
            // asked to give it up.
            controllers[left.rawValue].endEditing()
            isTitleFocused = false
            // The page arrived at has its own scroll position, and nothing will report
            // it until someone touches it — so it is asked, and the head of the note
            // travels to where that page has it rather than cutting to it. A page turn
            // is a move between two places, not a place appearing.
            withAnimation(.snappy(duration: 0.3)) {
                headerScroll.travel = max(0, controllers[arrived.rawValue].scrolledDistance)
            }
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
        // Both bars are their own floating buttons and nothing else: no backdrop
        // behind either of them, so the page is one surface from the top edge of the
        // screen to the bottom rather than a top, a middle and a bottom.
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
        .scrollEdgeEffectHidden(true, for: .all)
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
        .sheet(item: $pendingAttemptID, onDismiss: closeAttemptSheet) { id in
            AttemptFlowView(
                attemptID: id,
                ordinal: editorController.nextAttemptOrdinal(),
                // The heading this attempt will land under, so the recording page is
                // headed like the replay page.
                climbName: editorController.currentClimbName(),
                // The rest clock is started by the flow itself, the moment the
                // recording stops — the page that follows shows it running.
                stopwatch: stopwatch,
                attempt: { session.attempt(with: id) },
                onCapture: { saveAttempt(id: id, captured: $0) },
                onDiscard: { discardAttempt(id: id) },
                onClose: { pendingAttemptID = nil }
            )
        }
        // A native sheet, so dragging the page around comes from the system. On dismiss
        // rather than on Done: the note has to come back showing what the page ended up
        // saying.
        .sheet(item: $openedAttemptID, onDismiss: {
            syncEditedAttempt()
            // A retake can't open the camera until this sheet is actually gone — two
            // sheets swapping in one turn of the run loop leaves neither on screen.
            if retakeAfterClose {
                retakeAfterClose = false
                pendingAttemptID = UUID()
            }
        }) { id in
            if let attempt = session.attempt(with: id) {
                AttemptDetailView(
                    attempt: attempt,
                    ordinal: editorController.groupOrdinal(of: id) ?? session.ordinal(of: id),
                    startAt: openedAttemptStart,
                    stopwatch: stopwatch,
                    // Both do exactly what deleting the row in the note does — the
                    // reconcile on dismiss detaches the attempt, and Undo in the
                    // corner covers it until the note is left. Retake then opens the
                    // camera on the way out.
                    actions: AttemptActions(
                        onRetake: {
                            removeAttemptRow(id: id)
                            retakeAfterClose = true
                            openedAttemptID = nil
                        },
                        onDelete: {
                            removeAttemptRow(id: id)
                            openedAttemptID = nil
                        }
                    ),
                    onDone: { openedAttemptID = nil }
                )
            }
        }
    }

    // MARK: Header

    /// Scrolling on the page that is open. Straight through, no thresholds and no
    /// latching: the head of the note is being carried by the page under it, so it
    /// moves exactly as far as the page does until the pills reach the top.
    ///
    /// Pulling past the top is not travel — the head stays where it is rather than
    /// being dragged further down than it belongs.
    private func pageScrolled(_ distance: CGFloat, from page: NoteTab) {
        guard page == tab else { return }
        headerScroll.travel = max(0, distance)
    }

    // MARK: Pages

    /// The four documents, swipeable. Each is a real editor of its own, so turning a
    /// page keeps the cursor, the scroll and the undo stack of the one you left.
    private var pages: some View {
        TabView(selection: $tab) {
            ForEach(NoteTab.allCases) { page in
                editor(for: page)
                    // On the page itself, not on the `TabView` around it: the paging
                    // view lays its children out inside the bars whatever the
                    // container was told, and a page inset by them is a page cut off
                    // in a straight line at both ends.
                    .ignoresSafeArea(.container, edges: .vertical)
                    .tag(page)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Both here and on each page, and both are load-bearing: this one is what
        // stops the paging view clipping its children at the bars — measured with the
        // editor tinted, which showed its frame ending exactly at the nav bar and the
        // toolbar — and the one inside is what stops each page laying itself out
        // inside them.
        .ignoresSafeArea(.container, edges: .vertical)
    }

    private func editor(for page: NoteTab) -> some View {
        NoteEditor(
            session: session,
            tab: page,
            controller: controllers[page.rawValue],
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
            onFocusChange: { focused in focusChanged(page, focused: focused) },
            onScroll: { pageScrolled($0, from: page) },
            topInset: headerHeight
        )
    }

    /// A page taking or giving up the keyboard. Two pages can report in one turn of the
    /// run loop — a swipe hands focus straight over — so a page only ever clears the
    /// flag it set itself.
    private func focusChanged(_ page: NoteTab, focused: Bool) {
        if focused {
            focusedTab = page
        } else if focusedTab == page {
            focusedTab = nil
        }
        barModel.isEditing = isEditing
        // The keyboard can come back without the will-change notification
        // arriving in a useful order — dismissing the attempt sheet hands
        // focus straight back — so the bar swap keys off focus too.
        if focused { barPark.lift() }
    }

    // MARK: Toolbar

    /// Split out of `body` purely for the type-checker: inlined, the toolbar's
    /// branches plus the sized glyphs push the one-expression body past what it
    /// will solve in reasonable time.
    /// Undo, left of whatever else the corner is holding — the ellipsis with the
    /// keyboard down, the Done check with it up. It is the only way back now that the
    /// shake gesture is off, so it stays put, dimmed, when there is nothing to undo.
    private var undoButton: some View {
        Button {
            editorController.undo()
        } label: {
            Label { Text("Undo") } icon: { topBarGlyph("arrow.uturn.backward") }
        }
        .labelStyle(.iconOnly)
        .disabled(!editorController.canUndo)
    }

    /// Redo, in the same bubble as undo. Its own button, not a line in the ellipsis:
    /// taking an edit back and putting it again are the same gesture at the same
    /// moment, and one of them being two taps down a menu makes the pair unusable.
    private var redoButton: some View {
        Button {
            editorController.redo()
        } label: {
            Label { Text("Redo") } icon: { topBarGlyph("arrow.uturn.forward") }
        }
        .labelStyle(.iconOnly)
        .disabled(!editorController.canRedo)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Onboarding owns both corners itself — back to the quiz, and Skip/Done — so
        // the note contributes nothing up top while it is the walkthrough.
        if isOnboarding {
            ToolbarItem(placement: .topBarTrailing) { EmptyView() }
        } else if isEditing || isTitleFocused {
            // Undo and redo share one bubble — they are one control with two
            // directions — and the spacer breaks the glass so Done gets its own
            // circle beside it.
            ToolbarItemGroup(placement: .topBarTrailing) {
                undoButton
                redoButton
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorController.endEditing()
                    isTitleFocused = false
                } label: {
                    Label { Text("Done") } icon: { topBarGlyph("checkmark") }
                }
                .labelStyle(.iconOnly)
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                undoButton
                redoButton
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Label { Text("More") } icon: { topBarGlyph("ellipsis") }
                        .labelStyle(.iconOnly)
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

    /// A recording becomes an attempt the moment it lands — there is no "save" step.
    /// The attempt joins the session first, then the row is inserted: the inline view
    /// reads its data straight out of the session as it lays out. The sheet stays up
    /// on the attempt's own page, where it can be annotated, retaken or deleted.
    private func saveAttempt(id: UUID, captured: CapturedAttempt) {
        let attempt = Attempt(id: id)
        attempt.videoFilename = captured.videoFilename
        attempt.thumbnailFilename = captured.thumbnailFilename
        attempt.videoDuration = captured.duration
        attempt.session = session
        session.attempts.append(attempt)
        modelContext.insert(attempt)

        // Notes are typed into the page over the next while, so the sheet closing is
        // what puts them into the document (`closeAttemptSheet`).
        editedAttemptID = id
        attemptRestStart = captured.stoppedAt
        // Inserting rebuilds the rows, which also refreshes the heading's now-stale
        // "7 attempts · 3 sessions" line and renumbers the group.
        editorController.insertAttempt(id: id)
        saveChanges()
    }

    /// Retake and Delete both land here. The attempt was saved the instant it was
    /// recorded, so taking it back means unwinding all of it — row, record and video.
    /// Held onto first: pulling the row detaches the attempt from the session before
    /// the delete gets a look at it.
    private func discardAttempt(id: UUID) {
        let doomed = session.attempt(with: id) ?? detached.first { $0.attempt.id == id }?.attempt
        editorController.removeMarker(for: id)
        detached.removeAll { $0.attempt.id == id }
        session.attempts.removeAll { $0.id == id }
        if let doomed {
            VideoStore.delete(doomed)
            modelContext.delete(doomed)
        }
        editedAttemptID = nil
        attemptRestStart = nil
        try? modelContext.save()
    }

    /// The sheet is gone: the rest this attempt got is however long the page was up,
    /// counted from the moment the recording stopped, and the notes written on it go
    /// into the document. Then back to typing under the new row — UIKit only restores
    /// the keyboard by itself when the note was being edited at present time, so
    /// asking makes it every time.
    private func closeAttemptSheet() {
        if let id = editedAttemptID, let start = attemptRestStart,
           let attempt = session.attempt(with: id) {
            attempt.restSeconds = Date().timeIntervalSince(start)
        }
        attemptRestStart = nil
        syncEditedAttempt()
        editorController.focus()
    }

    /// Takes a row out of the note from the attempt page itself.
    ///
    /// Clearing the edited id is the whole point: the sync that runs when the page is
    /// dismissed writes that attempt's notes back into the document, and with its row
    /// gone they land as ordinary text — clip clocks and all — with nothing left to
    /// bind them to. `discardAttempt` clears it for the same reason.
    private func removeAttemptRow(id: UUID) {
        editorController.removeMarker(for: id)
        editedAttemptID = nil
        openedAttemptStart = nil
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
        let referenced = Set(session.allAttachmentIDs)

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
