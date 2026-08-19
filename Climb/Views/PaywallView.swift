import SwiftUI
import UIKit

/// The subscription screen, in either of the two places it comes up.
struct PaywallView: View {
    /// Where the paywall was reached from — the only thing that differs between them,
    /// and it differs in exactly one way that matters: whether there is a way out.
    enum Presentation {
        /// Reached by running out of free sessions. There is a close button, the sheet
        /// can be pulled down, and the app carries on without a purchase — everything
        /// already written stays readable, and deleting a session frees the slot back
        /// up. The wall is on making a sixth session, nothing else.
        case limitReached

        /// The last screen of onboarding, with no way past it but a purchase. Not used
        /// while `Onboarding.showsPaywall` is off; kept because the flow still has the
        /// phase, and a screen that can only be shown one way is a screen that quietly
        /// rots.
        case onboarding
    }

    /// The onboarding paywall is three screens rather than one, and in this order for
    /// a reason: the trial is offered before any price is on screen, the reminder is
    /// promised before the trial is taken, and only then is there a plan to pick. Each
    /// step asks for less than the one after it.
    ///
    /// With no trial configured there is nothing for the first two to say, and the
    /// flow is the plan screen alone.
    enum Step { case offer, reminder, plans }

    var presentation: Presentation = .onboarding
    var onPurchase: () -> Void
    /// Closing without buying. Absent for `.onboarding`, which has no such door.
    var onDismiss: (() -> Void)?

    @State private var store = Store.shared
    @State private var plan: Store.Plan = .yearly
    @State private var step: Step = .plans

    private var isDismissible: Bool { presentation == .limitReached }

    /// What the plan screen calls the trial, if the plan on it has one.
    private var trial: String? { store.trial(for: plan) }

    var body: some View {
        Group {
            switch step {
            case .offer: offerStep
            case .reminder: reminderStep
            case .plans: plans
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .animation(.easeInOut(duration: 0.25), value: step)
        // Prices are asked for as the screen comes up; until they land the plans show
        // what they cost in dollars, so the rows are never empty. The first two steps
        // wait on the same answer — whether there is a trial to talk about at all —
        // which is why the flow starts on the plan screen and steps back to the offer
        // once the store has spoken.
        .task {
            // Someone who already pays and is walking the flow again — from the replay
            // button, or by stepping back into the quiz from the walkthrough — is not
            // asked for the money twice. The wall is only a wall to somebody outside it.
            if store.isPro {
                onPurchase()
                return
            }
            await store.load()
            if presentation == .onboarding, store.hasTrial, step == .plans {
                step = .offer
            }
        }
        // The limit-reached paywall comes up as a sheet over a note that may well have
        // been typing a moment ago. Onboarding's has nothing behind it to worry about,
        // but the call costs nothing there and the screen has no field of its own
        // either way.
        .onAppear(perform: dismissKeyboard)
        // Onboarding's copy has no way out, so the drag has to be off too — otherwise
        // the sheet is a hard paywall that can be swiped away.
        .interactiveDismissDisabled(!isDismissible)
    }

    // MARK: - The offer

    /// What the app is, and that it costs nothing to find out. No price on this screen
    /// at all: the only number here is the one that isn't being asked for.
    private var offerStep: some View {
        VStack(spacing: 0) {
            Text("We want you to try Crux for free")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 40)

            Spacer()
            phoneMock
            Spacer()

            noPaymentDue
            continueButton("Try Now") { step = .reminder }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    /// The app standing in for itself: a session note the size of a phone, close enough
    /// to the real one that the screen is showing the thing being sold rather than an
    /// illustration of it.
    private var phoneMock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tuesday")
                .font(.title3.weight(.semibold))
            Text("Overhang session")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.45))

            ForEach(["Blue V5", "Yellow V6", "Comp slab V4"], id: \.self) { climb in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.routeHold)
                        .frame(width: 8, height: 8)
                    Text(climb)
                        .font(.subheadline)
                    Spacer()
                    Text("3")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.surface, in: .rect(cornerRadius: 10))
            }
            Spacer()
        }
        .padding(18)
        .frame(width: 230, height: 380, alignment: .topLeading)
        .background(Color.black)
        .clipShape(.rect(cornerRadius: 36))
        .overlay(RoundedRectangle(cornerRadius: 36)
            .stroke(Color.white.opacity(0.16), lineWidth: 5))
    }

    // MARK: - The reminder

    /// The one screen that asks for something. It is here rather than later because
    /// what it asks for is in the user's interest — a word before the trial turns into
    /// a charge — and asking for it is the same tap as going on.
    private var reminderStep: some View {
        VStack(spacing: 0) {
            back { step = .offer }

            Text("We'll send a reminder before your trial ends")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Text("As long as notifications are enabled")
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 10)

            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 120))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.red, Color.white.opacity(0.22))

            Spacer()

            noPaymentDue
            continueButton("Continue for FREE") {
                Task {
                    await TrialReminder.ask()
                    step = .plans
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    /// Said on both of the screens before the price, because it is the thing being
    /// doubted on both of them.
    private var noPaymentDue: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.bold))
            Text("No Payment Due Now")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.bottom, 14)
    }

    private func back(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.left")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.surface, in: .circle)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func continueButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.white, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: - The plans

    private var plans: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isDismissible {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.4))
                        .contentShape(Rectangle().inset(by: -12))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 12)
                .disabled(store.isPurchasing)
            } else if store.hasTrial {
                back { step = .reminder }
                    .padding(.bottom, 12)
            }

            Text(headline)
                .font(.largeTitle.weight(.semibold))
                .padding(.bottom, 8)

            Text(subhead)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 40)

            VStack(alignment: .leading, spacing: 14) {
                bullet("Unlimited sessions and climbs")
                bullet("Video on every attempt")
                bullet("Rest timer and session history")
            }

            Spacer()

            VStack(spacing: 10) {
                ForEach(Store.Plan.allCases, id: \.self) { option in
                    Button { plan = option } label: { planRow(option) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 16)

            if let failure = store.failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
            }

            Button(action: buy) {
                ZStack {
                    // The label stays in place while it spins, so the button doesn't
                    // resize under the finger that just pressed it.
                    Text("Continue").opacity(store.isPurchasing ? 0 : 1)
                    if store.isPurchasing {
                        ProgressView().tint(.black)
                    }
                }
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.white, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(store.isPurchasing)

            Text(terms)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            HStack(spacing: 20) {
                Button("Restore") { restore() }
                Link("Terms", destination: Legal.terms)
                Link("Privacy", destination: Legal.privacy)
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .disabled(store.isPurchasing)
        }
        .padding(.horizontal, 24)
        .padding(.top, isDismissible ? 24 : 24)
        .padding(.bottom, 24)
    }

    /// Says what happened, in the case where something happened. Onboarding's version
    /// is the app's name because nothing has gone wrong there — it is just the last
    /// screen of the flow.
    private var headline: String {
        switch presentation {
        case .limitReached: "You've filled your \(FreeTier.sessionLimit) free sessions"
        // The trial is the offer, so it is the headline. Without one there is nothing
        // to lead with but the app's name.
        case .onboarding: trial.map { "Start your \($0) FREE trial to continue" } ?? "Crux"
        }
    }

    /// The escape hatch is named here rather than hidden, because it is real: deleting
    /// a session gives the slot back, and someone who would rather do that than pay
    /// should be told they can. A wall worth putting up is one that survives being
    /// honest about the way around it.
    private var subhead: String {
        switch presentation {
        case .limitReached:
            "Subscribe to keep as many as you climb — or delete one to make room. Nothing you've already written goes away either way."
        case .onboarding:
            "Log every session, every attempt, every send."
        }
    }

    /// The small print, built from the plan that is actually selected — a screen that
    /// says three days free has to say what happens on the fourth, and say it in the
    /// price the store is really going to charge.
    private var terms: String {
        let price = store.price(for: plan)
        guard let trial else {
            return "\(price), renewing automatically unless cancelled in the App Store."
        }
        return "\(trial) free, then \(price). Renews automatically unless cancelled in the App Store."
    }

    /// Continue: the App Store's own sheet, and onwards only if it went through. With
    /// nothing set up to sell yet the screen says so and stays where it is — it never
    /// takes the tap as a purchase, and never moves anyone off the paywall for it.
    private func buy() {
        guard store.isConfigured else {
            store.reportUnavailable()
            return
        }
        Task {
            guard await store.purchase(plan) else { return }
            // Now, because now is when the trial's length is known and the clock on it
            // has just started — the screen two back promised this.
            if let length = store.trialLength(for: plan) {
                TrialReminder.schedule(trialLength: length)
            }
            onPurchase()
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    private func restore() {
        Task {
            if await store.restore() { onPurchase() }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.footnote.weight(.semibold))
            Text(text)
        }
    }

    /// The selected plan is the one with the white outline; unselected sits flat on
    /// the surface fill, same as everything else in the app.
    private func planRow(_ option: Store.Plan) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let trial = store.trial(for: option) {
                    Text("\(trial.uppercased()) FREE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.routeHold)
                }
                Text(option.title).font(.headline)
                if let note = option.note {
                    Text(note).font(.footnote).foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
            Text(store.price(for: option))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(Color.surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(.white, lineWidth: plan == option ? 1.5 : 0))
    }
}
