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
    enum Phase: String {
        case quiz, loading, profile, paywall, tutorial, done

        /// Place in the first run overall, counting the four slides and the fifteen
        /// questions in front of it, so a breakdown of the funnel sorts in the order
        /// the screens are actually walked rather than alphabetically. The quiz holds
        /// 5 through 19 — one per question — and these carry on from the end of it.
        /// 23 is missing on purpose: the purchase sits there, and `Store` reports it,
        /// because what was bought is known there and not here.
        var stepIndex: Int {
            switch self {
            case .quiz: 5
            case .loading: 20
            case .profile: 21
            // Not part of the first run at all. The wall that matters is the foot of
            // the profile screen and there is no way past it but to buy, so this phase
            // is only ever reached by a subscription that has since lapsed.
            case .paywall: 90
            case .tutorial: 23
            // Not a screen — `.done` only means the profile is behind them, which is
            // true whether they bought or declined. It reports nothing.
            case .done: 0
            }
        }

        /// What the screen is called in words, for reading the chart without the source.
        var label: String {
            switch self {
            case .quiz: "Quiz"
            case .loading: "Building your profile"
            case .profile: "Your profile & paywall"
            case .paywall: "Paywall (returning)"
            case .tutorial: "Walkthrough"
            case .done: ""
            }
        }
    }

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
#if DEBUG
    // Flip to true to have a purchase start the flow over instead of ending it.
    static let loopsForDevelopment = false
    #else
    // Release — TestFlight and the App Store — can never carry a development switch,
    // whatever the line above happens to say when a build is cut.
    static let loopsForDevelopment = false
    #endif

    /// Debug: straight past the whole flow into the app, for when the thing being
    /// looked at is the app rather than the way in. Where the flow actually got to is
    /// left written down untouched, so turning this back off comes back to that screen
    /// rather than to a run that has been marked finished.
#if DEBUG
    // Flip to true to jump straight past the first run into the app.
    static let skipsOnboarding = false
    #else
    // Release — TestFlight and the App Store — can never carry a development switch,
    // whatever the line above happens to say when a build is cut.
    static let skipsOnboarding = false
    #endif

    private static let introKey = "onboardingIntroSeen"
    private static let phaseKey = "onboardingPhase"
    private static let quizIndexKey = "onboardingQuizIndex"
    private static let answersKey = "onboardingAnswers"

    private(set) var phase: Phase {
        didSet {
            UserDefaults.standard.set(phase.rawValue, forKey: Self.phaseKey)
            // Every step of the flow reports itself from the one place the flow
            // actually moves, so the funnel has no holes in it and a run that is
            // abandoned mid-way is still the last stage it reached. Observers do not
            // fire for the normalising writes in `init`, so only real moves are sent.
            guard phase != oldValue else { return }
            // The quiz reports itself a question at a time from `QuizView`, which is
            // finer than anything this end can see; every phase past it is one screen.
            // The quiz reports itself a question at a time from `QuizView`, and `.done`
            // is not a screen at all — everything between them is one phase, one screen.
            if phase != .quiz, phase != .done {
                OnboardingAnalytics.step(phase.rawValue, stage: phase.rawValue,
                                         index: phase.stepIndex, label: phase.label)
            }
        }
    }

    /// Whether the opening slideshow has been past. Kept apart from `phase` on purpose:
    /// it is not a step of the flow but the thing in front of all of it, so it shows on
    /// a first launch whatever phase that launch would otherwise have opened on — and
    /// stays gone afterwards whatever the flow does next.
    var hasSeenIntro: Bool {
        didSet { UserDefaults.standard.set(hasSeenIntro, forKey: Self.introKey) }
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

    /// Set the moment onboarding hands the app over, and read once by the session list
    /// on the other side of it. Paying is the end of being asked things and the start of
    /// using the thing — so the app opens on a session already begun rather than on an
    /// empty list with a button on it. Deliberately not written to defaults: it is a
    /// hand-off between two screens in one run, not a fact about the account, and a
    /// relaunch a week later should open on the list like every other launch.
    var startsFirstSession = false

    /// Whether the walkthrough's note has everything in it. Not a phase change of its
    /// own — leaving the tutorial is always a tap — this only decides whether that tap
    /// says Skip or Done. Follows the note in both directions, so emptying it puts the
    /// word back to Skip.
    var tutorialComplete = false

    private init() {
        let defaults = UserDefaults.standard
        hasSeenIntro = defaults.bool(forKey: Self.introKey)
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
        if Self.skipsOnboarding {
            let saved = phase
            phase = .done
            defaults.set(saved.rawValue, forKey: Self.phaseKey)
        }
    }

    /// Past the slideshow, by walking it or by skipping it — the same thing, and it is
    /// meant to be: an intro you cannot decline is an advert.
    func finishIntro() { hasSeenIntro = true }

    /// Out of the quiz into the beat where the answers are made something of.
    func finishQuiz() { phase = .loading }

    /// Out of the fill into the thing it was filling for: the profile the answers
    /// were turned into. The loading screen promises a climbing profile in its first
    /// line — this is the screen that has to exist for that to be true.
    func finishLoading() { phase = .profile }

    /// Out of the goal screen and into the app. The wall used to be the screen after
    /// this one; it is now the bottom of this one, so a purchase made there is the end
    /// of the flow. The paywall itself is still built and still shown — over a sixth
    /// session, and to anybody whose subscription isn't current.
    func finishProfile() { handOff(from: .profile) }

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
    func finishPaywall() { handOff(from: .paywall) }

    /// Out of the last screen of the flow into whatever follows it. When what follows
    /// is the app itself, the first session is asked for on the way through: nothing is
    /// created here — the list is the only place a note is ever made — this only says
    /// that the app is being opened for the first time rather than returned to.
    private func handOff(from phase: Phase) {
        let next = Self.next(after: phase)
        // Off the first-run wall only. `.paywall` is the returning one — a lapsed
        // subscription paid up again — and somebody with a year of sessions behind
        // them reopening the app is not asking to be put in a check-in for the next
        // one; they came back to what they already had.
        if next == .done, phase == .profile { startsFirstSession = true }
        self.phase = next
    }

    /// What follows a screen once the screens that are switched off are stepped over.
    private static func next(after phase: Phase) -> Phase {
        switch phase {
        // Nothing follows the wall but the app itself. The walkthrough is gone — the
        // app is small enough to be read by opening it, and a note that explains a
        // note is a worse first session than a real one.
        case .profile, .paywall: .done
        default: .done
        }
    }

    /// Debug helper: back to the top of the flow. Where you are, and nothing you own —
    /// there is no path in the app that deletes a note without being asked to.
    func reset() {
        // The screens already reported are forgotten first, so a second pass through
        // the flow in one launch reports every one of them again.
        OnboardingAnalytics.reset()
        startsFirstSession = false
        phase = .quiz; quizIndex = 0; answers = [:]; hasSeenIntro = false
    }
}
