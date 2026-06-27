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

    @State private var showingUsernameSetup = false
    @State private var showingAgeVerification = false
    @State private var showingOnboarding = false
    @State private var isCheckingExistingAccount = false

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
                } else if !userProfile.hasCompletedSignIn {
                    if isCheckingExistingAccount {
                        // Checking Firestore for existing account…
                        ZStack {
                            Color.black.ignoresSafeArea()
                            ProgressView().tint(.white)
                        }
                    } else if let uid = auth.firebaseUID {
                        // No existing account found — show username setup
                        UsernameSetupView(
                            userProfile: userProfile,
                            uid: uid,
                            onComplete: { showingAgeVerification = !userProfile.hasCompletedAgeVerification }
                        )
                    }
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
        .task(id: auth.firebaseUID) {
            // When a user signs in, check Firestore for an existing account.
            // If they already have a username, they're a returning user — skip setup.
            guard let uid = auth.firebaseUID,
                  !userProfile.hasCompletedSignIn else { return }
            isCheckingExistingAccount = true
            if let firestoreUser = await FirestoreService.shared.getUser(uid: uid),
               firestoreUser.username != nil {
                userProfile.hasCompletedSignIn = true
            }
            isCheckingExistingAccount = false
        }
    }
}
