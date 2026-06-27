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
import FirebaseCore
import FirebaseAuth
import UIKit

// MARK: - AppDelegate
//
// Firebase Phone Auth in SwiftUI requires THREE things to be explicitly
// handled (swizzling is disabled via Info.plist):
//
//   1. Forward the APNs device token  ->  Auth.auth().setAPNSToken()
//   2. Forward silent push notifications  ->  Auth.auth().canHandleNotification()
//   3. Forward custom-scheme URLs  ->  Auth.auth().canHandle()
//
// IMPORTANT: Auth.auth() must NOT be called before UIApplication.shared is
// fully available. Firebase Auth's internal tokenManager is only initialized
// when UIApplication.sharedApplication succeeds, which is NOT guaranteed
// during SwiftUI App.init(). All Auth.auth() access is deferred to
// didFinishLaunchingWithOptions or later.

final class AppDelegate: NSObject, UIApplicationDelegate {

    /// Stored APNs token — forwarded to Firebase Auth when phone verification starts.
    static var pendingAPNsToken: Data?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // UIApplication.shared is fully available here, so Firebase Auth's
        // internal tokenManager will be correctly initialized when Auth.auth()
        // is first accessed.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        print("[AppDelegate] Firebase configured, UIApplication available")

        // Request APNs device token. Firebase Phone Auth sends a silent push
        // to verify the device before it sends the SMS code.
        application.registerForRemoteNotifications()
        print("[AppDelegate] registerForRemoteNotifications() called")

        return true
    }

    // MARK: 1) Store APNs token for Firebase Auth

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[AppDelegate] APNs token received: \(hex.prefix(16))…")

        // Store the token. We forward it to Auth.auth().setAPNSToken() right
        // before calling verifyPhoneNumber, because calling setAPNSToken too
        // early can crash (Firebase's internal tokenManager may be nil).
        AppDelegate.pendingAPNsToken = deviceToken
        print("[AppDelegate] APNs token stored (will forward to Auth when needed)")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[AppDelegate] APNs registration FAILED: \(error)")
    }

    // MARK: 2) Forward silent push to Firebase Auth

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Guard: don't touch Auth.auth() before Firebase is configured.
        guard FirebaseApp.app() != nil else {
            completionHandler(.newData)
            return
        }
        if Auth.auth().canHandleNotification(userInfo) {
            print("[AppDelegate] Silent push handled by Firebase Auth")
            completionHandler(.noData)
            return
        }
        print("[AppDelegate] Remote notification (not Firebase Auth)")
        completionHandler(.newData)
    }

    // MARK: 3) Forward custom-scheme URL to Firebase Auth

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        // Guard: don't touch Auth.auth() before Firebase is configured.
        guard FirebaseApp.app() != nil else { return false }
        if Auth.auth().canHandle(url) {
            print("[AppDelegate] URL handled by Firebase Auth: \(url.scheme ?? "")")
            return true
        }
        return false
    }
}

// MARK: - App

@main
struct PourChoicesApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var showSplash = true
    @State private var auth: AuthenticationManager
    @State private var subscriptions: SubscriptionManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // FirebaseApp.configure() happens in AppDelegate.didFinishLaunchingWithOptions,
        // which runs AFTER App.init() but BEFORE body is evaluated.
        // AuthenticationManager.init() no longer touches Auth.auth(), so this is safe.
        // restoreSession() is called via .task on the scene (see body).
        _auth = State(initialValue: AuthenticationManager())
        _subscriptions = State(initialValue: SubscriptionManager())

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.black
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().overrideUserInterfaceStyle = .dark
    }

    private static let lastForegroundKey = "lastForegroundDate"
    private static let autoEndThreshold: TimeInterval = 8 * 3600

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

        // Explicit URL in the app's own Application Support directory.
        // Without this, SwiftData may target the App Group shared container,
        // which causes hundreds of CoreData sandbox permission error logs.
        let storeURL = URL.applicationSupportDirectory.appending(path: "PourChoices.store")
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
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
            Group {
                if showSplash {
                    SplashScreenView(showSplash: $showSplash)
                } else {
                    RootView()
                        .environment(auth)
                        .environment(subscriptions)
                        .modelContainer(Self.sharedModelContainer)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                // Called once when the view appears. By this point
                // didFinishLaunchingWithOptions has run, UIApplication.shared
                // is fully available, and Firebase Auth's tokenManager is
                // initialized — so Auth.auth() is safe to call.
                auth.restoreSession()
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active || scenePhase == .background {
                UserDefaults.standard.set(Date(), forKey: Self.lastForegroundKey)
            }
        }
    }

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
                guard now.timeIntervalSince(last) > autoEndThreshold else { continue }
                endDate = last
            } else {
                endDate = now
            }
            session.endTime = endDate
        }

        try? context.save()

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    showSplash = false
                }
            }
        }
    }
}

