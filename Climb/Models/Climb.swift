import Foundation
import SwiftData

/// A route or boulder problem you can come back to.
///
/// Sessions and attempts are per-visit; a climb outlives both. Dropping a saved climb
/// into a session note links the attempts that follow it, so the climb accumulates
/// every go you have ever taken on it — that is what makes repeating one meaningful.
@Model
final class Climb {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()

    /// Nullify, not cascade: the attempts belong to their sessions. Retiring a climb
    /// from the library must not delete the videos it was tagged on.
    @Relationship(deleteRule: .nullify, inverse: \Attempt.climb)
    var attempts: [Attempt] = []

    init(name: String, createdAt: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
    }

    /// Newest first — the history reads backwards from the most recent go.
    var orderedAttempts: [Attempt] {
        attempts.sorted { $0.createdAt > $1.createdAt }
    }

    var lastAttemptAt: Date? {
        attempts.map(\.createdAt).max()
    }

    /// How many separate sessions this climb turns up in — the repeat count.
    var sessionCount: Int {
        Set(attempts.compactMap { $0.session?.id }).count
    }

    /// "7 attempts · 3 sessions" — the subtitle on the inline row and the picker.
    var summary: String {
        guard !attempts.isEmpty else { return "No attempts yet" }
        let goes = "\(attempts.count) attempt\(attempts.count == 1 ? "" : "s")"
        let sessions = sessionCount
        guard sessions > 1 else { return goes }
        return "\(goes) · \(sessions) sessions"
    }

    /// Sorted the way the picker lists them: most recently climbed first, then newest
    /// saved. Keeps whatever you are actually working on at the top of the list.
    static func recencySorted(_ climbs: [Climb]) -> [Climb] {
        climbs.sorted { left, right in
            let leftDate = left.lastAttemptAt ?? left.createdAt
            let rightDate = right.lastAttemptAt ?? right.createdAt
            if leftDate != rightDate { return leftDate > rightDate }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }
}
