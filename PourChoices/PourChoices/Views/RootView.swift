import SwiftUI
import SwiftData

/// Sits between the splash screen and ContentView.
/// Decides which screen to show based on auth state, subscription state, and onboarding.
struct RootView: View {
    @Environment(AuthenticationManager.self) private var auth
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.modelContext) private var modelContext
    @Query private var userProfiles: [UserProfile]

    @State private var showingAgeVerification = false
    @State private var showingOnboarding = false

    var userProfile: UserProfile {
        if let profile = userProfiles.first {
            return profile
        }
        let newProfile = UserProfile()
        modelContext.insert(newProfile)
        return newProfile
    }

    var body: some View {
        Group {
            switch auth.state {
            case .unknown:
                // Auth manager is checking persisted credentials — show a spinner
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView().tint(.white)
                }

            case .signedOut:
                AuthenticationView()

            case .signedIn:
                if subscriptions.subscriptionState == .unknown {
                    // Subscription manager still loading
                    ZStack {
                        Color.black.ignoresSafeArea()
                        ProgressView().tint(.white)
                    }
                    .task { await subscriptions.loadProductAndStatus() }
                } else if subscriptions.hasAccess {
                    ContentView()
                        .sheet(isPresented: $showingAgeVerification) {
                            AgeVerificationView(profile: userProfile, showingOnboarding: $showingOnboarding)
                                .interactiveDismissDisabled()
                        }
                        .sheet(isPresented: $showingOnboarding) {
                            OnboardingView(profile: userProfile)
                                .interactiveDismissDisabled()
                        }
                        .onAppear {
                            // Only request permissions and start background work after the
                            // user has signed in and their subscription is confirmed.
                            PourChoicesApp.closeAbandonedSessionsIfNeeded()
                            NotificationManager.requestPermission()
                            NotificationManager.schedulePartyNightNotification()

                            if !userProfile.hasCompletedAgeVerification {
                                showingAgeVerification = true
                            } else if !userProfile.hasCompletedOnboarding {
                                showingOnboarding = true
                            }
                        }
                } else {
                    SubscriptionGateView()
                }
            }
        }
    }
}
