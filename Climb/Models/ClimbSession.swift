import Foundation
import SwiftData

/// A single journal entry — one climbing session, stored as four documents.
///
/// Each page of the note (see `NoteTab`) is plain text with a `\u{FFFC}` (object
/// replacement character) at each point where an attempt is embedded, mirroring how
/// `NSAttributedString` represents attachments. The ids run parallel to those markers:
/// the *n*th marker in a page's text refers to the *n*th id in that page's list.
/// Keeping the two in sync means a user deleting a row in the editor deletes the
/// attempt, and reordering just works.
///
/// The title is the session's, not any page's: it sits above the tabs and is the same
/// whichever one is open. Notes written before the tabs existed kept their title as
/// their first line, Apple Notes style — `splitTitleIfNeeded` lifts it out once.
@Model
final class ClimbSession {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// The session's name, written in the header above the tabs.
    var title: String = ""

    /// Whether the title has been lifted out of `bodyText`. Set once, on the first
    /// open after the tabs landed — without it, a user who clears the title would have
    /// their first body line lifted into it again on the next open.
    var didSplitTitle: Bool = false

    /// The main page — the one every note had before there were four. Kept under its
    /// old name so the sessions already written stay exactly where they are.
    var bodyText: String = ""
    var attachmentIDs: [UUID] = []

    var checkInText: String = ""
    var checkInIDs: [UUID] = []
    var warmUpText: String = ""
    var warmUpIDs: [UUID] = []
    var reviewText: String = ""
    var reviewIDs: [UUID] = []

    /// The check-in's answers, one index into `CheckIn.fields[n].options` per
    /// question, `CheckIn.unanswered` for one not answered yet. Empty on a session
    /// from before the card existed, which reads as all six unanswered.
    ///
    /// Positional, so `CheckIn.fields` can be appended to but never reordered.
    var checkInAnswers: [Int] = []

    @Relationship(deleteRule: .cascade, inverse: \Attempt.session)
    var attempts: [Attempt] = []

    init(createdAt: Date = Date()) {
        self.id = UUID()
        self.createdAt = createdAt
        self.updatedAt = createdAt
        // Nothing to lift out of a note that starts empty.
        self.didSplitTitle = true
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

    // MARK: Pages

    /// One page's text as stored.
    func text(for tab: NoteTab) -> String {
        switch tab {
        case .checkIn: checkInText
        case .warmUp: warmUpText
        case .main: bodyText
        case .review: reviewText
        }
    }

    /// The markers on one page, in the order they appear in its text.
    func attachmentIDs(for tab: NoteTab) -> [UUID] {
        switch tab {
        case .checkIn: checkInIDs
        case .warmUp: warmUpIDs
        case .main: attachmentIDs
        case .review: reviewIDs
        }
    }

    /// Writes a page back after an edit. The two always land together — a text and its
    /// ids are one thing, and half of an edit would leave the markers out of step.
    func setDocument(text: String, ids: [UUID], for tab: NoteTab) {
        switch tab {
        case .checkIn: checkInText = text; checkInIDs = ids
        case .warmUp: warmUpText = text; warmUpIDs = ids
        case .main: bodyText = text; attachmentIDs = ids
        case .review: reviewText = text; reviewIDs = ids
        }
    }

    /// Every marker in the note, whichever page it is on — what decides which attempts
    /// still exist. An attempt is real because some page shows a row for it, and it
    /// does not matter which.
    var allAttachmentIDs: [UUID] {
        NoteTab.allCases.flatMap { attachmentIDs(for: $0) }
    }

    /// Everything written in the note, for the list's search field.
    var searchText: String {
        ([title] + NoteTab.allCases.map { text(for: $0) }).joined(separator: "\n")
    }

    /// Lifts the title out of the body, once, for a note written before the tabs.
    ///
    /// The title was the first non-empty line and nothing else marked it, so that line
    /// — and the blank ones above it — come off the front of the main page. Any markers
    /// caught in what is removed go with it, so text and ids stay in step.
    func splitTitleIfNeeded() {
        guard !didSplitTitle else { return }
        didSplitTitle = true

        var lines = bodyText.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return }

        let head = lines[...index].joined(separator: "\n")
        let lifted = lines[index]
        lines.removeSubrange(...index)
        bodyText = lines.joined(separator: "\n")
        // A heading is a line like any other to the title: the sentinel is dropped and
        // the name kept, so a note whose first line was somehow a section still ends up
        // named rather than titled "\u{FFF9}Warm-up".
        title = lifted
            .replacingOccurrences(of: NoteDocument.headingMarker, with: "")
            .replacingOccurrences(of: NoteDocument.sectionMarker, with: "")
            .replacingOccurrences(of: NoteDocument.attachmentMarker, with: "")
            .trimmingCharacters(in: .whitespaces)

        let taken = head.components(separatedBy: NoteDocument.attachmentMarker).count - 1
        if taken > 0 { attachmentIDs.removeFirst(min(taken, attachmentIDs.count)) }
    }

    // MARK: List row

    private func lines(of tab: NoteTab) -> [Substring] {
        text(for: tab)
            .replacingOccurrences(of: NoteDocument.attachmentMarker, with: " ")
            // Heading names read like any other line; only the sentinels go.
            .replacingOccurrences(of: NoteDocument.headingMarker, with: "")
            .replacingOccurrences(of: NoteDocument.sectionMarker, with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// What the list calls this session. A note from before the tabs that has not been
    /// opened since still has its name as its first line, so that is read as the title
    /// until `splitTitleIfNeeded` lifts it out for good.
    var displayTitle: String {
        let named = title.trimmingCharacters(in: .whitespaces)
        if !named.isEmpty { return named }
        if !didSplitTitle,
           let first = lines(of: .main).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return String(first).trimmingCharacters(in: .whitespaces)
        }
        return "New Session"
    }

    /// Everything written across the pages, collapsed to one line — nil for a note
    /// that is nothing but its title, so a caller can say what it likes about an empty
    /// one. The pages read in the order they are climbed.
    var bodyPreview: String? {
        var remainder: [String] = []
        var skipTitle = !didSplitTitle
        for tab in NoteTab.allCases {
            for line in lines(of: tab) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                // An unsplit note still carries its name as the first line of its
                // main page; the list already shows that above.
                if skipTitle, tab == .main {
                    skipTitle = false
                    continue
                }
                remainder.append(trimmed)
            }
        }
        let joined = remainder.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    /// The rest of the document, collapsed to one line for the list row.
    var previewText: String {
        if let bodyPreview { return bodyPreview }
        return attempts.isEmpty ? "No additional text" : "\(attempts.count) attempt\(attempts.count == 1 ? "" : "s")"
    }
}

extension ClimbSession {
    /// The check-in's answers, always exactly as long as there are questions: a
    /// session saved before a question was added answers it blank rather than
    /// dropping every answer after it out of alignment.
    var checkIn: [Int] {
        get {
            var answers = checkInAnswers.prefix(CheckIn.fields.count).map { $0 }
            while answers.count < CheckIn.fields.count { answers.append(CheckIn.unanswered) }
            return answers
        }
        set { checkInAnswers = newValue }
    }

    /// Today's readiness, 0-100 — nothing until all six are in.
    var readiness: Int? { CheckIn.readiness(checkIn) }

    /// Records one answer. The card never shuts — it is the whole of its page.
    func answerCheckIn(field: Int, option: Int) {
        guard CheckIn.fields.indices.contains(field) else { return }
        var answers = checkIn
        answers[field] = option
        checkIn = answers
    }
}
