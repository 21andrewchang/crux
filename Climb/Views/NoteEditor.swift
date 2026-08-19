import SwiftUI
import UIKit

/// Imperative handle onto the live text view, so the rest of the app can insert an
/// attempt at the cursor or refresh rows without owning the editor's state.
@Observable
final class NoteEditorController {
    @ObservationIgnored fileprivate weak var coordinator: NoteEditor.Coordinator?

    /// Mirrors the note's undo stack, so the toolbar's undo dims when there is
    /// nothing left to take back.
    fileprivate(set) var canUndo = false
    /// The other half of it: what undo has taken back and not yet been typed over.
    fileprivate(set) var canRedo = false

    /// Takes back the last edit. The only way to undo now that the shake gesture
    /// is off — a phone in a chalk bag shouldn't be able to erase the session.
    func undo() {
        coordinator?.undo()
    }

    /// Puts back the last thing undo took.
    func redo() {
        coordinator?.redo()
    }

    func insertAttempt(id: UUID) {
        coordinator?.insertAttempt(id: id)
    }

    /// Drops an empty climb bubble at the cursor, ready to be typed into.
    func insertClimbHeader() {
        coordinator?.insertClimbHeader()
    }

    /// Drops an empty section heading at the cursor, ready to be typed into.
    func insertSectionHeader() {
        coordinator?.insertSectionHeader()
    }

    /// The climb heading the cursor currently sits under, if any.
    func currentClimbName() -> String? {
        coordinator?.currentClimbName()
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

    /// Raises the keyboard at the caret — how finishing an attempt drops the user
    /// straight back into typing under the new row.
    func focus() {
        coordinator?.textView?.becomeFirstResponder()
    }

    /// How far this page is scrolled from its top. Asked when a page is turned to,
    /// which is the one time the header has to know without being told.
    var scrolledDistance: CGFloat { coordinator?.scrolledDistance ?? 0 }
}

/// The note itself: a plain `UITextView` you can just type in, with attempts embedded
/// as text attachments.
struct NoteEditor: UIViewRepresentable {
    let session: ClimbSession
    /// Which page of the note this editor is. Each tab is its own document, with its
    /// own text, its own markers and its own undo stack.
    let tab: NoteTab
    let controller: NoteEditorController
    /// Presents the toolbar action. Owned by the SwiftUI layer so capture flow stays there.
    var onStartAttempt: () -> Void
    var onAddClimb: () -> Void
    var onAddSection: () -> Void
    /// Shared with the system bottom bar's stopwatch item, so the clock agrees
    /// wherever the bar happens to be.
    var stopwatch: StopwatchModel
    /// Where the tutorial's walkthrough has got to — which hint the note shows and
    /// which buttons either bar is allowed to draw. `.done` for every other note.
    var guide: TutorialGuide
    /// Times the swap between the parked system bar and the keyboard clone; the
    /// editor hands it the accessory view so it can track where the clone is.
    var barPark: BarParkModel
    var onOpenAttempt: (UUID) -> Void
    /// A tapped clock token in a quote: open the attempt with its video at that moment.
    var onSeekAttempt: (UUID, TimeInterval) -> Void
    /// Resolves an old stored-climb marker to its name, so notes written before climbs
    /// became plain text come back with their headings as inline bubbles.
    var legacyClimbName: (UUID) -> String?
    /// An edit is about to take this many attempt rows out. The editor holds it until
    /// the answer comes back through `confirmPendingDeletion` / `cancelPendingDeletion`.
    var onConfirmDelete: (Int) -> Void
    var onChange: () -> Void
    var onFocusChange: (Bool) -> Void
    /// How far the page has been scrolled from its top, on every frame of it. The
    /// header above the tabs compacts off this.
    var onScroll: (CGFloat) -> Void = { _ in }
    /// What the pinned header covers. The page runs full height underneath it and
    /// holds this much room open at its top so nothing rests behind the chrome.
    var topInset: CGFloat = 0

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
        // The date and the title are in the pinned header above the tabs now, so the
        // page opens on its first line. The bottom is just breathing room under the
        // last line: clearance for the pinned bar and the keyboard lives in
        // `contentInset`, so the two never stack.
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 24, right: 16)
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
        timestampTap.name = NoteTextView.markerTapName
        textView.addGestureRecognizer(timestampTap)
        // A component is a link, not text: the row opens the attempt and each of its
        // note lines opens the clip it was taken at. The recognizer above takes those
        // taps, and the ones the text view puts on itself to place the caret are
        // refused anywhere on one.
        textView.isLinkTap = { [weak coordinator = context.coordinator] point in
            coordinator?.attemptRow(at: point) != nil || coordinator?.quoteLink(at: point) != nil
        }

        context.coordinator.textView = textView
        textView.onResize = { [weak coordinator = context.coordinator] in
            coordinator?.placeHint(force: true)
        }
        // iOS 26 fades the content of any scroll view in a bar's way, at both ends —
        // which on a black page reads as the text being cut off in a straight line
        // under the chrome. The whole point here is that it isn't: the page runs the
        // full height of the screen and you can watch a line travel the whole way.
        textView.topEdgeEffect.isHidden = true
        textView.bottomEdgeEffect.isHidden = true
        textView.headerInset = topInset
        context.coordinator.attachAccessoryView(to: textView)
        context.coordinator.attachPlaceholder(to: textView)
        context.coordinator.reloadDocument()
        context.coordinator.observeUndoManager()
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Deliberately does not push text back into the view: the text view is the
        // source of truth while editing, and reassigning would fight the cursor.
        context.coordinator.parent = self
        (uiView as? NoteTextView)?.headerInset = topInset
        // Every step but the last is read back out of the document on the edit that
        // completes it; the rest step ends on a tap in the bar, with the note left
        // exactly as it was. So the line on screen is brought up to date here too.
        context.coordinator.refreshHintIfNeeded()
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
        /// This page's clone of the bottom bar, ridden by the keyboard. Handed to
        /// `barPark` whenever this page takes focus, so the swap tracks the bar that
        /// is actually on screen.
        private weak var accessoryContainer: UIView?
        private weak var placeholderLabel: UILabel?
        private weak var hintLabel: UILabel?
        private var hintTop: NSLayoutConstraint?
        /// Moved with `hintTop` while the walkthrough is running, so its line hangs
        /// from the caret's margin — which steps in under a heading — rather than the
        /// page's.
        private var hintLeading: NSLayoutConstraint?
        private var isRestyling = false
        /// Turns the fold chevrons over the frames after a fold lands.
        private let foldAnimator = FoldAnimator()
        /// The tap of a heading folding shut or opening — kept around so it can be
        /// warmed up the moment the touch lands on the chevron.
        private let foldHaptic = UIImpactFeedbackGenerator(style: .light)
        /// An edit held back pending confirmation, as `(range, replacement)`.
        private var pendingDeletion: (range: NSRange, replacement: String)?
        /// The undo manager currently being watched, so re-registering is a no-op.
        private weak var observedUndoManager: UndoManager?

        init(parent: NoteEditor) {
            self.parent = parent
        }

        // MARK: Document

        func reloadDocument() {
            guard let textView else { return }
            let selected = textView.selectedRange
            let document = NoteDocument.attributedString(for: parent.session,
                                                         tab: parent.tab,
                                                         climbName: { [weak self] id in
                                                             self?.parent.legacyClimbName(id)
                                                         },
                                                         makeCheckIn: { [weak self] in
                                                             // Only the check-in page opens with the card.
                                                             guard self?.parent.tab.showsCheckIn == true else { return nil }
                                                             return self?.makeCheckInAttachment()
                                                         }) { [weak self] id in
                self?.makeAttachment(for: id)
            }
            // `textStorage`, not `attributedText`: assigning to the latter empties the
            // undo stack, and a reload has to be able to happen mid-edit.
            textView.textStorage.setAttributedString(document)
            textView.selectedRange = NSRange(location: min(selected.location, document.length), length: 0)
            (textView as? NoteTextView)?.resolveFullLayout()
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
                if let attempt = value as? AttemptAttachment,
                   let row = attempt.rowView, let snapshot = snapshot(for: attempt.attemptID) {
                    row.configure(with: snapshot)
                }
            }
        }

        /// The caret is drawn from `typingAttributes`, which UIKit carries over from the
        /// character before the cursor — a heading's, say, on the line just under one.
        /// Recomputing from the cursor's own line is what makes it shrink back on Return.
        private func syncTypingAttributes() {
            guard let textView else { return }
            // Inside a quote, typing carries the quote's style *and* its binding, so
            // what gets typed there is part of that attempt's notes. Inside a bubble,
            // it carries the heading's style, so the name grows in place.
            if let id = quoteID(onLineAt: textView.selectedRange.location) {
                textView.typingAttributes = NoteDocument.quoteAttributes(for: id)
            } else if let line = headingLine(onLineAt: textView.selectedRange.location) {
                textView.typingAttributes = NoteDocument.headerAttributes(tint: headingTint(of: line))
            } else if sectionLine(onLineAt: textView.selectedRange.location) != nil {
                textView.typingAttributes = NoteDocument.sectionHeaderAttributes
            } else {
                textView.typingAttributes = NoteDocument.bodyAttributes
            }
        }

        /// The line at `location`, if any of its characters carry `key`. Line-shaped
        /// like the quotes: one marked character makes the whole line a heading.
        private func line(carrying key: NSAttributedString.Key, at location: Int) -> NSRange? {
            guard let storage = textView?.textStorage, storage.length > 0 else { return nil }
            let line = (storage.string as NSString)
                .lineRange(for: NSRange(location: min(location, storage.length), length: 0))
            var found = false
            storage.enumerateAttribute(key, in: line) { value, _, stop in
                if value != nil {
                    found = true
                    stop.pointee = true
                }
            }
            return found ? line : nil
        }

        /// The climb heading line at `location`, if the line is one.
        private func headingLine(onLineAt location: Int) -> NSRange? {
            line(carrying: NoteDocument.climbHeader, at: location)
        }

        /// The section heading line at `location`, if the line is one.
        private func sectionLine(onLineAt location: Int) -> NSRange? {
            line(carrying: NoteDocument.sectionHeader, at: location)
        }

        private func headingTint(of line: NSRange) -> UIColor {
            guard let storage = textView?.textStorage else { return ClimbTint.fallback }
            let name = NoteDocument.headingName((storage.string as NSString).substring(with: line))
            return ClimbTint.color(for: name)
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
        /// The attempt whose component the caret is inside — row, notes and any bare
        /// line filed under it. A component is one thing to the reader, so a Return
        /// anywhere in it means the same thing.
        private func componentID(containing location: Int) -> UUID? {
            guard let storage = textView?.textStorage else { return nil }
            var found: UUID?
            storage.enumerateAttribute(.attachment,
                                       in: NSRange(location: 0, length: storage.length)) { value, _, stop in
                guard let attempt = value as? AttemptAttachment,
                      let extent = self.rowExtent(for: attempt.attemptID),
                      location >= extent.location, location <= NSMaxRange(extent)
                else { return }
                found = attempt.attemptID
                stop.pointee = true
            }
            return found
        }

        /// Puts the caret on a fresh body line under the whole component. The new line
        /// lands past everything the component holds, so pressing Return in one can
        /// never leave a line inside it.
        private func exitComponent(_ id: UUID, replacing range: NSRange) {
            guard let textView else { return }
            var caret = range.location
            performBlockEdit { storage in
                if range.length > 0 { storage.replaceCharacters(in: range, with: "") }
                let end = min(self.rowExtent(for: id).map(NSMaxRange) ?? range.location, storage.length)
                // Past a component ending in its own break the new line slots in whole;
                // after an unterminated one the inserted break first closes the last
                // line, and the caret belongs beyond it.
                let closesLine = end == 0 || (storage.string as NSString).character(at: end - 1) == 0x000A
                storage.insert(NSAttributedString(string: "\n", attributes: NoteDocument.bodyAttributes),
                               at: end)
                caret = closesLine ? end : end + 1
            }
            textView.selectedRange = NSRange(location: min(caret, textView.textStorage.length), length: 0)
            syncTypingAttributes()
        }

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

        // MARK: Placeholder

        /// A label rather than placeholder text in the storage: real text would be
        /// serialized into the page and read back as something the user wrote.
        ///
        /// Two of them — the page's own, saying what this tab is for, and the
        /// walkthrough's line. The page's is gone the moment anything is written on
        /// it; the walkthrough's belongs to the main page and to the tutorial note.
        func attachPlaceholder(to textView: UITextView) {
            let inset = textView.textContainerInset

            func add(_ text: NSAttributedString) -> (label: UILabel, leading: NSLayoutConstraint) {
                let label = UILabel()
                label.numberOfLines = 0
                label.attributedText = text
                label.isUserInteractionEnabled = false
                label.translatesAutoresizingMaskIntoConstraints = false
                textView.addSubview(label)
                let leading = label.leadingAnchor.constraint(
                    equalTo: textView.frameLayoutGuide.leadingAnchor, constant: inset.left)
                NSLayoutConstraint.activate([
                    leading,
                    label.trailingAnchor.constraint(equalTo: textView.frameLayoutGuide.trailingAnchor,
                                                    constant: -inset.right),
                ])
                return (label, leading)
            }

            // Pinned to the content, where the text will start: the view now rests
            // with a safe-area content inset, so the frame's top is under the bars.
            if let text = parent.tab.placeholder {
                let page = add(NoteDocument.pagePlaceholderText(text)).label
                page.topAnchor.constraint(equalTo: textView.contentLayoutGuide.topAnchor,
                                          constant: inset.top).isActive = true
                placeholderLabel = page
            }

            // The walkthrough's line sits under whatever is written so far, which on an
            // empty page is the page's first line. The walkthrough moves both of these
            // constants as it goes, to sit on the caret's own line.
            let hints = add(NoteDocument.hintText)
            let top = hints.label.topAnchor.constraint(equalTo: textView.contentLayoutGuide.topAnchor)
            top.isActive = true
            hintLabel = hints.label
            hintTop = top
            hintLeading = hints.leading
        }

        private func updatePlaceholder() {
            guard let textView else { return }
            // The page says what it is for until something is written on it. The
            // check-in's card doesn't count as written — it is on that page whether
            // anyone has typed a word there or not.
            let empty = isPageEmpty
            // On the page the walkthrough is teaching, the walkthrough's line is the
            // only thing that should be talking.
            placeholderLabel?.isHidden = !empty || (parent.guide.isRunning && parent.tab.showsHints)

            updateGuide()
            // Empty headings show their examples from inside their own layout
            // fragments, which have no view to ask — so the answer is left where they
            // read it, and the page is laid out again when it changes.
            if NoteDocument.showsTutorialExamples != parent.guide.isRunning {
                NoteDocument.showsTutorialExamples = parent.guide.isRunning
                isRestyling = true
                NoteDocument.applyStyles(to: textView.textStorage)
                isRestyling = false
            }
            // Only the main page is ever taught: the walkthrough's steps are the bar's
            // buttons, and the bar writes climbs and attempts into that page.
            guard parent.tab.showsHints else {
                hintLabel?.isHidden = true
                return
            }
            guard !parent.guide.isRunning else {
                // The walkthrough asks for one thing at a time, and it asks in the
                // place that thing would go: the line under everything written so
                // far, exactly where the cursor would land on it.
                let asked = Asked(step: parent.guide.step, needsName: parent.guide.needsName)
                if shownStep != asked {
                    shownStep = asked
                    hintLabel?.attributedText = hintText(for: asked)
                }
                hintLabel?.isHidden = false
                placeHint()
                return
            }
            // Everywhere else, nothing: the bar is taught once, during the
            // walkthrough, and a note that is not the walkthrough's is a blank page to
            // write on rather than a page of instructions. An empty page shows what
            // that page is for and nothing more.
            shownStep = nil
            hintLabel?.isHidden = true
        }

        /// Shows whatever the walkthrough is asking for now, if that is not already what
        /// is on screen. For the steps that end without the document changing — there is
        /// one, the rest panel — where nothing else would come back through here.
        func refreshHintIfNeeded() {
            let asked = parent.guide.isRunning
                ? Asked(step: parent.guide.step, needsName: parent.guide.needsName)
                : nil
            guard asked != shownStep else { return }
            updatePlaceholder()
        }

        /// Puts the walkthrough's line where the note's next line would be. Split from
        /// `updatePlaceholder` so a resize can place it again without re-reading the
        /// document — and because the first placement happens before the view has a
        /// size, when there is nothing yet to measure against.
        func placeHint(force: Bool = false) {
            guard parent.guide.isRunning else { return }
            // Placed once per line it is placed under, and then left alone. Writing on
            // that line does not move it: the line keeps its place in the note, so the
            // instruction keeps its place under it — and none of the small differences
            // between what an empty line measures and what a written one does can show
            // up as a step. It is placed again when it has a different line to sit
            // under, when the step changes, or when the view resizes and every measure
            // is stale anyway.
            let anchor = Anchor(step: parent.guide.step,
                                needsName: parent.guide.needsName,
                                line: hintTarget().location)
            guard force || anchor != placedAnchor else { return }
            placedAnchor = anchor

            let origin = hintOrigin
            hintTop?.constant = origin.y
            hintLeading?.constant = origin.x
        }

        /// What the instruction's current placement was measured for.
        private struct Anchor: Equatable {
            var step: TutorialGuide.Step
            var needsName: Bool
            var line: Int
        }

        private var placedAnchor: Anchor?

        /// The line the instruction sits under: the last one with anything on it, or
        /// the empty line the note ends on if it was left with one.
        ///
        /// Read off the document alone, never off the caret. The empty line under the
        /// title is part of the note — it is saved and it comes back — so the
        /// instruction has to sit under it either way. Taken from the caret instead,
        /// the line was only there while someone was standing on it: a reopened note
        /// has its caret back at the top, the instruction came up a line, and the
        /// empty line the note was left with read as gone until the first tap put the
        /// caret back on it.
        private func hintTarget() -> NSRange {
            guard let textView, textView.textStorage.length > 0 else {
                return NSRange(location: 0, length: 0)
            }
            let text = textView.textStorage.string as NSString
            var target = lastContentLine ?? text.lineRange(for: NSRange(location: 0, length: 0))
            // A note ending in a break shows one more line under everything written,
            // and that line is where the next thing goes.
            if text.character(at: text.length - 1) == 0x000A {
                let trailing = NSRange(location: text.length, length: 0)
                if trailing.location > target.location { target = trailing }
            }
            return target
        }

        /// Where the walkthrough's line goes: the line under everything written so far,
        /// at the exact spot the cursor would land on it — a step in when that line is
        /// inside a section or a climb, at the page's margin when it is not.
        ///
        /// Fixed to what the note says, never to the caret: pressing return under the
        /// instruction can't walk it down the page, and moving the caret away doesn't
        /// take it with you.
        private var hintOrigin: CGPoint {
            guard let textView else { return .zero }
            let inset = textView.textContainerInset
            let storage = textView.textStorage

            // An empty page: the instruction is the first line there is, sitting where
            // that line will be typed.
            guard storage.length > 0 else { return CGPoint(x: inset.left, y: inset.top) }

            // The line under the last thing written — or under the empty line the note
            // ends on, if it has one. The instruction is never the line the caret is
            // on: opening a line steps it down and the instruction moves with it, so
            // what gets typed there always lands above the instruction, never over it.
            let target = hintTarget()

            // Under the target: the bottom of the target's own laid-out line, plus the
            // trailing spacing its paragraph puts between itself and whatever comes
            // next — which is where the next line of text starts. An opened line at the
            // very end of the note has no characters to measure, so there the caret
            // standing on it is the measure.
            let bottom = nextLineTop(under: target) ?? 0

            // Always at the page's margin, whatever the line under it is filed inside:
            // the instruction is the walkthrough talking, not a line of the note, so it
            // hangs where every other one of its lines has hung.
            return CGPoint(x: inset.left, y: inset.top + bottom)
        }

        /// Where the line under `line` starts, in the text container's own coordinates:
        /// the bottom of that line's own laid-out box plus its paragraph's trailing
        /// spacing.
        ///
        /// The line's box, not the whole paragraph's fragment: a fragment can run on
        /// past the line — the empty paragraph a document ending in a break shows is
        /// laid out inside the one before it — and its bottom is then a line too low.
        /// That empty line is measured here too, as the last box of the fragment it
        /// was laid out in: one measurement for every case, which is what keeps the
        /// instruction from stepping as a line it was placed under becomes real.
        private func nextLineTop(under line: NSRange) -> CGFloat? {
            // Laid out on demand: TextKit lays out lazily, and asked about a fragment
            // it has not reached yet it simply says nothing — which is what put the
            // instruction back up on the title line until an edit forced layout through.
            (textView as? NoteTextView)?.resolveFullLayout()
            guard let storage = textView?.textStorage, storage.length > 0,
                  let manager = textView?.textLayoutManager,
                  let content = manager.textContentManager
            else { return nil }

            // An empty line at the end of the note has no characters of its own: it is
            // the last box of the fragment before it, and it takes its spacing from the
            // character that fragment ends with.
            let isTrailingEmpty = line.length == 0
            let anchor = isTrailingEmpty ? max(0, line.location - 1) : line.location
            guard let location = content.location(content.documentRange.location, offsetBy: anchor),
                  let fragment = manager.textLayoutFragment(for: location)
            else { return nil }

            // The box holding the line's last character — its own break, or its last
            // glyph on a line that ends the document without one.
            let boxes = fragment.textLineFragments
            let start = content.offset(from: content.documentRange.location,
                                       to: fragment.rangeInElement.location)
            let index = max(0, NSMaxRange(line) - 1 - start)
            let found = isTrailingEmpty
                ? boxes.indices.last
                : boxes.firstIndex(where: { NSLocationInRange(index, $0.characterRange) })
                    ?? boxes.indices.first
            guard let found, let box = boxes.indices.contains(found) ? boxes[found] : nil
            else { return nil }

            func paragraphSpacing(at offset: Int) -> CGFloat {
                (storage.attribute(.paragraphStyle, at: min(max(offset, 0), storage.length - 1),
                                   effectiveRange: nil) as? NSParagraphStyle)?.paragraphSpacing ?? 0
            }

            // Nothing of the fragment left below the line. If the note carries on past
            // it, the answer is not measured at all — it is read off the paragraph that
            // actually landed there, spacing and all. If the line ends the note, the
            // fragment's own bottom plus the room its paragraph keeps under itself is
            // where that paragraph would land: a fragment's frame stops at its last
            // line, the trailing spacing being what the next one is pushed down by.
            if !isTrailingEmpty, found == boxes.count - 1 {
                let end = fragment.rangeInElement.endLocation
                if content.offset(from: content.documentRange.location, to: end) < storage.length,
                   let next = manager.textLayoutFragment(for: end), next !== fragment {
                    let top = next.layoutFragmentFrame.minY
                    if top.isFinite { return top }
                }
                let bottom = fragment.layoutFragmentFrame.maxY + paragraphSpacing(at: line.location)
                return bottom.isFinite ? bottom : nil
            }

            // The line's own trailing spacing — and, for the empty line at the end, the
            // spacing of the paragraph it is laid out inside as well. That one is not in
            // its box: sharing a fragment, there is nothing between them. The moment a
            // character lands the line becomes a paragraph of its own and the fragment
            // above it opens up by exactly that much, which is the few points the
            // instruction has been stepping by.
            var spacing = paragraphSpacing(at: anchor)
            if isTrailingEmpty {
                spacing += paragraphSpacing(at: start)
            }
            let top = fragment.layoutFragmentFrame.minY + box.typographicBounds.maxY + spacing
            return top.isFinite ? top : nil
        }

        /// The line the walkthrough is currently talking about: the last one with
        /// anything on it. An empty heading counts — it is a line waiting for its name,
        /// and the instruction belongs under it rather than back above it — while the
        /// empty lines someone left below it do not.
        private var lastContentLine: NSRange? {
            guard let storage = textView?.textStorage, storage.length > 0 else { return nil }
            let text = storage.string as NSString

            var lines: [NSRange] = []
            var location = 0
            while location < text.length {
                let line = text.lineRange(for: NSRange(location: location, length: 0))
                lines.append(line)
                location = NSMaxRange(line)
            }

            for line in lines.reversed() {
                var written = !text.substring(with: line)
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                for key in [NoteDocument.climbHeader, NoteDocument.sectionHeader]
                where storage.attribute(key, at: line.location, effectiveRange: nil) != nil {
                    written = true
                }
                if written { return line }
            }
            return nil
        }

        /// What the walkthrough is currently asking for: the step, and whether the ask
        /// is the button or the name of the thing it just made.
        private struct Asked: Equatable {
            var step: TutorialGuide.Step
            var needsName: Bool
        }

        /// Which line the label is currently set to, so the text is only rebuilt when
        /// the walkthrough actually moves on rather than on every keystroke.
        private var shownStep: Asked?

        /// The one line the walkthrough is showing: the button to press, or — once it
        /// has been pressed and the thing is sitting there empty — the name to give
        /// what it made. The first step is the note's own name and has no button.
        private func hintText(for asked: Asked) -> NSAttributedString {
            switch asked.step {
            case .title:
                NoteDocument.promptText(NoteDocument.titlePrompt)
            case .section, .climb:
                asked.needsName
                    ? NoteDocument.promptText(NoteDocument.namePrompts[asked.step.rawValue - 1])
                    : NoteDocument.hintText([NoteDocument.hints[asked.step.rawValue - 1]])
            case .attempt:
                NoteDocument.hintText([NoteDocument.hints[asked.step.rawValue - 1]])
            case .rest:
                NoteDocument.restText
            case .done:
                NSAttributedString()
            }
        }

        /// What the note has, as the walkthrough measures it: a heading is only done
        /// once it has been *named* — an empty one is a step of its own, where the ask
        /// becomes the name rather than the button.
        private func updateGuide() {
            // `tracksNote`, not `isRunning`: a walkthrough that has reached the end is
            // still watching, or deleting the attempt back out could never bring the
            // last step back.
            guard parent.guide.tracksNote, parent.tab.showsHints,
                  let storage = textView?.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            let text = storage.string as NSString

            // The walkthrough asks for a name and waits for that name: anything else in
            // the heading is still an unnamed heading as far as the step is concerned,
            // so the instruction stays up rather than the step passing on a typo.
            func heading(_ key: NSAttributedString.Key, named wanted: String) -> TutorialGuide.Heading {
                var found = TutorialGuide.Heading.missing
                storage.enumerateAttribute(key, in: full) { value, range, stop in
                    guard value != nil else { return }
                    let line = text.lineRange(for: NSRange(location: range.location, length: 0))
                    guard NoteDocument.headingName(text.substring(with: line))
                        .caseInsensitiveCompare(wanted) == .orderedSame else {
                        found = .unnamed
                        return
                    }
                    found = .named
                    stop.pointee = true
                }
                return found
            }

            var hasAttempt = false
            storage.enumerateAttribute(.attachment, in: full) { value, _, stop in
                if value is AttemptAttachment {
                    hasAttempt = true
                    stop.pointee = true
                }
            }

            // The name is the session's now, written in the header rather than on any
            // page — so the step that asks for it is answered from there.
            let title = parent.session.title.trimmingCharacters(in: .whitespacesAndNewlines)
            parent.guide.update(hasTitle: title.caseInsensitiveCompare(NoteDocument.workoutName) == .orderedSame,
                                section: heading(NoteDocument.sectionHeader,
                                                 named: NoteDocument.sectionPlaceholder),
                                climb: heading(NoteDocument.climbHeader,
                                               named: NoteDocument.climbPlaceholder),
                                hasAttempt: hasAttempt)
        }

        /// Whether the page has anything on it. The check-in's card is not something
        /// anyone wrote, so the page it opens is still an empty page under it.
        private var isPageEmpty: Bool {
            guard let storage = textView?.textStorage else { return true }
            var text = storage.string
            if let card = NoteDocument.checkInRange(in: storage) {
                text = (storage.string as NSString).replacingCharacters(in: card, with: "")
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// Only attempts live behind markers now; anything else is dropped (or, for an
        /// old stored climb, turned back into text by the document builder).
        private func makeAttachment(for id: UUID) -> NSTextAttachment? {
            guard parent.session.attempt(with: id) != nil else { return nil }
            return makeAttemptAttachment(for: id)
        }

        /// The check-in card, or nothing at all on the walkthrough's own note. The
        /// walkthrough teaches the bar one button at a time and measures where to put
        /// its line off the note's own text — a block it never mentions sitting in the
        /// middle of that is noise in the lesson and a line in the wrong place after
        /// it. Every real session gets one.
        private func makeCheckInAttachment() -> CheckInAttachment? {
            guard parent.session.id != Tutorial.id else { return nil }
            let card = CheckInAttachment()
            card.answers = { [weak self] in self?.parent.session.checkIn ?? [] }
            card.onAnswer = { [weak self] field, option in
                self?.recordCheckIn(field: field, option: option)
            }
            card.onResize = { [weak self] in self?.relayoutCheckIn() }
            return card
        }

        /// One answer, straight onto the session. The card is a view onto the model
        /// and never a copy of it, so nothing here touches the document's text —
        /// which is also why answering a question leaves the undo stack alone.
        private func recordCheckIn(field: Int, option: Int) {
            parent.session.answerCheckIn(field: field, option: option)
            parent.session.updatedAt = Date()
            refreshCheckIn()
            parent.onChange()
        }

        /// Redraws the card where it stands, and re-measures it.
        private func refreshCheckIn() {
            guard let card = checkInAttachment() else { return }
            card.cardView?.configure(answers: parent.session.checkIn)
            card.invalidateHeight()
        }

        private func checkInAttachment() -> CheckInAttachment? {
            guard let storage = textView?.textStorage else { return nil }
            var found: CheckInAttachment?
            storage.enumerateAttribute(.attachment,
                                       in: NSRange(location: 0, length: storage.length)) { value, _, stop in
                if let card = value as? CheckInAttachment {
                    found = card
                    stop.pointee = true
                }
            }
            return found
        }

        /// The card just changed height. Its line is laid out from the view provider
        /// rather than from any attribute, so TextKit has to be told the line is stale
        /// — an attribute edit over it, which is the smallest thing that says so
        /// without touching a character.
        private func relayoutCheckIn() {
            guard let textView,
                  let range = NoteDocument.checkInRange(in: textView.textStorage) else { return }
            let card = NSRange(location: range.location, length: min(1, range.length))
            let restyle = { [self] in
                isRestyling = true
                textView.textStorage.beginEditing()
                textView.textStorage.edited(.editedAttributes, range: card, changeInLength: 0)
                textView.textStorage.endEditing()
                isRestyling = false
            }
            // The note must not jump under the finger that just tapped a pill.
            if let note = textView as? NoteTextView {
                note.holdingScrollPosition(restyle)
                note.resolveFullLayout()
            } else {
                restyle()
            }
        }

        private func makeAttemptAttachment(for id: UUID) -> AttemptAttachment {
            let attachment = AttemptAttachment(attemptID: id)
            attachment.snapshotProvider = { [weak self] id in self?.snapshot(for: id) }
            attachment.onTap = { [weak self] id in self?.parent.onOpenAttempt(id) }
            attachment.onToggleFold = { [weak self] id in self?.toggleNotesFold(for: id) }
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

        private func snapshot(for id: UUID) -> AttemptSnapshot? {
            let session = parent.session
            guard let attempt = session.attempt(with: id) else { return nil }
            let thumbnail = attempt.thumbnailURL.flatMap { UIImage(contentsOfFile: $0.path) }
            return AttemptSnapshot(ordinal: groupOrdinal(of: id) ?? session.ordinal(of: id),
                                   duration: attempt.videoDuration,
                                   rest: attempt.restSeconds,
                                   notes: attempt.notes,
                                   thumbnail: thumbnail,
                                   effort: attempt.effort)
        }

        /// Every attempt row and heading line up to `limit`, in document order — the
        /// walk both ordinal computations count along. A heading carries no id: it only
        /// restarts the numbering.
        private func groupEvents(upTo limit: Int) -> [(location: Int, attemptID: UUID?)] {
            guard let storage = textView?.textStorage else { return [] }
            let range = NSRange(location: 0, length: min(limit, storage.length))
            guard range.length > 0 else { return [] }

            var events: [(location: Int, attemptID: UUID?)] = []
            storage.enumerateAttribute(.attachment, in: range) { value, runRange, _ in
                if let attempt = value as? AttemptAttachment {
                    events.append((runRange.location, attempt.attemptID))
                }
            }
            for key in [NoteDocument.climbHeader, NoteDocument.sectionHeader] {
                storage.enumerateAttribute(key, in: range) { value, runRange, _ in
                    if value != nil { events.append((runRange.location, nil)) }
                }
            }
            return events.sorted { $0.location < $1.location }
        }

        /// Attempts are numbered within their climb group — the run of rows under one
        /// heading — so the count restarts at 1 under each new climb. Rows above the
        /// first heading form their own group.
        func groupOrdinal(of id: UUID) -> Int? {
            var ordinal = 0
            for event in groupEvents(upTo: Int.max) {
                if let attemptID = event.attemptID {
                    ordinal += 1
                    if attemptID == id { return ordinal }
                } else {
                    ordinal = 0
                }
            }
            return nil
        }

        /// What the next attempt recorded at the cursor will be called.
        func nextAttemptOrdinal() -> Int {
            guard let textView else { return 1 }
            var ordinal = 0
            for event in groupEvents(upTo: textView.selectedRange.location) {
                if event.attemptID != nil { ordinal += 1 } else { ordinal = 0 }
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

        /// The plus button: an empty gray bubble lands at the caret, ready to be typed
        /// into. An empty line becomes the bubble's line where it stands; a line with
        /// anything on it breaks first, and the bubble takes the fresh line.
        func insertClimbHeader() {
            insertHeadingLine(NoteDocument.headerAttributes(tint: ClimbTint.fallback),
                              kind: NoteDocument.climbHeader)
        }

        /// The section button: same landing rules as a bubble, but the line styles as
        /// a plain subheader with its fold chevron.
        func insertSectionHeader() {
            insertHeadingLine(NoteDocument.sectionHeaderAttributes,
                              kind: NoteDocument.sectionHeader)
        }

        /// Where the section the caret sits in ends: the first line past everything the
        /// heading above it collapses when folded. A new section lands there rather than
        /// at the caret, so it opens *after* the part of the note it was pressed from
        /// instead of cutting that part in half.
        ///
        /// Sections only: a climb bubble lands where the caret is, because moving the
        /// attempts under it into the climb is the point — see `splitStart`. A section
        /// is stopped by the section it is in, or, failing that, by the climb.
        private func endOfSection(containing location: Int) -> Int {
            guard let storage = textView?.textStorage, storage.length > 0 else { return location }
            let string = storage.string as NSString
            let full = NSRange(location: 0, length: storage.length)
            let caret = min(location, storage.length - 1)
            let lineStart = string.lineRange(for: NSRange(location: caret, length: 0)).location

            // Every heading line in the document, in order, tagged with its kind. One
            // entry per line, the climb kind winning if both attributes land on one —
            // the same rule serialization uses.
            var headings: [(start: Int, isSection: Bool)] = []
            for key in [NoteDocument.climbHeader, NoteDocument.sectionHeader] {
                storage.enumerateAttribute(key, in: full) { value, range, _ in
                    guard value != nil else { return }
                    let start = string.lineRange(for: NSRange(location: range.location, length: 0)).location
                    guard !headings.contains(where: { $0.start == start }) else { return }
                    headings.append((start, key == NoteDocument.sectionHeader))
                }
            }
            headings.sort { $0.start < $1.start }

            // Nothing above the caret: it is in the note's own text, ahead of every
            // group, and the heading opens one where it stands.
            guard let above = headings.last(where: { $0.start <= lineStart }) else { return location }

            let closesSection = above.isSection
            let next = headings.first { $0.start > lineStart && (!closesSection || $0.isSection) }
            return next?.start ?? storage.length
        }

        /// The line at `location` if it is a heading of `kind` that has not been named
        /// yet. An empty heading reads as nothing on the page — its line holds only a
        /// break or the filler space — so this is what stops the button from stacking
        /// invisible headings under each other when it is pressed again.
        private func unnamedHeadingLine(ofKind kind: NSAttributedString.Key,
                                        at location: Int) -> NSRange? {
            guard let storage = textView?.textStorage,
                  let line = line(carrying: kind, at: location) else { return nil }
            let text = (storage.string as NSString).substring(with: line)
            return NoteDocument.headingName(text).isEmpty ? line : nil
        }

        /// Puts the caret in a heading that is already sitting there empty, so pressing
        /// the button a second time asks for the name again rather than making another
        /// one. The caret lands where a freshly inserted heading would leave it: at the
        /// line's start, ahead of its break or filler.
        private func reuseUnnamedHeading(_ line: NSRange) {
            guard let textView else { return }
            textView.selectedRange = NSRange(location: min(line.location, textView.textStorage.length),
                                             length: 0)
            syncTypingAttributes()
            textView.becomeFirstResponder()
        }

        /// Where a climb bubble lands when the caret is parked on an attempt: the head
        /// of that row's line, so the row — and every row under it — moves into the
        /// climb the button is about to open. Recording a go and then realising it was
        /// a different problem is the ordinary way this happens: the plus splits the
        /// climb there and the go becomes attempt 1 of the new one, rather than an
        /// empty climb opening below the go it should have taken with it. Deleting the
        /// bubble again drops the rows straight back into the climb above, since a
        /// group is only ever the run of rows under a heading.
        ///
        /// nil when the caret is not on a row, or when the row is the first of its
        /// group: taking that one would leave the climb above empty, so the bubble
        /// lands under the row instead and the climb keeps its opening go.
        private func splitStart(forCaretAt location: Int) -> Int? {
            guard let storage = textView?.textStorage, storage.length > 0,
                  let id = rowID(onLineAt: location),
                  let marker = markerRange(for: id),
                  (groupOrdinal(of: id) ?? 1) > 1 else { return nil }
            return (storage.string as NSString).lineRange(for: marker).location
        }

        /// The attempt whose block the line at `location` belongs to — the row itself,
        /// or any of the notes filed under it.
        private func rowID(onLineAt location: Int) -> UUID? {
            guard let storage = textView?.textStorage, storage.length > 0 else { return nil }
            let line = (storage.string as NSString)
                .lineRange(for: NSRange(location: min(location, storage.length), length: 0))
            var found: UUID?
            storage.enumerateAttribute(.attachment, in: line) { value, _, stop in
                if let row = value as? AttemptAttachment {
                    found = row.attemptID
                    stop.pointee = true
                }
            }
            return found ?? quoteID(onLineAt: location)
        }

        private func insertHeadingLine(_ header: [NSAttributedString.Key: Any],
                                       kind: NSAttributedString.Key) {
            guard let textView else { return }
            let storage = textView.textStorage
            let cursor = min(textView.selectedRange.location, storage.length)

            // Parked on a go that belongs to a climb of its own: the bubble lands above
            // that row and takes it with it. See `splitStart`.
            let split = kind == NoteDocument.climbHeader ? splitStart(forCaretAt: cursor) : nil
            var location = split ?? endOfQuote(at: cursor)
            let string = storage.string as NSString

            // A heading never lands above the check-in card: the card is what the page
            // opens with, and nothing typed can get in front of it.
            if let card = NoteDocument.checkInRange(in: storage) {
                location = max(location, NSMaxRange(card))
            }

            // The caret is already in an empty one of these: that is the heading this
            // press is asking for, so it takes the caret instead of a second, just as
            // invisible, heading landing under it.
            if let empty = unnamedHeadingLine(ofKind: kind, at: location) {
                reuseUnnamedHeading(empty)
                return
            }

            if let split {
                // The row is already the first one under a bubble waiting for its name:
                // splitting again would only stack a second empty bubble on the first,
                // so this press asks for that name instead.
                if split > 0, let empty = unnamedHeadingLine(ofKind: kind, at: split - 1) {
                    reuseUnnamedHeading(empty)
                    return
                }
            } else {
                // Nor does a heading's own line: from inside a section's name, a bubble
                // lands on the line below it whole. Breaking the name where the caret
                // happens to be would split it in two and hand the tail the section's
                // own styling along with the bubble's.
                if let heading = headingLine(onLineAt: location) ?? sectionLine(onLineAt: location) {
                    location = NSMaxRange(heading)
                }

                // A section never lands inside the section it was pressed from: it
                // goes below everything that one owns. A climb bubble is the opposite
                // — it lands right here, and what was under the caret becomes its.
                if kind == NoteDocument.sectionHeader {
                    location = max(location, endOfSection(containing: location))
                }

                // Same again for where it would land: pressing the button from somewhere
                // else in the note still finds the empty heading already waiting there.
                if let empty = unnamedHeadingLine(ofKind: kind, at: location) {
                    reuseUnnamedHeading(empty)
                    return
                }
            }

            // A line is one kind of heading or the other, never both: styling over
            // characters that already carry the other kind — the break at the end of a
            // section's line, say — would leave a line that serializes as a climb and
            // draws as a section.
            let other = kind == NoteDocument.climbHeader
                ? NoteDocument.sectionHeader
                : NoteDocument.climbHeader
            func style(_ storage: NSTextStorage, _ range: NSRange) {
                storage.removeAttribute(other, range: range)
                storage.addAttributes(header, range: range)
            }

            // A heading landing at the end of the note takes the zero-width marker
            // rather than a break of its own: a break there would leave the note ending
            // in one, and the empty line that shows under it is a line the user never
            // asked for. Anywhere else the break is the heading's line and nothing is
            // left dangling. See `NoteDocument.headingFiller`.
            let atEnd = location >= storage.length
            let blank = NSAttributedString(string: atEnd ? NoteDocument.headingFiller : "\n",
                                           attributes: header)

            let caret: Int

            if location == 0 {
                // The head of the page — an empty one included. The heading is the
                // first line there is: there is no title above it to sit under any more.
                performBlockEdit { $0.replaceCharacters(in: NSRange(location: 0, length: 0), with: blank) }
                caret = 0
            } else if string.character(at: location - 1) == 0x000A {
                // At a line start (the document's end included): the line ahead, if it
                // is empty, becomes the bubble as it stands; otherwise the bubble takes
                // a fresh line here and pushes the rest down.
                let line = location < string.length
                    ? string.lineRange(for: NSRange(location: location, length: 0))
                    : NSRange(location: location, length: 0)
                if line.length == 1, string.character(at: line.location) == 0x000A {
                    performBlockEdit { style($0, line) }
                } else {
                    performBlockEdit { $0.insert(blank, at: location) }
                }
                caret = location
            } else if location < string.length, string.character(at: location) == 0x000A {
                // At the end of a written line: break it, and its own old break becomes
                // the bubble's line.
                performBlockEdit {
                    $0.insert(NSAttributedString(string: "\n", attributes: NoteDocument.bodyAttributes),
                              at: location)
                    style($0, NSRange(location: location + 1, length: 1))
                }
                caret = location + 1
            } else {
                // Mid-line, or past the last character of an unterminated line: new
                // line, then the bubble on its own.
                let piece = NSMutableAttributedString(string: "\n", attributes: NoteDocument.bodyAttributes)
                piece.append(blank)
                performBlockEdit { $0.replaceCharacters(in: NSRange(location: location, length: 0), with: piece) }
                caret = location + 1
            }

            textView.selectedRange = NSRange(location: min(caret, textView.textStorage.length), length: 0)
            syncTypingAttributes()
            textView.becomeFirstResponder()
        }

        /// The last climb heading before the cursor. Attempts recorded here are filed
        /// under it, which is what "typing under a climb" means in the document.
        func currentClimbName() -> String? {
            guard let textView else { return nil }
            let storage = textView.textStorage
            let upToCursor = NSRange(location: 0,
                                     length: min(textView.selectedRange.location, storage.length))
            guard upToCursor.length > 0 else { return nil }

            var start: Int?
            storage.enumerateAttribute(NoteDocument.climbHeader, in: upToCursor) { value, range, _ in
                if value != nil { start = range.location }
            }
            // A section heading ends a climb's group the way another climb would, so
            // attempts recorded under one carry no climb name.
            var sectionStart: Int?
            storage.enumerateAttribute(NoteDocument.sectionHeader, in: upToCursor) { value, range, _ in
                if value != nil { sectionStart = range.location }
            }
            guard let start, start > (sectionStart ?? -1) else { return nil }
            let line = (storage.string as NSString).lineRange(for: NSRange(location: start, length: 0))
            let name = NoteDocument.headingName((storage.string as NSString).substring(with: line))
            return name.isEmpty ? nil : name
        }

        /// `notes` non-nil means the row carries a quote block: the line under it is
        private func insert(_ attachment: NSTextAttachment, quote: NSAttributedString?) {
            guard let textView else { return }
            let storage = textView.textStorage
            // Never land in the middle of another attempt's notes: that would strand them
            // below the new block, under a row that is no longer above them. And never
            // mid-bubble: a row landing inside a heading would split its name in two.
            var location = endOfQuote(at: min(textView.selectedRange.location, storage.length))
            if let heading = headingLine(onLineAt: location) ?? sectionLine(onLineAt: location),
               location > heading.location {
                location = NSMaxRange(heading)
            }
            // Nor above the check-in card: that page opens with the card, whatever the
            // caret was doing.
            if let card = NoteDocument.checkInRange(in: storage) {
                location = max(location, NSMaxRange(card))
            }
            let string = storage.string as NSString

            // Give the row its own line — it lays out as a block, not an inline glyph.
            let breakPiece = NSAttributedString(string: "\n", attributes: NoteDocument.bodyAttributes)
            let needsLeadingBreak = location > 0 && string.character(at: location - 1) != 0x000A
            let piece = NSMutableAttributedString()
            if needsLeadingBreak {
                piece.append(breakPiece)
            }
            piece.append(NSAttributedString(attachment: attachment))

            // The caret is left at the end of the attempt itself — the row, or the last
            // of the notes that came with it. Nothing is opened under it: an empty line
            // nobody asked for is an empty line to delete.
            var caret = location + piece.length
            if let quote, quote.length > 0 {
                piece.append(breakPiece)
                piece.append(quote)
                caret = location + piece.length
            }
            // A break after it only if the note carries on: at the end of the note the
            // row ends the document, and the line under it is one that was never added.
            if location < storage.length, string.character(at: location) != 0x000A {
                piece.append(breakPiece)
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
            guard let textView, let doomed = rowExtent(for: id) else { return }

            performBlockEdit { $0.replaceCharacters(in: doomed, with: "") }
            textView.selectedRange = NSRange(location: min(doomed.location, textView.textStorage.length), length: 0)
            syncTypingAttributes()
        }

        /// The whole of a row: its own character, and everything filed under it that
        /// reads as its notes. This is what a row *is* — the attachment is only its
        /// head — so every way of deleting one deletes this much.
        ///
        /// A binding is not enough to go on. A line can lose one: drifting past a
        /// heading, an edit at its boundary, notes written on the attempt page that
        /// the document has not been handed yet. A clip left behind that way is a bare
        /// clock stranded in the middle of the note, which is what this exists to
        /// prevent. The walk stops at the first line that is neither this attempt's
        /// nor a clock line, so nothing past its own notes is ever taken.
        func rowExtent(for id: UUID) -> NSRange? {
            guard let storage = textView?.textStorage, let marker = markerRange(for: id) else { return nil }
            let text = storage.string as NSString

            var extent = marker
            storage.enumerateAttribute(NoteDocument.noteQuote,
                                       in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if value as? UUID == id { extent = extent.union(range) }
            }

            var location = NSMaxRange(text.lineRange(for: marker))
            while location < storage.length {
                let line = text.lineRange(for: NSRange(location: location, length: 0))
                guard line.length > 0 else { break }
                // The next block ends the region, exactly as `applyStyles` reckons it.
                guard storage.attribute(.attachment, at: line.location, effectiveRange: nil) == nil,
                      storage.attribute(NoteDocument.climbHeader, at: line.location, effectiveRange: nil) == nil,
                      storage.attribute(NoteDocument.sectionHeader, at: line.location, effectiveRange: nil) == nil
                else { break }
                let bound = storage.attribute(NoteDocument.noteQuote, at: line.location,
                                              effectiveRange: nil) as? UUID == id
                let opensWithClock = NoteTimestamp.regex.firstMatch(
                    in: storage.string, options: [], range: line)?.range.location == line.location
                guard bound || opensWithClock else { break }
                extent = extent.union(line)
                location = NSMaxRange(line)
            }
            return extent
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
            syncUndoState()
        }

        // MARK: Undo

        /// Runs the note's own undo stack. `endEditing` is not called: undoing from
        /// the bar should leave the caret and the keyboard exactly where they were.
        func undo() {
            guard let textView, textView.undoManager?.canUndo == true else { return }
            textView.undoManager?.undo()
            // Typing undo runs through `textViewDidChange`, which restyles and saves;
            // a block edit restyles inside its own registered inverse. Either way the
            // page is left consistent here.
            syncTypingAttributes()
            updatePlaceholder()
            persist()
            syncUndoState()
        }

        /// The same trip, the other way. Block edits register their inverse from
        /// inside an undo, which is what gives redo anything to run.
        func redo() {
            guard let textView, textView.undoManager?.canRedo == true else { return }
            textView.undoManager?.redo()
            syncTypingAttributes()
            updatePlaceholder()
            persist()
            syncUndoState()
        }

        /// Watches the undo manager rather than polling it: the stack also moves on
        /// plain typing, which UIKit groups on its own schedule. Called again once
        /// editing starts — before the view is on screen the responder chain has no
        /// undo manager to watch yet.
        func observeUndoManager() {
            guard let manager = textView?.undoManager, manager !== observedUndoManager else {
                syncUndoState()
                return
            }
            observedUndoManager = manager
            let center = NotificationCenter.default
            for name in [NSNotification.Name.NSUndoManagerDidUndoChange,
                         .NSUndoManagerDidRedoChange,
                         .NSUndoManagerDidOpenUndoGroup,
                         .NSUndoManagerDidCloseUndoGroup] {
                center.addObserver(self,
                                   selector: #selector(undoStackChanged),
                                   name: name,
                                   object: manager)
            }
            syncUndoState()
        }

        @objc private func undoStackChanged() {
            syncUndoState()
        }

        /// Hopped off the current turn: this also runs from `makeUIView`, and writing
        /// observed state straight into a view that is mid-update is a runtime warning.
        func syncUndoState() {
            let canUndo = textView?.undoManager?.canUndo ?? false
            let canRedo = textView?.undoManager?.canRedo ?? false
            guard parent.controller.canUndo != canUndo || parent.controller.canRedo != canRedo
            else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.controller.canUndo = canUndo
                self?.parent.controller.canRedo = canRedo
            }
        }

        // MARK: Deleting a row

        /// Backspacing over a row is a real deletion — the video goes with it — so the
        /// edit is held here and only applied once the user says yes.
        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            pendingDeletion = nil
            // The check-in is not text and cannot be typed over or backspaced away.
            // An edit that would take it out is done to everything on either side of
            // it instead, so a select-all still clears the note.
            if let card = NoteDocument.checkInRange(in: textView.textStorage),
               NSIntersectionRange(range, card).length > 0 {
                return editAround(card, range: range, replacement: text)
            }
            // A break never goes into a quote: notes are one line per clock. Return
            // anywhere in one steps the caret out to a fresh body line past the
            // notes instead, and breaks inside pasted text flatten to spaces.
            // Anywhere inside a component, Return leaves it — including on a bare line
            // that carries no binding yet. Checked before the quote-line rule, because
            // the caret sitting somewhere a note isn't is exactly the case that used to
            // grow the box by a line.
            if text == "\n", quoteID(onLineAt: range.location) == nil,
               let id = componentID(containing: range.location) {
                exitComponent(id, replacing: range)
                return false
            }
            if text.contains("\n"), let id = quoteID(onLineAt: range.location) {
                if text == "\n" {
                    // Anywhere in a note, Return means "done here": the caret comes out
                    // to a fresh body line past the notes. Nowhere in a note does it
                    // make a line, which is what keeps a component from ever holding
                    // one that isn't a note.
                    exitQuote(replacing: range)
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
            // An attempt's notes belong to the attempt. The quote under a row is a
            // mirror of them and a link into the clip, so nothing typed lands in one —
            // it is not a text box. An edit reaching past the quote is somebody taking
            // the component out, which still carries the notes off with it.
            if let quote = quoteExtent(at: range.location),
               range.location >= quote.location,
               range.location < NSMaxRange(quote),
               NSMaxRange(range) <= NSMaxRange(quote) {
                return false
            }
            // Return in a bubble finishes the name: no break ever enters the heading —
            // the caret steps out onto a fresh body line below it. Breaks riding in
            // with pasted text flatten to spaces, the way they do in a quote.
            if text.contains("\n"), let line = headingLine(onLineAt: range.location) {
                if text == "\n" {
                    // Return in an empty bubble deletes the climb in place: the line
                    // stays, plain body now, with the caret resting on it — no new
                    // line opens.
                    if !deleteEmptyHeadingInPlace(line) {
                        exitHeading(replacing: range)
                    }
                } else {
                    let flattened = text.replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                    let attributes = NoteDocument.headerAttributes(tint: headingTint(of: line))
                    performBlockEdit {
                        $0.replaceCharacters(in: range,
                                             with: NSAttributedString(string: flattened, attributes: attributes))
                    }
                    textView.selectedRange = NSRange(location: range.location + (flattened as NSString).length,
                                                     length: 0)
                }
                return false
            }
            // A section heading keeps its line whole the same way a bubble does:
            // Return steps out onto a fresh body line, pasted breaks flatten.
            if text.contains("\n"), let line = sectionLine(onLineAt: range.location) {
                if text == "\n" {
                    // An empty section header dissolves under Return the way an
                    // empty bubble does.
                    if !deleteEmptyHeadingInPlace(line) {
                        exitHeading(replacing: range)
                    }
                } else {
                    let flattened = text.replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                    performBlockEdit {
                        $0.replaceCharacters(in: range,
                                             with: NSAttributedString(string: flattened,
                                                                      attributes: NoteDocument.sectionHeaderAttributes))
                    }
                    textView.selectedRange = NSRange(location: range.location + (flattened as NSString).length,
                                                     length: 0)
                }
                return false
            }
            // A tap makes UIKit rebuild `typingAttributes` from its own reading of the
            // context, and the quote binding (a custom key) does not survive. Re-derive
            // them at the moment of insertion, so typing on a quote's line is always
            // that attempt's notes rather than unbound body text mid-quote — and, off
            // a quote's line, is never the quote's: whatever UIKit carried over from
            // the character behind the caret is replaced outright, so a quote's look
            // (or its binding) cannot ride past its edge onto a fresh line. Heading
            // lines get the same treatment, for the same reason.
            if !text.isEmpty {
                if let id = quoteID(onLineAt: range.location) {
                    textView.typingAttributes = NoteDocument.quoteAttributes(for: id)
                } else if let line = headingLine(onLineAt: range.location) {
                    textView.typingAttributes = NoteDocument.headerAttributes(tint: headingTint(of: line))
                } else if sectionLine(onLineAt: range.location) != nil {
                    textView.typingAttributes = NoteDocument.sectionHeaderAttributes
                } else if textView.typingAttributes[NoteDocument.noteQuote] != nil
                            || textView.typingAttributes[NoteDocument.climbHeader] != nil
                            || textView.typingAttributes[NoteDocument.sectionHeader] != nil {
                    textView.typingAttributes = NoteDocument.bodyAttributes
                }
            }
            // Backspacing into a clock never nibbles at it: the token goes whole, and
            // the line goes with it once the note's words are already gone.
            if text.isEmpty, deleteTimestamp(at: range) { return false }
            // An emptied bubble goes whole: with the name already gone, the next
            // backspace deletes the climb's line itself.
            if text.isEmpty, deleteEmptyHeadingLine(at: range) { return false }
            // A bubble keeps its line whole under deletion the way a row does:
            // deleting the break on either side would merge written text into the
            // heading — or the name down onto it — recolouring whatever it lands on
            // as part of the climb.
            if text.isEmpty, mergesIntoHeadingLine(range) { return false }
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

        /// Return anywhere in a bubble: the heading keeps its line whole, and the caret
        /// lands on a fresh body line just below it. A selected run of the name is
        /// consumed by the Return the way it would be anywhere else.
        private func exitHeading(replacing range: NSRange) {
            guard let textView else { return }
            var caret = range.location
            performBlockEdit { storage in
                if range.length > 0 {
                    storage.replaceCharacters(in: range, with: "")
                }
                let text = storage.string as NSString
                let line = text.lineRange(for: NSRange(location: min(range.location, storage.length),
                                                       length: 0))
                let hasBreak = line.length > 0 && text.character(at: NSMaxRange(line) - 1) == 0x000A
                storage.insert(NSAttributedString(string: "\n", attributes: NoteDocument.bodyAttributes),
                               at: NSMaxRange(line))
                // Past a heading ending in its own break, the new line slots in whole;
                // after an unterminated one, the inserted break first closes the
                // bubble's line, and the caret belongs beyond it.
                caret = hasBreak ? NSMaxRange(line) : NSMaxRange(line) + 1
            }
            textView.selectedRange = NSRange(location: min(caret, textView.textStorage.length), length: 0)
            // Derived, not assumed: the line below a heading is inside its group, and
            // body text there steps in to the group's margin. Left at plain body
            // attributes the caret sat out at the page's edge until the first
            // character landed and the restyle moved the line under it.
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
            // Same as leaving a heading: a line out from under a quote is still inside
            // whatever group the row belongs to, and the caret has to know it now.
            syncTypingAttributes()
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

        /// A bubble with no name deletes where it stands — Return or backspace both
        /// land here. The heading dissolves back into a plain empty body line and
        /// the caret stays on it: nothing inserted, nothing pulled up. False if the
        /// bubble has a name.
        private func deleteEmptyHeadingInPlace(_ line: NSRange) -> Bool {
            guard let textView else { return false }
            let text = textView.textStorage.string as NSString
            guard text.substring(with: line)
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

            let hasBreak = line.length > 0 && text.character(at: NSMaxRange(line) - 1) == 0x000A
            let replacement = hasBreak
                ? NSAttributedString(string: "\n", attributes: NoteDocument.bodyAttributes)
                : NSAttributedString()
            performBlockEdit { $0.replaceCharacters(in: line, with: replacement) }
            textView.selectedRange = NSRange(location: min(line.location, textView.textStorage.length),
                                             length: 0)
            textView.typingAttributes = NoteDocument.bodyAttributes
            return true
        }

        /// Backspace in a bubble whose name is already gone deletes the climb in
        /// place, the same dissolve Return does. Section headings go the same way.
        private func deleteEmptyHeadingLine(at range: NSRange) -> Bool {
            guard range.length == 1 else { return false }
            let caret = NSMaxRange(range)
            guard let line = headingLine(onLineAt: caret) ?? sectionLine(onLineAt: caret) else {
                return false
            }
            return deleteEmptyHeadingInPlace(line)
        }

        /// Whether this edit deletes exactly the break on one side of a heading's
        /// line — and would merge written text into it. The heading attribute is
        /// line-shaped, so whatever a bubble merges with becomes part of the climb;
        /// those breaks only go when the line merging away is empty, when nothing
        /// changes hands and the default deletion reads right.
        private func mergesIntoHeadingLine(_ range: NSRange) -> Bool {
            guard let storage = textView?.textStorage, range.length == 1 else { return false }
            let string = storage.string as NSString
            guard range.location < string.length,
                  string.character(at: range.location) == 0x000A else { return false }

            let ending = string.lineRange(for: NSRange(location: range.location, length: 0))
            let followingStart = NSMaxRange(ending)
            guard followingStart < string.length else { return false }
            let following = string.lineRange(for: NSRange(location: followingStart, length: 0))
            let isHeading: (NSRange) -> Bool = {
                self.headingLine(onLineAt: $0.location) != nil
                    || self.sectionLine(onLineAt: $0.location) != nil
            }
            let followingIsEmpty = following.length == 1 &&
                string.character(at: following.location) == 0x000A

            // The break is the bubble's own: the written line below would ride up
            // into it. An empty bubble's break may go — that deletes the bubble.
            if isHeading(ending), ending.length > 1, !followingIsEmpty { return true }
            // The break ends the written line above: the bubble's name would ride
            // up onto it.
            if isHeading(following), ending.length > 1 { return true }
            return false
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

        /// An edit whose range runs over the check-in card. The card stays — it is the
        /// one thing in the note nobody put there — and everything the edit was going
        /// to do on either side of it happens anyway. Always returns false: the edit
        /// has been dealt with here.
        ///
        /// The title's own break is held back too. The card hangs under the title
        /// line, and a select-all that took the break with it would leave the card as
        /// the note's first line with no title above it to be under.
        private func editAround(_ card: NSRange, range: NSRange, replacement: String) -> Bool {
            guard let textView else { return false }
            let keep = max(0, card.location - 1)
            let head = NSRange(location: range.location,
                               length: max(0, min(NSMaxRange(range), keep) - range.location))
            let tailStart = max(range.location, NSMaxRange(card))
            let tail = NSRange(location: tailStart, length: max(0, NSMaxRange(range) - tailStart))
            guard head.length > 0 || tail.length > 0 || !replacement.isEmpty else { return false }

            // Rows inside what is left of the range are still real deletions, and
            // still have to be asked about first.
            let doomed = attemptMarkers(in: head) + attemptMarkers(in: tail)
            guard doomed.isEmpty else {
                pendingDeletion = (range, replacement)
                parent.onConfirmDelete(doomed.count)
                return false
            }

            applyEditAround(card, head: head, tail: tail, replacement: replacement)
            return false
        }

        /// Back to front, so each piece is taken out of a document the ones before it
        /// have not moved: the tail first, then whatever was typed lands just past the
        /// card, then the head.
        private func applyEditAround(_ card: NSRange, head: NSRange, tail: NSRange, replacement: String) {
            guard let textView else { return }
            let typed = NSAttributedString(string: replacement, attributes: NoteDocument.bodyAttributes)
            performBlockEdit { storage in
                if tail.length > 0 { storage.deleteCharacters(in: tail) }
                if typed.length > 0 { storage.insert(typed, at: NSMaxRange(card)) }
                if head.length > 0 { storage.deleteCharacters(in: head) }
            }
            let caret = NSMaxRange(card) - head.length + typed.length
            textView.selectedRange = NSRange(location: min(max(caret, 0), textView.textStorage.length), length: 0)
            syncTypingAttributes()
        }

        func confirmPendingDeletion() {
            guard let pending = pendingDeletion, let textView else { return }
            pendingDeletion = nil

            // Held back from an edit that ran over the card: the same split, now that
            // the rows inside it have been said goodbye to.
            if let card = NoteDocument.checkInRange(in: textView.textStorage),
               NSIntersectionRange(pending.range, card).length > 0 {
                let keep = max(0, card.location - 1)
                let head = NSRange(location: pending.range.location,
                                   length: max(0, min(NSMaxRange(pending.range), keep) - pending.range.location))
                let tailStart = max(pending.range.location, NSMaxRange(card))
                let tail = NSRange(location: tailStart,
                                   length: max(0, NSMaxRange(pending.range) - tailStart))
                applyEditAround(card, head: head, tail: tail, replacement: pending.replacement)
                return
            }

            // The edit only ever covered the rows themselves — the notes under them
            // are separate text, and the caret never selected that far. Deleting a row
            // takes its notes with it however the deletion was asked for, so the range
            // grows to the full extent of every row inside it.
            var doomed = pending.range
            for id in attemptMarkers(in: pending.range) {
                if let extent = rowExtent(for: id) { doomed = doomed.union(extent) }
            }

            let replacement = NSAttributedString(string: pending.replacement,
                                                 attributes: NoteDocument.bodyAttributes)
            performBlockEdit { $0.replaceCharacters(in: doomed, with: replacement) }
            textView.selectedRange = NSRange(location: doomed.location + replacement.length, length: 0)
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
        /// The note line a tap at `point` lands on, and the moment it marks.
        ///
        /// The whole line, edge to edge: an attempt's notes are written in the attempt
        /// itself and only mirrored down here, so a line of one is not text you can
        /// get a caret into — it is a link into the clip it was taken at. `seconds` is
        /// nil for a line that carries no clock, which opens the attempt at its start.
        fileprivate func quoteLink(at point: CGPoint) -> (id: UUID, seconds: TimeInterval?)? {
            guard let textView, let manager = textView.textLayoutManager,
                  let content = manager.textContentManager
            else { return nil }
            let storage = textView.textStorage
            guard storage.length > 0 else { return nil }

            let inset = textView.textContainerInset
            let local = CGPoint(x: point.x - inset.left, y: point.y - inset.top)
            // Measured off the layout, not off the caret: the fragments under a row
            // tile its card top to bottom, so every point on the card belongs to one
            // of its lines — the gaps between them and the padding at the end
            // included. A caret test only ever caught the words themselves, and left
            // the rest of the card falling through to the row behind it.
            guard let fragment = manager.textLayoutFragment(for: local) else { return nil }
            let start = content.offset(from: content.documentRange.location,
                                       to: fragment.rangeInElement.location)
            guard start >= 0, start < storage.length,
                  let id = quoteID(onLineAt: start),
                  // A point off the ends of the text resolves to the nearest fragment
                  // rather than to none, so the card has to be under the finger.
                  local.y >= fragment.layoutFragmentFrame.minY,
                  local.y <= cardBottom(of: fragment, at: start)
            else { return nil }

            // The nearest clip to the finger. Anywhere on the card opens one — it is a
            // list of links to the video, not text you can get a caret into, and a tap
            // that lands a few points off a line meant the line it landed nearest.
            let text = storage.string as NSString
            var best: (distance: CGFloat, seconds: TimeInterval)?
            var location = quoteExtent(at: start)?.location ?? start
            let end = quoteExtent(at: start).map(NSMaxRange) ?? NSMaxRange(text.lineRange(
                for: NSRange(location: start, length: 0)))
            while location < end {
                let line = text.lineRange(for: NSRange(location: location, length: 0))
                defer { location = NSMaxRange(line) }
                guard line.location < storage.length,
                      let seconds = storage.attribute(NoteDocument.noteTimestamp, at: line.location,
                                                      effectiveRange: nil) as? TimeInterval,
                      let frame = lineFrame(atOffset: line.location)
                else { continue }
                let distance = max(frame.minY - local.y, local.y - frame.maxY, 0)
                if best == nil || distance < best!.distance { best = (distance, seconds) }
            }
            // A row whose notes carry no clock at all — nothing to seek to, so the
            // attempt opens where it starts.
            return (id, best?.seconds)
        }

        /// Where the card actually stops under a line. Its last line holds the gap to
        /// whatever follows inside its own fragment, and that gap is page, not card.
        private func cardBottom(of fragment: NSTextLayoutFragment, at offset: Int) -> CGFloat {
            let frame = fragment.layoutFragmentFrame
            guard let storage = textView?.textStorage,
                  storage.attribute(NoteDocument.noteQuoteEnd, at: offset,
                                    effectiveRange: nil) != nil,
                  let last = fragment.textLineFragments.last
            else { return frame.maxY }
            return frame.minY + last.typographicBounds.maxY + BookmarkLayoutFragment.cardBottomPadding
        }

        /// One note line's slice of the card, in the text container's coordinates.
        private func lineFrame(atOffset offset: Int) -> CGRect? {
            guard let manager = textView?.textLayoutManager,
                  let content = manager.textContentManager,
                  let location = content.location(content.documentRange.location, offsetBy: offset),
                  let fragment = manager.textLayoutFragment(for: location)
            else { return nil }
            return fragment.layoutFragmentFrame
        }

        /// The whole of the quote at `location` — every line of one attempt's notes,
        /// with the break that closes them.
        fileprivate func quoteExtent(at location: Int) -> NSRange? {
            guard let storage = textView?.textStorage, storage.length > 0,
                  let id = quoteID(at: location)
            else { return nil }
            var target: NSRange?
            storage.enumerateAttribute(NoteDocument.noteQuote,
                                       in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                guard value as? UUID == id else { return }
                target = target.map { $0.union(range) } ?? range
            }
            return target
        }

        @objc func timestampTapped(_ gesture: UITapGestureRecognizer) {
            guard let textView else { return }
            let point = gesture.location(in: textView)
            // The card's notes are asked first: a row's own line ends where its card
            // begins, so nothing here is ambiguous — but the row is the fallback for a
            // tap the text can't place, and it must not be given the card's own.
            if let hit = quoteLink(at: point) {
                if let seconds = hit.seconds {
                    parent.onSeekAttempt(hit.id, seconds)
                } else {
                    parent.onOpenAttempt(hit.id)
                }
                return
            }
            if let hit = attemptRow(at: point) {
                // The row knows where its own parts are; without one on screen there
                // is nothing to fold, so the tap can only be the link.
                if let row = hit.attachment.rowView {
                    row.handleTap(at: hit.local)
                } else {
                    hit.attachment.onTap?(hit.attachment.attemptID)
                }
                return
            }
            if let heading = headingChevron(at: point) {
                toggleFold(ofHeadingLine: heading)
                return
            }
        }

        /// The attempt row a tap at `point` lands on, and where in the row it landed.
        ///
        /// Read off the text, not off the view. A row is a real view UIKit hosts
        /// inside the text, so it could carry its own recognizer — but a touch on it
        /// belongs to the text view's recognizers too, and theirs is the one that
        /// places the caret. Answered from here it is the same tap a clock token is:
        /// one recognizer, which either opens the attempt or moves the caret, never
        /// both.
        fileprivate func attemptRow(at point: CGPoint)
            -> (attachment: AttemptAttachment, local: CGPoint)? {
            guard let textView, let manager = textView.textLayoutManager,
                  let content = manager.textContentManager
            else { return nil }
            let storage = textView.textStorage
            guard storage.length > 0, let position = textView.closestPosition(to: point)
            else { return nil }
            let offset = min(textView.offset(from: textView.beginningOfDocument, to: position),
                             storage.length - 1)

            // A row is one character wide and a position sits between characters, so
            // the attachment can be on either side of the one the tap resolved to.
            var found: (attachment: AttemptAttachment, index: Int)?
            for index in [offset, offset - 1] where index >= 0 {
                if let attachment = storage.attribute(.attachment, at: index,
                                                      effectiveRange: nil) as? AttemptAttachment {
                    found = (attachment, index)
                    break
                }
            }
            guard let found, !found.attachment.isCollapsed else { return nil }

            // The nearest character to a tap in the notes under a row is often the row
            // itself, so the tap has to land inside the row's own line to count —
            // otherwise writing under a row could not be tapped into.
            guard let location = content.location(content.documentRange.location,
                                                  offsetBy: found.index),
                  let fragment = manager.textLayoutFragment(for: location)
            else { return nil }
            let inset = textView.textContainerInset
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: inset.left, dy: inset.top)
            guard frame.contains(point) else { return nil }
            return (found.attachment, CGPoint(x: point.x - frame.minX, y: point.y - frame.minY))
        }

        // MARK: Folding

        /// The heading line a tap at `point` folds. On a climb heading that is the
        /// whole row past its pill — the attempt count, the chevron, and the empty
        /// space between them — so only the bubble itself is left as something to
        /// tap into and rename. A section heading has no pill to protect, so it keeps
        /// the narrower target: the trailing lane its chevron sits in, with slop to
        /// make a 12pt glyph finger-sized.
        fileprivate func headingChevron(at point: CGPoint) -> NSRange? {
            guard let textView, let position = textView.closestPosition(to: point) else { return nil }
            let caret = textView.caretRect(for: position)
            guard caret.height > 0, abs(point.y - caret.midY) < max(caret.height, 24) else { return nil }

            let storage = textView.textStorage
            guard storage.length > 0 else { return nil }
            let offset = min(textView.offset(from: textView.beginningOfDocument, to: position),
                             storage.length - 1)
            if let climb = headingLine(onLineAt: offset) {
                return point.x > pillMaxX(ofHeadingLine: climb) ? climb : nil
            }
            guard point.x > textView.bounds.width - 56 else { return nil }
            return sectionLine(onLineAt: offset)
        }

        /// The right edge of a climb heading's pill, in the text view's coordinates —
        /// measured the same way `ClimbHeaderLayoutFragment` draws it, example name
        /// and all, so an unnamed bubble is as tappable as a named one.
        private func pillMaxX(ofHeadingLine line: NSRange) -> CGFloat {
            guard let textView else { return .greatestFiniteMagnitude }
            let name = NoteDocument.headingName((textView.textStorage.string as NSString)
                .substring(with: line))
            let text = name.isEmpty ? NoteDocument.climbExample : name
            return textView.textContainerInset.left + NoteDocument.textIndent * 2
                + HeadingPlaceholder.width(of: text, font: NoteDocument.headerFont)
        }

        fileprivate func prepareFoldHaptic() { foldHaptic.prepare() }

        /// Whether the character at `location` is inside a collapsed group — folded
        /// text keeps its characters but draws at a hairline font, which is what makes
        /// a caret parked in there peek out as a sliver.
        private func isFoldHidden(_ location: Int, in storage: NSTextStorage,
                                  effective: UnsafeMutablePointer<NSRange>? = nil,
                                  within: NSRange? = nil) -> Bool {
            guard location >= 0, location < storage.length else { return false }
            let limit = within ?? NSRange(location: 0, length: storage.length)
            let font = effective.map {
                storage.attribute(.font, at: location, longestEffectiveRange: $0, in: limit) as? UIFont
            } ?? (storage.attribute(.font, at: location, effectiveRange: nil) as? UIFont)
            guard let font else { return false }
            return font.pointSize < 1
        }

        /// Where a caret at `location` belongs if the fold has swallowed it: the first
        /// character past the collapsed group — the line drawn under the heading — or,
        /// when the group runs to the end of the note, the end of the heading line
        /// above it. nil when the caret is somewhere visible and should stay put.
        fileprivate func visibleLocation(forCaretAt location: Int) -> Int? {
            guard let storage = textView?.textStorage, storage.length > 0,
                  isFoldHidden(location, in: storage) else { return nil }

            var run = NSRange(location: 0, length: 0)
            var forward = location
            while forward < storage.length {
                let tail = NSRange(location: forward, length: storage.length - forward)
                guard isFoldHidden(forward, in: storage, effective: &run, within: tail) else { return forward }
                forward = NSMaxRange(run)
            }

            // Nothing visible below: back out to the heading the group hangs off.
            var start = location
            while start > 0 {
                let head = NSRange(location: 0, length: start)
                guard isFoldHidden(start - 1, in: storage, effective: &run, within: head) else { break }
                start = run.location
            }
            return max(start - 1, 0)
        }

        /// Folds the group under a heading down to just the heading, or unfolds it.
        /// A restyle, not an edit: the text is untouched, so nothing is persisted and
        /// nothing lands on the undo stack — and a reopened note starts unfolded.
        func toggleFold(ofHeadingLine line: NSRange) {
            guard let textView, line.length > 0 else { return }
            let storage = textView.textStorage
            let folded = storage.attribute(NoteDocument.foldedHeading, at: line.location,
                                           effectiveRange: nil) != nil

            // Collapsing takes the keyboard with it: a caret left inside the group
            // keeps its insertion point in text that is now hairline-tall and clear,
            // and draws as a sliver of a cursor against the heading. Nothing under a
            // fold is editable, so the document gives up focus rather than hold a
            // caret somewhere invisible.
            if !folded { textView.resignFirstResponder() }

            isRestyling = true
            let selected = textView.selectedRange
            let restyle = { [self] in
                if folded {
                    storage.removeAttribute(NoteDocument.foldedHeading, range: line)
                } else {
                    storage.addAttribute(NoteDocument.foldedHeading, value: true, range: line)
                }
                NoteDocument.applyStyles(to: storage)
            }
            if let note = textView as? NoteTextView {
                note.holdingScrollPosition(restyle)
            } else {
                restyle()
            }
            // A caret the fold has just swallowed comes out below the group, the same
            // place a tap on a collapsed heading would put it — so refocusing later
            // lands somewhere visible instead of inside the fold.
            let caret = min(selected.location, storage.length)
            textView.selectedRange = NSRange(location: visibleLocation(forCaretAt: caret) ?? caret, length: 0)
            isRestyling = false
            syncTypingAttributes()

            // The group has already collapsed; the chevron turns after it, with a tap
            // under the finger as it goes.
            foldHaptic.impactOccurred()
            if let note = textView as? NoteTextView {
                foldAnimator.spin(lineAt: line.location, to: !folded, in: note)
            }
        }

        // MARK: UITextViewDelegate

        /// How far the page is scrolled from its own top — zero at rest, negative
        /// while it is being pulled past it.
        var scrolledDistance: CGFloat {
            guard let textView else { return 0 }
            return textView.contentOffset.y + textView.contentInset.top
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.onScroll(scrollView.contentOffset.y + scrollView.contentInset.top)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Four pages, four accessory clones — the bar swap has to follow the one
            // riding this keyboard, so the page taking focus claims it.
            parent.barPark.keyboardBar = accessoryContainer
            parent.onFocusChange(true)
            observeUndoManager()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange(false)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isRestyling else { return }
            // The restyle rewrites attributes over the whole storage, so it throws
            // away the entire layout and TextKit re-estimates the content height
            // from scratch — pinned so that churn can't drag the page.
            let restyle = { [self] in
                isRestyling = true
                let selected = textView.selectedRange
                NoteDocument.applyStyles(to: textView.textStorage)
                textView.selectedRange = selected
                isRestyling = false
            }
            if let note = textView as? NoteTextView {
                note.holdingScrollPosition(restyle)
                note.followCaretWhileTyping()
            } else {
                restyle()
            }
            syncTypingAttributes()
            updatePlaceholder()
            persist()
            syncUndoState()
        }

        /// Moving the caret across the title/body boundary has to resize it too.
        /// Deliberately does not scroll: a tap or an arrow key lands where the user
        /// aimed, and the page stays where they left it.
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isRestyling else { return }
            // A tap over a collapsed group lands the caret in text that is drawn at
            // hairline size, so what shows is a sliver of a cursor wedged into the
            // fold. There is nothing to edit in there: the caret comes out the far
            // side, onto the first line the fold leaves visible.
            if textView.selectedRange.length == 0,
               let visible = visibleLocation(forCaretAt: textView.selectedRange.location) {
                isRestyling = true
                textView.selectedRange = NSRange(location: visible, length: 0)
                isRestyling = false
            }
            // The card's line holds one character nobody typed. A caret parked on it
            // has nothing to edit and no room to draw, so it comes out onto the first
            // line under the card — where a tap on the card was aiming anyway.
            if textView.selectedRange.length == 0,
               let card = NoteDocument.checkInRange(in: textView.textStorage),
               NSLocationInRange(textView.selectedRange.location, card) {
                isRestyling = true
                textView.selectedRange = NSRange(location: min(NSMaxRange(card),
                                                               textView.textStorage.length), length: 0)
                isRestyling = false
            }
            // The notes under a row are read-only here — they are the attempt's, and
            // this is a link into it. A caret that lands in one anyway, arrow-keyed or
            // left behind by an edit, comes out under the notes onto the first line
            // there is anything to type on.
            if textView.selectedRange.length == 0,
               let quote = quoteExtent(at: textView.selectedRange.location),
               textView.selectedRange.location < NSMaxRange(quote) {
                isRestyling = true
                textView.selectedRange = NSRange(location: min(NSMaxRange(quote),
                                                               textView.textStorage.length), length: 0)
                isRestyling = false
            }
            syncTypingAttributes()
            // Cheap insurance for the walkthrough's line: its place is measured off
            // the laid-out text, and a tap is the first thing to happen after a note
            // opens with its layout still settling.
            if parent.guide.isRunning { updatePlaceholder() }
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
            // The break that ends the quote is the document's, not the notes'. Handed
            // one on the end, the quote gets a blank line under it — and hands that
            // line back the next time round.
            let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

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
            // The break after a note is what separates it from whatever follows. At the
            // end of the document nothing follows, and adding one there is what left a
            // blank line sitting under the component every time a clip was written.
            let atEnd = insertAt >= storage.length
            piece.append(NSAttributedString(string: atEnd ? notes : notes + "\n",
                                            attributes: NoteDocument.quoteAttributes(for: id)))

            performBlockEdit { $0.insert(piece, at: insertAt) }
        }

        private func persist() {
            guard let textView else { return }
            syncNotes()
            let (text, ids) = NoteDocument.serialize(textView.attributedText)
            // Adding or deleting a marker reshuffles the groups below it, so every row
            // after the edit is now labelled with a stale number.
            let markersChanged = ids != parent.session.attachmentIDs(for: parent.tab)
            parent.session.setDocument(text: text, ids: ids, for: parent.tab)
            parent.session.updatedAt = Date()
            parent.onChange()
            if markersChanged { refreshRowLabels() }
        }

        // MARK: Keyboard toolbar

        func attachAccessoryView(to textView: UITextView) {
            let toolbar = EditingToolbar(
                stopwatch: parent.stopwatch,
                guide: parent.guide,
                onAddClimb: { [weak self] in self?.parent.onAddClimb() },
                onAddSection: { [weak self] in self?.parent.onAddSection() },
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
            accessoryContainer = container
            parent.barPark.keyboardBar = container
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
        guard start >= 0, start < storage.length
        else { return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange) }

        // A heading hidden inside a folded section lays out as the hairline text it
        // now is — no pill, no chevron — rather than a ghost of its bubble. Only a
        // *folded* hairline though: a stamped note line also opens at hairline size —
        // its hidden clock token — and still carries `noteTimestamp`, which folding
        // strips. Without that distinction every note line lost its bookmark and clock.
        if let font = storage.attribute(.font, at: start, effectiveRange: nil) as? UIFont,
           font.pointSize < 1,
           storage.attribute(NoteDocument.noteTimestamp, at: start, effectiveRange: nil) == nil {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }

        // A heading paragraph draws as a bubble: the tinted pill behind the name,
        // with the fold chevron at the line's trailing edge.
        if storage.attribute(NoteDocument.climbHeader, at: start, effectiveRange: nil) != nil {
            let line = (storage.string as NSString).lineRange(for: NSRange(location: start, length: 0))
            let name = NoteDocument.headingName((storage.string as NSString).substring(with: line))
            let fragment = ClimbHeaderLayoutFragment(textElement: textElement,
                                                     range: textElement.elementRange)
            fragment.name = name
            fragment.tint = ClimbTint.color(for: name)
            fragment.isFolded = NoteDocument.isFolded(lineAt: start, in: storage)
            fragment.foldProgress = foldAnimator.progress(forLineAt: start, folded: fragment.isFolded)
            fragment.containerWidth = textView.textContainer.size.width
            fragment.attemptCount = attemptCount(below: NSMaxRange(line), in: storage)
            return fragment
        }

        // A section heading lays out as its own subheader text; only the chevron
        // is drawn in.
        if storage.attribute(NoteDocument.sectionHeader, at: start, effectiveRange: nil) != nil {
            let line = (storage.string as NSString).lineRange(for: NSRange(location: start, length: 0))
            let name = NoteDocument.headingName((storage.string as NSString).substring(with: line))
            let fragment = SectionHeaderLayoutFragment(textElement: textElement,
                                                       range: textElement.elementRange)
            fragment.name = name
            fragment.isFolded = NoteDocument.isFolded(lineAt: start, in: storage)
            fragment.foldProgress = foldAnimator.progress(forLineAt: start, folded: fragment.isFolded)
            fragment.containerWidth = textView.textContainer.size.width
            fragment.climbCount = climbCount(below: NSMaxRange(line), in: storage)
            return fragment
        }

        // Every line of a row's notes draws the card behind itself; the stamped ones
        // additionally get their bookmark and their clock.
        let seconds = storage.attribute(NoteDocument.noteTimestamp, at: start,
                                        effectiveRange: nil) as? TimeInterval
        guard seconds != nil || storage.attribute(NoteDocument.noteQuote, at: start,
                                                  effectiveRange: nil) != nil
        else { return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange) }

        let fragment = BookmarkLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.clock = seconds.map { NoteTimestamp.display(for: $0) }
        fragment.showsBookmark = seconds != nil
        fragment.closesCard = storage.attribute(NoteDocument.noteQuoteEnd, at: start,
                                                effectiveRange: nil) != nil
        // The line that opens the card is the one whose own line has no note line
        // before it — the break above it belongs to the row, not to a quote.
        let lineStart = (storage.string as NSString)
            .lineRange(for: NSRange(location: start, length: 0)).location
        fragment.opensCard = lineStart == 0
            || storage.attribute(NoteDocument.noteQuote, at: lineStart - 1,
                                 effectiveRange: nil) == nil
        fragment.containerWidth = textView.textContainer.size.width
        fragment.horizontalInset = textView.textContainer.lineFragmentPadding
        return fragment
    }

    /// The row's chevron: closes its notes away, or opens them again. A restyle, not
    /// an edit — the text is untouched, so nothing is persisted and nothing lands on
    /// the undo stack. The fold lives on the attachment, and `applyStyles` reads it
    /// back off every row it walks.
    private func toggleNotesFold(for id: UUID) {
        guard let textView else { return }
        let storage = textView.textStorage
        var folded: AttemptAttachment?
        storage.enumerateAttribute(.attachment,
                                   in: NSRange(location: 0, length: storage.length)) { value, _, stop in
            guard let attempt = value as? AttemptAttachment, attempt.attemptID == id else { return }
            attempt.areNotesFolded.toggle()
            folded = attempt
            stop.pointee = true
        }
        let closing = folded?.areNotesFolded ?? false
        // Same reason a folded heading gives up focus: a caret left in notes that are
        // now hairline-tall and clear draws as a sliver against the row.
        if closing { textView.resignFirstResponder() }
        // The same tap under the finger a heading's fold gives.
        foldHaptic.impactOccurred()

        isRestyling = true
        let selected = textView.selectedRange
        let restyle = { NoteDocument.applyStyles(to: storage) }
        if let note = textView as? NoteTextView {
            note.holdingScrollPosition(restyle)
        } else {
            restyle()
        }
        let caret = min(selected.location, storage.length)
        textView.selectedRange = NSRange(location: visibleLocation(forCaretAt: caret) ?? caret, length: 0)
        isRestyling = false
        syncTypingAttributes()
    }

    /// Attempts filed under the heading whose line ends at `start`: every row from
    /// there down to the next heading of either kind — the same boundary the group
    /// ordinals restart on, so the count always agrees with the numbering below it.
    private func attemptCount(below start: Int, in storage: NSTextStorage) -> Int {
        var end = storage.length
        guard start < end else { return 0 }
        let below = NSRange(location: start, length: storage.length - start)
        for key in [NoteDocument.climbHeader, NoteDocument.sectionHeader] {
            storage.enumerateAttribute(key, in: below) { value, range, stop in
                if value != nil {
                    end = min(end, range.location)
                    stop.pointee = true
                }
            }
        }
        guard start < end else { return 0 }
        var count = 0
        storage.enumerateAttribute(.attachment, in: NSRange(location: start, length: end - start)) { value, _, _ in
            if value is AttemptAttachment { count += 1 }
        }
        return count
    }

    /// Climbs filed under the section whose line ends at `start`: every climb heading
    /// from there down to the next section — the boundary the section's own fold
    /// stops at, so the tally counts exactly what folds away under it. Counted by
    /// line rather than by attribute run, because two headings on consecutive lines
    /// carry one unbroken run between them.
    private func climbCount(below start: Int, in storage: NSTextStorage) -> Int {
        var end = storage.length
        guard start < end else { return 0 }
        let below = NSRange(location: start, length: storage.length - start)
        storage.enumerateAttribute(NoteDocument.sectionHeader, in: below) { value, range, stop in
            if value != nil {
                end = min(end, range.location)
                stop.pointee = true
            }
        }
        guard start < end else { return 0 }
        let text = storage.string as NSString
        var count = 0
        var last: NSRange?
        storage.enumerateAttribute(NoteDocument.climbHeader,
                                   in: NSRange(location: start, length: end - start)) { value, range, _ in
            guard value != nil else { return }
            var location = text.lineRange(for: NSRange(location: range.location, length: 0)).location
            while location < NSMaxRange(range) {
                let line = text.lineRange(for: NSRange(location: location, length: 0))
                if last != line {
                    count += 1
                    last = line
                }
                location = NSMaxRange(line)
            }
        }
        return count
    }
}

extension NoteEditor.Coordinator: UIGestureRecognizerDelegate {
    /// Only touches on an attempt's row, on one of its note lines, or on a heading's
    /// fold target reach the recognizer — everything a component is made of is a link
    /// rather than text. Every other tap falls through to the text view untouched.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard let textView else { return false }
        let point = touch.location(in: textView)
        if attemptRow(at: point) != nil || quoteLink(at: point) != nil { return true }
        if headingChevron(at: point) != nil {
            // Warmed here, on touch-down, so the tap lands with the fold rather than
            // a beat after it.
            prepareFoldHaptic()
            return true
        }
        return false
    }
}

/// A text view whose caret stays text-sized on a climb heading's line, and which
/// keeps the caret above the keyboard itself. The SwiftUI layer opts out of keyboard
/// avoidance (`.ignoresSafeArea(.keyboard)`, for the pinned toolbar's sake), so the
/// view runs full-height under the keyboard and owns its own insets.
final class NoteTextView: UITextView {
    /// The name on the recognizer that handles taps on the note's own furniture —
    /// rows, clock tokens, fold chevrons — so the refusal below can tell it apart
    /// from the text view's built-in ones.
    static let markerTapName = "noteMarkerTap"

    /// Whether a point lands on something that is a link rather than text. Answered
    /// by the coordinator, which is the side that knows the document.
    var isLinkTap: ((CGPoint) -> Bool)?

    /// A tap on a link is not a tap into the text. The recognizer that follows the
    /// link is left alone; every other tap recognizer on this view — the ones that
    /// focus the page and drop the caret where you touched — is refused there, so
    /// opening an attempt from its row doesn't also start editing behind it.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UITapGestureRecognizer,
           gestureRecognizer.name != Self.markerTapName,
           isLinkTap?(gestureRecognizer.location(in: self)) == true {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// What the pinned header above the page covers, over and above the bars. The
    /// page runs underneath it like it runs under the status bar: the text starts
    /// below it and scrolls up beneath it.
    var headerInset: CGFloat = 0 {
        didSet {
            guard headerInset != oldValue else { return }
            applyTopInset()
        }
    }

    /// The view runs edge to edge under the status bar and the nav bar; at rest the
    /// content still starts below them, and scrolling carries it underneath. Owned
    /// here because automatic adjustment is off (it would fight the keyboard inset).
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        applyTopInset()
    }

    /// Everything covering the top of the page — the bars through the safe area, and
    /// the header on top of that. A page sitting at its top is kept there, so the
    /// header opening or shutting slides the text rather than leaving it behind.
    private func applyTopInset() {
        let wasAtTop = contentOffset.y <= -contentInset.top + 1
        contentInset.top = safeAreaInsets.top + headerInset
        verticalScrollIndicatorInsets.top = contentInset.top
        if wasAtTop { contentOffset.y = -contentInset.top }
        updateBottomInset()
    }

    /// How much of the view the keyboard currently covers, accessory bar included.
    private var keyboardOverlap: CGFloat = 0

    /// What the parked bottom bar covers when the keyboard is down — the capsule
    /// plus the home indicator.
    private var parkedBarClearance: CGFloat { safeAreaInsets.bottom + 56 }

    /// How much of the view's bottom is actually covered right now — keyboard if
    /// it's up, the parked bar if it isn't. Below this line nothing is readable.
    private var obscuredBottom: CGFloat { max(keyboardOverlap, parkedBarClearance) }

    /// The strip of the view text can actually be read in.
    private var visibleHeight: CGFloat {
        max(0, bounds.height - contentInset.top - obscuredBottom)
    }

    /// The covered strip, plus half a screen of empty scroll room under it. The
    /// room is what makes the end of a note reachable: without it the last line
    /// can only ever be dragged as far as the bottom edge, so finishing a note
    /// means typing against the keyboard. With it the user can pull the last line
    /// up to wherever they want to work — Notes leaves the same trailing gap.
    ///
    /// It lives here rather than in `textContainerInset` so it tracks the keyboard
    /// instead of stacking on top of it: a fixed container inset stranded the last
    /// line a bar's height above the keyboard with nothing left to scroll to.
    private func updateBottomInset() {
        contentInset.bottom = obscuredBottom + visibleHeight / 2
        // The indicator measures the real content, not the dead room below it.
        verticalScrollIndicatorInsets.bottom = obscuredBottom
    }

    /// The insets are sized off `bounds.height`, so a resize has to resettle them.
    private var lastLaidOutHeight: CGFloat = 0

    /// The width the document's fragments were vended against.
    private var lastLaidOutWidth: CGFloat = 0

    /// Called when the view's size settles, or changes later. Anything positioned
    /// against the laid-out text — the walkthrough's instruction line — is placed
    /// again from here, since the first placement happens before the view has a size.
    var onResize: (() -> Void)?

    /// Fragments capture the container's width when they are vended, and the document
    /// is laid out once on arrival — before the view has a size — so every right-edge
    /// decoration (chevron, attempt count, clock) was measured against nothing and
    /// drew off-screen. TextKit reuses those fragments when the real width arrives;
    /// `invalidateLayout` alone does not make it ask the delegate again — only an
    /// edit does. This is that edit, minus any actual change: the whole storage is
    /// marked attribute-edited, every fragment re-vends against the width the view
    /// now has, and the selection is untouched.
    private func revendFragments() {
        guard textStorage.length > 0 else { return }
        textStorage.beginEditing()
        textStorage.edited(.editedAttributes,
                           range: NSRange(location: 0, length: textStorage.length),
                           changeInLength: 0)
        textStorage.endEditing()
        resolveFullLayout()
    }

    /// Redraws one heading's line without changing a thing on it — the same trick
    /// `revendFragments` plays, narrowed to a single paragraph. A fragment only
    /// re-vends on an edit, so a chevron mid-spin needs one of these a frame; at one
    /// paragraph's worth of layout apiece that is cheap enough to run off a display
    /// link.
    func redrawFragment(onLineAt location: Int) {
        guard location < textStorage.length else { return }
        let line = (textStorage.string as NSString)
            .lineRange(for: NSRange(location: location, length: 0))
        textStorage.beginEditing()
        textStorage.edited(.editedAttributes, range: line, changeInLength: 0)
        textStorage.endEditing()
    }

    /// Where the page must stay while the layout underneath it is being rebuilt.
    private var heldOffset: CGPoint?

    /// Runs `body` — a restyle that invalidates the whole document's layout — and
    /// keeps the page where it was, through both the edit and the layout passes it
    /// provokes. TextKit 2 estimates the height of everything it hasn't laid out
    /// yet, so a full invalidation makes `contentSize` dip and recover over the
    /// next few frames; every dip that lands below the current scroll position
    /// makes UIScrollView clamp `contentOffset`, and that clamp is what jerked the
    /// page around while typing. Nothing here changes what the restyle computes —
    /// it only stops its churn from being visible.
    func holdingScrollPosition(_ body: () -> Void) {
        guard !isDragging, !isDecelerating else { return body() }
        let held = super.contentOffset
        heldOffset = held

        // The anchor is the character at the top of the visible strip, not the
        // numeric offset: if the relayout changes the height of anything above
        // the viewport, the same offset shows different text. What must not move
        // is the text the user is looking at.
        let anchorProbe = CGPoint(x: bounds.midX, y: held.y + safeAreaInsets.top + 1)
        let anchorIndex = closestPosition(to: anchorProbe).map { offset(from: beginningOfDocument, to: $0) }
        let anchorY = anchorIndex
            .flatMap { position(from: beginningOfDocument, offset: $0) }
            .map { caretRect(for: $0).minY }

        body()
        // Resolve the whole layout right now. After a full-document restyle
        // TextKit 2 only *estimates* the height of everything it hasn't re-laid
        // out yet, and those estimates resolving over the following frames is
        // the "document being resized" churn — each dip below the current scroll
        // position clamped the offset and jerked the page. With real geometry in
        // hand there is nothing left to drift.
        if let layout = textLayoutManager {
            layout.ensureLayout(for: layout.documentRange)
        }
        layoutIfNeeded()

        // Put the anchor character back at the exact height it was on screen.
        // Typing happens at the caret, below the anchor, so its character index
        // is untouched by the edit; any Δ found here is purely layout above the
        // viewport re-measuring — absorbed into the offset so the visible text
        // holds still.
        var target = held
        if let index = anchorIndex, let oldY = anchorY,
           let position = position(from: beginningOfDocument,
                                   offset: min(index, offset(from: beginningOfDocument, to: endOfDocument))) {
            let newY = caretRect(for: position).minY
            if abs(newY - oldY) > 0.5 { target.y += newY - oldY }
        }
        super.contentOffset = clamped(target)
        DispatchQueue.main.async { [weak self] in self?.heldOffset = nil }
    }

    /// Lay the whole document out for real on arrival, leaving no estimated
    /// heights for the first edit to collapse: that collapse was itself a
    /// content-height change, and it shifted the page by a fixed amount on the
    /// first keystroke — or backspace — after opening a note.
    func resolveFullLayout() {
        guard let layout = textLayoutManager else { return }
        layout.ensureLayout(for: layout.documentRange)
    }

    /// Clamped to what the content currently allows: if an edit genuinely made
    /// the note shorter, the held position may no longer exist, and fighting for
    /// it would leave the view stuck past its own end.
    private func clamped(_ offset: CGPoint) -> CGPoint {
        let lowest = -contentInset.top
        let highest = max(lowest, contentSize.height + contentInset.bottom - bounds.height)
        return CGPoint(x: offset.x, y: min(max(offset.y, lowest), highest))
    }

    /// The hold's teeth. The relayout's clamps arrive through this property
    /// setter — not through `setContentOffset(_:animated:)` — so while a hold is
    /// active, every offset change the user didn't make is refused outright.
    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set {
            if heldOffset != nil, !programmaticScroll, !isDragging, !isDecelerating { return }
            super.contentOffset = newValue
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var resized = false
        if bounds.width != lastLaidOutWidth {
            lastLaidOutWidth = bounds.width
            revendFragments()
            resized = true
        }
        if bounds.height != lastLaidOutHeight {
            lastLaidOutHeight = bounds.height
            updateBottomInset()
            resized = true
        }
        // Only on a size change, never on the every-frame layout a scroll brings:
        // whoever placed something against this view's text measured it at the old
        // size — the first one being zero, before the view had ever been on screen.
        if resized { onResize?() }
        guard let held = heldOffset, !isDragging, !isDecelerating else { return }
        let pinned = clamped(held)
        if super.contentOffset != pinned { super.contentOffset = pinned }
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        guard window != nil,
              let endFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }
        keyboardOverlap = max(0, bounds.maxY - convert(endFrame, from: nil).minY)
        updateBottomInset()
        guard keyboardOverlap > 0, isFirstResponder else { return }
        // After the inset lands, bring the caret back into the visible strip — this
        // is what moves the note up when a tap below the keyboard's edge focuses it.
        DispatchQueue.main.async { [weak self] in self?.keepCaretVisible() }
    }

    /// Called from exactly one place: the keyboard arriving. Typing never scrolls
    /// the page while the caret is visible, and neither does moving the caret —
    /// the note stays where the user put it. UIKit's own selection autoscroll is
    /// suppressed below, so nothing else can move it either. The one exception is
    /// `followCaretWhileTyping`, for when the caret has sunk behind the keyboard.
    ///
    /// On focus it lands the caret in the middle of the visible strip rather than
    /// just inside the edge, which leaves half a screen of room to type into
    /// before the caret would reach the keyboard.
    func keepCaretVisible() {
        guard !isAutoscrolling, let position = selectedTextRange?.end else { return }
        let caret = caretRect(for: position)
        guard caret.origin.y.isFinite, caret.height > 0 else { return }
        let visibleTop = contentOffset.y + safeAreaInsets.top
        let visibleBottom = contentOffset.y + bounds.height - obscuredBottom
        guard caret.minY >= visibleBottom || caret.maxY <= visibleTop else { return }

        let target = caret.midY - safeAreaInsets.top - visibleHeight / 2
        let lowest = -contentInset.top
        let highest = max(lowest, contentSize.height + contentInset.bottom - bounds.height)

        isAutoscrolling = true
        programmaticScroll = true
        setContentOffset(CGPoint(x: contentOffset.x, y: min(max(target, lowest), highest)),
                         animated: true)
        programmaticScroll = false
        // `contentOffset` reports mid-flight values while the animation runs, so a
        // keystroke landing inside it would read a stale position and scroll again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isAutoscrolling = false
        }
    }

    private var isAutoscrolling = false

    /// Typing's one exception to "the page stays put": when an edit leaves the
    /// caret below the readable strip — behind the toolbar and keyboard — the only
    /// way to see what is being typed is to follow it. The scroll is minimal, so
    /// the caret lands flush with the accessory container's top — whose built-in
    /// 8pt of headroom above the capsules matches the 8pt between the capsules and
    /// the keyboard, leaving equal daylight on both sides of the toolbar. From
    /// there every newline overshoots by exactly one line and the page shifts by
    /// that same line, so the caret appears to hold its height while the text
    /// slides up under it.
    func followCaretWhileTyping() {
        guard !isAutoscrolling, isFirstResponder, !isDragging, !isDecelerating,
              let position = selectedTextRange?.end else { return }
        let caret = caretRect(for: position)
        guard caret.origin.y.isFinite, caret.height > 0 else { return }

        let visibleBottom = contentOffset.y + bounds.height - obscuredBottom
        let overshoot = caret.maxY - visibleBottom
        guard overshoot > 0 else { return }

        let target = clamped(CGPoint(x: contentOffset.x, y: contentOffset.y + overshoot))
        if overshoot > caret.height * 2 {
            // The caret was fully out of view: one animated hop up to the toolbar.
            // The hold has to let go — its pin in `layoutSubviews` would fight
            // every frame of the animation.
            heldOffset = nil
            isAutoscrolling = true
            programmaticScroll = true
            setContentOffset(target, animated: true)
            programmaticScroll = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.isAutoscrolling = false
            }
        } else {
            // A single line's worth: instant, so the keystroke and the shift land
            // in the same frame and the caret never visibly moves. The hold, if
            // one is live, pins here instead of the pre-edit offset.
            super.contentOffset = target
            if heldOffset != nil { heldOffset = target }
        }
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

    /// UIKit sizes the caret to the line fragment; on a heading line the paragraph's
    /// breathing room can stretch it past the name it sits beside. Cut it back to text
    /// height, centred on the bubble. Attempt rows keep the full-height caret: they
    /// read as a block, and a tall caret suits them.
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        if let empty = emptyLastLineCaret(rect, at: position) { return empty }
        guard isOnClimbLine(position) else { return rect }

        let font = (typingAttributes[.font] as? UIFont) ?? UIFont.preferredFont(forTextStyle: .body)
        let limit = ceil(font.lineHeight * 1.15)
        guard rect.height > limit else { return rect }
        rect.origin.y += ((rect.height - limit) / 2).rounded()
        rect.size.height = limit
        return rect
    }

    /// The caret on an empty last line, placed and sized as the glyph about to land
    /// there will be.
    ///
    /// TextKit 2 never lays that line out on its own terms: it hangs off the paragraph
    /// above, and what it inherits depends on whether that paragraph has any text in
    /// it. Under a written title it takes the title's 34pt metrics; under an empty one
    /// there is nothing to take and it collapses to a default 14pt line that starts
    /// *inside* the title's own — which is why Return moved the caret down by
    /// different amounts depending on whether the title had been typed yet.
    ///
    /// So the line is measured rather than inherited, from the line above it: the top
    /// of that line, its height, the spacing it closes with, and the leading the new
    /// line opens with — the same four terms TextKit itself adds up, and the exact
    /// place the first character will land.
    private func emptyLastLineCaret(_ rect: CGRect, at position: UITextPosition) -> CGRect? {
        let text = textStorage.string as NSString
        guard text.length > 0,
              text.character(at: text.length - 1) == 0x000A,
              compare(position, to: endOfDocument) == .orderedSame,
              let font = typingAttributes[.font] as? UIFont,
              let end = self.position(from: endOfDocument, offset: -1) else { return nil }

        // One character back is the last line with anything on it. Its caret is asked
        // for rather than its layout: the answer is already in caret coordinates, and
        // the top of it is right even when the line is empty and the height is not.
        let above = super.caretRect(for: end)
        guard above.minY.isFinite else { return nil }
        let line = textStorage.attributes(at: text.length - 1, effectiveRange: nil)
        // A block's line is as tall as the block, which no font can answer for. Three
        // readings of that height, and the tallest wins: what UIKit laid the caret out
        // as, what the line's own font would make of it, and — since a caret on a line
        // that is nothing but an attachment is UIKit's business, not something this
        // relies on — what the attachment itself says it takes up.
        let lineHeight = max(above.height,
                             (line[.font] as? UIFont)?.lineHeight ?? 0,
                             attachmentHeight(onLineAt: text.length - 1))
        let closing = (line[.paragraphStyle] as? NSParagraphStyle)?.paragraphSpacing ?? 0
        let opening = typingAttributes[.paragraphStyle] as? NSParagraphStyle

        var rect = rect
        rect.origin.y = above.minY + lineHeight + closing + (opening?.lineSpacing ?? 0)
        rect.origin.x = textContainerInset.left + (opening?.firstLineHeadIndent ?? 0)
        rect.size.height = font.lineHeight
        return rect
    }

    /// How tall the block on a line draws itself, asked of the attachment rather than
    /// inferred from the line it sits on. Zero for a line of plain text.
    private func attachmentHeight(onLineAt index: Int) -> CGFloat {
        let line = (textStorage.string as NSString).lineRange(for: NSRange(location: index, length: 0))
        var height: CGFloat = 0
        textStorage.enumerateAttribute(.attachment, in: line) { value, range, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            let proposed = CGRect(x: 0, y: 0,
                                  width: textContainer.size.width,
                                  height: .greatestFiniteMagnitude)
            let bounds = attachment.attachmentBounds(for: textContainer,
                                                     proposedLineFragment: proposed,
                                                     glyphPosition: .zero,
                                                     characterIndex: range.location)
            height = max(height, bounds.height)
        }
        return height
    }

    private func isOnClimbLine(_ position: UITextPosition) -> Bool {
        let storage = textStorage
        guard storage.length > 0 else { return false }
        let index = min(offset(from: beginningOfDocument, to: position), storage.length - 1)
        let line = (storage.string as NSString).lineRange(for: NSRange(location: index, length: 0))

        var found = false
        storage.enumerateAttribute(NoteDocument.climbHeader, in: line) { value, _, stop in
            if value != nil {
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
