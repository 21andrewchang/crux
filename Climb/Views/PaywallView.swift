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

    var presentation: Presentation = .onboarding
    var onPurchase: () -> Void
    /// Closing without buying. Absent for `.onboarding`, which has no such door.
    var onDismiss: (() -> Void)?

    @State private var store = Store.shared
    @State private var plan: Store.Plan = .yearly

    private var isDismissible: Bool { presentation == .limitReached }

    var body: some View {
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

            HStack(spacing: 20) {
                Button("Restore") { restore() }
                Button("Terms") {}
                Button("Privacy") {}
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .disabled(store.isPurchasing)
        }
        // Prices are asked for as the screen comes up; until they land the plans show
        // what they cost in dollars, so the rows are never empty.
        .task { await store.load() }
        // The walkthrough's note is still there under this cover, and a note that is
        // still the first responder still has the keyboard up — over the paywall, on a
        // screen with nothing to type into. Taken away here rather than on the way out
        // of the note, because here is after the cover is up: whatever the note does
        // while it rises, it is not typing by the time this screen is on.
        .onAppear(perform: dismissKeyboard)
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.top, isDismissible ? 24 : 64)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        // Onboarding's copy has no way out, so the drag has to be off too — otherwise
        // the sheet is a hard paywall that can be swiped away.
        .interactiveDismissDisabled(!isDismissible)
    }

    /// Says what happened, in the case where something happened. Onboarding's version
    /// is the app's name because nothing has gone wrong there — it is just the last
    /// screen of the flow.
    private var headline: String {
        switch presentation {
        case .limitReached: "You've filled your \(FreeTier.sessionLimit) free sessions"
        case .onboarding: "Crux"
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

    /// Continue: the App Store's own sheet, and onwards only if it went through. With
    /// nothing set up to sell yet the screen says so and stays where it is — it never
    /// takes the tap as a purchase, and never moves anyone off the paywall for it.
    private func buy() {
        guard store.isConfigured else {
            store.reportUnavailable()
            return
        }
        Task {
            if await store.purchase(plan) { onPurchase() }
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
