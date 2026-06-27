import Foundation
import StoreKit

// MARK: - Product IDs

enum SubscriptionProductID {
    // Must match exactly what you create in App Store Connect
    static let sixMonth = "com.lkartvedt.PourChoices.subscription.sixmonth"
}

// MARK: - Subscription State

enum SubscriptionState: Equatable {
    case unknown
    case notSubscribed
    // inTrial: true when inside the 14-day free trial window
    case inTrial
    case subscribed
    case expired
}

// MARK: - SubscriptionManager

@Observable
final class SubscriptionManager {

    var subscriptionState: SubscriptionState = .unknown
    var product: Product?
    var isLoading = false
    var purchaseError: String?

    private var updateTask: Task<Void, Never>?

    init() {
        updateTask = Task { await listenForTransactionUpdates() }
        Task { await loadProductAndStatus() }
    }

    deinit {
        updateTask?.cancel()
    }

    // MARK: - Load

    @MainActor
    func loadProductAndStatus() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: [SubscriptionProductID.sixMonth])
            product = products.first
        } catch {
            // Products unavailable — App Store Connect not yet set up or no network.
            // App still runs; paywall will show a message.
        }

        await refreshSubscriptionStatus()
    }

    // MARK: - Status

    @MainActor
    func refreshSubscriptionStatus() async {
        // Walk all current entitlements looking for our subscription.
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == SubscriptionProductID.sixMonth else {
                continue
            }

            if transaction.revocationDate != nil {
                subscriptionState = .expired
                return
            }

            // Check for an active introductory offer (14-day free trial)
            if let offerType = transaction.offer?.type, offerType == .introductory {
                subscriptionState = .inTrial
                return
            }

            if let expDate = transaction.expirationDate, expDate > Date() {
                subscriptionState = .subscribed
                return
            } else {
                subscriptionState = .expired
                return
            }
        }

        // No matching entitlement found — check for trial eligibility to distinguish
        // brand-new users (who haven't purchased yet) from expired subscribers.
        subscriptionState = .notSubscribed
    }

    // MARK: - Purchase

    @MainActor
    func purchase() async {
        guard let product else {
            purchaseError = "Product not available. Check your internet connection and try again."
            return
        }

        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseError = "Transaction could not be verified."
                    return
                }
                await transaction.finish()
                // Set state directly from this transaction — don't re-query
                // currentEntitlements, which may not reflect the purchase yet
                // in sandbox/testing environments.
                applyTransaction(transaction)
            case .userCancelled:
                break
            case .pending:
                // Awaiting Ask to Buy or SCA — will arrive via transaction listener
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    /// Derives subscription state from a single known-good transaction.
    @MainActor
    private func applyTransaction(_ transaction: Transaction) {
        guard transaction.productID == SubscriptionProductID.sixMonth else { return }

        if transaction.revocationDate != nil {
            subscriptionState = .expired
            return
        }
        if let offerType = transaction.offer?.type, offerType == .introductory {
            subscriptionState = .inTrial
            return
        }
        if let expDate = transaction.expirationDate, expDate > Date() {
            subscriptionState = .subscribed
        } else {
            subscriptionState = .expired
        }
    }

    // MARK: - Restore

    @MainActor
    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshSubscriptionStatus()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Transaction Listener

    // Processes any transactions that arrive while the app is running
    // (renewals, Ask-to-Buy approvals, etc.)
    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await MainActor.run { self.applyTransaction(transaction) }
        }
    }

    // MARK: - Access Gate

    /// Returns true if the user is allowed to use full app features.
    var hasAccess: Bool {
        switch subscriptionState {
        case .subscribed, .inTrial: return true
        default: return false
        }
    }
}
