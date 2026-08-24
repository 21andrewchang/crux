import Foundation

/// The words typed into the search field.
///
/// Every one of them has to turn up for a line to count, and the order they were typed
/// in does not matter — "v2 blue" finds "Blue V2" the same as "blue v2" does. Matching
/// ignores case and accents, so what is typed in a hurry still finds what was written
/// carefully.
struct SearchTerms: Equatable {
    /// Exactly what was typed, trimmed — what ranking reads, since a name that *is*
    /// the query is a better answer than one that merely contains all of its words.
    let whole: String
    let words: [String]

    init(_ query: String) {
        whole = query.trimmingCharacters(in: .whitespacesAndNewlines)
        words = whole.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var isEmpty: Bool { words.isEmpty }

    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    func matches(_ text: String) -> Bool {
        words.allSatisfy { text.range(of: $0, options: Self.options) != nil }
    }

    /// How well a name fits: the query itself first, then a name that starts with it,
    /// then one that has it somewhere, then everything that matched word by word.
    func rank(_ text: String) -> Int {
        if text.compare(whole, options: Self.options) == .orderedSame { return 0 }
        if text.range(of: whole, options: Self.options.union(.anchored)) != nil { return 1 }
        if text.range(of: whole, options: Self.options) != nil { return 2 }
        return 3
    }

    /// Where each word landed, so a row can mark them. Overlaps are possible — two
    /// words of the query can find the same stretch of text — and the marking is
    /// idempotent, so nothing has to be done about that here.
    func ranges(in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for word in words {
            var from = text.startIndex
            while let range = text.range(of: word, options: Self.options, range: from..<text.endIndex),
                  !range.isEmpty {
                found.append(range)
                from = range.upperBound
            }
        }
        return found
    }
}

/// One row of the results: a climb, a clip, a line of a note, or a session.
///
/// A result is a *place in a note*, not a note — which is the whole point of the
/// field. It carries enough to open exactly there: the session, the page it is
/// written on, and for a clip the attempt and the moment it starts at.
struct SearchResult: Identifiable {
    enum Kind: Int, CaseIterable, Hashable {
        case climb, clip, note, session

        /// What the section over these rows is called.
        var title: String {
            switch self {
            case .climb: "Climbs"
            case .clip: "Clips"
            case .note: "Notes"
            case .session: "Sessions"
            }
        }
    }

    let id: String
    let kind: Kind
    let session: ClimbSession
    /// The page the match is written on. Nil for a session found by its own name,
    /// which belongs to no page.
    let tab: NoteTab?
    /// The attempt a clip was written on.
    let attemptID: UUID?
    /// Where in that attempt's video the clip starts.
    let start: TimeInterval?
    /// The text the query landed in — what the row marks.
    let text: String
    /// What that text belongs to, said beside it: the climb and attempt a clip is
    /// filed under, the session and page a line is written on.
    let context: String
    /// Drawn at the row's trailing edge — a clip's clock, a climb's attempt count,
    /// a session's date.
    let trailing: String?
    /// The climb a row is coloured by, when it has one.
    let climbName: String?
}

/// Searching the whole journal rather than the list of sessions.
///
/// The field is used to find a problem again — "blue v2", six weeks ago — or a thing
/// noticed once and worth doing again — "hip movement", written into whichever clip it
/// happened in. Neither of those is a session, and answering both with a list of
/// sessions is answering neither, so every result here is the thing itself with the
/// session named under it.
enum SessionSearch {
    /// How many of each kind are worth showing. Past this the field has stopped being
    /// a search and become a second copy of the journal.
    private static let limit = 40

    static func results(for query: String, in sessions: [ClimbSession]) -> [SearchResult] {
        let terms = SearchTerms(query)
        guard !terms.isEmpty else { return [] }

        var climbs: [(rank: Int, result: SearchResult)] = []
        var clips: [SearchResult] = []
        var notes: [SearchResult] = []
        var found: [SearchResult] = []

        // Sessions arrive newest first and are walked in that order, so every kind
        // comes out newest first without being sorted for it.
        for session in sessions {
            let structure = session.noteStructure
            let date = session.createdAt.formatted(.dateTime.month(.abbreviated).day())

            // Climbs. The same name twice in one note is one climb — coming back to a
            // problem later in the session is another go at it, not another problem —
            // so the attempts under both headings are counted together.
            var order: [String] = []
            var byName: [String: (name: String, tab: NoteTab, attempts: Int)] = [:]
            for group in structure.groups {
                let key = group.name.lowercased()
                if byName[key] == nil {
                    order.append(key)
                    byName[key] = (group.name, group.tab, 0)
                }
                byName[key]?.attempts += group.attemptIDs.count
            }
            for key in order {
                guard let climb = byName[key], terms.matches(climb.name) else { continue }
                let goes = climb.attempts
                climbs.append((terms.rank(climb.name), SearchResult(
                    id: "climb-\(session.id)-\(key)",
                    kind: .climb,
                    session: session,
                    tab: climb.tab,
                    attemptID: nil,
                    start: nil,
                    text: climb.name,
                    context: "\(session.displayTitle) · \(date)",
                    trailing: goes == 0 ? nil : "\(goes) attempt\(goes == 1 ? "" : "s")",
                    climbName: climb.name)))
            }

            // Clips. An attempt's notes are the same text the note shows under its row,
            // so the lines found here are struck off the note's own lines below —
            // otherwise every clip would be answered twice.
            var written = Set<String>()
            for attempt in session.orderedAttempts where attempt.deletedAt == nil {
                let placement = structure.placements[attempt.id]
                let ordinal = placement?.ordinal ?? session.ordinal(of: attempt.id)
                let heading = placement?.climbName
                for line in attempt.notes.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }
                    written.insert(trimmed)
                    let clip = self.clip(in: trimmed)
                    let text = clip?.words ?? trimmed
                    guard !text.isEmpty, terms.matches(text) else { continue }
                    clips.append(SearchResult(
                        id: "clip-\(attempt.id)-\(clips.count)",
                        kind: .clip,
                        session: session,
                        tab: placement?.tab,
                        attemptID: attempt.id,
                        start: clip?.start,
                        text: text,
                        context: [heading, "Attempt \(ordinal)", date].compactMap { $0 }.joined(separator: " · "),
                        trailing: clip.map { NoteTimestamp.display(for: $0.start) },
                        climbName: heading))
                }
            }

            // Everything else written on the pages. Headings are left out: a climb is
            // already a result of its own, and a section heading is the name of a
            // stretch of note rather than something written in it.
            for tab in NoteTab.allCases {
                for line in session.text(for: tab).components(separatedBy: "\n") {
                    guard !line.hasPrefix(NoteDocument.headingMarker) else { continue }
                    let trimmed = line
                        .replacingOccurrences(of: NoteDocument.sectionMarker, with: "")
                        .replacingOccurrences(of: NoteDocument.attachmentMarker, with: "")
                        .trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !written.contains(trimmed), terms.matches(trimmed) else { continue }
                    written.insert(trimmed)
                    notes.append(SearchResult(
                        id: "note-\(session.id)-\(tab.rawValue)-\(notes.count)",
                        kind: .note,
                        session: session,
                        tab: tab,
                        attemptID: nil,
                        start: nil,
                        text: trimmed,
                        context: "\(session.displayTitle) · \(tab.title)",
                        trailing: date,
                        climbName: nil))
                }
            }

            // The session itself, found by its name. Last of the four on purpose: the
            // field is for what is inside the notes far more often than for one of them.
            if terms.matches(session.displayTitle) {
                found.append(SearchResult(
                    id: "session-\(session.id)",
                    kind: .session,
                    session: session,
                    tab: nil,
                    attemptID: nil,
                    start: nil,
                    text: session.displayTitle,
                    context: session.previewText,
                    trailing: date,
                    climbName: nil))
            }
        }

        // Only the climbs are re-ordered, and only by how well the name fits: rows of
        // equal rank keep the newest-first order they were found in.
        let ranked = climbs.enumerated()
            .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
            .map(\.element.result)

        return Array(ranked.prefix(limit))
            + Array(clips.prefix(limit))
            + Array(notes.prefix(limit))
            + Array(found.prefix(limit))
    }

    /// The clip a note line marks out: the clock it opens with, and the words after it.
    /// Nil for a line that names no moment — an attempt can be written on plainly.
    private static func clip(in line: String) -> (start: TimeInterval, words: String)? {
        let text = line as NSString
        guard let match = NoteTimestamp.regex.firstMatch(in: line, options: [],
                                                         range: NSRange(location: 0, length: text.length)),
              match.range.location == 0 else { return nil }
        let token = text.substring(with: match.range)
        let words = text.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespaces)
        return (NoteTimestamp.seconds(from: token), words)
    }
}

extension ClimbSession {
    /// Where one attempt sits in the note: the page it is on, the climb it is filed
    /// under, and the number it carries there.
    struct AttemptPlacement {
        let tab: NoteTab
        let climbName: String?
        let ordinal: Int
    }

    /// A climb heading and the attempts recorded under it.
    struct ClimbGroup {
        let tab: NoteTab
        let name: String
        var attemptIDs: [UUID] = []
    }

    /// The note read back as it looks on the page.
    ///
    /// The document is the truth about which attempt belongs to which climb — a climb
    /// is a heading and nothing else, and the rows under it are filed there by where
    /// they sit — so the only way to answer that outside the editor is to walk the text
    /// the way the editor does: markers count off the page's ids in order, and either
    /// kind of heading ends the group above it.
    var noteStructure: (groups: [ClimbGroup], placements: [UUID: AttemptPlacement]) {
        var groups: [ClimbGroup] = []
        var placements: [UUID: AttemptPlacement] = [:]

        for tab in NoteTab.allCases {
            let ids = attachmentIDs(for: tab)
            var index = 0
            /// The group the rows being walked are landing in, if it is a named climb.
            var current: Int?
            var ordinal = 0

            for line in text(for: tab).components(separatedBy: "\n") {
                let markers = line.components(separatedBy: NoteDocument.attachmentMarker).count - 1
                let isClimb = line.hasPrefix(NoteDocument.headingMarker)
                let isSection = line.hasPrefix(NoteDocument.sectionMarker)

                if isClimb || isSection {
                    // A section heading ends a climb's group the way another climb
                    // would, so the attempts under one carry no climb name.
                    ordinal = 0
                    current = nil
                    if isClimb {
                        let name = NoteDocument.headingName(String(line.dropFirst())
                            .replacingOccurrences(of: NoteDocument.attachmentMarker, with: ""))
                        // A heading pressed and not yet typed into is a climb nobody
                        // has named; nothing is filed under it until it has one.
                        if !name.isEmpty {
                            groups.append(ClimbGroup(tab: tab, name: name))
                            current = groups.count - 1
                        }
                    }
                    index += markers
                    continue
                }

                for _ in 0..<markers {
                    defer { index += 1 }
                    guard index < ids.count else { continue }
                    let id = ids[index]
                    // A marker that is not an attempt is a climb dropped in from the
                    // library, in a note old enough to carry one. It heads what follows
                    // the way a typed heading does — its name lives on the climb rather
                    // than in the text, so the rows under it go unnamed here.
                    guard attempt(with: id) != nil else {
                        ordinal = 0
                        current = nil
                        continue
                    }
                    ordinal += 1
                    if let current { groups[current].attemptIDs.append(id) }
                    placements[id] = AttemptPlacement(tab: tab,
                                                      climbName: current.map { groups[$0].name },
                                                      ordinal: ordinal)
                }
            }
        }
        return (groups, placements)
    }
}
