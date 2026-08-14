import SwiftUI
import SwiftData

/// The note. Type freely; "Start Attempt" drops a recorded go into the document.
struct SessionDetailView: View {
    @Bindable var session: ClimbSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The whole library — the editor resolves climb markers against it, and it is
    /// small enough that a query beats a fetch per attachment.
    @Query private var climbs: [Climb]

    @State private var editorController = NoteEditorController()
    @State private var pendingAttemptID: UUID?
    @State private var openedAttemptID: UUID?
    /// Outlives `openedAttemptID`, which is already nil by the time the sheet's dismissal
    /// handler runs.
    @State private var editedAttemptID: UUID?
    @State private var openedClimbID: UUID?
    @State private var isPickingClimb = false
    @State private var isEditing = false
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
            onAddClimb: { isPickingClimb = true },
            onOpenAttempt: {
                openedAttemptID = $0
                editedAttemptID = $0
            },
            climbSnapshot: snapshot(forClimb:),
            onOpenClimb: { openedClimbID = $0 },
            onConfirmDelete: { count in
                doomedRowCount = count
                isConfirmingRowDelete = true
            },
            onChange: saveChanges,
            onFocusChange: { isEditing = $0 }
        )
        .background(Color.black)
        .ignoresSafeArea(.container, edges: .bottom)
        .onDisappear(perform: discardDetachedAttempts)
        .navigationTitle(session.createdAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { editorController.endEditing() }
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
        .fullScreenCover(item: $pendingAttemptID) { id in
            AttemptFlowView(
                attemptID: id,
                ordinal: editorController.nextAttemptOrdinal(),
                onFinish: { finishAttempt(id: id, captured: $0) },
                onCancel: { pendingAttemptID = nil }
            )
        }
        .sheet(isPresented: $isPickingClimb) {
            ClimbPickerView(onPick: addClimb)
        }
        .sheet(item: $openedClimbID) { id in
            if let climb = climb(with: id) {
                ClimbDetailView(climb: climb) {
                    openedClimbID = nil
                    saveChanges()
                    editorController.refreshRows()
                }
            }
        }
        // On dismiss rather than on Done: swiping the sheet away is an edit too, and the
        // note has to come back showing what the sheet ended up saying.
        .sheet(item: $openedAttemptID, onDismiss: syncEditedAttempt) { id in
            if let attempt = session.attempt(with: id) {
                AttemptDetailView(
                    attempt: attempt,
                    ordinal: editorController.groupOrdinal(of: id) ?? session.ordinal(of: id),
                    onDelete: { delete(attempt) },
                    onDone: { openedAttemptID = nil }
                )
            }
        }
    }

    // MARK: Climbs

    private func climb(with id: UUID) -> Climb? {
        climbs.first { $0.id == id }
    }

    private func snapshot(forClimb id: UUID) -> ClimbSnapshot? {
        climb(with: id).map { ClimbSnapshot(name: $0.name, attemptCount: $0.attempts.count) }
    }

    /// Drops a heading into the note. Everything recorded below it is filed against
    /// this climb until the next heading.
    private func addClimb(_ climb: Climb) {
        editorController.insertClimb(id: climb.id)
        saveChanges()
    }

    // MARK: Attempt lifecycle

    private func startAttempt() {
        pendingAttemptID = UUID()
    }

    /// The attempt joins the session first, then the row is inserted — the inline view
    /// reads its data straight out of the session as it lays out.
    private func finishAttempt(id: UUID, captured: CapturedAttempt) {
        // Read before inserting: the cursor is still where the row is about to land,
        // so this is the heading the user is typing under.
        let activeClimb = editorController.currentClimbID().flatMap(climb(with:))

        let attempt = Attempt(id: id)
        attempt.climb = activeClimb
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
        saveChanges()
    }

    /// Deleting from the sheet is the same edit as backspacing the row out: take the
    /// marker out of the document and let the reconcile below follow it.
    private func delete(_ attempt: Attempt) {
        openedAttemptID = nil
        editorController.removeMarker(for: attempt.id)
    }

    /// Notes written in the sheet are on the attempt already; this is what puts them
    /// into the note's own text. A deleted attempt has nothing to sync.
    private func syncEditedAttempt() {
        guard let id = editedAttemptID else { return }
        editedAttemptID = nil
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
