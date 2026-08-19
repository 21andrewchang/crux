import Foundation

/// The check-in a session opens with: six things you can answer honestly in ten
/// seconds, weighed into one number that says what kind of day today should be.
///
/// Readiness is not training load, and the two are asked at opposite ends of a
/// session. Load is what a session *cost* — the validated form of it is session RPE
/// multiplied by how long the session ran — and none of that can be known until the
/// session is over. Readiness is what you brought *to* it, and it is asked before
/// anything has happened. This is the second one.
enum CheckIn {
    /// One question. `options` read left to right the way the answer scales, and
    /// `quality` runs index-for-index beside them: 1 is the best answer there is, 0
    /// the worst. None of these numbers are measurements — they are weights someone
    /// chose — but they are the same weights every time, which is the whole of what a
    /// score like this is for: today against your own last month, not against anyone.
    struct Field {
        let title: String
        let options: [String]
        let quality: [Double]
        /// How much of the score this question carries. Fingers carry the most: a
        /// tendon is the injury this sport actually hands out, and it is the one
        /// thing here that a good night's sleep does not offset.
        let weight: Double
    }

    /// The questions, in the order they are asked and in the order their answers are
    /// stored. Appending one is safe — an older session answers it blank. Reordering
    /// or removing one is not: the stored answers are positional.
    static let fields: [Field] = [
        Field(title: "Sleep",
              options: ["<5h", "6h", "7h", "8h", "9h+"],
              quality: [0.15, 0.60, 0.85, 1.00, 1.00],
              weight: 0.20),
        Field(title: "Energy",
              options: ["Low", "Fair", "OK", "Good", "Great"],
              quality: [0, 0.25, 0.50, 0.75, 1.00],
              weight: 0.20),
        Field(title: "Fingers",
              options: ["Fine", "Mild", "Achy", "Sore", "Sharp"],
              quality: [1.00, 0.80, 0.55, 0.25, 0],
              weight: 0.25),
        Field(title: "Body",
              options: ["Fresh", "Mild", "Some", "Sore", "Wrecked"],
              quality: [1.00, 0.75, 0.50, 0.25, 0],
              weight: 0.15),
        Field(title: "Skin",
              options: ["Fresh", "Worn", "Thin", "Raw", "Split"],
              quality: [1.00, 0.75, 0.50, 0.25, 0],
              weight: 0.10),
        Field(title: "Drive",
              options: ["Low", "Fair", "OK", "Good", "Great"],
              quality: [0, 0.25, 0.50, 0.75, 1.00],
              weight: 0.10),
    ]

    /// Every question offers exactly five answers, which is what lets the card lay
    /// them out as one grid rather than six ragged rows.
    static let optionCount = 5

    /// Where the two questions that can overrule the score sit in `fields`.
    static let fingers = 2
    static let skin = 4

    /// What an unanswered question is stored as.
    static let unanswered = -1

    /// The score, 0–100 — or nothing at all until every question has an answer. A
    /// partial score would move as the remaining questions were answered, and a
    /// number that climbs while you fill a form in teaches you to game the form.
    static func readiness(_ answers: [Int]) -> Int? {
        guard answers.count == fields.count else { return nil }
        var total = 0.0
        for (field, answer) in zip(fields, answers) {
            guard field.quality.indices.contains(answer) else { return nil }
            total += field.weight * field.quality[answer]
        }
        return Int((total * 100).rounded())
    }

    /// How many of the six have been answered — what the card says instead of a score
    /// while it is still being filled in.
    static func answeredCount(_ answers: [Int]) -> Int {
        zip(fields, answers).filter { field, answer in field.quality.indices.contains(answer) }.count
    }

    struct Verdict {
        /// Two or three words, sitting beside the score.
        let headline: String
        /// What to actually do about it, in one sentence.
        let advice: String
    }

    static func verdict(for answers: [Int]) -> Verdict? {
        guard let score = readiness(answers) else { return nil }

        // Two answers outrank the average. A finger that is already talking to you and
        // skin that has split are specific damage, and no amount of sleep on the other
        // side of the mean makes today the day to load them — which is exactly what a
        // single blended number would otherwise let you conclude.
        if answers[fingers] >= 3 {
            return Verdict(headline: "Fingers first",
                           advice: "No hangboard, no small crimps. Feet and movement, or take the day.")
        }
        if answers[skin] == 4 {
            return Verdict(headline: "Skin is gone",
                           advice: "Jugs, slab, or rest. Nothing sharp today.")
        }

        return switch score {
        case 80...:
            Verdict(headline: "Send day",
                    advice: "Go at the project. This is the day you saved it for.")
        case 60..<80:
            Verdict(headline: "Good to go",
                    advice: "Train as planned. Nothing here to work around.")
        case 40..<60:
            Verdict(headline: "Easy session",
                    advice: "Technique or endurance. Keep the crimp volume down.")
        case 20..<40:
            Verdict(headline: "Light day",
                    advice: "Movement quality only. Nothing anywhere near a limit.")
        default:
            Verdict(headline: "Rest",
                    advice: "Nothing here says train. The session you skip is not the one that hurts you.")
        }
    }
}
