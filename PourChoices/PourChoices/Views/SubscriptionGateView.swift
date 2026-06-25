import SwiftUI
import StoreKit

// MARK: - Preview support

private extension SubscriptionManager {
    /// Returns a SubscriptionManager pre-configured for Xcode Previews.
    /// Skips the live StoreKit product fetch so the view renders immediately.
    static var preview: SubscriptionManager {
        let manager = SubscriptionManager()
        manager.subscriptionState = .notSubscribed
        manager.isLoading = false
        return manager
    }
}

struct SubscriptionGateView: View {
    @Environment(SubscriptionManager.self) private var subscriptions

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack() {
                    // Header
                    VStack() {
                        Image("SplashPage")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240)

                        Text("See your BAC in real time and wake up to a full recap of your night: Where you went, what you drank, and how cooked you got.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, AppLayout.horizontalPadding)

                    // Feature list
                    VStack(spacing: 0) {
                        FeatureRow(icon: "chart.bar.fill",        title: "Live BAC Tracking",     detail: "Science-backed, real-time estimates")
                        FeatureRow(icon: "location.fill",          title: "Bar-Hop Map",            detail: "Auto-log every venue you visit")
                        FeatureRow(icon: "person.2.fill",          title: "Friends & Social",       detail: "Share sessions and compare stats")
                        FeatureRow(icon: "bell.badge.fill",        title: "Smart Notifications",    detail: "Hydration reminders and more")
                        FeatureRow(icon: "lock.shield.fill",       title: "Privacy First",          detail: "Your data stays on your device")
                    }
                    .padding(.vertical, 32)
                    .padding(.horizontal, AppLayout.horizontalPadding)

                    // Pricing card
                    PricingCard(product: subscriptions.product)
                        .padding(.horizontal, AppLayout.horizontalPadding)
                        .padding(.bottom, 24)

                    // CTA
                    VStack(spacing: 14) {
                        Button {
                            Task { await subscriptions.purchase() }
                        } label: {
                            Group {
                                if subscriptions.isLoading {
                                    ProgressView().tint(.black)
                                } else {
                                    Text("Start Free Trial")
                                        .font(.headline)
                                        .foregroundStyle(.black)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: AppLayout.buttonHeight)
                            .background(Color.accent, in: Capsule())
                        }
                        .disabled(subscriptions.isLoading)

                        Button {
                            Task { await subscriptions.restorePurchases() }
                        } label: {
                            Text("Restore Purchases")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .disabled(subscriptions.isLoading)
                    }
                    .padding(.horizontal, AppLayout.horizontalPadding)

                    if let err = subscriptions.purchaseError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppLayout.horizontalPadding)
                            .padding(.top, 8)
                    }

                    // Legal
                    Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless it is cancelled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period. You can manage and cancel your subscriptions by going to your account settings on the App Store after purchase.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppLayout.horizontalPadding)
                        .padding(.vertical, 24)
                }
            }
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Preview

#Preview("Subscription Gate") {
    SubscriptionGateView()
        .environment(SubscriptionManager.preview)
        .preferredColorScheme(.dark)
}

// MARK: - Pricing Card

private struct PricingCard: View {
    let product: Product?

    var priceString: String {
        if let p = product {
            return p.displayPrice
        }
        return "$29.99"
    }
    
    var monthlyPriceString: String {
        guard let price = product?.price else { return "" }
        let monthly = (price / 6 as Decimal)
        let rounded = NSDecimalNumber(decimal: monthly).rounding(accordingToBehavior: NSDecimalNumberHandler(
            roundingMode: .down,
            scale: 2,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )).decimalValue
        return rounded.formatted(.currency(code: "USD"))
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("6-Month Access")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(priceString)
                    .font(.title3.bold())
                    .foregroundStyle(.accent)
            }

            HStack {
                // Badge
                Text("14-Day Free Trial")
                    .font(.caption.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accent, in: Capsule())
                Spacer()
                Text("just \(monthlyPriceString)/mo")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(20)
        .background(Color(.systemGray6).opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.accent.opacity(0.4), lineWidth: 1)
        )
    }
}
