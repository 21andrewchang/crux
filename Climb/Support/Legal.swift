import Foundation

/// The two links the App Store requires a subscription screen to carry, and will
/// reject the app for not carrying: terms of use and a privacy policy, both reachable
/// from the paywall itself rather than only from the store listing.
///
/// **These have to point at pages that exist before submitting.** Apple opens them.
/// The terms link may be Apple's own standard EULA if no custom terms are written;
/// the privacy policy must be a page of your own, and the same URL goes into App Store
/// Connect.
enum Legal {
    /// Apple's standard licence, which is the right answer unless custom terms are
    /// actually wanted — it is the EULA the app is shipped under by default anyway.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// TODO: replace with the real privacy policy before submitting. This one is a
    /// placeholder and will fail review.
    static let privacy = URL(string: "https://example.com/crux/privacy")!
}
