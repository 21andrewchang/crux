import Foundation
import SwiftData

/// One thing in a note: a section, a climb, an attempt, or a paragraph.
///
/// The note used to be a string that its own structure was guessed from — a climb was
/// a `\u{FFF9}` sentinel on a line, and which climb an attempt belonged to was
/// whichever heading happened to sit above it in the text. This is that structure
/// written down: a block knows its parent, so grouping is a pointer rather than a scan,
/// and moving a climb carries its attempts because they hang off it.
///
/// The tree is at most three deep — section → climb → leaf — which is the shape the
/// old fold logic already scanned for. Nothing nests further: a section holds climbs
/// and prose, a climb holds attempts and prose, and neither holds another of itself.
@Model
final class NoteBlock {
    var id: UUID = UUID()

    /// `Kind.rawValue`. Stored raw so a block written by a later build — one that
    /// knows a kind this one doesn't — loads as `.prose` instead of failing.
    var kindRaw: String = Kind.prose.rawValue

    /// Position among its siblings. Explicit rather than leaning on the relationship
    /// array's order, which SwiftData does not promise to keep.
    var order: Int = 0

    /// The block's own words: a section or climb's name, or a paragraph. Empty for an
    /// attempt, whose text is the attempt's — this is the only place text lives, and
    /// the only place a caret can go.
    var text: String = ""

    /// Whether this block's children are drawn. A fold is now nothing but this: the
    /// children aren't rendered. No hidden text, so no caret can land in them.
    var isFolded: Bool = false

    /// Which page of the note this block is on. `NoteTab.rawValue`; only meaningful on
    /// a top-level block, since a child is on whatever page its parent is.
    var tabRaw: Int = NoteTab.main.rawValue

    var parent: NoteBlock?

    /// Cascade: a climb taken out of the note takes its attempts' blocks with it. The
    /// `Attempt` records themselves are not touched — those are deleted deliberately,
    /// through the confirmation, because a recording cannot be made again.
    @Relationship(deleteRule: .cascade, inverse: \NoteBlock.parent)
    var children: [NoteBlock] = []

    /// Set on top-level blocks only; a child reaches the session through its parent.
    var session: ClimbSession?

    /// The library climb this block names, for a `.climb`. This is what makes an
    /// attempt's climb a relationship instead of a reading of the prose above it.
    var climb: Climb?

    /// The go this block stands for, for an `.attempt`.
    var attempt: Attempt?

    init(kind: Kind, tab: NoteTab = .main, order: Int = 0, text: String = "") {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.tabRaw = tab.rawValue
        self.order = order
        self.text = text
    }

    /// What a block is. Raw strings rather than an integer so a store dumped to SQL
    /// reads without a lookup table.
    enum Kind: String {
        /// The largest break a note has — "Warmup". Holds climbs and prose.
        case section
        /// A problem worked. Holds attempts and prose, and points at a `Climb`.
        case climb
        /// One go, drawn as the inline row. Holds nothing.
        case attempt
        /// A written line. Holds nothing.
        case prose
    }

    /// Unknown kinds read as prose: a block is always *something* on the page, and a
    /// paragraph is the kind that loses the least by being wrong.
    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .prose }
        set { kindRaw = newValue.rawValue }
    }

    var tab: NoteTab {
        get { NoteTab(rawValue: tabRaw) ?? .main }
        set { tabRaw = newValue.rawValue }
    }

    /// Whether this kind can hold anything. Only the two heading kinds group.
    var groups: Bool { kind == .section || kind == .climb }

    /// The children in the order they are written, which is the order they are drawn.
    var orderedChildren: [NoteBlock] {
        children.sorted { $0.order < $1.order }
    }

    /// The climb this block is filed under: its own, if it is one, else its parent's.
    /// What `Attempt.climb` is set from, rather than read off the note.
    var owningClimb: Climb? {
        kind == .climb ? climb : parent?.climb
    }
}
