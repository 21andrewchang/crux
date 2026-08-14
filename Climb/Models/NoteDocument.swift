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

    /// Ties a run of text to the attempt whose notes it is.
    ///
    /// It is an attribute on the characters, not a rule about which line sits where:
    /// UIKit carries attributes along as text is typed, split, joined and undone, so the
    /// binding survives editing on its own. Position only ever *adds* a binding — a bare
    /// line under a row is adopted as its notes — and nothing takes one away.
    static let noteQuote = NSAttributedString.Key("climbNoteQuote")

    /// Body text in every way but colour and a step of indent — the notes sit in the
    /// note like anything else you typed, just quieter and tucked under their row.
    static func quoteAttributes(for id: UUID) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 2
        paragraph.firstLineHeadIndent = quoteIndent
        paragraph.headIndent = quoteIndent

        var attributes = bodyAttributes
        attributes[.foregroundColor] = UIColor.secondaryLabel
        attributes[.paragraphStyle] = paragraph
        attributes[noteQuote] = id
        return attributes
    }

    static let quoteIndent: CGFloat = 16

    // MARK: Typography
    //
    // Apple Notes styles the first line as the document title and everything after it
    // as body text. There is no formatting UI yet, so these are applied wholesale on
    // every edit rather than tracked as user intent.

    static var titleAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 6
        return [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph,
        ]
    }

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 2
        return [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph,
        ]
    }

    /// Shown behind an empty document, so the first line reads as the title it becomes.
    static var placeholderText: NSAttributedString {
        let text = NSMutableAttributedString(string: "Workout Name", attributes: titleAttributes)
        text.addAttribute(.foregroundColor,
                          value: UIColor.placeholderText,
                          range: NSRange(location: 0, length: text.length))
        return text
    }

    /// Rebuilds the editable document, substituting a live attachment at each marker.
    ///
    /// A marker whose ID no longer resolves — a climb retired from the library, say —
    /// is dropped along with its ID, so the two never drift out of alignment.
    static func attributedString(for session: ClimbSession, makeAttachment: (UUID) -> NSTextAttachment?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var idIndex = 0

        for character in session.bodyText {
            if String(character) == attachmentMarker {
                guard idIndex < session.attachmentIDs.count else { continue }
                let id = session.attachmentIDs[idIndex]
                idIndex += 1
                guard let attachment = makeAttachment(id) else { continue }
                result.append(NSAttributedString(attachment: attachment))
            } else {
                result.append(NSAttributedString(string: String(character)))
            }
        }

        restoreNotes(in: result) { session.attempt(with: $0)?.notes ?? "" }
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
            } else if let quote {
                // Nothing written yet: hold the empty line open so it can be typed into.
                storage.addAttribute(noteQuote, value: marker.id, range: quote)
            }
        }
    }

    /// The line after a row — unless that line is another row, in which case there is
    /// nowhere for the notes to sit.
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
        return isBlock ? nil : quote
    }

    /// Flattens the editor's contents back to storage, recovering attachment order
    /// from the document itself so edits and deletions need no separate bookkeeping.
    static func serialize(_ attributed: NSAttributedString) -> (text: String, ids: [UUID]) {
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
        return (text, ids)
    }

    /// A row draws its own height exactly; the body's line and paragraph spacing on top
    /// of that just reads as slack above and below it, so its line gets none.
    static var blockAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = 0
        return [.paragraphStyle: paragraph]
    }

    /// Restyles in place: first line as title, remainder as body, rows tight, and the
    /// notes bound to a row as a quote. Attribute-only edits, so the selection and any
    /// attachments are left untouched.
    ///
    /// The quote bindings are read first and written back last. They are never derived
    /// away: a run that is bound stays bound, whatever the editing did to the lines
    /// around it. That is the whole difference between this and a quote that wanders.
    static func applyStyles(to storage: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }

        let text = storage.string as NSString

        // Every block line in order, which is what gives each attempt a region for its
        // notes: from the line under its row down to wherever the next block starts.
        var blocks: [(line: NSRange, id: UUID, takesNotes: Bool)] = []
        storage.enumerateAttribute(.attachment, in: full) { value, range, _ in
            guard let marker = value as? MarkerAttachment else { return }
            blocks.append((text.lineRange(for: range), marker.markerID, marker.takesNotes))
        }

        var regions: [UUID: NSRange] = [:]
        for (index, block) in blocks.enumerated() where block.takesNotes {
            let start = NSMaxRange(block.line)
            let end = index + 1 < blocks.count ? blocks[index + 1].line.location : storage.length
            guard start < end else { continue }
            regions[block.id] = NSRange(location: start, length: end - start)
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
            quotes.append((range, id))
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

        // `addAttributes`, not `setAttributes`: the latter would strip `.attachment`
        // and silently turn every inline attempt row back into a bare placeholder.
        storage.beginEditing()
        storage.removeAttribute(noteQuote, range: full)
        storage.addAttributes(bodyAttributes, range: full)
        let firstLine = text.lineRange(for: NSRange(location: 0, length: 0))
        storage.addAttributes(titleAttributes, range: firstLine)
        for block in blocks {
            storage.addAttributes(blockAttributes, range: block.line)
        }
        for quote in quotes {
            storage.addAttributes(quoteAttributes(for: quote.id), range: quote.range)
        }
        storage.endEditing()
    }

    /// What each attempt's notes currently read as in the document.
    static func notes(in storage: NSAttributedString) -> [UUID: String] {
        var runs: [UUID: String] = [:]
        storage.enumerateAttribute(noteQuote, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let id = value as? UUID else { return }
            runs[id, default: ""] += storage.attributedSubstring(from: range).string
        }
        return runs.mapValues { $0.trimmingCharacters(in: .newlines) }
    }
}
