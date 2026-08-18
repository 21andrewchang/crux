import SwiftUI
import SwiftData
import UIKit

/// What the app opens on. First run walks quiz → tutorial → paywall, and the notes
/// list is on the far side of all three: nothing about the app proper is reachable
/// until the paywall is answered.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var onboarding = Onboarding.shared

    var body: some View {
        Group {
            switch onboarding.phase {
            case .quiz:
                QuizView(onFinish: onboarding.finishQuiz)
            case .loading:
                LoadingView(onFinish: onboarding.finishLoading)
            case .tutorial, .paywall:
                // The walkthrough is the seeded note itself, opened on its own — there
                // is no list behind it to go back to. It stays up under the paywall so
                // the cover rises over the thing that was just finished.
                TutorialHost()
            case .done:
                SessionListView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: onboarding.phase)
        // The goal note exists from the first launch onward, whatever phase this one
        // opens in: onboarding writes into it before the list is ever reached.
        .task { Goals.seedIfNeeded(into: modelContext) }
        // Launched with `-resetOnboarding`, the first run starts over: quiz at the
        // first question, practice note thrown away. Only what onboarding owns — the
        // user's own sessions are not part of it and are not touched.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-resetOnboarding") else { return }
            Tutorial.reset(in: modelContext)
            onboarding.reset()
        }
        .fullScreenCover(isPresented: .constant(onboarding.phase == .paywall)) {
            PaywallView(onPurchase: finishPaywall)
        }
    }

    /// The last tap of the flow: into the app, or — while onboarding is what is being
    /// worked on — back to the top of it with the practice note wiped, so the next
    /// pass is the same first run this one was.
    private func finishPaywall() {
        guard Onboarding.loopsForDevelopment else {
            onboarding.finishPaywall()
            return
        }
        Tutorial.reset(in: modelContext)
        onboarding.reset()
    }
}

/// The tutorial note as the whole app: one session, no navigation out of it, with the
/// same floating timer bar every other page gets.
private struct TutorialHost: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [ClimbSession]
    @State private var barModel = BottomBarModel()
    @State private var onboarding = Onboarding.shared

    private var note: ClimbSession? { sessions.first { $0.id == Tutorial.id } }

    var body: some View {
        NavigationStack {
            if let note {
                SessionDetailView(session: note, startsEditing: true, isOnboarding: true)
                    .navigationBarBackButtonHidden()
                    .toolbar { corners }
            } else {
                // The one frame before the seed lands.
                Color.black.ignoresSafeArea()
            }
        }
        .task { Tutorial.seedIfNeeded(into: modelContext) }
        .bottomBarHost(barModel)
    }

    /// Onboarding's own two corners, in place of the note's: back to the quiz, and the
    /// way out. The way out is always there — Skip before the walkthrough has been
    /// worked through, Done once it has — so the wording is the only thing the note's
    /// state moves, never whether the button is there at all.
    @ToolbarContentBuilder
    private var corners: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Back", systemImage: "chevron.left") {
                dismissKeyboard()
                onboarding.backToQuiz()
            }
            .labelStyle(.iconOnly)
        }
        ToolbarItem(placement: .topBarTrailing) {
            let complete = onboarding.tutorialComplete
            Button(complete ? "Done" : "Skip Tutorial") { leave() }
                .fontWeight(complete ? .semibold : .regular)
        }
    }

    /// Out to the paywall. The note stays up behind the cover — that is the point, the
    /// paywall rises over the thing just finished — and a note that is still the first
    /// responder still has the keyboard up under it. Nothing takes it away, so it is
    /// handed back here on the way out.
    private func leave() {
        dismissKeyboard()
        onboarding.leaveTutorial()
    }

    /// Neither door out of the walkthrough takes the note's keyboard with it unless it
    /// is told to: the quiz behind and the paywall over the top both end up sharing the
    /// screen with a keyboard belonging to a note that isn't there any more.
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
