import SwiftUI
import SwiftData
import UIKit

/// What the app opens on. First run walks quiz → paywall → tutorial, and the notes
/// list is on the far side of all three: nothing about the app proper is reachable
/// until the paywall is answered.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var onboarding = Onboarding.shared
    @State private var store = Store.shared

    var body: some View {
        Group {
            // In front of the whole flow rather than inside it: the app says what it is
            // before it asks anything, and after that it never comes back.
            if !onboarding.hasSeenIntro {
                IntroView(onFinish: onboarding.finishIntro)
            } else {
                phases
            }
        }
        .animation(.easeInOut(duration: 0.25), value: onboarding.hasSeenIntro)
        .animation(.easeInOut(duration: 0.25), value: onboarding.phase)
        // The goal note exists from the first launch onward, whatever phase this one
        // opens in: onboarding writes into it before the list is ever reached.
        .task { Goals.seedIfNeeded(into: modelContext) }
        // What the App Store says is owned, asked for once at launch and then listened
        // for. Both halves matter: without the refresh a subscriber is locked out of
        // their own sessions until they buy again, and without the listener a lapsed
        // subscription keeps working until the app is next relaunched.
        .task {
            Store.shared.watchForChanges()
            await Store.shared.refresh()
        }
        // Launched with `-resetOnboarding`, the first run starts over at the first
        // question. It moves where you are in the flow and nothing else: no note, no
        // attempt and no video is touched by it, so walking onboarding again is never a
        // thing that can cost you anything.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-resetOnboarding") else { return }
            onboarding.reset()
        }
    }

    /// The first-run flow proper, once the slideshow is behind them.
    @ViewBuilder
    private var phases: some View {
        switch onboarding.phase {
        case .quiz:
            QuizView(onFinish: onboarding.finishQuiz)
        case .loading:
            LoadingView(onFinish: onboarding.finishLoading)
        case .profile:
            // What the quiz was for, before anything is asked for in return: the
            // answers drawn as one shape. It comes before the wall on purpose —
            // this is the screen that makes the wall worth answering.
            ProfileView(onFinish: onboarding.finishProfile)
        case .paywall:
            // A screen of its own rather than a cover over anything: there is
            // nothing behind it at this point in the flow, and nothing behind it
            // is the point — it is the only way on.
            PaywallView(onPurchase: finishPaywall)
        case .tutorial:
            // The walkthrough is the seeded note itself, opened on its own — there
            // is no list behind it to go back to.
            TutorialHost()
        case .done:
            // The wall is the door to the app, not a screen at the end of
            // onboarding: a subscription that lapses, is refunded, or was never
            // bought puts it straight back up. Nothing is deleted by it — what was
            // written is still there on the other side of paying again.
            if store.isPro || !Onboarding.showsPaywall {
                SessionListView()
            } else {
                PaywallView(onPurchase: {})
            }
        }
    }

    /// Out of the paywall into the walkthrough, or — while onboarding is what is being
    /// worked on — back to the top of the flow for another pass. The practice note
    /// carries over from the last pass rather than being wiped for the next one; a
    /// debug loop is not a good enough reason for the app to throw a note away.
    private func finishPaywall() {
        guard Onboarding.loopsForDevelopment else {
            onboarding.finishPaywall()
            return
        }
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
            Button {
                dismissKeyboard()
                onboarding.backToQuiz()
            } label: {
                Label { Text("Back") } icon: { topBarGlyph("chevron.backward") }
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

