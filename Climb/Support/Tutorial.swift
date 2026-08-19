import Foundation
import Observation
import SwiftData

/// The note every user starts with: a session that explains the bar by setting the
/// bar's own glyphs in its text, so the mark you read is the mark you press.
///
/// It belongs to onboarding and to nothing else: opened on its own, once, and never
/// listed afterwards — what the user writes in it is practice, not their first
/// session. Seeded exactly once, so throwing it away is final rather than something
/// the next launch undoes.
enum Tutorial {
    private static let seededKey = "didSeedFirstSession"

    /// Fixed, so this one note can be picked out of the query — opened by onboarding,
    /// held out of the list — without a column on the model to say so.
    static let id = UUID(uuidString: "5EA71001-0000-4000-A000-000000000001")!

    /// Empty on purpose: the walkthrough's first step is naming the workout, so the
    /// note has to arrive with nothing in it — the title's own placeholder is what
    /// says what a name looks like (see `TutorialGuide`).
    static let bodyText = ""

    /// Set the first time the rest panel is opened. The walkthrough's last step is the
    /// one thing the note cannot record — the panel is a tap in the bar, not a mark in
    /// the document — so it is remembered here instead, or reopening the note would ask
    /// for it again.
    static let restKey = "didOpenTutorialRest"

    /// Set the first time the walkthrough's last step lands. Not what stops it running
    /// — the note itself is the only thing that decides that — only a record that this
    /// copy has been used, so the seeder stops treating its title as one of its own.
    static let finishedKey = "didFinishTutorialWalkthrough"

    /// How earlier builds worded the same note, back when the hints were characters
    /// in it. A copy still reading as one of these was never touched, so it is brought
    /// up to date; an edited one is the user's.
    private static let previousBodies = ["""
    First Session
    Press \u{E000} to add a climb
    Press \u{E001} to add a section
    Press \u{E002} to start an attempt
    """, """
    Tutorial
    Press \u{E000} to add a climb
    Press \u{E001} to add a section
    Press \u{E002} to start an attempt
    """,
    // The name the note carried while the walkthrough started at the section button
    // rather than at the title. Only cleared for someone the walkthrough has not
    // finished with — after that it is just a note that happens to be called this.
    "Tutorial"]

    static func seedIfNeeded(into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ClimbSession>())) ?? []
        // An earlier build seeded this note under a random id, before the list had a
        // reason to recognise it. Adopt that copy rather than seeding a second beside it.
        if let seeded = existing.first(where: { $0.id == id || previousBodies.contains($0.bodyText) }) {
            if previousBodies.contains(seeded.bodyText),
               !UserDefaults.standard.bool(forKey: finishedKey) {
                seeded.bodyText = bodyText
                // The name went with it: the walkthrough's first step is naming the
                // workout, so the copy it is handed has to arrive unnamed.
                seeded.title = ""
                seeded.didSplitTitle = true
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

    // There is deliberately no way to un-seed this note. It starts life as the
    // walkthrough's practice note, but the moment anyone climbs on it it is a note like
    // any other, and nothing that runs on its own at launch should be able to tell the
    // difference. Deleting it is the user's to do, from the list, like any other note.
}

/// Walks the tutorial note through the bar one button at a time: a single instruction
/// on screen, and only the button that carries it out in the bar. Everything the user
/// has not been told about yet is simply not there, so there is never more than one
/// thing to press.
///
/// A step is done when the thing it asks for is *in the note* — a named section, a
/// named climb, a recorded attempt — read back out of the document rather than counted
/// as taps, so it is the result that advances the walkthrough and not the gesture.
/// Which also means it is never anywhere the note doesn't say it is: delete the climb
/// and the walkthrough is back to asking for one, empty the note and it is back at the
/// beginning. Nothing is remembered but the note itself.
///
/// All but the last step, which leaves nothing behind in the note at all: opening the
/// rest panel is a tap and only a tap. That one is written down (`Tutorial.restKey`),
/// so it is asked for once and never again.
@Observable
final class TutorialGuide {
    /// What the note is missing, in the order it is asked for. `done` is also every
    /// other note in the app: nothing hidden, nothing prompted.
    enum Step: Int { case title, section, climb, attempt, rest, done }

    /// How far along a heading the note is: never pressed, pressed but still empty,
    /// or written in. The middle one is a step of its own — the button has been found
    /// and the ask is now the name — so the instruction changes rather than sitting
    /// there telling you to press what you just pressed.
    enum Heading { case missing, unnamed, named }

    private(set) var step: Step

    /// The step's ask is a name, not a button press.
    private(set) var needsName = false

    /// How far through the walkthrough the note is, counting the halves: pressing the
    /// button and then naming what it made are two asks answered, not one, and this
    /// climbs by one for each. Whatever watches it can tell being carried forward from
    /// being walked back, without knowing what the asks are.
    var reached: Int { step.rawValue * 2 + (needsName ? 1 : 0) }

    /// Whether this note is the one the walkthrough follows at all. Every other note
    /// in the app is left alone: full bar, no instructions, nothing to re-read on an
    /// edit.
    let tracksNote: Bool

    /// Whether the walkthrough is showing anything right now. `done` is the note
    /// having everything — until something is deleted back out of it.
    var isRunning: Bool { tracksNote && step != .done }

    /// A button the walkthrough has not asked for yet stays in the bar — the shape of
    /// the bar never changes, so nothing shifts under the finger — but it is dark
    /// enough to read as not-yet-there, and it doesn't answer a tap. The whole bar is
    /// dark until the workout has a name: the note is the first thing to write.
    var isSectionUnlocked: Bool { step.rawValue >= Step.section.rawValue }
    var isClimbUnlocked: Bool { step.rawValue >= Step.climb.rawValue }
    var isAttemptUnlocked: Bool { step.rawValue >= Step.attempt.rawValue }
    /// The rest timer is the one button that has already done something before it is
    /// pressed: it starts itself the moment the first attempt is recorded, which is the
    /// moment the walkthrough turns to it. Dark until then.
    var isRestUnlocked: Bool { step.rawValue >= Step.rest.rawValue }

    /// Barely a glyph: enough to see the bar has more in it, not enough to reach for.
    /// One number for both bars, and the reason every locked button is held back by
    /// `allowsHitTesting` rather than `disabled`: disabling dims a second time, by an
    /// amount of the system's choosing that differs between the real bar and the
    /// keyboard clone, which is exactly how the two drifted apart. Nothing dims these
    /// now but this.
    ///
    /// The number is what the clone was already landing on once its own double-dim
    /// was measured off a screenshot — 12% dimmed again by the disabled state — so
    /// this is that look, held on purpose instead of by accident.
    static let lockedOpacity: Double = 0.055

    /// Whether the rest panel has been opened at least once. The last step's only
    /// record — see the note on the class.
    private var didOpenRest = UserDefaults.standard.bool(forKey: Tutorial.restKey)

    init(session: ClimbSession) {
        let tracks = session.id == Tutorial.id
        tracksNote = tracks
        step = tracks ? .title : .done
    }

    /// The rest panel opened. Ends the walkthrough if it was what was being asked for,
    /// and is remembered either way, so emptying the note out and starting over does not
    /// ask for this one a second time.
    func restOpened() {
        guard tracksNote, !didOpenRest else { return }
        didOpenRest = true
        UserDefaults.standard.set(true, forKey: Tutorial.restKey)
        guard step == .rest else { return }
        step = .done
        Onboarding.shared.tutorialComplete = true
    }

    /// Re-read from the document on every edit. The step follows what the note says
    /// in both directions: delete the climb you just added and the walkthrough goes
    /// back to asking for one, rather than standing there asking for the next thing.
    func update(hasTitle: Bool, section: Heading, climb: Heading, hasAttempt: Bool) {
        guard tracksNote else { return }
        step = !hasTitle ? .title
            : section != .named ? .section
            : climb != .named ? .climb
            : !hasAttempt ? .attempt
            : !didOpenRest ? .rest : .done
        needsName = step == .section && section == .unnamed
            || step == .climb && climb == .unnamed
        // Noted the first time the note is whole — not to stop the walkthrough, which
        // is free to come back if the note is emptied again, but so the seeder knows
        // this note has been lived in and leaves its title alone. Read off the note
        // alone: the rest panel is a step past everything the note can hold.
        if hasAttempt { UserDefaults.standard.set(true, forKey: Tutorial.finishedKey) }
        // Onboarding's corner word follows the same reading of the note: Skip until
        // every part of the bar has been used, Done after — and back to Skip if the
        // note is emptied out again.
        Onboarding.shared.tutorialComplete = step == .done
    }
}
