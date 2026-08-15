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
    /// Shared with the system bottom bar's stopwatch item, so the clock agrees
    /// wherever the bar happens to be.
    var stopwatch: StopwatchModel
    var onOpenAttempt: (UUID) -> Void
    /// A tapped clock token in a quote: open the attempt with its video at that moment.
    var onSeekAttempt: (UUID, TimeInterval) -> Void
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
        // `.interactive` would drag the keyboard only: the accessory bar rides
        // above your finger, so it beaches at the bottom edge and then pops out
        // of existence when the text view resigns. `.interactiveWithAccessory`
        // drags the bar too.
        textView.keyboardDismissMode = .interactiveWithAccessory
        // Top clears the date line above the title; bottom clears the pinned bar.
        textView.textContainerInset = UIEdgeInsets(top: 32, left: 16, bottom: 120, right: 16)
        // The view runs edge to edge under the bars; the resting inset is owned
        // by `safeAreaInsetsDidChange` below, not inferred by UIKit — automatic
        // adjustment would stack onto the keyboard inset this view manages itself.
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainer.lineFragmentPadding = 0
        textView.typingAttributes = NoteDocument.bodyAttributes
        textView.attributedText = NSAttributedString(string: "", attributes: NoteDocument.bodyAttributes)

        // Stamped note lines draw a bookmark in their gutter, vended per paragraph.
        textView.textLayoutManager?.delegate = context.coordinator

        // Clock tokens in quotes seek the attempt's video. The recognizer only ever
        // receives touches that land on a token — everything else still just moves
        // the caret — and it cancels the touch, so a tapped token doesn't also focus.
        let timestampTap = UITapGestureRecognizer(target: context.coordinator,
                                                  action: #selector(Coordinator.timestampTapped(_:)))
        timestampTap.delegate = context.coordinator
        textView.addGestureRecognizer(timestampTap)

        context.coordinator.textView = textView
        context.coordinator.attachAccessoryView(to: textView)
        context.coordinator.attachDateLine(to: textView, date: session.createdAt)
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
        private var accessoryHost: UIHostingController<EditingToolbar>?
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
            if let id = quoteID(onLineAt: textView.selectedRange.location) {
                textView.typingAttributes = NoteDocument.quoteAttributes(for: id)
            } else {
                textView.typingAttributes = NoteDocument.bodyAttributes
            }
        }

        /// The attempt whose notes the line at `location` is. Line-shaped on purpose:
        /// tapping anywhere on a quote's line means editing that attempt's notes, even
        /// mid-word or at the line's start.
        private func quoteID(onLineAt location: Int) -> UUID? {
            guard let storage = textView?.textStorage, storage.length > 0 else { return nil }
            let line = (storage.string as NSString)
                .lineRange(for: NSRange(location: min(location, storage.length), length: 0))
            var found: UUID?
            storage.enumerateAttribute(NoteDocument.noteQuote, in: line) { value, _, stop in
                if let id = value as? UUID {
                    found = id
                    stop.pointee = true
                }
            }
            // The document's empty last line has no characters to carry a binding, so
            // typing at the end of the notes would silently fall out of them. That
            // line belongs to the quote whose break sits just above it.
            if found == nil, line.length == 0, line.location > 0 {
                found = storage.attribute(NoteDocument.noteQuote, at: line.location - 1,
                                          effectiveRange: nil) as? UUID
            }
            return found
        }

        /// Past the end of the notes the caret is in, if it is in any — where a new block
        /// can go without cutting them off from their row.
        private func endOfQuote(at location: Int) -> Int {
            guard let storage = textView?.textStorage, storage.length > 0 else { return location }
            let full = NSRange(location: 0, length: storage.length)
            for index in [location - 1, location] where index >= 0 && index < storage.length {
                var run = NSRange(location: 0, length: 0)
                // The longest run, not the nearest: a quote is several attribute runs —
                // clock tokens carry their own font and colour — and the caret can sit
                // in any of them.
                guard storage.attribute(NoteDocument.noteQuote, at: index,
                                        longestEffectiveRange: &run, in: full) != nil else {
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

        // MARK: Date line

        /// The session's date sits in the note itself, above the title — the top
        /// bar stays bare, the way Notes does it. It scrolls away with the content.
        func attachDateLine(to textView: UITextView, date: Date) {
            let label = UILabel()
            label.text = date.formatted(date: .long, time: .shortened)
            label.font = .preferredFont(forTextStyle: .footnote)
            label.textColor = .secondaryLabel
            label.isUserInteractionEnabled = false
            label.translatesAutoresizingMaskIntoConstraints = false
            textView.addSubview(label)

            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: textView.contentLayoutGuide.topAnchor, constant: -2),
                label.centerXAnchor.constraint(equalTo: textView.frameLayoutGuide.centerXAnchor),
            ])
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

            // Pinned to the content, where the text will start: the view now rests
            // with a safe-area content inset, so the frame's top is under the bars.
            let inset = textView.textContainerInset
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: textView.contentLayoutGuide.topAnchor, constant: inset.top),
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
            // A break never goes into a quote: notes are one line per clock. Return
            // anywhere in one steps the caret out to a fresh body line past the
            // notes instead, and breaks inside pasted text flatten to spaces.
            if text.contains("\n"), let id = quoteID(onLineAt: range.location) {
                if text == "\n" {
                    // At the head of the note — before its words start — Return reads
                    // as "make room above": the whole line moves down intact, caret
                    // riding with it. Anywhere in the words, it steps out as usual.
                    if range.length == 0, isAtNoteStart(range.location) {
                        pushNoteLineDown(at: range.location)
                    } else {
                        exitQuote(replacing: range)
                    }
                } else {
                    // Words that ride in with a return — an autocorrect commit, a
                    // pasted line — still land in the note; only the breaks don't.
                    let flattened = text.replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                    let attributes = NoteDocument.quoteAttributes(for: id)
                    performBlockEdit {
                        $0.replaceCharacters(in: range,
                                             with: NSAttributedString(string: flattened, attributes: attributes))
                    }
                    let caret = range.location + (flattened as NSString).length
                    if text.hasSuffix("\n") {
                        exitQuote(replacing: NSRange(location: caret, length: 0))
                    } else {
                        textView.selectedRange = NSRange(location: caret, length: 0)
                    }
                }
                return false
            }
            // A tap makes UIKit rebuild `typingAttributes` from its own reading of the
            // context, and the quote binding (a custom key) does not survive. Re-derive
            // them at the moment of insertion, so typing on a quote's line is always
            // that attempt's notes rather than unbound body text mid-quote — and, off
            // a quote's line, is never the quote's: whatever UIKit carried over from
            // the character behind the caret is replaced outright, so a quote's look
            // (or its binding) cannot ride past its edge onto a fresh line.
            if !text.isEmpty {
                if let id = quoteID(onLineAt: range.location) {
                    textView.typingAttributes = NoteDocument.quoteAttributes(for: id)
                } else if textView.typingAttributes[NoteDocument.noteQuote] != nil {
                    textView.typingAttributes = NoteDocument.bodyAttributes
                }
            }
            // Backspacing into a clock never nibbles at it: the token goes whole, and
            // the line goes with it once the note's words are already gone.
            if text.isEmpty, deleteTimestamp(at: range) { return false }
            // Backspacing the break under a row would pull the next line up onto the
            // row's own line, where text cannot be that attempt's notes — or anything
            // else legible. The row is deleted by deleting the row. An empty line is
            // the exception: nothing merges up, the line just goes, and the caret
            // lands beside the row — one more backspace from deleting it.
            if text.isEmpty, mergesIntoBlockLine(range) { return false }

            let doomed = attemptMarkers(in: range)
            guard !doomed.isEmpty else { return true }

            pendingDeletion = (range, text)
            parent.onConfirmDelete(doomed.count)
            return false
        }

        /// Whether the caret sits before the note's words begin: at the line start,
        /// inside the clock, or on the space just after it.
        private func isAtNoteStart(_ location: Int) -> Bool {
            guard let storage = textView?.textStorage, storage.length > 0 else { return false }
            let text = storage.string as NSString
            let line = text.lineRange(for: NSRange(location: min(location, storage.length), length: 0))

            var wordsStart = line.location
            if let clock = NoteTimestamp.regex.firstMatch(in: storage.string, options: [], range: line),
               clock.range.location == line.location {
                wordsStart = NSMaxRange(clock.range)
                if wordsStart < NSMaxRange(line), text.character(at: wordsStart) == 0x0020 {
                    wordsStart += 1
                }
            }
            return location <= wordsStart
        }

        /// A body break slides in above the note's line, moving it down whole; the
        /// caret keeps its place in the note.
        private func pushNoteLineDown(at location: Int) {
            guard let textView else { return }
            let storage = textView.textStorage
            let line = (storage.string as NSString)
                .lineRange(for: NSRange(location: min(location, storage.length), length: 0))
            performBlockEdit {
                $0.insert(NSAttributedString(string: "\n", attributes: NoteDocument.bodyAttributes),
                          at: line.location)
            }
            textView.selectedRange = NSRange(location: min(location + 1, textView.textStorage.length),
                                             length: 0)
            syncTypingAttributes()
        }

        /// Return anywhere in a quote: the quote itself is untouched — no break enters
        /// it — and the caret lands on a fresh body line just past the notes, back in
        /// the document proper. A selected run of note text is consumed by the Return
        /// the way it would be anywhere else.
        private func exitQuote(replacing range: NSRange) {
            guard let textView else { return }
            var caret = range.location
            performBlockEdit { storage in
                if range.length > 0 {
                    storage.replaceCharacters(in: range, with: "")
                }
                let end = self.endOfQuote(at: min(range.location, storage.length))
                // Past a quote ending in its own break, the new line slots in whole;
                // after an unterminated one, the inserted break first closes the
                // note's line, and the caret belongs beyond it.
                let closesLine = end == 0 || (storage.string as NSString).character(at: end - 1) == 0x000A
                storage.insert(NSAttributedString(string: "\n", attributes: NoteDocument.bodyAttributes),
                               at: end)
                caret = closesLine ? end : end + 1
            }
            textView.selectedRange = NSRange(location: min(caret, textView.textStorage.length), length: 0)
            textView.typingAttributes = NoteDocument.bodyAttributes
        }

        /// The clock token is atomic under deletion: one backspace into it takes the
        /// whole clock — and, when the note's words are already gone, the line too.
        /// The first note line folds back to the held-open empty line under its row;
        /// a later one is removed outright, the caret closing up to the line above.
        private func deleteTimestamp(at range: NSRange) -> Bool {
            guard let textView, range.length == 1 else { return false }
            let storage = textView.textStorage
            let string = storage.string as NSString
            guard range.location < storage.length,
                  quoteID(onLineAt: range.location) != nil
            else { return false }

            // Backspacing the clock itself, or the space that closes it — deleting
            // just that space would weld clock and words into unstyled text.
            let anchor: Int
            if storage.attribute(NoteDocument.noteTimestamp, at: range.location,
                                 effectiveRange: nil) != nil {
                anchor = range.location
            } else if string.character(at: range.location) == 0x0020, range.location > 0,
                      storage.attribute(NoteDocument.noteTimestamp, at: range.location - 1,
                                        effectiveRange: nil) != nil {
                anchor = range.location - 1
            } else {
                return false
            }

            var token = NSRange(location: 0, length: 0)
            _ = storage.attribute(NoteDocument.noteTimestamp, at: anchor,
                                  longestEffectiveRange: &token,
                                  in: NSRange(location: 0, length: storage.length))
            // The space between clock and words belongs to the clock: it goes too,
            // so the words are left flush at the line's start.
            while NSMaxRange(token) < string.length,
                  string.character(at: NSMaxRange(token)) == 0x0020 {
                token.length += 1
            }

            let line = string.lineRange(for: NSRange(location: anchor, length: 0))
            let remainder = (string.substring(with: line) as NSString)
                .replacingCharacters(in: NSRange(location: token.location - line.location,
                                                 length: token.length), with: "")
            let bareToken = remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasBreak = string.character(at: NSMaxRange(line) - 1) == 0x000A

            let doomed: NSRange
            let caret: Int
            if !bareToken {
                // Words still on the line: only the clock goes, and what is left
                // reads on as a plain note line.
                doomed = token
                caret = token.location
            } else if isDirectlyUnderRow(line) {
                doomed = NSRange(location: line.location, length: line.length - (hasBreak ? 1 : 0))
                caret = line.location
            } else {
                // Take the line's own break with it — or, at the document's end, the
                // break above — so no empty quote line is left behind.
                doomed = hasBreak ? line
                                  : NSRange(location: line.location - 1, length: line.length + 1)
                caret = line.location - 1
            }

            performBlockEdit { $0.replaceCharacters(in: doomed, with: "") }
            textView.selectedRange = NSRange(location: min(caret, textView.textStorage.length), length: 0)
            syncTypingAttributes()
            return true
        }

        /// Whether this edit deletes exactly the line break that ends a row's own line —
        /// and would pull real text up onto it. An empty line below is safe to merge:
        /// deleting either of the two adjacent breaks reads the same, so the default
        /// deletion is left to run and the caret comes to rest just right of the row.
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
            guard isBlock else { return false }

            // Past the end of the document there is no line to pull up at all.
            let followingStart = NSMaxRange(line)
            guard followingStart < string.length else { return false }
            let following = string.lineRange(for: NSRange(location: followingStart, length: 0))
            let followingIsEmpty = following.length == 1 &&
                string.character(at: following.location) == 0x000A
            return !followingIsEmpty
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

        // MARK: Timestamp taps

        /// The clock token under `point`, if the touch really lands on one.
        /// `closestPosition` happily maps a tap in empty space to faraway text, so the
        /// hit is confirmed against the caret geometry at that position first.
        fileprivate func timestamp(at point: CGPoint) -> (id: UUID, seconds: TimeInterval)? {
            guard let textView, let position = textView.closestPosition(to: point) else { return nil }
            let caret = textView.caretRect(for: position)
            guard caret.height > 0, abs(point.y - caret.midY) < caret.height else { return nil }

            let storage = textView.textStorage
            guard storage.length > 0 else { return nil }
            let offset = min(textView.offset(from: textView.beginningOfDocument, to: position),
                             storage.length - 1)

            // On the token itself (hidden, but its characters still anchor the line's
            // start, under the bookmark). The position sits between characters; the
            // token can be on either side.
            if abs(point.x - caret.midX) < 32 {
                for index in [offset, offset - 1] where index >= 0 {
                    if let seconds = storage.attribute(NoteDocument.noteTimestamp, at: index,
                                                       effectiveRange: nil) as? TimeInterval,
                       let id = storage.attribute(NoteDocument.noteQuote, at: index,
                                                  effectiveRange: nil) as? UUID {
                        return (id, seconds)
                    }
                }
            }

            // On the clock drawn at the line's trailing edge: any tap in the reserved
            // right lane of a stamped line counts.
            let line = (storage.string as NSString)
                .lineRange(for: NSRange(location: offset, length: 0))
            if point.x > textView.bounds.width - NoteDocument.clockReserve - 24,
               let seconds = storage.attribute(NoteDocument.noteTimestamp, at: line.location,
                                               effectiveRange: nil) as? TimeInterval,
               let id = storage.attribute(NoteDocument.noteQuote, at: line.location,
                                          effectiveRange: nil) as? UUID {
                return (id, seconds)
            }
            return nil
        }

        @objc func timestampTapped(_ gesture: UITapGestureRecognizer) {
            guard let textView, let hit = timestamp(at: gesture.location(in: textView)) else { return }
            parent.onSeekAttempt(hit.id, hit.seconds)
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
            (textView as? NoteTextView)?.keepCaretVisible()
        }

        /// Moving the caret across the title/body boundary has to resize it too.
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isRestyling else { return }
            syncTypingAttributes()
            (textView as? NoteTextView)?.keepCaretVisible()
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
            let toolbar = EditingToolbar(
                stopwatch: parent.stopwatch,
                onAddClimb: { [weak self] in self?.parent.onAddClimb() },
                onStartAttempt: { [weak self] in self?.parent.onStartAttempt() }
            )
            let host = UIHostingController(rootView: toolbar)
            host.view.backgroundColor = .clear
            host.sizingOptions = [.intrinsicContentSize]
            // An accessory view straddles the keyboard's safe area, and UIKit feeds
            // that inset into the hosted SwiftUI content on and off — the bar's
            // bottom padding would randomly double. The bar spaces itself with its
            // own padding only.
            host.safeAreaRegions = []
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

extension NoteEditor.Coordinator: NSTextLayoutManagerDelegate {
    /// A paragraph opening with a clock token lays out with a bookmark beside it.
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager,
                           textLayoutFragmentFor location: NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        guard let textView,
              let contentManager = textLayoutManager.textContentManager,
              let elementRange = textElement.elementRange
        else { return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange) }

        let storage = textView.textStorage
        let start = contentManager.offset(from: contentManager.documentRange.location,
                                          to: elementRange.location)
        guard start >= 0, start < storage.length,
              let seconds = storage.attribute(NoteDocument.noteTimestamp, at: start,
                                              effectiveRange: nil) as? TimeInterval
        else { return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange) }

        let fragment = BookmarkLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.clock = NoteTimestamp.display(for: seconds)
        fragment.containerWidth = textView.textContainer.size.width
        return fragment
    }
}

extension NoteEditor.Coordinator: UIGestureRecognizerDelegate {
    /// Only touches on a clock token reach the recognizer, so every other tap falls
    /// through to the text view untouched.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard let textView else { return false }
        return timestamp(at: touch.location(in: textView)) != nil
    }
}

/// A text view whose caret stays text-sized on a climb heading's line, and which
/// keeps the caret above the keyboard itself. The SwiftUI layer opts out of keyboard
/// avoidance (`.ignoresSafeArea(.keyboard)`, for the pinned toolbar's sake), so the
/// view runs full-height under the keyboard and owns its own insets.
final class NoteTextView: UITextView {
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The view runs edge to edge under the status bar and the nav bar; at rest the
    /// content still starts below them, and scrolling carries it underneath. Owned
    /// here because automatic adjustment is off (it would fight the keyboard inset).
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        let wasAtTop = contentOffset.y <= -contentInset.top + 1
        contentInset.top = safeAreaInsets.top
        verticalScrollIndicatorInsets.top = safeAreaInsets.top
        if wasAtTop { contentOffset.y = -contentInset.top }
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        guard window != nil,
              let endFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }
        let overlap = max(0, bounds.maxY - convert(endFrame, from: nil).minY)
        contentInset.bottom = overlap
        verticalScrollIndicatorInsets.bottom = overlap
        guard overlap > 0, isFirstResponder else { return }
        // After the inset lands, bring the caret back into the visible strip — this
        // is what moves the note up when a tap below the keyboard's edge focuses it.
        DispatchQueue.main.async { [weak self] in self?.keepCaretVisible() }
    }

    /// UIKit's own selection autoscroll is suppressed below, so this is the only
    /// thing that moves the page for the caret — and it moves it only when the
    /// caret is actually hidden (under the keyboard, or off the top). A caret
    /// anywhere in the visible strip stays put.
    func keepCaretVisible() {
        guard let position = selectedTextRange?.end else { return }
        let caret = caretRect(for: position)
        guard caret.origin.y.isFinite, caret.height > 0 else { return }
        let visibleTop = contentOffset.y + safeAreaInsets.top
        let visibleBottom = contentOffset.y + bounds.height - contentInset.bottom
        guard caret.maxY > visibleBottom - 8 || caret.minY < visibleTop else { return }
        programmaticScroll = true
        scrollRectToVisible(caret.insetBy(dx: 0, dy: -24), animated: true)
        programmaticScroll = false
    }

    /// UITextView autoscrolls the selection into view on focus and on every tap,
    /// and with the tall custom line fragments it drags the page around even when
    /// the caret was already visible. Drop every scroll we didn't ask for; user
    /// pans go through the property setter (animated: false) and are untouched.
    private var programmaticScroll = false

    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        guard programmaticScroll else { return }
        super.scrollRectToVisible(rect, animated: animated)
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        if animated && !programmaticScroll && !isDragging && !isDecelerating { return }
        super.setContentOffset(contentOffset, animated: animated)
    }

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
/// does not supply reliably here. A `UIInputView` rather than a plain view: the system
/// draws its keyboard backdrop behind plain accessory views, and only an input view
/// with the `.default` style opts out of it — the bar floats over the note.
/// 64 = 8pt padding + the 48pt capsules + 8pt of daylight above the keyboard.
final class AccessoryContainerView: UIInputView {
    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 64), inputViewStyle: .default)
        backgroundColor = .clear
        autoresizingMask = .flexibleWidth
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 64)
    }
}
