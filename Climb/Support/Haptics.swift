import UIKit

/// The taps the app answers with, in one place so the same event feels the same
/// wherever it happens.
enum Haptics {
    /// Kept alive rather than made on the spot. The engine takes a moment to wake, and a
    /// generator built and fired in the same breath can be missed entirely — which is
    /// what swallowed the tap when an attempt landed, the one moment the phone had just
    /// been busy with the camera.
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)

    /// Something the walkthrough asked for has been done. One knock, heavier than the
    /// tap a choice gets in the quiz — answering an ask is worth more than picking an
    /// option, and there is no sound to carry it.
    static func stepDone() {
        // Always from the main thread, and always left warm for the next one.
        if Thread.isMainThread {
            fire()
        } else {
            DispatchQueue.main.async(execute: fire)
        }
    }

    private static func fire() {
        heavy.impactOccurred()
        heavy.prepare()
    }

    /// Warms the engine so the first tap of a run lands as hard as the rest.
    static func warmUp() {
        heavy.prepare()
    }

    /// Kept warm for the same reason as the knock above: the pills are tapped in
    /// quick succession, and the first of a run must feel like the rest.
    private static let selector = UISelectionFeedbackGenerator()

    /// Something has been picked out of a row of choices — turning to a page of the
    /// note. The lightest tap there is: a page turn is a move, not an achievement.
    static func selection() {
        selector.selectionChanged()
        selector.prepare()
    }
}
