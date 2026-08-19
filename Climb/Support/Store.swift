import Foundation
import Observation
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
        case yearly = "com.andrewchang.Crux.pro.yearly"
        case monthly = "com.andrewchang.Crux.pro.monthly"

        var title: String { self == .yearly ? "Yearly" : "Monthly" }

        /// Shown until the real product lands — and on a build with nothing configured
        /// to sell, shown for good, so the paywall is never a screen of blank rows.
        var fallbackPrice: String { self == .yearly ? "$39.99 / year" : "$4.99 / month" }

        /// The yearly plan's own selling point, worked out here rather than fetched:
        /// it is the same number however the price is written.
        var note: String? { self == .yearly ? "$3.33 / month" : nil }
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
    /// It starts false, so the one frame before the first refresh lands looks like
    /// not-subscribed. That is the safe direction for a paywall to be wrong in for a
    /// frame: the gate is on making a *new* session, never on reading an existing one,
    /// so the worst it can do is briefly offer a subscription to somebody who has one.
    private(set) var isPro = false

    /// Brings `isPro` back in line with what the App Store says is owned.
    func refresh() async {
        isPro = await isSubscribed
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
                isPro = true
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
        if isPro { return true }
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
