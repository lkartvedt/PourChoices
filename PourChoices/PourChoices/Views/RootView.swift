import SwiftUI
import SwiftData

/// Sits between the splash screen and ContentView.
/// Decides which screen to show based on auth state, subscription state, and onboarding.
struct RootView: View {
    @Environment(AuthenticationManager.self) private var auth
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.modelContext) private var modelContext
    @Query private var userProfiles: [UserProfile]

    // Single LocationTracker instance shared across OnboardingView and RecordTab
    // so the map reacts the moment location permission is granted during onboarding.
    @State private var locationTracker = LocationTracker()

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
                    ContentView(locationTracker: locationTracker)
                        .sheet(isPresented: $showingAgeVerification) {
                            AgeVerificationView(profile: userProfile, showingOnboarding: $showingOnboarding)
                                .interactiveDismissDisabled()
                        }
                        .sheet(isPresented: $showingOnboarding) {
                            OnboardingView(profile: userProfile, locationTracker: locationTracker)
                                .interactiveDismissDisabled()
                        }
                        .onAppear {
                            PourChoicesApp.closeAbandonedSessionsIfNeeded()
                            // Notification permission is deferred until the user taps
                            // "Start Session" for the first time (handled in RecordTab).
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
