import Foundation
import SwiftData

/// A single journal entry — one climbing session, stored as a document.
///
/// The body is plain text with a `\u{FFFC}` (object replacement character) at each
/// point where an attempt is embedded, mirroring how `NSAttributedString` represents
/// attachments. `attachmentIDs` runs parallel to those markers: the *n*th marker in
/// `bodyText` refers to `attachmentIDs[n]`. Keeping the two in sync means a user
/// deleting a row in the editor deletes the attempt, and reordering just works.
@Model
final class ClimbSession {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var bodyText: String = ""
    var attachmentIDs: [UUID] = []

    @Relationship(deleteRule: .cascade, inverse: \Attempt.session)
    var attempts: [Attempt] = []

    init(createdAt: Date = Date()) {
        self.id = UUID()
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// Attempts in the order they were recorded — the order their numbering follows.
    var orderedAttempts: [Attempt] {
        attempts.sorted { $0.createdAt < $1.createdAt }
    }

    func attempt(with id: UUID) -> Attempt? {
        attempts.first { $0.id == id }
    }

    /// 1-based position used for the "Attempt 3" label on an inline row.
    func ordinal(of id: UUID) -> Int {
        (orderedAttempts.firstIndex { $0.id == id } ?? 0) + 1
    }

    private var lines: [Substring] {
        var text = bodyText
        // A glyph has nowhere to draw in a list row, so it reads as its name instead.
        for (character, fallback) in NoteDocument.glyphFallbacks {
            text = text.replacingOccurrences(of: String(character), with: fallback)
        }
        return text
            .replacingOccurrences(of: NoteDocument.attachmentMarker, with: " ")
            // Heading names read like any other line; only the sentinels go.
            .replacingOccurrences(of: NoteDocument.headingMarker, with: "")
            .replacingOccurrences(of: NoteDocument.sectionMarker, with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// Apple Notes convention: the first non-empty line is the title.
    var displayTitle: String {
        let title = lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return title.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "New Session"
    }

    /// The rest of the document, collapsed to one line for the list row.
    var previewText: String {
        var seenTitle = false
        var remainder: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !seenTitle {
                if !trimmed.isEmpty { seenTitle = true }
                continue
            }
            if !trimmed.isEmpty { remainder.append(trimmed) }
        }
        let joined = remainder.joined(separator: " ")
        if joined.isEmpty {
            return attempts.isEmpty ? "No additional text" : "\(attempts.count) attempt\(attempts.count == 1 ? "" : "s")"
        }
        return joined
    }
}
