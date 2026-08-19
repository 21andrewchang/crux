import Foundation
import UserNotifications

/// The promise the second paywall screen makes: a word before the free trial turns
/// into a charge.
///
/// It is a local notification rather than anything sent from a server, which is the
/// only reason the screen can be honest about it — the trial's length is known at the
/// moment of purchase, so the reminder can be laid down there and then.
enum TrialReminder {
    /// A day's warning. Long enough to cancel without hurrying, short enough that the
    /// trial has actually been used by the time it arrives.
    private static let warning: TimeInterval = 24 * 60 * 60

    private static let id = "trial-ending"

    /// Asks for notifications, and says nothing about the answer: the flow carries on
    /// either way, which is why the screen says "as long as notifications are enabled"
    /// rather than insisting.
    static func ask() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Lays down the reminder for a trial of `length` starting now. A trial shorter
    /// than the warning gets its notice the moment it is half over instead, so a very
    /// short trial is not silently un-reminded.
    static func schedule(trialLength length: TimeInterval) {
        let delay = length > warning ? length - warning : length / 2
        guard delay > 60 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your Crux trial ends tomorrow"
        content.body = "Keep going, or cancel in the App Store before it renews."
        content.sound = .default

        let center = UNUserNotificationCenter.current()
        // Only ever one of these outstanding: a second purchase replaces the reminder
        // from the first rather than stacking on it.
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.add(UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
    }
}
