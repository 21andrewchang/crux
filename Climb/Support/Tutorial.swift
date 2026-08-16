import Foundation
import SwiftData

/// The note every user starts with: a session that explains the bar by setting the
/// bar's own glyphs in its text, so the mark you read is the mark you press.
///
/// It is an ordinary session in every other way — editable, deletable — and it is
/// seeded exactly once, so throwing it away is final rather than something the next
/// launch undoes.
enum Tutorial {
    private static let seededKey = "didSeedFirstSession"

    /// Fixed, so the list can pick this one note out of the query and pin it to the
    /// top without a column on the model to say so.
    static let id = UUID(uuidString: "5EA71001-0000-4000-A000-000000000001")!

    /// The first line is the title, the way it is in any note.
    static let bodyText = """
    Tutorial
    Press \u{E000} to add a climb
    Press \u{E001} to add a section
    Press \u{E002} to start an attempt
    """

    /// How earlier builds worded the same note. A copy still reading as one of these
    /// was never touched, so it is brought up to date; an edited one is the user's.
    private static let previousBodies = ["""
    First Session
    Press \u{E000} to add a climb
    Press \u{E001} to add a section
    Press \u{E002} to start an attempt
    """]

    static func seedIfNeeded(into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ClimbSession>())) ?? []
        // An earlier build seeded this note under a random id, before the list had a
        // reason to recognise it. Adopt that copy rather than seeding a second beside it.
        if let seeded = existing.first(where: { $0.id == id || previousBodies.contains($0.bodyText) }) {
            if previousBodies.contains(seeded.bodyText) {
                seeded.bodyText = bodyText
                seeded.id = id
                try? context.save()
            }
            return
        }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seededKey) else { return }
        // Written before the insert: a save that fails is not worth showing the note
        // twice over.
        defaults.set(true, forKey: seededKey)

        let session = ClimbSession()
        session.id = id
        session.bodyText = bodyText
        context.insert(session)
        try? context.save()
    }
}
