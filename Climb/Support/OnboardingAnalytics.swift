import Foundation
import PostHog

/// Every screen of the first run, reported the moment it is reached.
///
/// One event per screen, named `onboarding_<place>_<screen>` — `onboarding_01_intro_1`
/// through `onboarding_21_profile`. The place is in the name because event lists sort
/// alphabetically, so numbering them is what makes a list of them read in walking order.
///
/// Arrival rather than completion, which is the part that matters: a screen that only
/// reports itself once it is finished cannot show the screen somebody quit on, because
/// quitting is precisely the case where the event never fires. Reporting on the way in
/// means the last event a person sent *is* the place they stopped.
enum OnboardingAnalytics {
    /// Screens already reported this launch. Stepping back and forward through the quiz
    /// is one visit to each question, not several — the funnel counts people who reached
    /// a screen, and reaching it twice is still one person.
    private static var seen: Set<String> = []

    /// - Parameters:
    ///   - step: machine name, stable across releases — what the funnel is built on.
    ///   - stage: which part of the flow it belongs to, for reading drop-off by section.
    ///   - index: place in the flow overall, so a breakdown sorts in walking order
    ///     rather than alphabetically.
    ///   - label: the words actually on screen, so the chart is readable by someone who
    ///     has never seen the source.
    static func step(_ step: String, stage: String, index: Int, label: String) {
        guard !seen.contains(step) else { return }
        seen.insert(step)
        // A screen is an event of its own rather than one shared event carrying a name
        // in a property. It costs a longer list of event names, and it buys the thing
        // that list is read with: a funnel step is picked straight out of the event
        // list, no filter to add per step and none to get wrong.
        //
        // Numbered, because that list is sorted alphabetically wherever it is shown —
        // so the names themselves put the screens in the order they are walked.
        let name = "onboarding_\(String(format: "%02d", index))_\(step)"
        PostHogSDK.shared.capture(name, properties: [
            "stage": stage,
            "step_index": index,
            "label": label,
        ])
    }

    /// Into the app, once and once only.
    ///
    /// Sent from the moment the session list is actually on screen rather than from the
    /// flow being marked done, which happens a screen too early: leaving the profile is
    /// not the same as getting past the wall, and somebody who declined is still outside
    /// looking at the second one. Written down rather than held in memory, because every
    /// launch after the first one opens on the list too, and "finished onboarding" is a
    /// thing that happens to a person once.
    private static let completedKey = "onboardingCompletionReported"

    static func completed() {
        guard !UserDefaults.standard.bool(forKey: Self.completedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        PostHogSDK.shared.capture("onboarding_completed")
    }

    /// Walking the flow again in one launch — `-resetOnboarding`, or the development
    /// loop — is a fresh run and reports every screen again rather than staying quiet
    /// because this launch has already seen them.
    static func reset() {
        seen.removeAll()
        UserDefaults.standard.set(false, forKey: Self.completedKey)
    }
}
