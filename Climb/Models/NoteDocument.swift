import UIKit

/// Converts between the stored `(bodyText, attachmentIDs)` pair and the
/// `NSAttributedString` the editor works with.
/// An attachment that stands for one entry in `attachmentIDs`. Both the attempt rows
/// and the climb headings are markers, and serialization only has to know that much.
protocol MarkerAttachment: AnyObject {
    var markerID: UUID { get }
    /// Whether the line under this marker is the thing's notes. True for attempts.
    var takesNotes: Bool { get }
}

enum NoteDocument {
    static let attachmentMarker = "\u{FFFC}"

    /// Marks a line as a climb heading — the coloured bubble the attempts below it are
    /// filed under. An attribute on the line's characters, like `noteQuote`: UIKit
    /// carries it through typing and undo, and `applyStyles` keeps it line-shaped.
    static let climbHeader = NSAttributedString.Key("climbHeader")

    /// Prefixes a heading's line in the stored `bodyText` — the heading is nothing but
    /// text, so this sentinel is all that survives a round trip.
    static let headingMarker = "\u{FFF9}"

    /// Marks a line as a section heading — a plain subheader the lines below it group
    /// under. A climb heading is the special, tinted kind of section: the two are
    /// peers, never nested, and either one ends the group above it.
    static let sectionHeader = NSAttributedString.Key("climbSectionHeader")

    /// Prefixes a section heading's line in `bodyText`, the way `headingMarker`
    /// does a climb heading's.
    static let sectionMarker = "\u{FFFA}"

    /// What an empty heading at the very end of a note holds instead of a line break
    /// of its own: one space, which gives the line something to carry its heading
    /// attribute on and reads as nothing.
    ///
    /// A heading's style lives on its characters, so an empty heading line needs at
    /// least one. The obvious candidate — its own break — would leave the document
    /// ending in a newline, and a document ending in a newline shows one more empty
    /// line under it that the caret can be put on: a line nobody asked for. This is
    /// what lets a note end at the heading someone just added.
    ///
    /// A space rather than a zero-width character on purpose: U+200B is a *format*
    /// character, and the keyboard's own machinery — autocorrect ranges, word
    /// boundaries, caret movement — does not treat one as ordinary text. A trailing
    /// space is the most ordinary thing in a text field there is. It rides along at
    /// the end of the name from then on, which is why every read of a heading's name
    /// goes through `headingName`.
    static let headingFiller = " "

    /// A heading's name as it reads: the line's text with its break, its surrounding
    /// space, and any filler taken off.
    static func headingName(_ line: String) -> String {
        // The zero-width kind is gone from new notes but may sit in one already saved.
        line.replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Marks a heading's line as folded: everything under it, down to the next
    /// heading of either kind, is styled away to nothing. An attribute on the line's
    /// characters so it rides through editing like `noteQuote` does — but display
    /// only, never serialized, so a reopened note starts unfolded.
    static let foldedHeading = NSAttributedString.Key("climbFoldedHeading")

    /// A climb heading sits under the attempts it heads in size — 21 bold section,
    /// 16 semibold attempt, 15 semibold climb. A climb is a name in the note, not a
    /// banner, and its colour and dot do the telling-apart, not its size.
    static let headerFont = UIFont.systemFont(ofSize: 15, weight: .semibold)

    /// Trailing room held open on a climb heading's line for the attempt count drawn
    /// between the name and the fold chevron.
    static let countReserve: CGFloat = 72

    /// The room a heading keeps under itself, before the first line of what it heads:
    /// a body line's own, opened up a little so that line reads as filed under the
    /// heading rather than run on from it. Both kinds of heading keep the same one, so
    /// the note has a single rhythm — and so does the walkthrough's instruction, which
    /// lands exactly where that first line would.
    static let headingSpacing: CGFloat = 8

    /// What a climb heading keeps under itself instead. What it heads is a card, not a
    /// line of text, and a card brings `blockLead` of its own air with it — the two
    /// stacked left the first attempt sitting well clear of the name it is filed
    /// under. A section keeps the full room, because what it heads is a heading.
    ///
    /// Held against `blockLead` rather than set on its own: the two are the gap under
    /// a climb heading, and moving one without the other moves that gap.
    static let climbHeadingTrail: CGFloat = 7

    /// Air under everything a climb heads, before the next climb starts. Hung on the
    /// last line of the group rather than above the heading below it, because that is
    /// the thing the gap is made of: a climb with its attempts open ends well clear of
    /// the next name, and a folded one — whose last line collapses to a hairline along
    /// with the rest of its group — sits directly under the one above it, so a note of
    /// collapsed climbs reads as a list instead of a column of gaps.
    ///
    /// A climb heading with nothing under it yet has no last line to hang it on and
    /// keeps the room above itself instead, so two headings never sit flush.
    static let climbGroupTrail: CGFloat = 14

    /// Air above a section heading — the same idea as `climbGroupTrail` and a good
    /// deal more of it. A section is the largest break the note has, and the climbs
    /// filed under the one before it run right up to where the next one starts; the
    /// gap is what says the list has ended rather than carried on.
    static let sectionHeadingLead: CGFloat = 30

    /// A step off full strength: the name is a label on the stretch of note under it,
    /// and at full colour it shouted over the attempts it heads. The dot before it is
    /// drawn at the same strength, so mark and name read as one thing.
    static let headerTintAlpha: CGFloat = 0.7

    /// The name reads in the climb's colour, with a dot of that colour drawn before it
    /// by the layout fragment. The line holds a lane open for the dot the same way a
    /// stamped note line holds one for its bookmark.
    static func headerAttributes(tint: UIColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = climbHeadingTrail
        paragraph.firstLineHeadIndent = textIndent + ClimbHeaderLayoutFragment.dotGutter
        paragraph.headIndent = textIndent + ClimbHeaderLayoutFragment.dotGutter
        // Stops short of the trailing edge, where the attempt count and the fold
        // chevron live.
        paragraph.tailIndent = -(textIndent + chevronReserve + countReserve)
        return [
            .font: headerFont,
            .foregroundColor: tint.withAlphaComponent(headerTintAlpha),
            .paragraphStyle: paragraph,
            climbHeader: true,
        ]
    }

    /// Ties a run of text to the attempt whose notes it is.
    ///
    /// It is an attribute on the characters, not a rule about which line sits where:
    /// UIKit carries attributes along as text is typed, split, joined and undone, so the
    /// binding survives editing on its own. Position only ever *adds* a binding — a bare
    /// line under a row is adopted as its notes — and nothing takes one away.
    static let noteQuote = NSAttributedString.Key("climbNoteQuote")

    /// The note's own left edge: none. Headings, rows, clips and prose all hang off
    /// the page margin the text view holds, the way the title does — the step in
    /// existed to clear a climb's pill and an attempt's card, and both are gone.
    static let textIndent: CGFloat = 0

    /// Body text in every way but colour — the notes sit in the note like anything
    /// else you typed, just quieter, tucked under their row.
    /// The shape of a note's line. The last one of a row's notes takes a copy with a
    /// deeper trailing space — see `quoteEndSpacing`.
    ///
    /// Indented by the card's own padding rather than the page's: these lines are
    /// inside the box the row started, and have to clear its edges the way the row's
    /// name does.
    static let quoteParagraph: NSParagraphStyle = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        // A step more than body text, so the quote reads as a block that ends before
        // whatever comes next rather than running into it.
        paragraph.paragraphSpacing = 8
        paragraph.firstLineHeadIndent = AttemptRowView.cardPadding
        paragraph.headIndent = AttemptRowView.cardPadding
        paragraph.tailIndent = -AttemptRowView.cardPadding
        return paragraph
    }()

    /// The bottom of the note's ladder: what is written under a row is a note on that
    /// go, read after the name above it, so it is set smaller as well as quieter — and
    /// far enough under the 16 of that name to be told from it at a glance.
    static let quoteFont = UIFont.preferredFont(forTextStyle: .footnote)

    static func quoteAttributes(for id: UUID) -> [NSAttributedString.Key: Any] {
        let paragraph = quoteParagraph

        var attributes = bodyAttributes
        attributes[.font] = quoteFont
        // A step back from the label white the rest of the note is written in — enough
        // that the row's name reads as the head of the block and the notes as what is
        // filed under it, and still well clear of the grey the clock steps back to.
        attributes[.foregroundColor] = UIColor(white: 0.75, alpha: 1)
        attributes[.paragraphStyle] = paragraph
        attributes[noteQuote] = id
        return attributes
    }

    /// Set on the last note line under a row, so the card drawn behind the notes
    /// knows where to close off instead of running into whatever follows.
    static let noteQuoteEnd = NSAttributedString.Key("climbNoteQuoteEnd")

    /// The clock a note line opens with, as seconds — carried on the token's own
    /// characters so a tap can read the moment straight off the text under it.
    static let noteTimestamp = NSAttributedString.Key("climbNoteTimestamp")

    /// The clock steps back to grey — the note's words carry the line; the bookmark
    /// beside it is what marks the link.
    static func timestampAttributes(seconds: TimeInterval) -> [NSAttributedString.Key: Any] {
        [
            .font: quoteFont,
            .foregroundColor: UIColor.secondaryLabel,
            noteTimestamp: seconds,
        ]
    }

    /// Room for the bookmark drawn in the gutter before the clock. Measured off the
    /// mark itself rather than guessed: it stands on the same left edge as the row's
    /// name above it, and the words start a clear step past its right edge, so the
    /// mark reads as a label on the clip and not as its first letter.
    static let bookmarkGutter: CGFloat = BookmarkLayoutFragment.iconLead
        + BookmarkLayoutFragment.iconSize.width + 9

    /// Trailing room held open on a stamped line for the clock drawn at its right edge.
    static let clockReserve: CGFloat = 52

    /// A stamped line sits one gutter past the text indent, leaving the bookmark its
    /// lane before the words — and stops short on the right, where the clock lives.
    ///
    /// One line, always, however much was written into the clip: a row's clips are a
    /// list of links to skim, and a wordy one wrapping to four lines buries the rest of
    /// them. The whole note is a tap away, in the clip it belongs to.
    private static let stampedParagraph: NSParagraphStyle = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 8
        paragraph.firstLineHeadIndent = AttemptRowView.cardPadding + bookmarkGutter
        paragraph.headIndent = AttemptRowView.cardPadding + bookmarkGutter
        paragraph.tailIndent = -(AttemptRowView.cardPadding + clockReserve)
        paragraph.lineBreakMode = .byTruncatingTail
        return paragraph
    }()

    /// Walks a quote's lines: one opening with a clock gets the token tinted and
    /// tagged with its seconds — what makes it tappable.
    private static func styleQuoteLines(in storage: NSMutableAttributedString, range: NSRange, id: UUID) {
        let text = storage.string as NSString
        var location = range.location
        while location < NSMaxRange(range) {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            let lineInQuote = NSIntersectionRange(line, range)
            defer { location = NSMaxRange(line) }
            guard lineInQuote.length > 0 else { continue }

            if let match = NoteTimestamp.regex.firstMatch(in: storage.string, options: [], range: lineInQuote),
               match.range.location == lineInQuote.location {
                let seconds = NoteTimestamp.seconds(from: text.substring(with: match.range))
                storage.addAttributes(timestampAttributes(seconds: seconds), range: match.range)
                storage.addAttributes([.paragraphStyle: stampedParagraph], range: lineInQuote)
                // The token stays in the text — it is the note's identity and what
                // makes the seek frame-exact — but takes no space in the line: the
                // clock the reader sees is drawn at the line's trailing edge by the
                // layout fragment. The space after the token hides with it, so the
                // words sit flush against the bookmark's gutter.
                var hidden = match.range
                if NSMaxRange(hidden) < NSMaxRange(line),
                   text.character(at: NSMaxRange(hidden)) == 0x0020 {
                    hidden.length += 1
                }
                storage.addAttributes([.font: UIFont.systemFont(ofSize: 0.1),
                                       .foregroundColor: UIColor.clear], range: hidden)
            }
        }
    }

    // MARK: Typography
    //
    // Every page of the note is body text — the title is not in any of them, it sits
    // in the header above the tabs. There is no formatting UI yet, so these are
    // applied wholesale on every edit rather than tracked as user intent.

    /// The session's name, as drawn in the header. Nothing in the document carries
    /// these any more; the title field and its placeholder do.
    static var titleAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 6
        return [
            .font: UIFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph,
        ]
    }

    /// Trailing room held open on a heading's line for the fold chevron: at the right
    /// edge on a climb, a step past the name on a section — either way the name wraps
    /// this much early so the chevron always has somewhere to stand.
    static let chevronReserve: CGFloat = 28

    /// The top rung of the note's three, and the widest step: a section, the climbs
    /// under it and the attempts under those have to be told apart at a glance, from
    /// scrolling speed, without reading a word of them.
    static let sectionFont = UIFont.systemFont(ofSize: 21, weight: .bold)

    /// A section heading: bigger and heavier than body, well short of the title —
    /// a subheader. The text on the line *is* the section's name.
    static var sectionHeaderAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        // Set apart from what came before it, and spaced like every heading under it
        // below. `applyStyles` takes the room above back off a section that opens the
        // note, which has nothing up there to stand clear of.
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacingBefore = sectionHeadingLead
        paragraph.paragraphSpacing = headingSpacing
        // Flush left, like the title: the subheader hangs at the margin while the
        // body text under it keeps its indent.
        paragraph.tailIndent = -(textIndent + chevronReserve)
        return [
            .font: sectionFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph,
            sectionHeader: true,
        ]
    }

    /// What an unnamed heading shows in its own place: not "Section name" but a name
    /// someone would actually give one, so the example teaches the habit as well as
    /// the field. The climb's doubles as a hint that the colour in a name is what
    /// tints its bubble.
    ///
    /// These are the walkthrough's own words too — it asks for these exact names, and
    /// waits until it has them — so the example a heading shows and the name being
    /// asked for are always the same string.
    static let workoutName = "Project Day"
    static let sectionPlaceholder = "Warmup"
    static let climbPlaceholder = "Blue V4"

    /// What an empty heading says on any other note: the thing it is, not an example
    /// of one. The examples are the walkthrough's — it asks for those exact names.
    static let newSectionPlaceholder = "New Section"
    static let newClimbPlaceholder = "New Climb"

    /// Whether the walkthrough is running, and headings should therefore show the
    /// names it asks for. Headings draw themselves from a text-layout fragment, which
    /// has no view to ask — and only one note is ever on screen, so the note sets this
    /// as the walkthrough starts and ends. See `NoteEditor.updatePlaceholder`.
    static var showsTutorialExamples = false

    /// The example an empty section heading shows.
    static var sectionExample: String {
        showsTutorialExamples ? sectionPlaceholder : newSectionPlaceholder
    }

    /// The example an empty climb bubble shows.
    static var climbExample: String {
        showsTutorialExamples ? climbPlaceholder : newClimbPlaceholder
    }

    /// Text you type into the note, wherever it sits: always flush with the title, at
    /// the page's own margin. Being filed under a climb or a section buys a line
    /// nothing — the headings step in, the prose under them does not, so the whole
    /// note reads down one left edge.
    static var bodyAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 2
        return [
            .font: UIFont.preferredFont(forTextStyle: .body),
            // A step back from pure white: the headings, the bubbles and the counts
            // are what the eye should catch first, and prose written in full label
            // white competes with them.
            .foregroundColor: UIColor(white: 0.88, alpha: 1),
            .paragraphStyle: paragraph,
        ]
    }

    /// What an empty title says outside the walkthrough: the field, not an example.
    /// The walkthrough is the one place that asks for a particular name, and there the
    /// placeholder is that name — see `SessionDetailView.titleField`.
    static let titlePlaceholder = "Workout Name"

    /// The bar, a button at a time, each named by the mark that is actually on it —
    /// in the order the walkthrough asks for them, which is also the order they sit
    /// in the bar. `TutorialGuide.Step` indexes straight into this.
    static let hints: [(symbol: String, tail: String)] = [
        ("textformat.size", "to add a section"),
        ("plus", "to add a climb"),
        ("video.fill", "to start an attempt"),
    ]

    /// Where the walkthrough starts: the note itself, before any of the bar. Nothing
    /// to press for this one — the caret is already sitting in the title.
    ///
    /// It asks for a name rather than for *a* name: one thing to do, no decision to
    /// make in the middle of being shown how the app works, and the walkthrough knows
    /// exactly when it has been done.
    static let titlePrompt = "Name the workout “\(workoutName)”"

    /// What the walkthrough asks once the button has been pressed and the heading is
    /// sitting there empty: the ask is no longer the button. Indexed like `hints`.
    static let namePrompts = ["Name the section “\(sectionPlaceholder)”",
                              "Name the climb “\(climbPlaceholder)”"]

    /// The last step, and the only one whose button has already done something before
    /// it is pressed: recording an attempt starts the rest countdown by itself. One
    /// line, like every other step — the countdown is already running where it can be
    /// seen, so all that is left to say is what the tap on it is for. Named by the mark
    /// on the capsule rather than by the word, the way every other button is.
    static let restHint = (symbol: "timer", tail: "to adjust rest")

    /// Set like every other line the walkthrough shows.
    static var restText: NSAttributedString {
        hintText([restHint])
    }

    /// What an empty page says behind its first line: the tab's own job, set in the
    /// hand the page is written in and in the colour a placeholder is. A label behind
    /// the document, never characters in it — see `attachPlaceholder`.
    static func pagePlaceholderText(_ text: String) -> NSAttributedString {
        promptText(text)
    }

    /// One of those, set like a hint line: same margin, same quiet colour.
    static func promptText(_ prompt: String) -> NSAttributedString {
        var attributes = bodyAttributes
        attributes[.foregroundColor] = UIColor.placeholderText
        return NSAttributedString(string: prompt, attributes: attributes)
    }

    /// What an unwritten note says under its title: all three, since nothing about it
    /// says which one to press first. Placeholder text like the title above it — a
    /// label behind the document, never characters in it, so it cannot be typed over,
    /// serialized, or left behind in a note someone has since written.
    static var hintText: NSAttributedString { hintText(hints) }

    /// The same lines, chosen: the walkthrough shows one at a time.
    static func hintText(_ hints: [(symbol: String, tail: String)]) -> NSAttributedString {
        // Body text in the margin the body actually starts at, so the caret that lands
        // on a hint line sits at the head of it rather than a step in.
        var attributes = bodyAttributes
        attributes[.foregroundColor] = UIColor.placeholderText

        let text = NSMutableAttributedString()
        for (symbol, tail) in hints {
            if text.length > 0 { text.append(NSAttributedString(string: "\n", attributes: attributes)) }
            text.append(NSAttributedString(string: "Press ", attributes: attributes))
            text.append(glyph(symbol))
            text.append(NSAttributedString(string: " \(tail)", attributes: attributes))
        }
        // Over the glyph runs too: an attachment brings no paragraph style of its own,
        // and a line missing it would hang at a different indent from the others.
        text.addAttributes(attributes, range: NSRange(location: 0, length: text.length))
        return text
    }

    /// A toolbar button's mark, set in a line of words at the size the words are and
    /// seated on their baseline — so it reads in the sentence rather than riding above
    /// or below it. The names are the toolbar's own: what `EditingToolbar` draws.
    private static func glyph(_ name: String) -> NSAttributedString {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let configuration = UIImage.SymbolConfiguration(font: font)
        guard let image = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(.placeholderText, renderingMode: .alwaysOriginal)
        else { return NSAttributedString() }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0,
                                   y: (font.capHeight - image.size.height) / 2,
                                   width: image.size.width,
                                   height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    /// Rebuilds the editable document, substituting a live attachment at each marker.
    ///
    /// A marker whose ID no longer resolves is dropped along with its ID, so the two
    /// never drift out of alignment. A marker that `climbName` resolves instead is a
    /// legacy stored-climb heading: its name comes in as an inline heading line, and
    /// the ID is gone on the next save.
    static func attributedString(for session: ClimbSession,
                                 tab: NoteTab = .main,
                                 climbName: (UUID) -> String? = { _ in nil },
                                 makeCheckIn: () -> CheckInAttachment? = { nil },
                                 makeAttachment: (UUID) -> NSTextAttachment?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var idIndex = 0
        var headingStarts: [Int] = []
        var sectionStarts: [Int] = []
        let ids = session.attachmentIDs(for: tab)

        for character in session.text(for: tab) {
            if String(character) == attachmentMarker {
                guard idIndex < ids.count else { continue }
                let id = ids[idIndex]
                idIndex += 1
                if let attachment = makeAttachment(id) {
                    result.append(NSAttributedString(attachment: attachment))
                } else if let name = climbName(id) {
                    headingStarts.append(result.length)
                    result.append(NSAttributedString(string: name))
                }
            } else if String(character) == headingMarker {
                headingStarts.append(result.length)
            } else if String(character) == sectionMarker {
                sectionStarts.append(result.length)
            } else {
                result.append(NSAttributedString(string: String(character)))
            }
        }

        let text = result.string as NSString
        for start in headingStarts where start < result.length {
            let line = text.lineRange(for: NSRange(location: start, length: 0))
            if line.length > 0 {
                result.addAttribute(climbHeader, value: true, range: line)
            }
        }
        for start in sectionStarts where start < result.length {
            let line = text.lineRange(for: NSRange(location: start, length: 0))
            if line.length > 0 {
                result.addAttribute(sectionHeader, value: true, range: line)
            }
        }

        restoreNotes(in: result) { session.attempt(with: $0)?.notes ?? "" }
        if let card = makeCheckIn() { insertCheckIn(card, into: result) }
        applyStyles(to: result)
        return result
    }

    /// `bodyText` is plain text, so the bindings are gone by the time a note is reopened.
    /// This puts them back once, on the way in: the line under a row is that attempt's
    /// notes if it matches what the attempt has, and is written in if it is missing.
    private static func restoreNotes(in storage: NSMutableAttributedString, notes: (UUID) -> String) {
        var markers: [(line: NSRange, id: UUID)] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let marker = value as? MarkerAttachment, marker.takesNotes else { return }
            markers.append(((storage.string as NSString).lineRange(for: range), marker.markerID))
        }

        // Back to front: inserting a line shifts everything after it.
        for marker in markers.reversed() {
            let written = notes(marker.id).trimmingCharacters(in: .newlines)
            let text = storage.string as NSString
            let start = NSMaxRange(marker.line)

            // Notes can run to several lines, so bind what is actually there rather than
            // the first line of it — otherwise every line but the first comes back as
            // ordinary text and is then lost from the attempt.
            if !written.isEmpty, start <= text.length,
               text.substring(from: start).hasPrefix(written) {
                var length = (written as NSString).length
                if start + length < text.length, text.character(at: start + length) == 0x000A {
                    length += 1
                }
                storage.addAttribute(noteQuote, value: marker.id, range: NSRange(location: start, length: length))
                continue
            }

            let quote = quoteLine(after: marker.line, in: storage)
            let existing = quote.map { text.substring(with: $0) }?.trimmingCharacters(in: .newlines)

            if let quote, let existing, !existing.isEmpty {
                // Something else is written under the row — bind that, since it is what
                // the note reads as, and the attempt catches up on the next edit.
                storage.addAttribute(noteQuote, value: marker.id, range: quote)
            } else if !written.isEmpty {
                let insertAt = quote?.location ?? start
                let inserted = quote == nil ? written + "\n" : written
                storage.replaceCharacters(in: NSRange(location: insertAt, length: 0),
                                          with: NSAttributedString(string: inserted,
                                                                   attributes: quoteAttributes(for: marker.id)))
            }
            // Nothing written and nothing under the row: no binding, no quote. The
            // empty line stays plain, and typing there is adopted as the attempt's
            // notes by `applyStyles` on the first keystroke.
        }
    }

    /// The line after a row — unless that line is another row or a climb heading, in
    /// which case there is nowhere for the notes to sit.
    static func quoteLine(after line: NSRange, in storage: NSAttributedString) -> NSRange? {
        let start = NSMaxRange(line)
        guard start < storage.length else { return nil }
        let quote = (storage.string as NSString).lineRange(for: NSRange(location: start, length: 0))

        var isBlock = false
        storage.enumerateAttribute(.attachment, in: quote) { value, _, stop in
            if value is MarkerAttachment {
                isBlock = true
                stop.pointee = true
            }
        }
        for key in [climbHeader, sectionHeader] {
            storage.enumerateAttribute(key, in: quote) { value, _, stop in
                if value != nil {
                    isBlock = true
                    stop.pointee = true
                }
            }
        }
        return isBlock ? nil : quote
    }

    /// Opens the check-in page with the card, on a line of its own above whatever is
    /// written under it.
    ///
    /// The card is never in the stored text. It is not something anyone typed — it is
    /// something every session simply has — so it is put in on the way out of storage
    /// and taken off again on the way back (`withoutCheckIn`). That is what hands one
    /// to every note written before the card existed, and what keeps the marker ids
    /// out of it entirely.
    private static func insertCheckIn(_ card: CheckInAttachment, into result: NSMutableAttributedString) {
        let block = NSMutableAttributedString(attachment: card)
        block.append(NSAttributedString(string: "\n"))
        block.addAttributes(blockAttributes(), range: NSRange(location: 0, length: block.length))
        result.insert(block, at: 0)
    }

    /// Where the check-in card sits, its own line break included — the run
    /// `insertCheckIn` put in, and the run that has to come back out before anything
    /// reads the document as text. nil for a page that has no card.
    static func checkInRange(in storage: NSAttributedString) -> NSRange? {
        var found: NSRange?
        storage.enumerateAttribute(.attachment,
                                   in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if value is CheckInAttachment {
                found = range
                stop.pointee = true
            }
        }
        guard var range = found else { return nil }
        let text = storage.string as NSString
        if NSMaxRange(range) < text.length, text.character(at: NSMaxRange(range)) == 0x000A {
            range.length += 1
        }
        return range
    }

    /// The document as text, with the card taken back out. Its break goes with it, or
    /// the page would grow a blank line at its head every time it was saved.
    private static func withoutCheckIn(_ attributed: NSAttributedString) -> NSAttributedString {
        guard let range = checkInRange(in: attributed) else { return attributed }
        let stripped = NSMutableAttributedString(attributedString: attributed)
        stripped.deleteCharacters(in: range)
        return stripped
    }

    /// Flattens the editor's contents back to storage, recovering attachment order
    /// from the document itself so edits and deletions need no separate bookkeeping.
    /// Heading lines go out behind their sentinel — it is the only trace they leave.
    static func serialize(_ attributed: NSAttributedString) -> (text: String, ids: [UUID]) {
        let attributed = withoutCheckIn(attributed)
        var text = ""
        var ids: [UUID] = []
        let full = NSRange(location: 0, length: attributed.length)

        attributed.enumerateAttribute(.attachment, in: full) { value, range, _ in
            if let attachment = value as? MarkerAttachment {
                text += attachmentMarker
                ids.append(attachment.markerID)
            } else {
                text += attributed.attributedSubstring(from: range).string
            }
        }

        // The built text runs index-for-index with the attributed string — markers and
        // attachments are one character each — so the heading line starts map straight
        // across. Inserted back to front so earlier positions stay true.
        let string = attributed.string as NSString
        var sentinels: [(start: Int, marker: String)] = []
        for (key, marker) in [(climbHeader, headingMarker), (sectionHeader, sectionMarker)] {
            attributed.enumerateAttribute(key, in: full) { value, range, _ in
                guard value != nil else { return }
                var location = string.lineRange(for: NSRange(location: range.location, length: 0)).location
                while location < NSMaxRange(range) {
                    let line = string.lineRange(for: NSRange(location: location, length: 0))
                    // One sentinel per line, the climb kind winning if both attributes
                    // somehow land on one line.
                    if !sentinels.contains(where: { $0.start == line.location }) {
                        sentinels.append((line.location, marker))
                    }
                    location = NSMaxRange(line)
                }
            }
        }
        let out = NSMutableString(string: text)
        for sentinel in sentinels.sorted(by: { $0.start > $1.start }) {
            out.insert(sentinel.marker, at: sentinel.start)
        }
        return (out as String, ids)
    }

    /// Air above a block, so one card never sits flush against whatever ended above
    /// it — an expanded attempt's notes run right down to their card's edge, and the
    /// next row began exactly where they stopped.
    static let blockLead: CGFloat = 2

    /// The slack a row's own line leaves under the card it draws: the block sits on
    /// the baseline, and the line break sharing the line with it still carries the
    /// body font, whose descent hangs below the card as nobody's-space.
    static let rowDescent: CGFloat = ceil(-UIFont.preferredFont(forTextStyle: .body).descender)

    /// Trailing space on the last line of a note: the padding the card takes out of it
    /// as its own bottom, plus the same slack a row leaves under its card.
    ///
    /// The gap between two attempts is meant to be one thing — the next block's own
    /// `blockLead` — and nothing about whether the notes between them are open should
    /// touch it. Any more room than this and an open row pushed the next one down; any
    /// less and it pulled it up.
    static let quoteEndSpacing: CGFloat = BookmarkLayoutFragment.cardBottomPadding + rowDescent

    /// A row draws its own height exactly; the body's line and paragraph spacing on top
    /// of that just reads as slack above and below it, so its line gets none of that —
    /// only the lead that keeps it off the block before it.
    ///
    /// Given a height, the line is pinned to exactly that. The break sharing the line
    /// with the block still carries the body font, and its descent hangs below the
    /// block as a few points of nobody's-space — which is why the gap between two
    /// plain rows read as bigger than the gap under an expanded one, where the last
    /// thing above the gap is real text whose descent belongs to it.
    static func blockAttributes(lineHeight: CGFloat? = nil) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = 0
        paragraph.paragraphSpacingBefore = blockLead
        if let lineHeight {
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
        }
        return [.paragraphStyle: paragraph]
    }

    /// Title-cases a heading's line in place: the first letter of every word raised,
    /// everything else left exactly as typed — so "V4 crimpy" keeps its lowercase
    /// "crimpy" raised to "Crimpy" and nothing else about the name is touched.
    ///
    /// A letter swapped for a letter, never an insert or a delete: the line's length
    /// never changes, so the caret, the selection and every range measured against the
    /// storage survive the swap untouched.
    ///
    /// A word starts after a space or a bracket-ish mark, not after a digit or an
    /// apostrophe: "5.10a" stays as it is and "don't" doesn't become "Don'T".
    private static let wordBreaks: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.formUnion(CharacterSet(charactersIn: "-–—/\\([{\"“·,;:"))
        return set
    }()

    /// The same rule, for text that is not in the document — the workout's name in the
    /// header. Built rather than swapped in place, since there is no caret parked in a
    /// `String`.
    static func capitalizedName(_ name: String) -> String {
        var raised = ""
        var startsWord = true
        for scalar in name.unicodeScalars {
            let letter = String(scalar)
            let upper = letter.uppercased()
            raised += (startsWord && upper.utf16.count == 1) ? upper : letter
            startsWord = wordBreaks.contains(scalar)
        }
        return raised
    }

    private static func capitalizeNames(on lines: [NSRange], in storage: NSMutableAttributedString) {
        let text = storage.string as NSString
        for line in lines {
            var startsWord = true
            for index in line.location..<NSMaxRange(line) {
                guard let scalar = UnicodeScalar(text.character(at: index)) else {
                    startsWord = false
                    continue
                }
                if startsWord {
                    let raised = String(scalar).uppercased()
                    // Only a same-length raise: anything that grows in uppercase — ß,
                    // ﬁ — is left alone rather than shifting everything after it.
                    if raised != String(scalar), raised.utf16.count == 1 {
                        storage.replaceCharacters(in: NSRange(location: index, length: 1), with: raised)
                    }
                }
                startsWord = wordBreaks.contains(scalar)
            }
        }
    }

    /// Restyles in place: body text throughout, rows tight, heading
    /// lines as tinted bubbles, and the notes bound to a row as a quote. Attribute-only
    /// edits, so the selection and any attachments are left untouched.
    ///
    /// The quote bindings are read first and written back last. They are never derived
    /// away: a run that is bound stays bound, whatever the editing did to the lines
    /// around it. That is the whole difference between this and a quote that wanders.
    static func applyStyles(to storage: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }

        let text = storage.string as NSString

        // Heading lines, read before the wipe. Line-shaped like the quotes: any
        // character carrying the attribute makes its whole line a heading.
        func lines(carrying key: NSAttributedString.Key) -> [NSRange] {
            var found: [NSRange] = []
            storage.enumerateAttribute(key, in: full) { value, range, _ in
                guard value != nil else { return }
                var location = text.lineRange(for: NSRange(location: range.location, length: 0)).location
                while location < NSMaxRange(range) {
                    let line = text.lineRange(for: NSRange(location: location, length: 0))
                    if found.last != line { found.append(line) }
                    location = NSMaxRange(line)
                }
            }
            return found
        }
        let headings = lines(carrying: climbHeader)
        let sections = lines(carrying: sectionHeader)

        // Both kinds of heading read as names, whatever they were typed as: "orange"
        // is Orange, "deadpoint drill" is Deadpoint Drill. Done to the text itself
        // rather than drawn that way, so what is saved, searched and read back is the
        // name as it reads on the page.
        capitalizeNames(on: headings + sections, in: storage)

        // Folded heading lines, also read before the wipe — kept only where the line
        // still is a heading of either kind, so a fold cannot outlive its chevron.
        let folds = lines(carrying: foldedHeading)
            .filter { line in headings.contains(line) || sections.contains(line) }

        // Every block line in order — attachment rows and heading lines both — which is
        // what gives each attempt a region for its notes: from the line under its row
        // down to wherever the next block starts. Headings carry no id: nothing binds
        // to them, they only end the group above.
        var blocks: [(line: NSRange, id: UUID?, takesNotes: Bool)] = []
        storage.enumerateAttribute(.attachment, in: full) { value, range, _ in
            guard let marker = value as? MarkerAttachment else { return }
            blocks.append((text.lineRange(for: range), marker.markerID, marker.takesNotes))
        }
        for line in headings + sections {
            blocks.append((line, nil, false))
        }
        blocks.sort { $0.line.location < $1.line.location }

        var regions: [UUID: NSRange] = [:]
        for (index, block) in blocks.enumerated() where block.takesNotes {
            guard let id = block.id else { continue }
            let start = NSMaxRange(block.line)
            let end = index + 1 < blocks.count ? blocks[index + 1].line.location : storage.length
            guard start < end else { continue }
            regions[id] = NSRange(location: start, length: end - start)
        }

        // A binding only means anything where it sits. Notes that have drifted out from
        // under their row — pushed past a heading inserted above them, say — stop being
        // notes and go back to being ordinary text, where they now read.
        var quotes: [(range: NSRange, id: UUID)] = []
        storage.enumerateAttribute(noteQuote, in: full) { value, range, _ in
            guard let id = value as? UUID,
                  let region = regions[id],
                  NSIntersectionRange(range, region) == range
            else { return }
            // Text typed into a quote can arrive without the binding — UIKit rebuilds
            // typingAttributes around a tap and custom keys don't survive — leaving
            // unbound gaps inside the quote's lines. The quote is line-shaped, so a
            // run grows back to the start of its own line, absorbing any gap before
            // it; a gap later in the line is absorbed by the run that owns the
            // line's break growing back over it.
            let lineStart = text.lineRange(for: NSRange(location: range.location, length: 0)).location
            let grown = NSIntersectionRange(NSRange(location: lineStart,
                                                    length: NSMaxRange(range) - lineStart), region)
            quotes.append((grown.length > 0 ? grown : range, id))
        }

        // A bare line under a row is adopted as its notes, so notes typed after the fact
        // still belong to something. Adoption only ever adds a binding.
        for (id, region) in regions {
            let line = NSIntersectionRange(text.lineRange(for: NSRange(location: region.location, length: 0)),
                                           region)
            guard line.length > 0 else { continue }
            guard !quotes.contains(where: { NSIntersectionRange($0.range, line).length > 0 }) else { continue }
            quotes.append((line, id))
        }

        // A note line is a written line under its row, or a line opening with a
        // clock — nothing else, now that a break can never be typed into a quote.
        // A binding on any other line leaked there — carried past the quote's edge
        // by the system's typing attributes, or left behind by an edit at its
        // boundary — and is dropped here. A quote can never grow a line the user
        // didn't record, and a row with nothing written under it shows no quote
        // at all.
        quotes = quotes.flatMap { quote -> [(range: NSRange, id: UUID)] in
            var lines: [(range: NSRange, id: UUID)] = []
            var location = quote.range.location
            while location < NSMaxRange(quote.range) {
                let line = text.lineRange(for: NSRange(location: location, length: 0))
                defer { location = NSMaxRange(line) }
                let inQuote = NSIntersectionRange(line, quote.range)
                guard inQuote.length > 0 else { continue }
                let written = !text.substring(with: line)
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let opensRegion = regions[quote.id]?.location == line.location
                let clock = NoteTimestamp.regex.firstMatch(in: storage.string, options: [], range: line)
                if (opensRegion && written) || clock?.range.location == line.location {
                    lines.append((inQuote, quote.id))
                }
            }
            return lines
        }

        // `addAttributes`, not `setAttributes`: the latter would strip `.attachment`
        // and silently turn every inline attempt row back into a bare placeholder.
        storage.beginEditing()
        storage.removeAttribute(noteQuote, range: full)
        // Re-derived below from what the text now says, so an edited token never
        // keeps a stale time or a stale tint.
        storage.removeAttribute(noteTimestamp, range: full)
        storage.removeAttribute(noteQuoteEnd, range: full)
        // Rewritten below from the fold list, so a fold that leaked onto body text —
        // or whose heading stopped being one — dies here rather than lingering.
        storage.removeAttribute(foldedHeading, range: full)
        // Re-derived below for whatever is trailing now: a space that has stopped
        // being last must get its width back.
        storage.removeAttribute(.kern, range: full)
        storage.addAttributes(bodyAttributes, range: full)
        for block in blocks where block.id != nil {
            storage.addAttributes(blockAttributes(lineHeight: AttemptAttachment.rowHeight),
                                  range: block.line)
        }
        // The check-in draws its own height and keeps its own margins, so its line
        // gets none of the body's slack — the same deal an attempt row gets. It is
        // not in `blocks`: nothing files notes under it and nothing ends a group at
        // it, it is simply the block the note opens with.
        storage.enumerateAttribute(.attachment, in: full) { value, range, _ in
            guard value is CheckInAttachment else { return }
            storage.addAttributes(blockAttributes(), range: text.lineRange(for: range))
        }
        for quote in quotes {
            storage.addAttributes(quoteAttributes(for: quote.id), range: quote.range)
        }
        for quote in quotes {
            styleQuoteLines(in: storage, range: quote.range, id: quote.id)
        }
        // The last line under each row closes that row's card off, and carries the
        // room the card needs under its words plus the gap that follows it.
        for id in Set(quotes.map(\.id)) {
            guard let last = quotes.filter({ $0.id == id }).max(by: { $0.range.location < $1.range.location })
            else { continue }
            storage.addAttribute(noteQuoteEnd, value: true, range: last.range)
            // Built on whatever the line already has, never on the plain quote style:
            // a line opening with a clock has been given the deeper indent that clears
            // its bookmark, and handing it a fresh style takes that away — which drops
            // the words back on top of the mark.
            guard last.range.location < storage.length else { continue }
            let current = storage.attribute(.paragraphStyle, at: last.range.location,
                                            effectiveRange: nil) as? NSParagraphStyle ?? quoteParagraph
            let paragraph = NSMutableParagraphStyle()
            paragraph.setParagraphStyle(current)
            paragraph.paragraphSpacing = quoteEndSpacing
            storage.addAttribute(.paragraphStyle, value: paragraph, range: last.range)
        }

        // Each row is told whether anything is written under it — that is what puts a
        // chevron on it and stops its card rounding off at its own bottom edge — and
        // a row whose chevron is closed hides its notes with the same hairline trick a
        // folded heading uses on its group.
        let written = Set(quotes.map(\.id))
        var closed: Set<UUID> = []
        storage.enumerateAttribute(.attachment, in: full) { value, _, _ in
            guard let attempt = value as? AttemptAttachment else { return }
            attempt.hasNotes = written.contains(attempt.attemptID)
            if attempt.areNotesFolded, attempt.hasNotes { closed.insert(attempt.attemptID) }
            attempt.rowView?.showNotes(attempt.hasNotes, folded: attempt.areNotesFolded)
        }
        for quote in quotes where closed.contains(quote.id) {
            storage.addAttributes([.font: UIFont.systemFont(ofSize: 0.1),
                                   .foregroundColor: UIColor.clear,
                                   .paragraphStyle: foldedParagraph], range: quote.range)
            storage.removeAttribute(noteTimestamp, range: quote.range)
            storage.removeAttribute(noteQuoteEnd, range: quote.range)
        }
        // Headings last, tinted from what the line now says — this is what recolours
        // the bubble as a colour word is typed into it. Climbs after sections, so a
        // line that has somehow ended up carrying both draws as the climb it
        // serializes as rather than as a section that reopens as one.
        for line in sections {
            var attributes = sectionHeaderAttributes
            // The first line of the note has nothing above it to be clear of, and the
            // room would only push it off the top of the page.
            if line.location == 0,
               let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?
                   .mutableCopy() as? NSMutableParagraphStyle {
                paragraph.paragraphSpacingBefore = 0
                attributes[.paragraphStyle] = paragraph
            }
            storage.addAttributes(attributes, range: line)
            shrinkTrailingFiller(in: storage, line: line, font: sectionFont)
        }
        let headingStarts = (headings + sections).map(\.location).sorted()
        for line in headings {
            let name = headingName(text.substring(with: line))
            var attributes = headerAttributes(tint: ClimbTint.color(for: name))
            // The gap before the next climb, hung on the bottom of this one's group —
            // the last line before the heading that ends it. Nothing is hung on the
            // final group in the note: there is nothing under it to be clear of.
            let start = NSMaxRange(line)
            let end = headingStarts.first(where: { $0 >= start })
            if let end, start < end {
                let last = text.lineRange(for: NSRange(location: end - 1, length: 0))
                // Built on whatever the line already carries — a row's pinned height, a
                // card's closing room — so the gap adds to it rather than replaces it.
                let current = storage.attribute(.paragraphStyle, at: last.location,
                                                effectiveRange: nil) as? NSParagraphStyle
                let paragraph = NSMutableParagraphStyle()
                paragraph.setParagraphStyle(current ?? NSParagraphStyle.default)
                paragraph.paragraphSpacing += climbGroupTrail
                storage.addAttribute(.paragraphStyle, value: paragraph, range: last)
            } else if end != nil, !folds.contains(line),
                      let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?
                          .mutableCopy() as? NSMutableParagraphStyle {
                // Nothing under this heading yet, so there is no last line to hang the
                // gap on: the heading's own trailing room stands in for its group's, and
                // the heading below it still lands clear of this one. A folded empty
                // climb is left alone — it collapses to nothing, like any other.
                paragraph.paragraphSpacing += climbGroupTrail
                attributes[.paragraphStyle] = paragraph
            }
            storage.addAttributes(attributes, range: line)
            shrinkTrailingFiller(in: storage, line: line, font: headerFont)
        }

        // A note ending in a break shows one more line under it, and that empty line
        // takes its look from the character before it — the break. Left as the title's
        // or a heading's, it hands a line of body text their font and the room they
        // keep above themselves, which then vanishes the moment a character lands and
        // the line becomes its own. So the final break is styled as the body line it is
        // about to become: what is laid out there before anything is typed is what will
        // be laid out there after. It keeps carrying whatever key it had, so the line
        // it ends is still a heading in every other way, and a paragraph takes its
        // style from its first character, so nothing above it moves.
        if text.character(at: storage.length - 1) == 0x000A {
            let last = NSRange(location: storage.length - 1, length: 1)
            storage.addAttributes(bodyAttributes, range: last)
        }

        // Folding, last, over everything above: a folded heading's group — attempt
        // rows, quotes, stray body lines — draws at hairline size in clear, down to
        // the next heading of either kind. The rows are told directly, since their
        // height comes from their view provider and not from any attribute.
        // Timestamps come off the hidden lines so no bookmark is drawn beside text
        // that isn't there; they re-derive on the next restyle.
        storage.enumerateAttribute(.attachment, in: full) { value, _, _ in
            guard let attempt = value as? AttemptAttachment else { return }
            attempt.isCollapsed = false
            attempt.rowView?.isHidden = false
        }
        let sectionLines = sections.sorted { $0.location < $1.location }
        let headingLines = (headings + sections).sorted { $0.location < $1.location }
        for line in folds {
            storage.addAttribute(foldedHeading, value: true, range: line)
            let start = NSMaxRange(line)
            // Climbs nest under sections: a folded section swallows everything down
            // to the next section, climb headings included. A folded climb hides
            // only its own group — to the next heading of either kind.
            let boundaries = sections.contains(line) ? sectionLines : headingLines
            let end = boundaries.first(where: { $0.location >= start })?.location ?? storage.length
            guard start < end else { continue }
            let region = NSRange(location: start, length: end - start)
            storage.addAttributes([.font: UIFont.systemFont(ofSize: 0.1),
                                   .foregroundColor: UIColor.clear,
                                   .paragraphStyle: foldedParagraph], range: region)
            storage.removeAttribute(noteTimestamp, range: region)
            storage.enumerateAttribute(.attachment, in: region) { value, _, _ in
                guard let attempt = value as? AttemptAttachment else { return }
                attempt.isCollapsed = true
                attempt.rowView?.isHidden = true
            }
        }
        storage.endEditing()
    }

    /// Takes the width off a heading line's trailing space — the filler an empty
    /// heading needs to exist at all, and whatever is left of it once a name is typed
    /// in front of it. Kerned to nothing rather than shrunk: the character keeps the
    /// line's own font, so the line keeps its height and its baseline, and the caret
    /// landing after it sits exactly where the name ends instead of a space past it.
    private static func shrinkTrailingFiller(in storage: NSMutableAttributedString,
                                             line: NSRange, font: UIFont) {
        let text = storage.string as NSString
        var end = NSMaxRange(line)
        if end > line.location, text.character(at: end - 1) == 0x000A { end -= 1 }
        guard end > line.location, text.character(at: end - 1) == 0x0020 else { return }
        let width = (headingFiller as NSString).size(withAttributes: [.font: font]).width
        storage.addAttribute(.kern, value: -width, range: NSRange(location: end - 1, length: 1))
    }

    /// No spacing anywhere: a folded line's only height is its hairline font.
    private static let foldedParagraph: NSParagraphStyle = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = 0
        paragraph.paragraphSpacingBefore = 0
        return paragraph
    }()

    /// Whether the line at `location` is a folded heading's.
    static func isFolded(lineAt location: Int, in storage: NSAttributedString) -> Bool {
        guard storage.length > 0 else { return false }
        let line = (storage.string as NSString)
            .lineRange(for: NSRange(location: min(location, storage.length), length: 0))
        guard line.length > 0 else { return false }
        return storage.attribute(foldedHeading, at: line.location, effectiveRange: nil) != nil
    }

    /// What each attempt's notes currently read as in the document.
    ///
    /// Collected line by line, not by raw run: a run can have unbound gaps — the
    /// binding is a custom key and does not survive every edit — and joining raw runs
    /// would weld two note lines together without the break between them.
    static func notes(in storage: NSAttributedString) -> [UUID: String] {
        let text = storage.string as NSString
        var lines: [UUID: [NSRange]] = [:]
        storage.enumerateAttribute(noteQuote, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let id = value as? UUID else { return }
            var location = range.location
            while location < NSMaxRange(range) {
                let line = text.lineRange(for: NSRange(location: location, length: 0))
                if lines[id]?.last != line {
                    lines[id, default: []].append(line)
                }
                location = NSMaxRange(line)
            }
        }
        return lines.mapValues { ranges in
            ranges.map { text.substring(with: $0).trimmingCharacters(in: .newlines) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
        }
    }
}
