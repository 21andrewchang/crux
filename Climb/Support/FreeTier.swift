import Foundation

/// What the app gives away.
///
/// Crux is free to use rather than free to try: there is no clock running and nothing
/// expires. What is capped is how many sessions are kept at once. Under the cap the app
/// is whole — every feature, nothing withheld, no nag — and the wall arrives only when
/// someone reaches for one more session than they are allowed, which is to say after
/// they have used the thing enough to know whether it is worth paying for.
///
/// A cap on what is kept, rather than a trial on how long the app has been installed,
/// is also the version with no state of its own: nothing written down at first launch,
/// so nothing to hide in the Keychain, and nothing a delete-and-reinstall can put back.
/// The limit is the data, and the data is already there to be counted.
enum FreeTier {
    /// How many of the user's own sessions are kept without a subscription.
    ///
    /// Five rather than three because the part worth paying for is not writing a
    /// session down, it is opening one from three weeks ago and watching the attempt
    /// back. At three they would be deleting to make room before any session ever got
    /// old enough for that to have happened.
    static let sessionLimit = 5

    /// Whether another session can be started.
    ///
    /// The seeded notes are not counted against anyone: the walkthrough belongs to
    /// onboarding and the goal note is a page of the app rather than something the user
    /// made, so neither eats into what they get. `ownSessions` in the list is already
    /// exactly this set, which is what should be handed in here.
    static func allowsAnotherSession(ownSessionCount: Int, isPro: Bool) -> Bool {
        isPro || ownSessionCount < sessionLimit
    }

    /// How many are left, for saying so before the wall is hit. Zero once the cap is
    /// reached, and never negative — a session count over the limit is what someone who
    /// let a subscription lapse looks like, and that is not a debt to show them.
    static func remaining(ownSessionCount: Int) -> Int {
        max(0, sessionLimit - ownSessionCount)
    }
}
