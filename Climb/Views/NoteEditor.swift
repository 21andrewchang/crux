import SwiftUI
import UIKit

/// Imperative handle onto the live text view, so the rest of the app can insert an
/// attempt at the cursor or refresh rows without owning the editor's state.
final class NoteEditorController {
    fileprivate weak var coordinator: NoteEditor.Coordinator?

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
}

/// The note itself: a plain `UITextView` you can just type in, with attempts embedded
/// as text attachments.
struct NoteEditor: UIViewRepresentable {
    let session: ClimbSession
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
        // Top clears the date line above the title. The bottom is just breathing
        // room under the last line: clearance for the pinned bar and the keyboard
        // lives in `contentInset`, so the two never stack.
        textView.textContainerInset = UIEdgeInsets(top: 32, left: 16, bottom: 24, right: 16)
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
        textView.onResize = { [weak coordinator = context.coordinator] in
            coordinator?.placeHint(force: true)
        }
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

        init(parent: NoteEditor) {
            self.parent = parent
        }

        // MARK: Document

        func reloadDocument() {
            guard let textView else { return }
            let selected = textView.selectedRange
            let document = NoteDocument.attributedString(for: parent.session,
                                                         climbName: { [weak self] id in
                                                             self?.parent.legacyClimbName(id)
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
            // what gets typed there is part of that attempt's notes. Inside a bubble,
            // it carries the heading's style, so the name grows in place.
            if let id = quoteID(onLineAt: textView.selectedRange.location) {
                textView.typingAttributes = NoteDocument.quoteAttributes(for: id)
            } else if let line = headingLine(onLineAt: textView.selectedRange.location) {
                textView.typingAttributes = NoteDocument.headerAttributes(tint: headingTint(of: line))
            } else if sectionLine(onLineAt: textView.selectedRange.location) != nil {
                textView.typingAttributes = NoteDocument.sectionHeaderAttributes
            } else if isGrouped(at: textView.selectedRange.location) {
                textView.typingAttributes = NoteDocument.groupedBodyAttributes
            } else {
                textView.typingAttributes = NoteDocument.bodyAttributes
            }
        }

        /// Whether the line at `location` is inside a group — anywhere below a climb or
        /// section heading, where body text indents to line up under it. The caret has
        /// to know before the character lands: the restyle would move the line a moment
        /// later, and the cursor would jump out from under what was just typed.
        private func isGrouped(at location: Int) -> Bool {
            guard let storage = textView?.textStorage, storage.length > 0 else { return false }
            let line = (storage.string as NSString)
                .lineRange(for: NSRange(location: min(location, storage.length), length: 0))
            guard line.location > 0 else { return false }
            let above = NSRange(location: 0, length: line.location)
            var found = false
            for key in [NoteDocument.climbHeader, NoteDocument.sectionHeader] where !found {
                storage.enumerateAttribute(key, in: above) { value, _, stop in
                    if value != nil {
                        found = true
                        stop.pointee = true
                    }
                }
            }
            return found
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
        ///
        /// Two of them — the title's, and the hints that sit under it. The title's is
        /// gone the moment anything at all is in the document; the hints stay until
        /// something is written *under* the title, so a named-but-empty note still
        /// says what its buttons do.
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
            let title = add(NoteDocument.placeholderText).label
            title.topAnchor.constraint(equalTo: textView.contentLayoutGuide.topAnchor,
                                       constant: inset.top).isActive = true
            placeholderLabel = title

            // The hints hang off the title line, whose height is measured from the
            // title alone — so they follow a title that wraps, and nothing else moves
            // them: lines one through three of the body, always. The walkthrough moves
            // both of these constants instead, to sit on the caret's own line.
            let hints = add(NoteDocument.hintText)
            let top = hints.label.topAnchor.constraint(equalTo: textView.contentLayoutGuide.topAnchor)
            top.isActive = true
            hintLabel = hints.label
            hintTop = top
            hintLeading = hints.leading
        }

        private func updatePlaceholder() {
            guard let textView else { return }
            placeholderLabel?.isHidden = textView.textStorage.length > 0

            updateGuide()
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
            if shownStep != nil {
                shownStep = nil
                hintLabel?.attributedText = NoteDocument.hintText
                hintLeading?.constant = textView.textContainerInset.left
            }
            hintLabel?.isHidden = !isUnwritten
            hintTop?.constant = textView.textContainerInset.top + titleLineHeight
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
            let text = storage.string as NSString
            let titleLine = storage.length > 0
                ? text.lineRange(for: NSRange(location: 0, length: 0))
                : NSRange(location: 0, length: 0)

            // The line under the last thing written — or under the empty line the note
            // ends on, if it has one. The instruction is never the line the caret is
            // on: opening a line steps it down and the instruction moves with it, so
            // what gets typed there always lands above the instruction, never over it.
            let target = hintTarget()

            // Nothing under the title yet — an empty note included, where the first
            // instruction is the title's own. Measured off the title the way the note's
            // own hints are, and never off the layout: an empty line under the title
            // takes its font from whatever the caret is currently typing in, so its
            // laid-out top moves as the caret crosses into it. The title's text and the
            // width it wraps in are the only things that can move this.
            guard target.location > titleLine.location else {
                return CGPoint(x: inset.left, y: inset.top + titleLineHeight)
            }

            // Under the target: the bottom of the target's own laid-out line, plus the
            // trailing spacing its paragraph puts between itself and whatever comes
            // next — which is where the next line of text starts. An opened line at the
            // very end of the note has no characters to measure, so there the caret
            // standing on it is the measure.
            let bottom = nextLineTop(under: target) ?? titleLineHeight

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
            guard parent.guide.tracksNote, let storage = textView?.textStorage else { return }
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

            let title = text.substring(with: text.lineRange(for: NSRange(location: 0, length: 0)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            parent.guide.update(hasTitle: title.caseInsensitiveCompare(NoteDocument.workoutName) == .orderedSame,
                                section: heading(NoteDocument.sectionHeader,
                                                 named: NoteDocument.sectionPlaceholder),
                                climb: heading(NoteDocument.climbHeader,
                                               named: NoteDocument.climbPlaceholder),
                                hasAttempt: hasAttempt)
        }

        /// Nothing written under the title line — the note has a name at most. Empty
        /// lines are not writing: pressing return off the title puts the caret on the
        /// hints the way it sat on the title's own placeholder, and they stay until
        /// there is something to read there. An attachment counts as written: its
        /// marker is not whitespace.
        private var isUnwritten: Bool {
            guard let storage = textView?.textStorage else { return true }
            let text = storage.string as NSString
            let title = text.lineRange(for: NSRange(location: 0, length: 0))
            guard NSMaxRange(title) < text.length else { return true }
            return text.substring(from: NSMaxRange(title))
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// How tall the title line came out, its trailing paragraph spacing included —
        /// the hints hang off the bottom of it.
        ///
        /// Measured from the title's own text and the width it has to wrap in, never
        /// from the laid-out document: a fragment's height moves with what follows it
        /// (a trailing empty paragraph lands in the same fragment, paragraph spacing
        /// comes and goes with whether the title is the last paragraph), and the hints
        /// would then shuffle down a line every time someone pressed return. Nothing
        /// below the title can change this number; only the title wrapping can.
        private var titleLineHeight: CGFloat {
            let font = NoteDocument.titleAttributes[.font] as? UIFont ?? .preferredFont(forTextStyle: .largeTitle)
            let spacing = (NoteDocument.titleAttributes[.paragraphStyle] as? NSParagraphStyle)?.paragraphSpacing ?? 0
            var lines: CGFloat = 1
            if let textView {
                let container = textView.textContainer
                let width = container.size.width - container.lineFragmentPadding * 2
                let text = textView.textStorage.string as NSString
                let title = text.substring(with: text.lineRange(for: NSRange(location: 0, length: 0)))
                    .trimmingCharacters(in: .newlines)
                if !title.isEmpty, width > 0 {
                    let bounds = (title as NSString).boundingRect(
                        with: CGSize(width: width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: font],
                        context: nil
                    )
                    lines = max(1, (bounds.height / font.lineHeight).rounded())
                }
            }
            return ceil(font.lineHeight * lines) + spacing
        }

        /// Only attempts live behind markers now; anything else is dropped (or, for an
        /// old stored climb, turned back into text by the document builder).
        private func makeAttachment(for id: UUID) -> NSTextAttachment? {
            guard parent.session.attempt(with: id) != nil else { return nil }
            return makeAttemptAttachment(for: id)
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

        /// Where the group the caret sits in ends: the first line past everything the
        /// heading above it collapses when folded. A new heading lands there rather than
        /// at the caret, so pressing the button from the middle of a climb opens the next
        /// climb *after* it instead of splitting its attempts across the two.
        ///
        /// Climbs nest under sections, so only a climb group stops a climb heading — from
        /// inside a section, one more climb belongs right where the caret is. A section is
        /// stopped by the section it is in, or, failing that, by the climb.
        private func endOfGroup(containing location: Int, for kind: NSAttributedString.Key) -> Int {
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
            if kind == NoteDocument.climbHeader, above.isSection { return location }

            let closesSection = kind == NoteDocument.sectionHeader && above.isSection
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

        private func insertHeadingLine(_ header: [NSAttributedString.Key: Any],
                                       kind: NSAttributedString.Key) {
            guard let textView else { return }
            let storage = textView.textStorage
            var location = endOfQuote(at: min(textView.selectedRange.location, storage.length))
            let string = storage.string as NSString

            // The title line never becomes a heading: from anywhere on it, the heading
            // goes below.
            if string.length > 0 {
                let titleLine = string.lineRange(for: NSRange(location: 0, length: 0))
                if location < NSMaxRange(titleLine) { location = NSMaxRange(titleLine) }
            }

            // The caret is already in an empty one of these: that is the heading this
            // press is asking for, so it takes the caret instead of a second, just as
            // invisible, heading landing under it.
            if let empty = unnamedHeadingLine(ofKind: kind, at: location) {
                reuseUnnamedHeading(empty)
                return
            }

            // Nor does a heading's own line: from inside a section's name, a bubble
            // lands on the line below it whole. Breaking the name where the caret
            // happens to be would split it in two and hand the tail the section's own
            // styling along with the bubble's.
            if let heading = headingLine(onLineAt: location) ?? sectionLine(onLineAt: location) {
                location = NSMaxRange(heading)
            }

            // A heading never lands inside a group: it goes below everything the one
            // above it owns, so the climb the caret was in keeps all of its attempts.
            location = max(location, endOfGroup(containing: location, for: kind))

            // Same again for where it would land: pressing the button from somewhere
            // else in the note still finds the empty heading already waiting there.
            if let empty = unnamedHeadingLine(ofKind: kind, at: location) {
                reuseUnnamedHeading(empty)
                return
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

            if storage.length == 0 || location == 0 {
                // An empty document: the first line stays the title, the bubble opens
                // the line under it.
                let piece = NSMutableAttributedString(string: "\n", attributes: NoteDocument.bodyAttributes)
                piece.append(blank)
                performBlockEdit { $0.replaceCharacters(in: NSRange(location: 0, length: 0), with: piece) }
                caret = 1
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
            guard let textView else { return }
            let point = gesture.location(in: textView)
            if let heading = headingChevron(at: point) {
                toggleFold(ofHeadingLine: heading)
                return
            }
            guard let hit = timestamp(at: point) else { return }
            parent.onSeekAttempt(hit.id, hit.seconds)
        }

        // MARK: Folding

        /// The heading line whose fold chevron the point is on: the trailing lane of
        /// a climb or section heading's line, with slop to make a 12pt glyph a
        /// finger-sized target.
        fileprivate func headingChevron(at point: CGPoint) -> NSRange? {
            guard let textView, point.x > textView.bounds.width - 56,
                  let position = textView.closestPosition(to: point) else { return nil }
            let caret = textView.caretRect(for: position)
            guard caret.height > 0, abs(point.y - caret.midY) < max(caret.height, 24) else { return nil }

            let storage = textView.textStorage
            guard storage.length > 0 else { return nil }
            let offset = min(textView.offset(from: textView.beginningOfDocument, to: position),
                             storage.length - 1)
            return headingLine(onLineAt: offset) ?? sectionLine(onLineAt: offset)
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

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange(true)
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
            return fragment
        }

        guard let seconds = storage.attribute(NoteDocument.noteTimestamp, at: start,
                                              effectiveRange: nil) as? TimeInterval
        else { return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange) }

        let fragment = BookmarkLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.clock = NoteTimestamp.display(for: seconds)
        fragment.containerWidth = textView.textContainer.size.width
        return fragment
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
}

extension NoteEditor.Coordinator: UIGestureRecognizerDelegate {
    /// Only touches on a clock token or a heading's fold chevron reach the recognizer,
    /// so every other tap falls through to the text view untouched.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard let textView else { return false }
        let point = touch.location(in: textView)
        if headingChevron(at: point) != nil {
            // Warmed here, on touch-down, so the tap lands with the fold rather than
            // a beat after it.
            prepareFoldHaptic()
            return true
        }
        return timestamp(at: point) != nil
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
        max(0, bounds.height - safeAreaInsets.top - obscuredBottom)
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
