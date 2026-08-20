import SwiftUI
import UIKit

/// The subscription screen: the last thing onboarding asks, and the door the app
/// sits behind afterwards. There is one of it and no way past it but a purchase —
/// the app used to give five sessions away and wall the sixth, and that tier is
/// gone. Either you are subscribed or you are on this screen.
struct PaywallView: View {
    /// The onboarding paywall is three screens rather than one, and in this order for
    /// a reason: the trial is offered before any price is on screen, the reminder is
    /// promised before the trial is taken, and only then is there a plan to pick. Each
    /// step asks for less than the one after it.
    ///
    /// With no trial configured there is nothing for the first two to say, and the
    /// flow is the plan screen alone.
    enum Step { case offer, reminder, plans }

    var onPurchase: () -> Void

    @State private var store = Store.shared
    @State private var plan: Store.Plan = .yearly
    @State private var step: Step = .plans

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
        .foregroundStyle(Color.paper)
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
            if store.hasTrial, step == .plans {
                step = .offer
            }
        }
        // Nothing behind this screen is typing, but the call costs nothing and the
        // screen has no field of its own either way.
        .onAppear(perform: dismissKeyboard)
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
                .foregroundStyle(Color.paper.opacity(0.45))

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
                        .foregroundStyle(Color.paper.opacity(0.4))
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
            .stroke(Color.paper.opacity(0.16), lineWidth: 5))
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
                .foregroundStyle(Color.paper.opacity(0.45))
                .padding(.top, 10)

            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 120))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.red, Color.paper.opacity(0.22))

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
                .foregroundStyle(Color.paper)
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
                .background(Color.paper, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: - The plans

    private var plans: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.hasTrial {
                back { step = .reminder }
                    .padding(.bottom, 12)
            }

            Text(headline)
                .font(.largeTitle.weight(.semibold))
                .padding(.bottom, 8)

            Text(subhead)
                .foregroundStyle(Color.paper.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 40)

            VStack(alignment: .leading, spacing: 14) {
                bullet("Unlimited sessions and climbs")
                bullet("Video on every attempt")
                bullet("Rest timer and session history")
            }

            Spacer()

            PurchaseFooter(plan: $plan, onPurchase: onPurchase)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
    }

    /// The trial is the offer, so it is the headline. Without one there is nothing to
    /// lead with but the app's name — nothing has gone wrong here, it is just the last
    /// screen of the flow.
    private var headline: String {
        trial.map { "Start your \($0) FREE trial" } ?? "Crux"
    }

    private var subhead: String {
        "Log every session, every attempt, every send."
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.footnote.weight(.semibold))
            Text(text)
        }
    }

}

/// The asking half of the paywall: the plans, the button, and the small print under it.
///
/// Its own view because it is no longer only the paywall's. The goal screen at the end
/// of onboarding carries it too — the shape, the grade you're on, the grade you're
/// after, and then this, on the same screen rather than a tap further on. What is being
/// paid for is the gap that screen just drew, and putting a page break between the two
/// was spending the only thing that makes the price read as small.
struct PurchaseFooter: View {
    @Binding var plan: Store.Plan
    var onPurchase: () -> Void
    /// Handed in while the screen above this one is being worked on: with it, the
    /// button plays that screen again instead of going to the App Store. Nothing else about
    /// the footer changes — it is the same button in the same place, so what is being
    /// dialled in is what will ship.
    var replay: (() -> Void)?

    @State private var store = Store.shared

    /// What the small print calls the trial, if the plan carrying it has one.
    private var trial: String? { store.trial(for: plan) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                ForEach(Store.Plan.allCases, id: \.self) { option in
                    Button { plan = option } label: { planRow(option) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 14)

            if let failure = store.failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(Color.paper.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
            }

            Button(action: replay ?? buy) {
                ZStack {
                    // The label stays in place while it spins, so the button doesn't
                    // resize under the finger that just pressed it.
                    Text("Continue").opacity(store.isPurchasing ? 0 : 1)
                    if store.isPurchasing {
                        ProgressView().tint(.black)
                    }
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.paper, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(store.isPurchasing)

            Text(terms)
                .font(.system(size: 12))
                .foregroundStyle(Color.paper.opacity(0.4))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            HStack(spacing: 8) {
                Link("Terms", destination: Legal.terms)
                Text("·")
                Link("Privacy", destination: Legal.privacy)
                Text("·")
                Button("Restore") { restore() }
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.paper.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .disabled(store.isPurchasing)
        }
        .foregroundStyle(Color.paper)
        // The footer fetches what it is selling. It used to be the paywall screen that
        // did this, which was fine while the paywall was the only place any of it was
        // shown — and stopped being fine the moment the goal screen started carrying
        // the plans, because nothing on that screen had ever asked the App Store
        // anything. Every price and every trial on it was a hardcoded stand-in.
        .task {
            guard !store.isConfigured else { return }
            await store.load()
        }
    }

    /// A plan as one card: the trial across the top of it in a band of its own, then
    /// the offer, what it is billed as, and what that comes to a month.
    ///
    /// The proportions are lifted wholesale from the screens that do this well — a
    /// twenty-point offer line over a sixteen-point billing line, the per-month price
    /// out on the right in the same sixteen, and a mark rather than a tick box on the
    /// left. Ours is the same card read the other way up: white on black, and the band
    /// that was black over white is white over black.
    private func planRow(_ option: Store.Plan) -> some View {
        let selected = plan == option
        let trial = store.trialLabel(for: option)
        return VStack(spacing: 0) {
            // The band stays on the row whether or not the row is taken — dimmed with
            // everything else on it. A trial that appeared only once its plan was
            // selected would be an offer you had to find by tapping.
            if let trial {
                Text("\(trial.uppercased()) FREE")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.3)
                    .foregroundStyle(.black.opacity(selected ? 1 : 0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    // Rounded over the top and square along the bottom: it is the head
                    // of the card, not a badge sitting on it.
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 0,
                                               bottomTrailingRadius: 0, topTrailingRadius: 16)
                            .fill(Color.paper.opacity(selected ? 1 : 0.35))
                    )
            }

            HStack(spacing: 12) {
                mark(selected: selected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(offer(option))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.paper.opacity(selected ? 1 : 0.4))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let billing = billing(option) {
                        Text(billing)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.paper.opacity(selected ? 0.45 : 0.28))
                    }
                }

                Spacer(minLength: 8)

                Text(monthly(option))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.paper.opacity(selected ? 0.45 : 0.28))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        // No fill on either row: the card is the outline and the band, the same as the
        // page behind it. A surface panel inside a white border was reading as two
        // rounded rectangles, one inside the other.
        .clipShape(.rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(selected ? Color.paper : Color.paper.opacity(0.15),
                    lineWidth: selected ? 2 : 1))
        // The whole card takes the tap, not just what is drawn on it. Neither row has a
        // fill, so without this the empty space inside the border — most of the monthly
        // one, which is a single line of text — was passing the tap through to the page.
        .contentShape(.rect(cornerRadius: 16))
    }

    /// The circle on the left: filled and ticked on the plan being bought, an empty
    /// ring on the one that isn't. Small, and set close to the words: it is only a state
    /// and the row is a sentence, and the width it was taking was coming off the end of
    /// that sentence as an ellipsis.
    private func mark(selected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(selected ? Color.paper : .clear)
                .overlay(Circle().stroke(Color.paper.opacity(selected ? 0 : 0.25),
                                         lineWidth: 1.5))
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
            }
        }
        .frame(width: 22, height: 22)
    }

    /// The headline on a row. Short on purpose: the band over the row already says the
    /// trial is free, so a row that opened with "start for free" was the same words a
    /// second time and long enough with them to run off the end as an ellipsis.
    ///
    /// The saving belongs on the yearly row and only reads as anything next to the
    /// monthly one it is a saving against — which is the whole reason the monthly row is
    /// on the screen. Where it isn't known yet the row is simply its own name.
    private func offer(_ option: Store.Plan) -> String {
        guard option == .yearly, let saving = store.yearlySaving else { return option.title }
        return "Start Free · Save \(saving)%"
    }

    /// How it is billed, under the offer: the real sum that leaves the account, as
    /// against the per-month figure on the right that only ever divides it.
    ///
    /// Only the yearly row has one. On the monthly row the sum and the division are the
    /// same number, and printing $9.99 twice on one row made a plan that costs one price
    /// look like a plan that costs two.
    private func billing(_ option: Store.Plan) -> String? {
        guard option == .yearly else { return nil }
        return store.price(for: option).replacingOccurrences(of: " / year",
                                                             with: " billed annually")
    }

    /// What it comes to a month, which is the only way two plans of different lengths
    /// can be read against each other at a glance.
    private func monthly(_ option: Store.Plan) -> String {
        "\(store.perMonth(for: option))/mo"
    }

    /// The small print, built from the plan that is actually selected — a screen that
    /// says three days free has to say what happens on the fourth, and say it in the
    /// price the store is really going to charge.
    private var terms: String {
        // What it costs is already on the row that was picked, in the row's own words —
        // saying it again a line lower was the same sentence twice. What is left is the
        // part the row doesn't say: that it keeps going until it is stopped.
        let period = plan == .yearly ? "annually" : "monthly"
        return "Billed \(period) and renews automatically unless cancelled in the App Store."
    }

    /// The press: the App Store's own sheet, and onwards only if it went through. With
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

    private func restore() {
        Task {
            if await store.restore() { onPurchase() }
        }
    }

}
