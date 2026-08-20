import Foundation
import Observation

/// First-run flow: a quiz, then a hard paywall, then the interactive tutorial note.
///
/// The wall goes before the walkthrough rather than after it, which is the order the
/// two screens are actually worth something in: the quiz is what builds any reason to
/// pay, and every screen between that and the asking spends it. The walkthrough on the
/// far side stops being a free look at the product and becomes the first thing done
/// with it — which is what a trial has to be used for to be worth renewing.
///
/// Where the user got to is written down as they go, so a launch that lands in the
/// middle of the flow opens on the screen they left rather than at the top: the phase,
/// and inside the quiz the question itself. Only `isComplete` is behind them for good.
@Observable
final class Onboarding {
    enum Phase: String { case quiz, loading, profile, paywall, tutorial, done }

    static let shared = Onboarding()

    /// Whether the walkthrough is in the flow at all. Off, the paywall is the last
    /// screen of onboarding and paying opens the app itself. The tutorial, its seeded
    /// note and the host that puts it on screen are all still here and still work —
    /// this only decides whether the flow goes through them.
    static let showsTutorial = false

    /// Whether the flow ends on the paywall at all. Off, the walkthrough hands
    /// straight over to the app — the screen and everything behind it (`Store`,
    /// the products, the purchase) is still here, just not in the way while the
    /// rest of onboarding is being worked on.
    static let showsPaywall = true

    /// Off: a purchase opens the app, which is what it is for. On, it starts the run
    /// over from the quiz instead, so the flow can be walked end to end as many times as
    /// it takes without reinstalling between passes — one line to flip while onboarding
    /// is what is being worked on. It puts back only where you are in the flow: whatever
    /// the last pass left in the practice note is still there at the start of the next.
    static let loopsForDevelopment = false

    private static let phaseKey = "onboardingPhase"
    private static let quizIndexKey = "onboardingQuizIndex"
    private static let answersKey = "onboardingAnswers"

    private(set) var phase: Phase {
        didSet { UserDefaults.standard.set(phase.rawValue, forKey: Self.phaseKey) }
    }

    /// Whether the first run is behind them — the one thing the rest of the app asks.
    /// Everything else here is only about where inside the flow they stopped.
    var isComplete: Bool { phase == .done }

    /// The question the quiz is on. It stays where the quiz was left even after the
    /// quiz is done, so quitting mid-way comes back to the right screen and stepping
    /// back out of the walkthrough lands on the last question rather than the first.
    /// Only a full `reset` puts it back to the beginning.
    var quizIndex = 0 {
        didSet { UserDefaults.standard.set(quizIndex, forKey: Self.quizIndexKey) }
    }

    /// What the quiz answered. Nothing reads it yet, but it is kept so the answers
    /// given before a relaunch are not asked for twice.
    var answers: [String: String] = [:] {
        didSet { UserDefaults.standard.set(answers, forKey: Self.answersKey) }
    }

    /// Whether the walkthrough's note has everything in it. Not a phase change of its
    /// own — leaving the tutorial is always a tap — this only decides whether that tap
    /// says Skip or Done. Follows the note in both directions, so emptying it puts the
    /// word back to Skip.
    var tutorialComplete = false

    private init() {
        let defaults = UserDefaults.standard
        phase = defaults.string(forKey: Self.phaseKey).flatMap(Phase.init) ?? .quiz
        quizIndex = defaults.integer(forKey: Self.quizIndexKey)
        var saved = defaults.dictionary(forKey: Self.answersKey) as? [String: String] ?? [:]
        // The middle rung of the hang question dropped its "=" — an answer given before
        // that is the same answer and is rewritten rather than left as a row the quiz
        // no longer offers, which would come back unticked and read out with the sign
        // still on it.
        if saved["hang"] == "= Bodyweight" {
            saved["hang"] = "Bodyweight"
            defaults.set(saved, forKey: Self.answersKey)
        }
        answers = saved
        // Someone left standing on the paywall by an earlier build is let through to
        // the walkthrough rather than held on a screen that is no longer shown.
        if !Self.showsPaywall, phase == .paywall { phase = Self.showsTutorial ? .tutorial : .done }
        // Likewise for anyone left standing in the walkthrough by an earlier build.
        if !Self.showsTutorial, phase == .tutorial { phase = .done }
    }

    /// Out of the quiz into the beat where the answers are made something of.
    func finishQuiz() { phase = .loading }

    /// Out of the fill into the thing it was filling for: the profile the answers
    /// were turned into. The loading screen promises a climbing profile in its first
    /// line — this is the screen that has to exist for that to be true.
    func finishLoading() { phase = .profile }

    func finishProfile() { phase = Self.showsPaywall ? .paywall : Self.next(after: .paywall) }

    /// Back out of the walkthrough into the quiz — onto its last question. The index is
    /// left where the quiz ended for exactly this: back is one step back, not a return
    /// to the beginning. It skips back over the paywall, which is behind them for good
    /// once it has been answered.
    func backToQuiz() { phase = .quiz }

    /// Leaving the walkthrough — Skip and Done are the same door, one taken early, and
    /// both open on the app itself. This is the end of the flow now.
    func leaveTutorial() { phase = .done }

    /// Paid, and into the walkthrough — or, with the walkthrough out of the flow,
    /// straight into the app, which is what was just bought.
    func finishPaywall() { phase = Self.next(after: .paywall) }

    /// What follows a screen once the screens that are switched off are stepped over.
    private static func next(after phase: Phase) -> Phase {
        switch phase {
        case .paywall: showsTutorial ? .tutorial : .done
        default: .done
        }
    }

    /// Debug helper: back to the top of the flow. Where you are, and nothing you own —
    /// there is no path in the app that deletes a note without being asked to.
    func reset() { phase = .quiz; quizIndex = 0; answers = [:] }
}
