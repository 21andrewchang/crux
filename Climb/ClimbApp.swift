import SwiftUI
import SwiftData
import UIKit

@main
struct ClimbApp: App {
    init() {
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
