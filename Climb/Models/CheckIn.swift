import Foundation

/// The check-in a session opens with: four things you can answer honestly in ten
/// seconds, averaged into one number that says what kind of day today should be.
///
/// Readiness is not training load, and the two are asked at opposite ends of a
/// session. Load is what a session *cost* — the validated form of it is session RPE
/// multiplied by how long the session ran — and none of that can be known until the
/// session is over. Readiness is what you brought *to* it, and it is asked before
/// anything has happened. This is the second one.
///
/// The four are the Hooper Index's, less its stress item, plus the one this sport
/// needs. Hooper asks sleep, stress, fatigue and muscle soreness, sums them
/// unweighted, and has been the standard wellness questionnaire in sport for thirty
/// years — it tracks match-fatigue recovery more sensitively than heart rate
/// variability does. Fingers is the addition: a tendon is the injury climbing
/// actually hands out, it is not muscle soreness, and nothing else here would catch
/// it. Stress is the one worth adding back first if this ever grows.
enum CheckIn {
    /// One question. `options` read left to right the way the answer scales, and
    /// `quality` runs index-for-index beside them: 1 is the best answer there is, 0
    /// the worst. None of these numbers are measurements — they are a curve someone
    /// chose — but it is the same curve every time, which is the whole of what a score
    /// like this is for: today against your own last month, not against anyone.
    ///
    /// Five options rather than three. The reason is range: a three-point scale hits
    /// its own ends inside a fortnight and then reads the same every day, and a score
    /// that cannot move cannot show you a trend, which is the only thing it is for.
    /// What five options cost is reading, and that is paid for in the card rather than
    /// here — only the answer you are on is ever drawn.
    struct Field {
        /// What the answer is filed under afterwards — one word, for the summary.
        let title: String
        /// What the question actually asks, for the screen it gets to itself.
        let prompt: String
        let options: [String]
        let quality: [Double]
    }

    /// The questions, in the order they are asked and in the order their answers are
    /// stored. Positional: appending is safe, and anything else needs a migration
    /// alongside it — see `migrating`.
    static let fields: [Field] = [
        Field(title: "Sleep",
              prompt: "How long did you sleep?",
              options: ["<5h", "6h", "7h", "8h", "9h+"],
              quality: [0.15, 0.60, 0.85, 1.00, 1.00]),
        Field(title: "Energy",
              prompt: "How's your energy?",
              options: ["Low", "Fair", "OK", "Good", "Great"],
              quality: [0, 0.25, 0.50, 0.75, 1.00]),
        Field(title: "Soreness",
              prompt: "How sore are you?",
              options: ["Fresh", "Mild", "Some", "Sore", "Wrecked"],
              quality: [1.00, 0.75, 0.50, 0.25, 0]),
        Field(title: "Fingers",
              prompt: "How do your fingers feel?",
              options: ["Fine", "Mild", "Achy", "Sore", "Sharp"],
              quality: [1.00, 0.80, 0.55, 0.25, 0]),
    ]

    /// Every question offers exactly five answers, which is what lets the card lay
    /// them out as one grid rather than four ragged rows.
    static let optionCount = 5

    /// Where the question that can overrule the score sits in `fields`.
    static let fingers = 3

    /// What an unanswered question is stored as.
    static let unanswered = -1

    // MARK: - Migration

    /// How many answers a session stored back when the check-in asked six questions:
    /// sleep, energy, fingers, body, skin, drive.
    private static let legacyCount = 6

    /// Which of those six each of today's four was, so an old session's answers land
    /// under the questions they were actually given. Body became Soreness — the same
    /// question under the name Hooper gives it — and the two that went are skin, which
    /// is a comfort constraint rather than an injury one, and drive, which turned out
    /// to be a readout of the other five rather than an input of its own.
    private static let legacyIndex = [0, 1, 3, 2]

    /// An old session's answers, read under the current questions.
    ///
    /// Told apart by count alone, which is enough: six is the only other shape these
    /// have ever had. A session storing anything else is one the card never finished,
    /// and it is padded out with blanks rather than guessed at.
    static func migrating(_ stored: [Int]) -> [Int] {
        if stored.count == legacyCount {
            return legacyIndex.map { stored[$0] }
        }
        var answers = stored.prefix(fields.count).map { $0 }
        while answers.count < fields.count { answers.append(unanswered) }
        return answers
    }

    // MARK: - Scoring

    /// The score, 0–100 — or nothing at all until every question has an answer. A
    /// partial score would move as the remaining questions were answered, and a
    /// number that climbs while you fill a form in teaches you to game the form.
    ///
    /// A plain average, deliberately. The weighted version this replaces was inventing
    /// its own coefficients, and the literature is clear that weighting a wellness
    /// questionnaire does not make it more sensitive than summing it — Hooper has been
    /// an unweighted sum since 1995. What the weights were really trying to say was
    /// that fingers matter more, and that belongs in `verdict` as a rule that can stop
    /// a session outright, not smeared into a mean where a good night's sleep can
    /// average it away.
    static func readiness(_ answers: [Int]) -> Int? {
        guard answers.count == fields.count else { return nil }
        var total = 0.0
        for (field, answer) in zip(fields, answers) {
            guard field.quality.indices.contains(answer) else { return nil }
            total += field.quality[answer]
        }
        return Int((total / Double(fields.count) * 100).rounded())
    }

    /// How many of the four have been answered.
    static func answeredCount(_ answers: [Int]) -> Int {
        zip(fields, answers).filter { field, answer in field.quality.indices.contains(answer) }.count
    }

    /// What a score comes to, as one of five. The thresholds live here and nowhere
    /// else: the words, the colour the number is drawn in, and the advice underneath
    /// are all read off this, so they cannot drift apart from each other.
    enum Band {
        case send, good, easy, light, rest

        var headline: String {
            switch self {
            case .send: "Send day"
            case .good: "Good to go"
            case .easy: "Easy session"
            case .light: "Light day"
            case .rest: "Rest"
            }
        }

        var advice: String {
            switch self {
            case .send: "Go at the project. This is the day you saved it for."
            case .good: "Train as planned. Nothing here to work around."
            case .easy: "Technique or endurance. Keep the crimp volume down."
            case .light: "Movement quality only. Nothing anywhere near a limit."
            case .rest: "Nothing here says train. The session you skip is not the one that hurts you."
            }
        }
    }

    static func band(for score: Int) -> Band {
        switch score {
        case 80...: .send
        case 60..<80: .good
        case 40..<60: .easy
        case 20..<40: .light
        default: .rest
        }
    }

    struct Verdict {
        /// Two or three words, sitting beside the score.
        let headline: String
        /// What to actually do about it, in one sentence.
        let advice: String
        /// Which band the number is drawn in — the band the score falls in, except
        /// where a finger overrules it.
        let band: Band
    }

    static func verdict(for answers: [Int]) -> Verdict? {
        guard let score = readiness(answers) else { return nil }

        // One answer outranks the average. A finger that is already talking to you is
        // specific damage, and no amount of sleep on the other side of the mean makes
        // today the day to load it — which is exactly what a single blended number
        // would otherwise let you conclude. It takes the colour with it: a number
        // drawn green over "no hangboard, no small crimps" is the card arguing with
        // itself, and the colour is the half that gets read first.
        if answers[fingers] >= 3 {
            return Verdict(headline: "Fingers first",
                           advice: "No hangboard, no small crimps. Feet and movement, or take the day.",
                           band: .light)
        }

        let band = band(for: score)
        return Verdict(headline: band.headline, advice: band.advice, band: band)
    }
}
