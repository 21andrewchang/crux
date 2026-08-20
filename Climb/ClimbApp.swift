import SwiftUI
import SwiftData
import UIKit
import PostHog

// PostHog configuration.
// The project token is a public client-side key — it ships in the binary, which is
// the recommended approach for iOS. The host value is also embedded so the SDK can
// always reach its servers regardless of how the app is launched.
private let posthogProjectToken = "phc_Ayc7VNr8hc7hCoU6CBCwDTgoefmVxjcmg9RcpqZbXD4n"
private let posthogHost = "https://us.i.posthog.com"

@main
struct ClimbApp: App {
    init() {
        // PostHog: set up analytics once, as early as possible, before any event
        // capture. The token and host ship in the binary so analytics work in all
        // build flavors — debug, TestFlight, and App Store.
        let config = PostHogConfig(projectToken: posthogProjectToken, host: posthogHost)
        config.captureApplicationLifecycleEvents = true
        // Replay is off for the first release. It records the screen rather than only
        // what was tapped, which is a different thing to have to declare on the App
        // Store privacy card and a different thing to ask somebody to agree to — and
        // nothing in the first version needs it to answer the questions being asked of
        // it. Turning it back on is these two lines and the project's own switch:
        //   config.sessionReplay = true
        //   config.sessionReplayConfig.screenshotMode = true
        config.sessionReplay = false
        // Crashes are written to disk and uploaded on the next launch. Non-fatal
        // exception autocapture rides on the project's remote error-tracking setting
        // rather than a flag here.
        config.errorTrackingConfig.autoCapture = true
        #if DEBUG
        config.debug = true
        #endif
        PostHogSDK.shared.setup(config)

        // Shaking the phone is not an undo gesture here — the note carries its own
        // undo button, and a bag-jostle should never eat what was just typed.
        UIApplication.shared.applicationSupportsShakeToEdit = false

        // The back chevron is the system's own button, not one of ours, so it can only
        // be sized through the bar's appearance — and it has to be, or it stands a
        // head taller than every mark beside it. The appearance objects already on the
        // proxy are edited in place rather than replaced: a fresh one would come with
        // its own background and take the bar's glass with it.
        let back = topBarGlyphImage("chevron.backward")
        let bar = UINavigationBar.appearance()
        for appearance in [bar.standardAppearance, bar.scrollEdgeAppearance, bar.compactAppearance] {
            appearance?.setBackIndicatorImage(back, transitionMaskImage: back)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // The app is one surface, black, in any system appearance.
                .preferredColorScheme(.dark)
                .tint(.white)
        }
        .modelContainer(for: [ClimbSession.self, Attempt.self, Climb.self])
    }
}
