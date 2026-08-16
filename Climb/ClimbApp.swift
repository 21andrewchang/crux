import SwiftUI
import SwiftData

@main
struct ClimbApp: App {
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
