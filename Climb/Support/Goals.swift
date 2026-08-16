import Foundation
import SwiftData

/// The goal note: one document, pinned above the weeks in the list, holding what the
/// user is working toward.
///
/// It is a `ClimbSession` like every other note — same editor, same climbs, same
/// attempts if they ever want them — so nothing new has to be taught to open it. What
/// makes it the goal page is only its fixed id: that is how the list picks it out to
/// pin it, and how onboarding finds it to write the answers into.
///
/// Unlike the tutorial note, this one is not seeded once and then gone for good. It is
/// a page of the app rather than a note someone happened to make, so a missing copy —
/// deleted, or never seeded because the app was installed before there was a goal
/// page — is simply written again on the next launch.
enum Goals {
    /// Whether the card shows above the weeks in the list. Off, the note is still
    /// seeded and still written to — onboarding's answers have somewhere to land — it
    /// just isn't on screen yet. One line to flip when the page is ready to show.
    static let isPinned = false

    /// Fixed, so this one note can be found without a column on the model saying so.
    static let id = UUID(uuidString: "5EA71001-0000-4000-A000-000000000002")!

    /// The note's title, which — Apple Notes style — is nothing but its first line.
    static let title = "Goals"

    /// Empty but for the title: the page is written by onboarding and by the user,
    /// and starts out saying only what it is.
    static let bodyText = title

    /// What the list shows under the title while nothing has been written yet.
    static let placeholder = "What you're working toward"

    static func seedIfNeeded(into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ClimbSession>())) ?? []
        guard !existing.contains(where: { $0.id == Self.id }) else { return }

        let goal = ClimbSession()
        goal.id = Self.id
        goal.bodyText = bodyText
        context.insert(goal)
        try? context.save()
    }

    /// The goal note, if it is there yet. One frame at first launch has it missing —
    /// the seed lands in a task — and callers show nothing in its place rather than
    /// standing in for it.
    static func note(in sessions: [ClimbSession]) -> ClimbSession? {
        sessions.first { $0.id == Self.id }
    }
}
