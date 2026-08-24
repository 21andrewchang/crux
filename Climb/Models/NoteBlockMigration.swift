import Foundation
import SwiftData

/// Reads a session's four text pages into a `NoteBlock` tree, once.
///
/// This is the one place that still knows how a note was stored as prose. It runs
/// against `bodyText` and leaves it exactly as it found it: the blocks are built
/// alongside, so a parse that gets something wrong is fixed by deleting them and
/// running again rather than by a restore.
///
/// The rules are the ones `NoteDocument.attributedString` and `applyStyles` already
/// used, written out plainly — a `\u{FFF9}` line is a climb, a `\u{FFFA}` line is a
/// section, either one ends the group above it, and a `\u{FFFC}` is the *n*th id in
/// the page's list.
enum NoteBlockMigration {

    /// Builds the tree for every session that hasn't got one yet.
    @discardableResult
    static func run(in context: ModelContext) throws -> Int {
        let sessions = try context.fetch(FetchDescriptor<ClimbSession>())
        let climbs = try context.fetch(FetchDescriptor<Climb>())
        var built = 0
        for session in sessions where !session.didBuildBlocks {
            build(for: session, in: context, library: climbs)
            built += 1
        }
        return built
    }

    /// Reads one session's pages. Safe to call again after clearing `blocks` and
    /// `didBuildBlocks` — nothing outside the tree is written.
    static func build(for session: ClimbSession, in context: ModelContext, library: [Climb]) {
        // Resolve only, never create: a heading that doesn't match a saved climb keeps
        // its name as the block's text and links to nothing. Making 70-odd library
        // climbs out of old headings is a decision to take deliberately, with the
        // result on screen — not a side effect of opening the app once.
        var byName: [String: Climb] = [:]
        for climb in library where !climb.name.isEmpty {
            byName[climb.name.lowercased()] = climb
        }

        for tab in NoteTab.allCases {
            let roots = parse(page: session.text(for: tab),
                              ids: session.attachmentIDs(for: tab),
                              tab: tab,
                              attempt: { session.attempt(with: $0) },
                              climb: { byName[$0.lowercased()] })
            for block in roots {
                block.session = session
                context.insert(block)
            }
        }
        session.didBuildBlocks = true
    }

    /// One page's top-level blocks, in order. Children hang off them.
    static func parse(page: String,
                      ids: [UUID],
                      tab: NoteTab,
                      attempt: (UUID) -> Attempt?,
                      climb: (String) -> Climb?) -> [NoteBlock] {
        var roots: [NoteBlock] = []
        var section: NoteBlock?
        var currentClimb: NoteBlock?
        var idIndex = 0
        /// The row a following line's words might belong to — an attempt's notes are
        /// already on the attempt, so they are dropped here rather than doubled.
        var lastAttempt: Attempt?

        var lines = page.components(separatedBy: "\n")[...]

        /// Files a block under the innermost thing open, and hands back the parent it
        /// was filed under so nothing has to reach for `roots` twice.
        func file(_ block: NoteBlock, under parent: NoteBlock?) {
            if let parent {
                block.order = parent.children.count
                block.parent = parent
                parent.children.append(block)
            } else {
                block.order = roots.count
                roots.append(block)
            }
        }

        while let line = lines.first {
            lines = lines.dropFirst()

            if line.hasPrefix(NoteDocument.headingMarker) {
                let name = NoteDocument.headingName(String(line.dropFirst()))
                let block = NoteBlock(kind: .climb, tab: tab, text: name)
                block.climb = climb(name)
                file(block, under: section)
                currentClimb = block
                lastAttempt = nil
                continue
            }

            if line.hasPrefix(NoteDocument.sectionMarker) {
                let name = NoteDocument.headingName(String(line.dropFirst()))
                let block = NoteBlock(kind: .section, tab: tab, text: name)
                file(block, under: nil)
                section = block
                // A section ends the climb above it, exactly as it did in the text.
                currentClimb = nil
                lastAttempt = nil
                continue
            }

            if line.contains(NoteDocument.attachmentMarker) {
                // A row is its own line in every note written, but the marker is a
                // character like any other — so each one on the line gets a block, in
                // the order the ids run.
                let markers = line.components(separatedBy: NoteDocument.attachmentMarker).count - 1
                for _ in 0..<markers {
                    guard idIndex < ids.count else { break }
                    let id = ids[idIndex]
                    idIndex += 1
                    guard let go = attempt(id) else { continue }
                    let block = NoteBlock(kind: .attempt, tab: tab)
                    block.attempt = go
                    file(block, under: currentClimb ?? section)
                    // The relationship the note used to only imply. Written from the
                    // heading the row actually sits under, which is what the app has
                    // been reading off the prose all along.
                    if let owner = currentClimb?.climb { go.climb = owner }
                    lastAttempt = go
                }
                continue
            }

            // A row's notes are the attempt's, not the note's. `restoreNotes` wrote
            // them under the row on the way in; here they are read back off and left
            // where they belong.
            if let go = lastAttempt, consumeNotes(of: go, from: line, rest: &lines) {
                lastAttempt = nil
                continue
            }

            let written = line.trimmingCharacters(in: .whitespaces)
            guard !written.isEmpty else { continue }
            file(NoteBlock(kind: .prose, tab: tab, text: written), under: currentClimb ?? section)
        }

        return roots
    }

    /// Whether `line` — and however many lines after it — are `go`'s notes verbatim.
    /// Consumes them from `rest` when they are, so they don't come back as prose.
    ///
    /// Matched whole rather than line by line: notes run to several lines, and a
    /// partial match would drop the first and keep the rest as stray paragraphs.
    private static func consumeNotes(of go: Attempt,
                                     from line: String,
                                     rest: inout ArraySlice<String>) -> Bool {
        let written = go.notes.trimmingCharacters(in: .newlines)
        guard !written.isEmpty else { return false }

        let wanted = written.components(separatedBy: "\n")
        guard let first = wanted.first, first == line else { return false }
        guard wanted.count > 1 else { return true }

        let following = Array(rest.prefix(wanted.count - 1))
        guard following == Array(wanted.dropFirst()) else { return false }
        rest = rest.dropFirst(wanted.count - 1)
        return true
    }
}
