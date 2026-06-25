//
//  PourChoicesApp.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/8/26.
//

import SwiftUI
import SwiftData
import ActivityKit
import UserNotifications

@main
struct PourChoicesApp: App {
    @State private var showSplash = true
    @State private var auth = AuthenticationManager()
    @State private var subscriptions = SubscriptionManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Force tab bar to always use dark appearance regardless of system setting
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.black
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().overrideUserInterfaceStyle = .dark
    }

    /// If the app is killed while a session is active, we have no callback.
    /// Instead, we record the last time the app was in the foreground and on
    /// next launch close any session whose start is older than that timestamp
    /// by more than a reasonable session length (8 hours).
    private static let lastForegroundKey = "lastForegroundDate"
    private static let autoEndThreshold: TimeInterval = 8 * 3600

    /// Static so QuickAddHandler (called from a LiveActivityIntent) can
    /// access the same container instance without re-creating it.
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DrinkingSession.self,
            DrinkEntry.self,
            LocationStop.self,
            NicotineEntry.self,
            FoodEntry.self,
            WaterEntry.self,
            UserProfile.self
        ])
        // allowsSave: true + no explicit URL lets SwiftData pick the default store location.
        // cloudKitDatabase: .none keeps it local-only.
        // The schema version bump from adding `hasCompletedSignIn` to UserProfile is an
        // additive change (new column with a default), so lightweight migration handles it
        // automatically when we pass the versioned schema rather than a bare Schema.
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If migration still fails (e.g. a destructive change on a development build),
            // destroy the store and start fresh rather than leaving the app unlaunchable.
            // In production this should never be hit because all schema changes must be
            // additive with defaults.
            let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: storeURL)
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after store reset: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            if showSplash {
                SplashScreenView(showSplash: $showSplash)
                    .preferredColorScheme(.dark)
            } else {
                RootView()
                    .environment(auth)
                    .environment(subscriptions)
                    .modelContainer(Self.sharedModelContainer)
                    .preferredColorScheme(.dark)
            }
        }
        .onChange(of: scenePhase) {
            // Stamp the foreground date at every active/background transition so
            // closeAbandonedSessionsIfNeeded can detect force-kills accurately.
            // This runs regardless of auth/subscription state — it's harmless and
            // we need it to be reliable.
            if scenePhase == .active || scenePhase == .background {
                UserDefaults.standard.set(Date(), forKey: Self.lastForegroundKey)
            }
        }
    }

    /// Ends any active session that was abandoned when the app was force-killed.
    ///
    /// On a force-kill iOS sends SIGKILL with no callback, so we can't end the
    /// session at that moment. Instead, on the next launch we check whether the
    /// last recorded foreground timestamp is older than `autoEndThreshold`. If
    /// it is, the user clearly isn't in an active session anymore.
    ///
    /// Called as a static method from RootView once the user has passed auth
    /// and subscription checks, so it runs at the right point in the flow.
    static func closeAbandonedSessionsIfNeeded() {
        let context = sharedModelContainer.mainContext
        guard let sessions = try? context.fetch(FetchDescriptor<DrinkingSession>()) else { return }
        let activeSessions = sessions.filter { $0.isActive }
        guard !activeSessions.isEmpty else { return }

        let lastForeground = UserDefaults.standard.object(forKey: lastForegroundKey) as? Date
        let now = Date()

        for session in activeSessions {
            let endDate: Date
            if let last = lastForeground {
                // Only close if the app was last seen more than the threshold ago.
                guard now.timeIntervalSince(last) > autoEndThreshold else { continue }
                endDate = last
            } else {
                // No recorded timestamp means a fresh install with a stale session.
                endDate = now
            }
            session.endTime = endDate
        }

        try? context.save()

        // End any Live Activities left from the abandoned session.
        if activeSessions.allSatisfy({ $0.endTime != nil }) {
            LiveActivityManager.endAllActivities()
        }
    }
}
// MARK: - Splash Screen View
struct SplashScreenView: View {
    @Binding var showSplash: Bool
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            Image("SplashPage")
                .resizable()
                .scaledToFit()
        }
        .onAppear {
            // Dismiss splash after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    showSplash = false
                }
            }
        }
    }
}

