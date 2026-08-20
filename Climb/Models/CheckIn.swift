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
    /// One question. `options` run best answer first, every question, so the colour
    /// down the list is always blue at the top and red at the bottom — the shape of a
    /// question is then something you know before you have read it. `quality` runs
    /// index-for-index beside them: 1 is the best answer there is, 0
    /// the worst. None of these numbers are measurements — they are a curve someone
    /// chose — but it is the same curve every time, which is the whole of what a score
    /// like this is for: today against your own last month, not against anyone.
    ///
    /// Five options, and the same five everywhere: none, low, medium, high, severe.
    /// Sleep keeps hours because hours are the one thing on this card you actually
    /// know, but it is the same five steps underneath.
    ///
    /// Every question asks how much of a bad thing you have, which is Hooper's own
    /// design and not a stylistic choice: all four of its items run 1 "very very low
    /// or good" to 7 "very very high or bad". This asked for energy instead of fatigue
    /// for a while, and one item pointing the other way is what made "None" an answer
    /// that read as terrible on a question where it is the best one there is.
    ///
    /// It briefly asked in each question's own words — fine, mild, achy, sore, sharp —
    /// and the trouble with that is that nobody can tell achy from sore. A scale you
    /// cannot answer honestly is worse than a coarse one, because it gets answered
    /// anyway and the noise goes into the score looking like signal. One vocabulary
    /// across all five means the answer is a level rather than a word to be read
    /// differently per question.
    ///
    /// Five steps rather than Hooper's seven, and rather than the four this had for an
    /// afternoon. Seven is the 1995 paper's convention and not a psychometric finding —
    /// four-, five- and seven-point forms come out with much the same reliability, and
    /// the five-point form is the one people complete most readily and skip least. What
    /// the step count buys is resolution, `(options - 1) x questions + 1` distinct
    /// scores: five questions of five is 21 of them, against 13 for four of four. That
    /// is the whole argument for the extra step — a score that cannot move cannot show
    /// you a trend, and a trend is the only thing a number like this is for.
    struct Field {
        /// What the answer is filed under afterwards — one word, for the summary.
        let title: String
        /// The symbol that word travels with, so the four rows can be told apart at a
        /// glance rather than read one at a time.
        let icon: String
        /// What the question actually asks, for the screen it gets to itself.
        let prompt: String
        let options: [String]
        let quality: [Double]

        /// How good one answer to this question was, 0–1, or nothing if it was never
        /// given. What the row it lands on is coloured by: the five steps land one to
        /// a colour, worst to best, red through green and then blue for the top.
        func score(for option: Int) -> Double? {
            quality.indices.contains(option) ? quality[option] : nil
        }
    }

    /// The questions, in the order they are asked and in the order their answers are
    /// stored. Positional: appending is safe, and anything else needs a migration
    /// alongside it — see `migrating`.
    static let fields: [Field] = [
        Field(title: "Sleep",
              icon: "moon.fill",
              prompt: "How long did you sleep?",
              // The ends are where the evidence is: under six is the night that shows
              // up as injury risk, and past eight is the extension the sleep studies
              // measured their gains against. The three in between are just the walk
              // from one to the other.
              options: [">8h", "8h", "7h", "6h", "<6h"],
              quality: [1.00, 0.75, 0.50, 0.25, 0]),
        Field(title: "Fatigue",
              icon: "bolt.fill",
              prompt: "How fatigued are you?",
              options: ["None", "Low", "Medium", "High", "Severe"],
              quality: [1.00, 0.75, 0.50, 0.25, 0]),
        Field(title: "Stress",
              icon: "cloud.fill",
              prompt: "How stressed are you?",
              options: ["None", "Low", "Medium", "High", "Severe"],
              quality: [1.00, 0.75, 0.50, 0.25, 0]),
        Field(title: "Soreness",
              icon: "flame.fill",
              prompt: "How sore are you?",
              options: ["None", "Low", "Medium", "High", "Severe"],
              quality: [1.00, 0.75, 0.50, 0.25, 0]),
        Field(title: "Fingers",
              icon: "hand.raised.fill",
              prompt: "How much finger pain?",
              options: ["None", "Low", "Medium", "High", "Severe"],
              quality: [1.00, 0.75, 0.50, 0.25, 0]),
    ]

    /// Where the question that can overrule the score sits in `fields`.
    static let fingers = 4

    /// What an unanswered question is stored as.
    static let unanswered = -1

    // MARK: - Migration

    /// A stored answer set, read under the current questions.
    ///
    /// Nothing is carried across from the shapes this had before — the questions, the
    /// option counts and the direction of one of them all changed, and there is no
    /// honest way to read an old answer under the new questions. What is left is the
    /// defensive part: a set of the wrong length is padded or cut to fit, and an index
    /// past the end of its question comes back unanswered rather than crashing on it.
    static func migrating(_ stored: [Int]) -> [Int] {
        var answers = stored.prefix(fields.count).map { $0 }
        while answers.count < fields.count { answers.append(unanswered) }
        return zip(answers, fields).map { answer, field in
            field.options.indices.contains(answer) ? answer : unanswered
        }
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

    /// How many of the questions have been answered.
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
        // The bottom two answers, as it has always been — high and severe. Read it off
        // the colour if that is easier: an orange finger or a red one stops the
        // session, a yellow one does not.
        if answers[fingers] >= 3 {
            return Verdict(headline: "Fingers first",
                           advice: "No hangboard, no small crimps. Feet and movement, or take the day.",
                           band: .light)
        }

        let band = band(for: score)
        return Verdict(headline: band.headline, advice: band.advice, band: band)
    }
}
