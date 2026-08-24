import Foundation
import Observation
import PostHog
import StoreKit

/// The subscription behind the paywall.
///
/// A subscription to an app is bought with the Apple ID, in the system's own sheet —
/// the card already on file, confirmed with Face ID. That sheet is StoreKit's, not
/// PassKit's: Apple Pay proper is for goods and services delivered outside the app, and
/// the review guidelines will not take it for this. So Continue opens the App Store's
/// purchase sheet, which is the thing people mean by paying with Apple.
@Observable
@MainActor
final class Store {
    static let shared = Store()

    /// What is for sale. The ids are what App Store Connect has to call these, and
    /// what a local `.storekit` configuration has to call them to stand in for it.
    enum Plan: String, CaseIterable {
        case yearly = "com.627b8d.Crux.pro.yearly"
        case monthly = "com.627b8d.Crux.pro.monthly"

        var title: String { self == .yearly ? "Yearly" : "Monthly" }

        /// What the plan costs, written down once. Everything the paywall says about
        /// money before the App Store has answered — the price, the month it divides
        /// into, the saving one plan is against the other — comes off these two numbers,
        /// so a screen drawn early says one consistent set of figures rather than three
        /// separately maintained ones.
        var fallbackAmount: Decimal { self == .yearly ? 39.99 : 9.99 }

        /// Shown until the real product lands — and on a build with nothing configured
        /// to sell, shown for good, so the paywall is never a screen of blank rows.
        var fallbackPrice: String {
            "\(fallbackAmount.formatted(.currency(code: "USD"))) / \(self == .yearly ? "year" : "month")"
        }

        /// The trial the yearly plan is set up with, for a screen drawn before the
        /// products have come back. Same standing as `fallbackPrice`: what the screen
        /// says while it is waiting, replaced by the App Store's own answer the moment
        /// there is one.
        var fallbackTrial: String? { self == .yearly ? "3 days" : nil }

    }

    private(set) var products: [Product] = []
    private(set) var isPurchasing = false

    /// The last thing that went wrong, in words the paywall can show. Cleared by the
    /// next attempt — a failed purchase is not a state to be stuck in.
    private(set) var failure: String?

    /// Whether the store has anything to sell here. False on a build whose products
    /// are not set up yet, which is the difference between "the purchase failed" and
    /// "there is no purchase to make".
    var isConfigured: Bool { !products.isEmpty }

    /// Whether the subscription is live, as something a view body can read.
    /// `isSubscribed` below walks the entitlements and so can only be awaited, and a
    /// body cannot await; this is that same answer kept current — at launch, after a
    /// purchase, and whenever the App Store sends a change of its own.
    ///
    /// It is remembered across launches rather than starting false, because the whole
    /// app is behind it now: asking the App Store takes a moment, and a subscriber must
    /// not watch the paywall flash past on every cold launch while that moment passes.
    /// The remembered answer is replaced by the real one as soon as it lands, so the
    /// worst this can be is one launch out of date for somebody who just cancelled.
    var isPro: Bool {
        get { Self.forcesPro || storedIsPro }
        set { storedIsPro = newValue }
    }

    /// Debug: a subscription without a purchase, for working inside the app rather
    /// than on the way into it. It only masks the answer — what the App Store actually
    /// says is still asked for and still written down underneath, so turning this off
    /// leaves the real entitlement exactly as it was.
#if DEBUG
    // On while working inside the app. Flip to false to walk the wall for real.
    static let forcesPro = true
    #else
    // Release — TestFlight and the App Store — can never carry a development switch,
    // whatever the line above happens to say when a build is cut.
    static let forcesPro = false
    #endif

    private var storedIsPro = UserDefaults.standard.bool(forKey: Store.proKey) {
        didSet { UserDefaults.standard.set(storedIsPro, forKey: Self.proKey) }
    }

    private static let proKey = "isPro"

    /// Brings `isPro` back in line with what the App Store says is owned.
    func refresh() async {
        storedIsPro = await isSubscribed
    }

    /// Watches for the entitlement changes the app never asks for: a renewal, a lapse,
    /// a refund, or a purchase made on the user's other phone. Without this the
    /// entitlement is only ever as fresh as the last launch. Safe to call more than
    /// once — the second call is a no-op rather than a second listener.
    func watchForChanges() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard case let .verified(transaction) = update else { continue }
                await transaction.finish()
                await self?.refresh()
            }
        }
    }

    private var updates: Task<Void, Never>?

    private init() {}

    /// Why the last load came back with nothing, kept so the paywall can say which of
    /// the two it was: the store answered and had none of these products, or it never
    /// answered at all.
    private var loadError: String?

    /// Said out loud on the paywall rather than swallowed: a build with no products
    /// behind it is a thing to fix, not a tap to quietly ignore.
    func reportUnavailable() {
        failure = loadError.map { "The store didn't answer: \($0)" }
            ?? "The store has no products under these IDs — they need setting up in App Store Connect, or run from Xcode to use Crux.storekit."
    }

    func product(for plan: Plan) -> Product? {
        products.first { $0.id == plan.rawValue }
    }

    /// What a year costs a month, in the user's own currency — the number the yearly
    /// plan is actually judged on, since the two plans are different lengths and only
    /// a common unit lets them be read against each other.
    func perMonth(for plan: Plan) -> String {
        guard let product = product(for: plan) else {
            let value = plan == .yearly ? plan.fallbackAmount / 12 : plan.fallbackAmount
            return value.formatted(.currency(code: "USD"))
        }
        let value = plan == .yearly ? product.price / 12 : product.price
        return value.formatted(product.priceFormatStyle)
    }

    /// How much less a year costs than twelve of the monthly plan, as a whole
    /// percentage — the yearly row's one real selling point.
    ///
    /// Worked out from the two prices rather than written down as a percentage — the
    /// App Store's where it has answered, and the plans' own figures where it hasn't,
    /// which are the same prices set up in Connect and in `Crux.storekit`. Nothing at
    /// all if the year somehow isn't the cheaper of the two.
    var yearlySaving: Int? {
        let yearly = product(for: .yearly)?.price ?? Plan.yearly.fallbackAmount
        let monthly = product(for: .monthly)?.price ?? Plan.monthly.fallbackAmount
        guard monthly > 0 else { return nil }
        let year = monthly * 12
        guard year > yearly else { return nil }
        let share = (year - yearly) / year
        let percent = Int((NSDecimalNumber(decimal: share).doubleValue * 100).rounded())
        return percent > 0 ? percent : nil
    }

    /// Price as the App Store writes it, in the user's own currency — the hardcoded
    /// one only until it arrives.
    func price(for plan: Plan) -> String {
        guard let product = product(for: plan) else { return plan.fallbackPrice }
        let period = plan == .yearly ? "year" : "month"
        return "\(product.displayPrice) / \(period)"
    }

    func load() async {
        let ids = Plan.allCases.map(\.rawValue)
        do {
            products = try await Product.products(for: ids)
            loadError = nil
        } catch {
            products = []
            loadError = error.localizedDescription
        }
        #if DEBUG
        // Which of the three stores answered, and with what. Empty from a run with a
        // `.storekit` file attached means the file itself isn't being read; empty from
        // a run without one means App Store Connect has nothing under these ids.
        print("[Store] asked for \(ids) — got \(products.map(\.id)), error: \(loadError ?? "none")")
        #endif
    }

    /// The free trial the App Store has on a plan, said the way the plan screen wants
    /// to say it — "3 days" — or nothing at all where there is no trial to have.
    ///
    /// Read off the product rather than written down here, so a build whose App Store
    /// Connect entry has no introductory offer simply stops promising one instead of
    /// promising one it cannot give.
    func trial(for plan: Plan) -> String? {
        guard let offer = product(for: plan)?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let count = offer.period.value
        let unit = switch offer.period.unit {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        @unknown default: "day"
        }
        return "\(count) \(unit)\(count == 1 ? "" : "s")"
    }

    /// The trial as the paywall should print it: what the App Store said, or — while it
    /// hasn't answered yet — what the plan is set up to offer.
    ///
    /// The fallback stands in every build, not just debug ones. The offer is configured
    /// in App Store Connect and in `Crux.storekit` alike, so the two answers are the
    /// same answer; what the fallback buys is a paywall that says it on the first frame
    /// rather than after the products land.
    func trialLabel(for plan: Plan) -> String? {
        trial(for: plan) ?? plan.fallbackTrial
    }

    /// The same trial as a length of time, for laying down the reminder that it is
    /// about to end.
    func trialLength(for plan: Plan) -> TimeInterval? {
        guard let offer = product(for: plan)?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let day: TimeInterval = 24 * 60 * 60
        let unit: TimeInterval = switch offer.period.unit {
        case .day: day
        case .week: 7 * day
        case .month: 30 * day
        case .year: 365 * day
        @unknown default: day
        }
        return Double(offer.period.value) * unit
    }

    /// Whether anything on sale here comes with a trial. The onboarding paywall's first
    /// two screens are entirely about the trial, so with no trial anywhere they are
    /// skipped rather than shown as copy about nothing.
    var hasTrial: Bool { Plan.allCases.contains { trial(for: $0) != nil } }

    /// Runs the purchase and says whether it went through. Cancelling is not a failure
    /// — nothing is shown for it, the paywall simply stays up.
    func purchase(_ plan: Plan) async -> Bool {
        failure = nil
        guard let product = product(for: plan) else {
            failure = "This plan isn't available right now."
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case let .success(verification):
                guard case let .verified(transaction) = verification else {
                    failure = "That purchase couldn't be verified."
                    return false
                }
                // Finished as soon as it is honoured: the entitlement is what the app
                // reads from here on, and an unfinished transaction comes back at
                // every launch.
                await transaction.finish()
                storedIsPro = true
                // PostHog: track successful subscription purchase
                let hasTrial = trial(for: plan) != nil
                PostHogSDK.shared.capture("subscription_purchased", properties: [
                    "plan": plan.title.lowercased(),
                    "product_id": plan.rawValue,
                    "has_trial": hasTrial,
                ])
                // Named for what actually happened, not for the tap. Starting a free
                // trial and paying today are the same button and completely different
                // outcomes — one is revenue and one is a promise to look again in a
                // week — so they are different events rather than one event with a
                // flag on it that has to be remembered when a chart is built.
                OnboardingAnalytics.step(
                    (hasTrial ? "trial_" : "purchased_") + plan.title.lowercased(),
                    stage: "purchase",
                    index: 22,
                    label: hasTrial ? "Started trial (\(plan.title))"
                                    : "Purchased (\(plan.title))"
                )
                return true
            case .userCancelled:
                return false
            case .pending:
                failure = "Waiting on approval — you'll get in as soon as it clears."
                return false
            @unknown default:
                return false
            }
        } catch {
            failure = error.localizedDescription
            return false
        }
    }

    /// The Restore button: hand the account back to the App Store and see what it
    /// already owns.
    func restore() async -> Bool {
        failure = nil
        isPurchasing = true
        defer { isPurchasing = false }
        try? await AppStore.sync()
        await refresh()
        if isPro {
            // PostHog: track successful subscription restore
            PostHogSDK.shared.capture("subscription_restored")
            return true
        }
        failure = "Nothing to restore on this Apple Account."
        return false
    }

    /// Whether the subscription is live right now, straight from the entitlements —
    /// no receipt of our own to keep in step with them.
    var isSubscribed: Bool {
        get async {
            for await entitlement in Transaction.currentEntitlements {
                guard case let .verified(transaction) = entitlement else { continue }
                if Plan(rawValue: transaction.productID) != nil,
                   transaction.revocationDate == nil {
                    return true
                }
            }
            return false
        }
    }
}
