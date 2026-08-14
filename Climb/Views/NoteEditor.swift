import SwiftUI
import UIKit

/// Imperative handle onto the live text view, so the rest of the app can insert an
/// attempt at the cursor or refresh rows without owning the editor's state.
final class NoteEditorController {
    fileprivate weak var coordinator: NoteEditor.Coordinator?

    func insertAttempt(id: UUID) {
        coordinator?.insertAttempt(id: id)
    }

    func insertClimb(id: UUID) {
        coordinator?.insertClimb(id: id)
    }

    /// The climb heading the cursor currently sits under, if any.
    func currentClimbID() -> UUID? {
        coordinator?.currentClimbID()
    }

    /// An attempt's number within its climb group, as the note currently reads.
    func groupOrdinal(of id: UUID) -> Int? {
        coordinator?.groupOrdinal(of: id)
    }

    /// The number the attempt about to be recorded at the cursor will carry.
    func nextAttemptOrdinal() -> Int {
        coordinator?.nextAttemptOrdinal() ?? 1
    }

    /// Re-labels inline rows after an attempt's details change elsewhere.
    func refreshRows() {
        coordinator?.refreshRowLabels()
    }

    /// Takes a block out of the document. Undoable, and the attempt comes back with it.
    func removeMarker(for id: UUID) {
        coordinator?.removeMarker(for: id)
    }

    /// Goes through with the edit that `onConfirmDelete` paused.
    func confirmPendingDeletion() {
        coordinator?.confirmPendingDeletion()
    }

    func cancelPendingDeletion() {
        coordinator?.cancelPendingDeletion()
    }

    /// Puts notes edited outside the note back into the row's quote.
    func setNotes(_ notes: String, for id: UUID) {
        coordinator?.setNotes(notes, for: id)
    }

    func endEditing() {
        coordinator?.textView?.resignFirstResponder()
    }
}

/// The note itself: a plain `UITextView` you can just type in, with attempts embedded
/// as text attachments.
struct NoteEditor: UIViewRepresentable {
    let session: ClimbSession
    let controller: NoteEditorController
    /// Presents the toolbar action. Owned by the SwiftUI layer so capture flow stays there.
    var onStartAttempt: () -> Void
    var onAddClimb: () -> Void
    var onOpenAttempt: (UUID) -> Void
    /// Resolves a marker ID to a climb; returning nil is how the editor tells the two
    /// kinds of marker apart, and how it drops references to climbs that are gone.
    var climbSnapshot: (UUID) -> ClimbSnapshot?
    var onOpenClimb: (UUID) -> Void
    /// An edit is about to take this many attempt rows out. The editor holds it until
    /// the answer comes back through `confirmPendingDeletion` / `cancelPendingDeletion`.
    var onConfirmDelete: (Int) -> Void
    var onChange: () -> Void
    var onFocusChange: (Bool) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = NoteTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        // `.interactive` drags the keyboard only: the accessory bar rides above your
        // finger, so it beaches at the bottom edge and then pops out of existence when
        // the text view resigns. `.interactiveWithAccessory` drags the bar too.
        textView.keyboardDismissMode = .interactiveWithAccessory
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 16, bottom: 120, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.typingAttributes = NoteDocument.bodyAttributes
        textView.attributedText = NSAttributedString(string: "", attributes: NoteDocument.bodyAttributes)

        context.coordinator.textView = textView
        context.coordinator.attachAccessoryView(to: textView)
        context.coordinator.attachPlaceholder(to: textView)
        context.coordinator.reloadDocument()
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Deliberately does not push text back into the view: the text view is the
        // source of truth while editing, and reassigning would fight the cursor.
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(parent: self)
        controller.coordinator = coordinator
        return coordinator
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteEditor
        weak var textView: UITextView?
        private var accessoryHost: UIHostingController<KeyboardToolbar>?
        private weak var placeholderLabel: UILabel?
        private var isRestyling = false
        /// An edit held back pending confirmation, as `(range, replacement)`.
        private var pendingDeletion: (range: NSRange, replacement: String)?

        init(parent: NoteEditor) {
            self.parent = parent
        }

        // MARK: Document

        func reloadDocument() {
            guard let textView else { return }
            let selected = textView.selectedRange
            let document = NoteDocument.attributedString(for: parent.session) { [weak self] id in
                self?.makeAttachment(for: id)
            }
            // `textStorage`, not `attributedText`: assigning to the latter empties the
            // undo stack, and a reload has to be able to happen mid-edit.
            textView.textStorage.setAttributedString(document)
            textView.selectedRange = NSRange(location: min(selected.location, document.length), length: 0)
            syncTypingAttributes()
            updatePlaceholder()
        }

        /// Re-labels the rows where they stand — renumbering a group, or picking up a
        /// note edited in a sheet. Rebuilding the document would do it too, but this is
        /// only ever a label change, and it leaves the text (and the undo stack) alone.
        func refreshRowLabels() {
            guard let storage = textView?.textStorage else { return }
            storage.enumerateAttribute(.attachment,
                                       in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                switch value {
                case let attempt as AttemptAttachment:
                    if let row = attempt.rowView, let snapshot = snapshot(for: attempt.attemptID) {
                        row.configure(with: snapshot)
                    }
                case let climb as ClimbAttachment:
                    if let row = climb.rowView, let snapshot = parent.climbSnapshot(climb.climbID) {
                        row.configure(with: snapshot)
                    }
                default:
                    break
                }
            }
        }

        /// The caret is drawn from `typingAttributes`, which UIKit carries over from the
        /// character before the cursor. On the empty line just after the title that is
        /// still the 28pt title font, so the caret stays tall until the first keystroke
        /// restyles the line. Recomputing from the cursor's line makes it shrink on Return.
        private func syncTypingAttributes() {
            guard let textView else { return }
            let storage = textView.textStorage
            let firstLine = (storage.string as NSString).lineRange(for: NSRange(location: 0, length: 0))
            let onTitleLine = storage.length == 0 || textView.selectedRange.location < NSMaxRange(firstLine)
            guard !onTitleLine else {
                textView.typingAttributes = NoteDocument.titleAttributes
                return
            }
            // Inside a quote, typing carries the quote's style *and* its binding, so
            // what gets typed there is part of that attempt's notes.
            if let id = quoteID(at: textView.selectedRange.location) {
                textView.typingAttributes = NoteDocument.quoteAttributes(for: id)
            } else {
                textView.typingAttributes = NoteDocument.bodyAttributes
            }
        }

        /// Past the end of the notes the caret is in, if it is in any — where a new block
        /// can go without cutting them off from their row.
        private func endOfQuote(at location: Int) -> Int {
            guard let storage = textView?.textStorage, storage.length > 0 else { return location }
            for index in [location - 1, location] where index >= 0 && index < storage.length {
                var run = NSRange(location: 0, length: 0)
                guard storage.attribute(NoteDocument.noteQuote, at: index, effectiveRange: &run) != nil else {
                    continue
                }
                return min(NSMaxRange(run), storage.length)
            }
            return location
        }

        /// The attempt whose notes the caret is inside, looking behind it first: that is
        /// the run typing extends.
        private func quoteID(at location: Int) -> UUID? {
            guard let storage = textView?.textStorage, storage.length > 0 else { return nil }
            for index in [location - 1, location] where index >= 0 && index < storage.length {
                if let id = storage.attribute(NoteDocument.noteQuote, at: index, effectiveRange: nil) as? UUID {
                    return id
                }
            }
            return nil
        }

        // MARK: Placeholder

        /// A label rather than placeholder text in the storage: real text would be
        /// serialized into `bodyText` and become the session's title.
        func attachPlaceholder(to textView: UITextView) {
            let label = UILabel()
            label.numberOfLines = 0
            label.attributedText = NoteDocument.placeholderText
            label.isUserInteractionEnabled = false
            label.translatesAutoresizingMaskIntoConstraints = false
            textView.addSubview(label)

            // Pinned to the frame, not the content: it only shows when there is nothing
            // to scroll, and must not drift with contentOffset.
            let inset = textView.textContainerInset
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: textView.frameLayoutGuide.topAnchor, constant: inset.top),
                label.leadingAnchor.constraint(equalTo: textView.frameLayoutGuide.leadingAnchor, constant: inset.left),
                label.trailingAnchor.constraint(equalTo: textView.frameLayoutGuide.trailingAnchor, constant: -inset.right),
            ])
            placeholderLabel = label
        }

        private func updatePlaceholder() {
            placeholderLabel?.isHidden = (textView?.textStorage.length ?? 0) > 0
        }

        /// A marker ID is an attempt if the session owns one, otherwise a climb.
        private func makeAttachment(for id: UUID) -> NSTextAttachment? {
            if parent.session.attempt(with: id) != nil { return makeAttemptAttachment(for: id) }
            if parent.climbSnapshot(id) != nil { return makeClimbAttachment(for: id) }
            return nil
        }

        private func makeAttemptAttachment(for id: UUID) -> AttemptAttachment {
            let attachment = AttemptAttachment(attemptID: id)
            attachment.snapshotProvider = { [weak self] id in self?.snapshot(for: id) }
            attachment.onTap = { [weak self] id in self?.parent.onOpenAttempt(id) }
            return attachment
        }

        private func markerRange(for id: UUID) -> NSRange? {
            guard let storage = textView?.textStorage else { return nil }
            var target: NSRange?
            storage.enumerateAttribute(.attachment,
                                       in: NSRange(location: 0, length: storage.length)) { value, range, stop in
                if let marker = value as? MarkerAttachment, marker.markerID == id {
                    target = range
                    stop.pointee = true
                }
            }
            return target
        }

        private func makeClimbAttachment(for id: UUID) -> ClimbAttachment {
            let attachment = ClimbAttachment(climbID: id)
            attachment.snapshotProvider = { [weak self] id in self?.parent.climbSnapshot(id) }
            attachment.onTap = { [weak self] id in self?.parent.onOpenClimb(id) }
            return attachment
        }

        private func snapshot(for id: UUID) -> AttemptSnapshot? {
            let session = parent.session
            guard let attempt = session.attempt(with: id) else { return nil }
            let thumbnail = attempt.thumbnailURL.flatMap { UIImage(contentsOfFile: $0.path) }
            return AttemptSnapshot(ordinal: groupOrdinal(of: id) ?? session.ordinal(of: id),
                                   duration: attempt.videoDuration,
                                   rest: attempt.restSeconds,
                                   notes: attempt.notes,
                                   thumbnail: thumbnail)
        }

        /// Attempts are numbered within their climb group — the run of rows under one
        /// heading — so the count restarts at 1 under each new climb. Rows above the
        /// first heading form their own group.
        func groupOrdinal(of id: UUID) -> Int? {
            guard let storage = textView?.textStorage else { return nil }
            var ordinal = 0
            var found: Int?
            storage.enumerateAttribute(.attachment,
                                       in: NSRange(location: 0, length: storage.length)) { value, _, stop in
                if value is ClimbAttachment {
                    ordinal = 0
                } else if let attempt = value as? AttemptAttachment {
                    ordinal += 1
                    if attempt.attemptID == id {
                        found = ordinal
                        stop.pointee = true
                    }
                }
            }
            return found
        }

        /// What the next attempt recorded at the cursor will be called.
        func nextAttemptOrdinal() -> Int {
            guard let textView else { return 1 }
            let storage = textView.textStorage
            let upToCursor = NSRange(location: 0,
                                     length: min(textView.selectedRange.location, storage.length))
            guard upToCursor.length > 0 else { return 1 }

            var ordinal = 0
            storage.enumerateAttribute(.attachment, in: upToCursor) { value, _, _ in
                if value is ClimbAttachment {
                    ordinal = 0
                } else if value is AttemptAttachment {
                    ordinal += 1
                }
            }
            return ordinal + 1
        }

        /// The row lands with its notes already under it — whatever was written during
        /// capture — and the caret at the end of them, ready to add more.
        func insertAttempt(id: UUID) {
            let notes = parent.session.attempt(with: id)?.notes ?? ""
            insert(makeAttemptAttachment(for: id),
                   quote: NSAttributedString(string: notes, attributes: NoteDocument.quoteAttributes(for: id)))
        }

        func insertClimb(id: UUID) {
            insert(makeClimbAttachment(for: id), quote: nil)
        }

        /// The last climb heading before the cursor. Attempts recorded here are filed
        /// against it, which is what "typing under a climb" means in the document.
        func currentClimbID() -> UUID? {
            guard let textView else { return nil }
            let storage = textView.textStorage
            let upToCursor = NSRange(location: 0,
                                     length: min(textView.selectedRange.location, storage.length))
            guard upToCursor.length > 0 else { return nil }

            var found: UUID?
            storage.enumerateAttribute(.attachment, in: upToCursor) { value, _, _ in
                if let climb = value as? ClimbAttachment { found = climb.climbID }
            }
            return found
        }

        /// `notes` non-nil means the row carries a quote block: the line under it is
        private func insert(_ attachment: NSTextAttachment, quote: NSAttributedString?) {
            guard let textView else { return }
            let storage = textView.textStorage
            // Never land in the middle of another attempt's notes: that would strand them
            // below the new block, under a row that is no longer above them.
            let location = endOfQuote(at: min(textView.selectedRange.location, storage.length))
            let string = storage.string as NSString

            // Give the row its own line — it lays out as a block, not an inline glyph.
            let needsLeadingBreak = location > 0 && string.character(at: location - 1) != 0x000A
            let piece = NSMutableAttributedString()
            if needsLeadingBreak {
                piece.append(NSAttributedString(string: "\n", attributes: NoteDocument.bodyAttributes))
            }
            piece.append(NSAttributedString(attachment: attachment))
            piece.append(NSAttributedString(string: "\n", attributes: NoteDocument.bodyAttributes))

            var caret = location + piece.length
            if let quote {
                piece.append(quote)
                caret = location + piece.length
                piece.append(NSAttributedString(string: "\n", attributes: NoteDocument.bodyAttributes))
            }

            performBlockEdit {
                $0.replaceCharacters(in: NSRange(location: location, length: 0), with: piece)
            }
            textView.selectedRange = NSRange(location: caret, length: 0)
            syncTypingAttributes()
        }

        /// Pulls a row out of the document. The attempt behind it is not destroyed here —
        /// `onChange` detaches it, and undoing this edit hands it straight back.
        func removeMarker(for id: UUID) {
            guard let textView, let target = markerRange(for: id) else { return }
            let storage = textView.textStorage

            // The notes go with the row: they are that attempt's, and nothing else's.
            var doomed = target
            storage.enumerateAttribute(NoteDocument.noteQuote,
                                       in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if value as? UUID == id { doomed = doomed.union(range) }
            }

            performBlockEdit { $0.replaceCharacters(in: doomed, with: "") }
            textView.selectedRange = NSRange(location: min(doomed.location, textView.textStorage.length), length: 0)
            syncTypingAttributes()
        }

        /// Every change that adds or removes a block goes through here. UIKit's undo
        /// stack only tracks the edits it makes itself, so ours register their own
        /// inverse: the document as it stood, attachments and all. Registering that
        /// inverse from inside an undo is what gives redo for free.
        private func performBlockEdit(_ mutation: (NSTextStorage) -> Void) {
            guard let textView else { return }
            let before = NSAttributedString(attributedString: textView.textStorage)
            let beforeSelection = textView.selectedRange

            isRestyling = true
            mutation(textView.textStorage)
            NoteDocument.applyStyles(to: textView.textStorage)
            isRestyling = false

            textView.undoManager?.registerUndo(withTarget: self) { coordinator in
                coordinator.performBlockEdit { $0.setAttributedString(before) }
                coordinator.textView?.selectedRange = NSRange(
                    location: min(beforeSelection.location, before.length),
                    length: 0
                )
                coordinator.syncTypingAttributes()
            }

            syncTypingAttributes()
            updatePlaceholder()
            persist()
        }

        // MARK: Deleting a row

        /// Backspacing over a row is a real deletion — the video goes with it — so the
        /// edit is held here and only applied once the user says yes.
        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            pendingDeletion = nil
            if text == "\n", leaveQuoteIfEmpty(at: range) { return false }
            // Backspacing the break under a row would pull the next line up onto the
            // row's own line, where text cannot be that attempt's notes — or anything
            // else legible. The row is deleted by deleting the row.
            if text.isEmpty, mergesIntoBlockLine(range) { return false }

            let doomed = attemptMarkers(in: range)
            guard !doomed.isEmpty else { return true }

            pendingDeletion = (range, text)
            parent.onConfirmDelete(doomed.count)
            return false
        }

        /// Return inside the notes breaks a line like anywhere else. Return again on the
        /// empty line it just made means there is nothing more to add: that line drops
        /// out of the quote and becomes ordinary text, in place.
        private func leaveQuoteIfEmpty(at range: NSRange) -> Bool {
            guard let textView, quoteID(at: range.location) != nil else { return false }
            let storage = textView.textStorage
            let string = storage.string as NSString
            let line = string.lineRange(for: NSRange(location: range.location, length: 0))
            guard string.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }

            if line.length == 0 {
                // Already on a bare last line — only the typing needs to leave the quote.
            } else if isDirectlyUnderRow(line) {
                // The line under a row is always that attempt's notes, so stepping out
                // of an empty one means a new line beneath it rather than taking it.
                let caret = NSMaxRange(line)
                performBlockEdit {
                    $0.insert(NSAttributedString(string: "\n", attributes: NoteDocument.bodyAttributes), at: caret)
                }
                textView.selectedRange = NSRange(location: min(caret, textView.textStorage.length), length: 0)
            } else {
                isRestyling = true
                storage.beginEditing()
                storage.removeAttribute(NoteDocument.noteQuote, range: line)
                storage.addAttributes(NoteDocument.bodyAttributes, range: line)
                storage.endEditing()
                isRestyling = false
                textView.selectedRange = NSRange(location: line.location, length: 0)
                persist()
            }

            textView.typingAttributes = NoteDocument.bodyAttributes
            return true
        }

        /// Whether this edit deletes exactly the line break that ends a row's own line.
        private func mergesIntoBlockLine(_ range: NSRange) -> Bool {
            guard let storage = textView?.textStorage, range.length == 1 else { return false }
            let string = storage.string as NSString
            guard range.location < string.length, string.character(at: range.location) == 0x000A else {
                return false
            }

            let line = string.lineRange(for: NSRange(location: range.location, length: 0))
            var isBlock = false
            storage.enumerateAttribute(.attachment, in: line) { value, _, stop in
                if value is MarkerAttachment {
                    isBlock = true
                    stop.pointee = true
                }
            }
            return isBlock
        }

        private func isDirectlyUnderRow(_ line: NSRange) -> Bool {
            guard let storage = textView?.textStorage, line.location > 0 else { return false }
            let previous = (storage.string as NSString).lineRange(for: NSRange(location: line.location - 1, length: 0))

            var found = false
            storage.enumerateAttribute(.attachment, in: previous) { value, _, stop in
                if let marker = value as? MarkerAttachment, marker.takesNotes {
                    found = true
                    stop.pointee = true
                }
            }
            return found
        }

        func confirmPendingDeletion() {
            guard let pending = pendingDeletion, let textView else { return }
            pendingDeletion = nil

            let replacement = NSAttributedString(string: pending.replacement,
                                                 attributes: NoteDocument.bodyAttributes)
            performBlockEdit { $0.replaceCharacters(in: pending.range, with: replacement) }
            textView.selectedRange = NSRange(location: pending.range.location + replacement.length, length: 0)
            syncTypingAttributes()
        }

        func cancelPendingDeletion() {
            pendingDeletion = nil
        }

        private func attemptMarkers(in range: NSRange) -> [UUID] {
            guard let storage = textView?.textStorage, range.length > 0 else { return [] }
            var ids: [UUID] = []
            storage.enumerateAttribute(.attachment, in: range) { value, _, _ in
                if let attempt = value as? AttemptAttachment { ids.append(attempt.attemptID) }
            }
            return ids
        }

        // MARK: UITextViewDelegate

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange(false)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isRestyling else { return }
            isRestyling = true
            let selected = textView.selectedRange
            NoteDocument.applyStyles(to: textView.textStorage)
            textView.selectedRange = selected
            isRestyling = false
            syncTypingAttributes()
            updatePlaceholder()
            persist()
        }

        /// Moving the caret across the title/body boundary has to resize it too.
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isRestyling else { return }
            syncTypingAttributes()
        }

        /// The quote in the document *is* the attempt's notes, so it is written through
        /// on every edit. One direction only: the document is what the user is typing in.
        private func syncNotes() {
            guard let storage = textView?.textStorage else { return }
            let written = NoteDocument.notes(in: storage)

            // Every row is asked, not just the ones with a quote: notes deleted out of
            // the note have to clear the attempt too, or they would come back on reload.
            var ids: [UUID] = []
            storage.enumerateAttribute(.attachment,
                                       in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                if let attempt = value as? AttemptAttachment { ids.append(attempt.attemptID) }
            }

            for id in ids {
                guard let attempt = parent.session.attempt(with: id) else { continue }
                let notes = written[id] ?? ""
                if attempt.notes != notes { attempt.notes = notes }
            }
        }

        /// Puts notes edited outside the note — in the attempt's sheet — back into its
        /// quote, so the two never disagree.
        func setNotes(_ notes: String, for id: UUID) {
            guard let textView else { return }
            let storage = textView.textStorage

            var target: NSRange?
            storage.enumerateAttribute(NoteDocument.noteQuote,
                                       in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                guard value as? UUID == id else { return }
                target = target.map { $0.union(range) } ?? range
            }
            guard let target else {
                addNotes(notes, for: id)
                return
            }

            // The line break at the end belongs to the document, not to the notes.
            let string = storage.string as NSString
            let hasBreak = string.substring(with: target).hasSuffix("\n")
            let body = NSRange(location: target.location, length: target.length - (hasBreak ? 1 : 0))
            guard string.substring(with: body) != notes else { return }

            performBlockEdit {
                $0.replaceCharacters(in: body,
                                     with: NSAttributedString(string: notes,
                                                              attributes: NoteDocument.quoteAttributes(for: id)))
            }
        }

        /// A row at the very end of the note has no line under it to hold its notes yet.
        /// Writing some in the sheet is what asks for one.
        private func addNotes(_ notes: String, for id: UUID) {
            guard !notes.isEmpty, let textView, let marker = markerRange(for: id) else { return }
            let storage = textView.textStorage
            let string = storage.string as NSString
            let insertAt = NSMaxRange(string.lineRange(for: marker))

            let piece = NSMutableAttributedString()
            if insertAt > 0, string.character(at: insertAt - 1) != 0x000A {
                piece.append(NSAttributedString(string: "\n", attributes: NoteDocument.bodyAttributes))
            }
            piece.append(NSAttributedString(string: notes + "\n",
                                            attributes: NoteDocument.quoteAttributes(for: id)))

            performBlockEdit { $0.insert(piece, at: insertAt) }
        }

        private func persist() {
            guard let textView else { return }
            syncNotes()
            let (text, ids) = NoteDocument.serialize(textView.attributedText)
            // Adding or deleting a marker reshuffles the groups below it, so every row
            // after the edit is now labelled with a stale number.
            let markersChanged = ids != parent.session.attachmentIDs
            parent.session.bodyText = text
            parent.session.attachmentIDs = ids
            parent.session.updatedAt = Date()
            parent.onChange()
            if markersChanged { refreshRowLabels() }
        }

        // MARK: Keyboard toolbar

        func attachAccessoryView(to textView: UITextView) {
            let toolbar = KeyboardToolbar(
                onAddClimb: { [weak self] in self?.parent.onAddClimb() },
                onStartAttempt: { [weak self] in self?.parent.onStartAttempt() }
            )
            let host = UIHostingController(rootView: toolbar)
            host.view.backgroundColor = .clear
            host.sizingOptions = [.intrinsicContentSize]
            accessoryHost = host

            let container = AccessoryContainerView()
            container.addSubview(host.view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: container.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            textView.inputAccessoryView = container
        }
    }
}

/// A text view whose caret stays text-sized on a climb heading's line.
final class NoteTextView: UITextView {
    /// UIKit sizes the caret to the line fragment, and a climb row makes its line as
    /// tall as the tag — so parking the cursor beside one drew a 52pt bar next to a
    /// short chip. Cut it back to text height, centred on the tag. Attempt rows keep
    /// the full-height caret: they read as a block, and a tall caret suits them.
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        guard isOnClimbLine(position) else { return rect }

        let font = (typingAttributes[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
        let limit = ceil(font.lineHeight * 1.15)
        guard rect.height > limit else { return rect }
        rect.origin.y += ((rect.height - limit) / 2).rounded()
        rect.size.height = limit
        return rect
    }

    private func isOnClimbLine(_ position: UITextPosition) -> Bool {
        let storage = textStorage
        guard storage.length > 0 else { return false }
        let index = min(offset(from: beginningOfDocument, to: position), storage.length - 1)
        let line = (storage.string as NSString).lineRange(for: NSRange(location: index, length: 0))

        var found = false
        storage.enumerateAttribute(.attachment, in: line) { value, _, stop in
            if value is ClimbAttachment {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}

/// `inputAccessoryView` sizes from the intrinsic height, which SwiftUI hosting alone
/// does not supply reliably here.
final class AccessoryContainerView: UIView {
    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 60))
        backgroundColor = .clear
        autoresizingMask = .flexibleWidth
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 60)
    }
}
