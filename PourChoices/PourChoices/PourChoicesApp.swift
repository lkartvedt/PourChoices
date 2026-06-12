//
//  PourChoicesApp.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/8/26.
//

import SwiftUI
import SwiftData

@main
struct PourChoicesApp: App {
    @State private var showSplash = true
    @Environment(\.scenePhase) private var scenePhase

    /// If the app is killed while a session is active, we have no callback.
    /// Instead, we record the last time the app was in the foreground and on
    /// next launch close any session whose start is older than that timestamp
    /// by more than a reasonable session length (8 hours).
    private static let lastForegroundKey = "lastForegroundDate"
    private static let autoEndThreshold: TimeInterval = 8 * 3600

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DrinkingSession.self,
            DrinkEntry.self,
            LocationStop.self,
            NicotineEntry.self,
            FoodEntry.self,
            WaterEntry.self,
            UserProfile.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            if showSplash {
                SplashScreenView(showSplash: $showSplash)
                    .preferredColorScheme(.dark)
            } else {
                ContentView()
                    .modelContainer(sharedModelContainer)
                    .preferredColorScheme(.dark)
                    .onAppear {
                        closeAbandonedSessions()
                    }
            }
        }
        .onChange(of: scenePhase) {
            // Record whenever the app is active or going to background.
            // .background is the last reliable callback before a force-kill,
            // so we stamp the time at both transitions to get the most accurate
            // "last seen" timestamp possible.
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
    private func closeAbandonedSessions() {
        let context = sharedModelContainer.mainContext
        guard let sessions = try? context.fetch(FetchDescriptor<DrinkingSession>()) else { return }
        let activeSessions = sessions.filter { $0.isActive }
        guard !activeSessions.isEmpty else { return }

        let lastForeground = UserDefaults.standard.object(forKey: Self.lastForegroundKey) as? Date
        let now = Date()

        for session in activeSessions {
            let endDate: Date
            if let last = lastForeground {
                // Only close if the app was last seen more than the threshold ago.
                guard now.timeIntervalSince(last) > Self.autoEndThreshold else { continue }
                endDate = last
            } else {
                // No recorded timestamp means a fresh install with a stale session.
                endDate = now
            }
            session.endTime = endDate
        }

        try? context.save()
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

