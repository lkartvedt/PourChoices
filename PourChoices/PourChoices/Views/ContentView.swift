//
//  ContentView.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/8/26.
//

import SwiftUI
import SwiftData
import CoreLocation
import MapKit
import ActivityKit
import UserNotifications

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DrinkingSession.startTime, order: .reverse) private var sessions: [DrinkingSession]
    @Query private var userProfiles: [UserProfile]

    // Passed in from RootView so the same tracker instance that received
    // permission during onboarding drives the map here immediately.
    var locationTracker: LocationTracker

    @State private var selectedTab: Tab = .record
    // History tab's navigation path is lifted here so RecordTab can push a
    // session detail into it when a session ends.
    @State private var historyPath: [DrinkingSession] = []
    // Record tab's navigation path is lifted here so the widget URL handler
    // can push the active session without needing to reach into RecordTab.
    @State private var recordPath: [RecordDestination] = []

    enum Tab { case history, stats, record, friends, profile }

    var activeSession: DrinkingSession? {
        sessions.first { $0.isActive }
    }

    var userProfile: UserProfile {
        if let profile = userProfiles.first {
            return profile
        } else {
            let newProfile = UserProfile()
            modelContext.insert(newProfile)
            return newProfile
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HistoryTab(
                sessions: sessions,
                userProfile: userProfile,
                deleteSessions: deleteSessions,
                navigationPath: $historyPath
            )
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(Tab.history)

            StatsTab()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
                .tag(Tab.stats)

            RecordTab(
                activeSession: activeSession,
                userProfile: userProfile,
                locationTracker: locationTracker,
                onSessionEnded: { session in
                    // Switch to History tab and push the detail page for the ended session.
                    historyPath = [session]
                    selectedTab = .history
                },
                navigationPath: $recordPath
            )
            .tabItem { Label("Record", systemImage: "record.circle") }
            .tag(Tab.record)

            FriendsTab()
                .tabItem { Label("Friends", systemImage: "person.2") }
                .tag(Tab.friends)

            ProfileTab(profile: userProfile)
                .tabItem { Label("Profile", systemImage: "person.circle") }
                .tag(Tab.profile)
        }
        .onOpenURL { url in
            // Launched from the Live Activity widget — go straight to the active session.
            guard url.scheme == "pourchocies",
                  url.host == "active-session",
                  let session = activeSession else { return }
            selectedTab = .record
            recordPath = [.activeSession(session)]
        }
    }

    private func deleteSessions(offsets: IndexSet) {
        withAnimation {
            let inactiveSessions = sessions.filter { !$0.isActive }
            for index in offsets {
                modelContext.delete(inactiveSessions[index])
            }
        }
    }
}

// MARK: - History Tab

struct HistoryTab: View {
    let sessions: [DrinkingSession]
    let userProfile: UserProfile
    let deleteSessions: (IndexSet) -> Void
    @Binding var navigationPath: [DrinkingSession]

    var pastSessions: [DrinkingSession] { sessions.filter { !$0.isActive } }

    var body: some View {
        NavigationStack(path: $navigationPath) { // path bound to ContentView.recordPath
            Group {
                if pastSessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions Yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Your past sessions will appear here")
                    )
                } else {
                    List {
                        ForEach(pastSessions) { session in
                            NavigationLink(value: session) {
                                PastSessionRow(session: session, userProfile: userProfile)
                            }
                        }
                        .onDelete(perform: deleteSessions)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: DrinkingSession.self) { session in
                SessionDetailView(session: session, userProfile: userProfile)
            }
        }
    }
}

// MARK: - Stats Tab

struct StatsTab: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Coming Soon",
                systemImage: "chart.bar",
                description: Text("Session statistics will appear here")
            )
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Record Tab

// Typed navigation destinations within the Record tab's NavigationStack.
// Using an enum lets us push both an active session and an ended session's
// detail page from the same stack without ambiguity.
enum RecordDestination: Hashable {
    case activeSession(DrinkingSession)
    case sessionDetail(DrinkingSession)
}

struct RecordTab: View {
    @Environment(\.modelContext) private var modelContext
    let activeSession: DrinkingSession?
    let userProfile: UserProfile
    // Shared tracker from RootView — already holds location permission state
    // granted during onboarding, so the map loads immediately if allowed.
    var locationTracker: LocationTracker
    // Called by ContentView to switch tabs and push the detail into History.
    var onSessionEnded: (DrinkingSession) -> Void
    // Bound to ContentView so the URL handler can push the active session here.
    @Binding var navigationPath: [RecordDestination]
    // Step 1: warn about missing location before the safety disclaimer
    @State private var showingLocationWarning = false
    // Step 2: safety disclaimer (shown after location warning is dismissed or skipped)
    @State private var showingSessionWarning = false
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    private var locationAuthorized: Bool {
        locationTracker.authorizationStatus == .authorizedWhenInUse ||
        locationTracker.authorizationStatus == .authorizedAlways
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // Map background showing current location — interactive
                Map(position: $mapPosition) {
                    UserAnnotation()
                        .mapOverlayLevel(level: .aboveRoads)
                }
                .tint(.blue)
                .mapStyle(.standard)
                .ignoresSafeArea()
                // When permission is granted (e.g. right after onboarding), snap the
                // camera to the user's current position.
                .onChange(of: locationTracker.authorizationStatus) { _, newStatus in
                    if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                        mapPosition = .userLocation(fallback: .automatic)
                    }
                }

                // Black ombre: pure black at top, transparent by halfway — decorative only
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.8, y: 0.8)
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // Content pinned to top and bottom; Spacer passes touches through to the map
                VStack(spacing: 10) {
                    // Top text — sits over the dark gradient
                    if let _ = activeSession {
                        VStack(spacing: 4) {
                            Text("Active Session")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                            Text("You're currently tracking")
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.top, 10)
                    } else {
                        VStack(spacing: 4) {
                            Text("No Active Session")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                            Text("Start tracking your night")
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(.top, 10)
                    }

                    Spacer()
                        .allowsHitTesting(false)

                    // Bottom button
                    if let session = activeSession {
                        NavigationLink(value: RecordDestination.activeSession(session)) {
                            Label("View Session", systemImage: "arrow.right.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green, in: Capsule())
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    } else {
                        Button(action: handleStartSessionTap) {
                            Label("Start Session", systemImage: "play.fill")
                                .font(.headline)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accent, in: Capsule())
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("TextLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)
                }
            }
            .navigationDestination(for: RecordDestination.self) { destination in
                switch destination {
                case .activeSession(let session):
                    ActiveSessionView(session: session, userProfile: userProfile) { endedSession in
                        // Clear the Record tab stack, then let ContentView switch to
                        // History and push the detail there.
                        navigationPath = []
                        onSessionEnded(endedSession)
                    }
                case .sessionDetail:
                    // Unused — detail is now always in the History tab stack.
                    EmptyView()
                }
            }
            // Location warning — shown first when location access is missing
            .alert("Location Access Off", isPresented: $showingLocationWarning) {
                Button("Enable in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Continue Anyway") {
                    // User acknowledged — proceed to the safety disclaimer
                    showingSessionWarning = true
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Without location access the map won't show your position and bar hops won't be logged automatically. You can enable it in Settings > Privacy & Security > Location Services > PourChoices.")
            }
            // Safety disclaimer — shown after location check passes
            .alert("Safety Disclaimer", isPresented: $showingSessionWarning) {
                Button("Accept") { createNewSession() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("DO NOT DRIVE after consuming any alcohol. BAC calculations are estimates based on user-provided data and may not be accurate. This app cannot determine your actual BAC or fitness to drive. Never use this app to decide if you are safe to drive. Always use a designated driver, rideshare, or public transportation.")
            }
        }
    }

    // Called when the user taps "Start Session"
    private func handleStartSessionTap() {
        if locationAuthorized {
            showingSessionWarning = true
        } else {
            showingLocationWarning = true
        }
    }

    private func createNewSession() {
        // Request notification permission the first time a session is created —
        // after the user has chosen to start tracking, which is the right moment
        // to explain why we need notifications.
        NotificationManager.requestPermission()

        let session = DrinkingSession()
        withAnimation {
            modelContext.insert(session)
            navigationPath.append(.activeSession(session))
        }
        LiveActivityManager.startActivity(session: session, peakBAC: 0.0, timeToBAC: 0)
    }
}

// MARK: - Friends Tab

struct FriendsTab: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Coming Soon",
                systemImage: "person.2",
                description: Text("Connect with friends here")
            )
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Profile Tab

struct ProfileTab: View {
    @Bindable var profile: UserProfile

    var body: some View {
        NavigationStack {
            ProfileSettingsView(profile: profile)
        }
    }
}

// MARK: - Active Session View
struct ActiveSessionView: View {
    @Bindable var session: DrinkingSession
    let userProfile: UserProfile
    let onSessionEnded: ((DrinkingSession) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingAddDrink = false
    @State private var showingAddOther = false
    @State private var locationTracker = LocationTracker()
    @State private var showLocationPermissionAlert = false
    @State private var showLocationDeniedAlert = false
    @State private var showingEndSessionConfirmation = false
    @State private var cachedBAC: Double = 0.0
    @State private var cachedTimeToBAC: Double = 0.0
    @State private var cachedPeakBACDate: Date = Date()
    @State private var editingItem: TimelineItem? = nil

    private func recalculateBAC() {
        let (bac, time) = BACCalculator.estimateBAC(
            drinks: session.drinks,
            food: session.food,
            water: session.water,
            nicotine: session.nicotine,
            weight: userProfile.weight,
            sex: userProfile.sex,
            heightInches: userProfile.heightInches,
            ageYears: userProfile.age,
            sessionStart: session.startTime,
            at: Date()
        )
        cachedBAC = bac
        cachedTimeToBAC = time
        cachedPeakBACDate = Date().addingTimeInterval(time * 60)
        if bac > session.peakBAC {
            session.peakBAC = bac
        }
        // Keep the Live Activity in sync with the latest BAC values.
        LiveActivityManager.updateActivity(
            peakBAC: bac,
            timeToBAC: time,
            drinkCount: session.drinks.count,
            sessionStart: session.startTime
        )
        // Reschedule smart notifications based on updated BAC and last-activity time.
        let lastActivity = ([
            session.drinks.map(\.timestamp),
            session.food.map(\.timestamp),
            session.water.map(\.timestamp),
            session.nicotine.map(\.timestamp)
        ].flatMap { $0 }.max()) ?? session.startTime
        NotificationManager.scheduleSessionNotifications(currentBAC: bac, lastActivityDate: lastActivity)
    }
    
    var canLogLocation: Bool {
        locationTracker.authorizationStatus == .authorizedWhenInUse || 
        locationTracker.authorizationStatus == .authorizedAlways
    }
    
    var uniqueLocationsCount: Int {
        var uniqueLocationNames = Set<String>()
        
        // Add explicit location stops
        for location in session.locations {
            if let name = location.locationName, !name.isEmpty, name != "Unknown Location" {
                uniqueLocationNames.insert(name)
            }
        }
        
        // Add locations from drinks
        for drink in session.drinks {
            if let name = drink.locationName, !name.isEmpty, name != "Unknown Location", name != "Loading..." {
                uniqueLocationNames.insert(name)
            }
        }
        
        // Add locations from food
        for food in session.food {
            if let name = food.locationName, !name.isEmpty, name != "Unknown Location", name != "Loading..." {
                uniqueLocationNames.insert(name)
            }
        }
        
        // Add locations from water
        for water in session.water {
            if let name = water.locationName, !name.isEmpty, name != "Unknown Location", name != "Loading..." {
                uniqueLocationNames.insert(name)
            }
        }
        
        return uniqueLocationNames.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Big BAC Display
            VStack {
                
                Text("BAC: \(bacStatus(cachedBAC))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(String(format: "%.3f%%", cachedBAC))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(BacColors.bac(cachedBAC))
                
                TimelineView(.everyMinute) { _ in
                    let minsLeft = max(0, Int((cachedPeakBACDate.timeIntervalSinceNow / 60).rounded()))
                    Text(minsLeft > 0 ? "in \(minsLeft) min" : "now")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(BacColors.bac(cachedBAC))
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            
            // Quick stats
            HStack(spacing: 20) {
                StatBox(title: "Drinks", value: "\(session.drinks.count)")
                StatBox(title: "Locations", value: "\(uniqueLocationsCount)")
                StatBox(title: "Duration", value: durationText())
            }
            .padding()
            
            // Action buttons
            VStack(spacing: 12) {
                Button(action: { showingAddDrink = true }) {
                    Label("Log Drink", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accent, in: Capsule())
                }
                
                HStack(spacing: 12) {
                    Button(action: addPizza) {
                        Label {
                            Text("Pizza")
                        } icon: {
                            Image("PizzaDark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.darkGray), in: Capsule())
                    }
                    
                    Button(action: addWater) {
                        Label("Water", systemImage: "drop")
                            .font(.subheadline)
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.darkGray), in: Capsule())
                    }
                }
                
                HStack(spacing: 12) {
                    Button(action: { showingAddOther = true }) {
                        Label {
                            Text("Nicotine")
                        } icon: {
                            Image("CigDark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.darkGray), in: Capsule())
                    }
                    
                    Button(action: addLocation) {
                        Label("Log Location", systemImage: "location")
                            .font(.subheadline)
                            .foregroundStyle(canLogLocation ? Color.white : Color.gray)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canLogLocation ? Color(.darkGray) : Color(.systemGray5), in: Capsule())
                    }
                    .disabled(!canLogLocation)
                }
                
                // Location tracking status
                if locationTracker.isTracking {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                        Text("Auto-tracking locations")
                            .font(.caption2)
                    }
                    .foregroundStyle(.green)
                    .padding(.top, 4)
                }
                
            }
            .padding(.horizontal)
            
            // Timeline
            List {
                Section("Timeline") {
                    ForEach(combinedTimeline(), id: \.id) { item in
                        TimelineRow(item: item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteTimelineItem(item: item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingItem = item
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .foregroundStyle(.black)
                                .tint(.accent)
                            }
                    }
                }
            }
            .listStyle(.plain)
            
            // End session button
            Button(action: { showingEndSessionConfirmation = true }) {
                Text("End Session")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 200)
                    .padding()
                    .background(Color.red, in: Capsule())
            }
        }
        .sheet(isPresented: $showingAddDrink) {
            AddDrinkView(session: session, locationTracker: locationTracker)
        }
        .sheet(isPresented: $showingAddOther) {
            AddOtherView(session: session)
        }
        .sheet(item: $editingItem) { item in
            EditTimelineItemView(item: item) {
                recalculateBAC()
            }
        }
        .alert("Location Permission", isPresented: $showLocationPermissionAlert) {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enable location access to automatically track bar hops. Go to Settings > Privacy > Location Services.")
        }
        .alert("End Session", isPresented: $showingEndSessionConfirmation) {
            Button("End Session", role: .destructive) {
                endSession()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to end this session?")
        }
        .alert("Location Access Denied", isPresented: $showLocationDeniedAlert) {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Location access is required to log locations. Please enable location permissions in Settings > Privacy & Security > Location Services > Pour Choices.")
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            setupLocationTracking()
            recalculateBAC()
        }
        .onDisappear {
            locationTracker.stopTracking()
        }
        .onChange(of: session.drinks.count) { _, _ in recalculateBAC() }
        .onChange(of: session.food.count) { _, _ in recalculateBAC() }
        .onChange(of: session.water.count) { _, _ in recalculateBAC() }
        .onChange(of: session.nicotine.count) { _, _ in recalculateBAC() }
        .onChange(of: locationTracker.authorizationStatus) { oldValue, newValue in
            // Update UI when authorization status changes
            print("Authorization changed from \(oldValue.rawValue) to \(newValue.rawValue)")
            
            // If permission was just granted, start tracking
            if (oldValue == .notDetermined || oldValue == .denied) &&
               (newValue == .authorizedWhenInUse || newValue == .authorizedAlways) {
                print("Permission granted, start tracking automatically")
            }
        }
    }
    
    /// Returns true if an automatic stop with this name already exists in the session.
    private func isDuplicateAutoLocation(_ name: String) -> Bool {
        session.locations.contains { !$0.isManualLog && $0.locationName == name }
    }

    private func setupLocationTracking() {
        // Set up callback for automatic location changes
        locationTracker.onSignificantLocationChange = { location, venueName in
            let stopName = venueName ?? "Unknown Location"
            guard !self.isDuplicateAutoLocation(stopName) else {
                print("Skipping duplicate auto location: \(stopName)")
                return
            }
            let stop = LocationStop(
                locationName: stopName,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            session.locations.append(stop)
            modelContext.insert(stop)
        }
        
        // Set up callback for when permission is first granted
        locationTracker.onInitialPermissionGranted = { [weak locationTracker] in
            guard let locationTracker = locationTracker else { return }
            
            // Log initial location after permission is granted
            Task {
                // Wait for location to be acquired
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                guard let location = locationTracker.currentLocation else {
                    print("⚠️ No location available after permission granted")
                    return
                }
                
                let venueName = await locationTracker.getBestVenueName(for: location)
                
                await MainActor.run {
                    guard !self.isDuplicateAutoLocation(venueName) else {
                        print("Skipping duplicate initial location after permission: \(venueName)")
                        return
                    }
                    let stop = LocationStop(
                        locationName: venueName,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                    session.locations.append(stop)
                    modelContext.insert(stop)
                    print("Logged initial location after permission: \(venueName)")
                }
            }
        }
        
        // Check authorization status first
        let status = locationTracker.authorizationStatus
        
        switch status {
        case .notDetermined:
            // Request permission - the delegate will handle starting tracking after permission is granted
            locationTracker.requestPermission()
            
        case .authorizedWhenInUse, .authorizedAlways:
            // Permission already granted - start tracking immediately
            locationTracker.startTracking()
            
            // Log initial location after a short delay to ensure we have a location
            Task {
                // Wait a moment for location to be acquired
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                
                guard let location = locationTracker.currentLocation else {
                    print("⚠️ No location available yet")
                    return
                }
                
                let venueName = await locationTracker.getBestVenueName(for: location)
                
                await MainActor.run {
                    guard !self.isDuplicateAutoLocation(venueName) else {
                        print("Skipping duplicate initial location: \(venueName)")
                        return
                    }
                    let stop = LocationStop(
                        locationName: venueName,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                    session.locations.append(stop)
                    modelContext.insert(stop)
                    print("Logged initial location: \(venueName)")
                }
            }
            
        case .denied, .restricted:
            // Show alert that location is denied
            showLocationPermissionAlert = true
            
        @unknown default:
            break
        }
    }
    
    private func durationText() -> String {
        let duration = Date().timeIntervalSince(session.startTime)
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        return "\(hours)h \(minutes)m"
    }
    
    private func bacStatus(_ bac: Double) -> String {
        switch bac {
        case 0..<0.01: return "Too sober"
        case 0.01..<0.02: return "This is just juice"
        case 0.02..<0.03: return "Just warming up"
        case 0.03..<0.04: return "Found my personality"
        case 0.04..<0.05: return "Vibes: immaculate"
        case 0.05..<0.06: return "Feeling myself"
        case 0.06..<0.07: return "Liver is activated"
        case 0.07..<0.08: return "I love this song (every song)"
        case 0.08..<0.09: return "Legally a problem"
        case 0.09..<0.10: return "When we drink, we do it right, gettin' slizzered"
        case 0.10..<0.11: return "Texting exes"
        case 0.11..<0.12: return "Everyone's best friend"
        case 0.12..<0.13: return "Said 'I love you' to the bartender"
        case 0.13..<0.14: return "Let's order Taco Bell"
        case 0.14..<0.15: return "Where are my shoes?!"
        case 0.15..<0.16: return "Where are your keys? Wallet?? Phone???"
        case 0.16..<0.17: return "Wasted"
        case 0.17..<0.20: return "Tomorrow is going to HURT"
        case 0.20..<0.3: return "Ghost of decisions past"
        case 0.3..<1.0: return "Go the the fucking hospital"
        default: return "Do not operate heavy machinery"
        }
    }
    
    private func addPizza() {
        withAnimation {
            let location = locationTracker.currentLocation
            let pizza = FoodEntry(
                foodType: "Pizza",
                quantity: 1,
                locationName: location != nil ? "Loading..." : nil,
                latitude: location?.coordinate.latitude,
                longitude: location?.coordinate.longitude
            )
            session.food.append(pizza)
            modelContext.insert(pizza)
            
            // Fetch the actual venue name asynchronously
            if let location = location {
                Task {
                    let venueName = await locationTracker.getBestVenueName(for: location)
                    await MainActor.run {
                        pizza.locationName = venueName
                    }
                }
            }
        }
    }
    
    private func addWater() {
        withAnimation {
            let location = locationTracker.currentLocation
            let water = WaterEntry(
                volumeOz: 8.0,
                locationName: location != nil ? "Loading..." : nil,
                latitude: location?.coordinate.latitude,
                longitude: location?.coordinate.longitude
            )
            session.water.append(water)
            modelContext.insert(water)
            
            // Fetch the actual venue name asynchronously
            if let location = location {
                Task {
                    let venueName = await locationTracker.getBestVenueName(for: location)
                    await MainActor.run {
                        water.locationName = venueName
                    }
                }
            }
        }
    }
    
    private func addLocation() {
        // Check if location permission is denied
        guard canLogLocation else {
            showLocationDeniedAlert = true
            return
        }
        
        // Manual location logging
        guard let location = locationTracker.currentLocation else {
            // If we don't have a current location yet, request it
            if locationTracker.authorizationStatus == .notDetermined {
                locationTracker.requestPermission()
            }
            
            // Fallback if no location available
            let stop = LocationStop(
                locationName: "Unknown Location",
                latitude: 0,
                longitude: 0,
                isManualLog: true
            )
            session.locations.append(stop)
            modelContext.insert(stop)
            return
        }
        
        Task {
            let venueName = await locationTracker.getBestVenueName(for: location)
            
            await MainActor.run {
                let stop = LocationStop(
                    locationName: venueName,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    isManualLog: true
                )
                session.locations.append(stop)
                modelContext.insert(stop)
            }
        }
    }
    
    private func endSession() {
        // Log final location before ending
        if let location = locationTracker.currentLocation {
            Task {
                let venueName = await locationTracker.getBestVenueName(for: location)
                
                await MainActor.run {
                    let stop = LocationStop(
                        locationName: venueName,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                    session.locations.append(stop)
                    modelContext.insert(stop)
                    
                    // Stop tracking and end session
                    locationTracker.stopTracking()
                    withAnimation {
                        session.endTime = Date()
                    }
                    
                    // Dismiss the Live Activity
                    LiveActivityManager.endActivity()
                    
                    // Cancel any pending session notifications
                    NotificationManager.cancelAllSessionNotifications()
                    
                    // Navigate to session detail
                    if let onSessionEnded {
                        onSessionEnded(session)
                    } else {
                        dismiss()
                    }
                }
            }
        } else {
            // No location available, just end session
            locationTracker.stopTracking()
            withAnimation {
                session.endTime = Date()
            }
            // Dismiss the Live Activity
            LiveActivityManager.endActivity()
            // Cancel any pending session notifications
            NotificationManager.cancelAllSessionNotifications()
            if let onSessionEnded {
                onSessionEnded(session)
            } else {
                dismiss()
            }
        }
    }
    
    private func combinedTimeline() -> [TimelineItem] {
        var items: [TimelineItem] = []
        
        for drink in session.drinks {
            items.append(TimelineItem(id: drink.id.uuidString, timestamp: drink.timestamp, type: .drink(drink)))
        }
        
        for location in session.locations {
            items.append(TimelineItem(id: location.id.uuidString, timestamp: location.arrivalTime, type: .location(location)))
        }
        
        for other in session.nicotine {
            items.append(TimelineItem(id: other.id.uuidString, timestamp: other.timestamp, type: .nicotine(other)))
        }
        
        for food in session.food {
            items.append(TimelineItem(id: food.id.uuidString, timestamp: food.timestamp, type: .food(food)))
        }
        
        for water in session.water {
            items.append(TimelineItem(id: water.id.uuidString, timestamp: water.timestamp, type: .water(water)))
        }
        
        return items.sorted { $0.timestamp > $1.timestamp }
    }
    
    private func deleteTimelineItem(item: TimelineItem) {
        withAnimation {
            switch item.type {
            case .drink(let drink):
                if let drinkIndex = session.drinks.firstIndex(where: { $0.id == drink.id }) {
                    session.drinks.remove(at: drinkIndex)
                    modelContext.delete(drink)
                }
            case .location(let location):
                if let locationIndex = session.locations.firstIndex(where: { $0.id == location.id }) {
                    session.locations.remove(at: locationIndex)
                    modelContext.delete(location)
                }
            case .nicotine(let nicotine):
                if let nicotineIndex = session.nicotine.firstIndex(where: { $0.id == nicotine.id }) {
                    session.nicotine.remove(at: nicotineIndex)
                    modelContext.delete(nicotine)
                }
            case .food(let food):
                if let foodIndex = session.food.firstIndex(where: { $0.id == food.id }) {
                    session.food.remove(at: foodIndex)
                    modelContext.delete(food)
                }
            case .water(let water):
                if let waterIndex = session.water.firstIndex(where: { $0.id == water.id }) {
                    session.water.remove(at: waterIndex)
                    modelContext.delete(water)
                }
            }
        }
    }
}

func drinkAccentAsset(for drinkType: String) -> String {
    switch drinkType {
    case "Beer":        return "BeerAccent"
    case "Wine":        return "WineAccent"
    case "Shot":        return "ShotAccent"
    case "Cocktail":    return "CocktailAccent"
    case "Mixed Drink": return "MixedDrinkAccent"
    default:            return "OtherAccent"
    }
}

struct TimelineItem: Identifiable {
    let id: String
    let timestamp: Date
    let type: TimelineItemType
}

enum TimelineItemType {
    case drink(DrinkEntry)
    case location(LocationStop)
    case nicotine(NicotineEntry)
    case food(FoodEntry)
    case water(WaterEntry)
}

struct TimelineRow: View {
    let item: TimelineItem
    
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if case .drink(let drink) = item.type {
                    Image(drinkAccentAsset(for: drink.drinkType))
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)
                }
            }
            .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                HStack(spacing: 4) {
                    Text(item.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Show location if available (but not for location entries themselves)
                    if let locationName = itemLocationName, !locationName.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(locationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            if case .drink(let drink) = item.type {
                Text(String(format: "%.2f std", drink.standardDrinks))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    var itemLocationName: String? {
        switch item.type {
        case .drink(let drink):
            return drink.locationName
        case .food(let food):
            return food.locationName
        case .water(let water):
            return water.locationName
        case .location, .nicotine:
            return nil // Don't show location for location entries or other entries
        }
    }
    
    var icon: String {
        switch item.type {
        case .drink: return "wineglass"
        case .location: return "location.fill"
        case .nicotine: return "smoke"
        case .food: return "fork.knife"
        case .water: return "drop.fill"
        }
    }
    
    var color: Color {
        switch item.type {
        case .drink: return .accent
        case .location: return .green
        case .nicotine: return .gray
        case .food: return Color(.systemOrange)
        case .water: return Color(.systemCyan)
        }
    }
    
    var title: String {
        switch item.type {
        case .drink(let drink):
            return drink.name ?? drink.drinkType
        case .location(let location):
            return location.locationName ?? "Unknown Location"
        case .nicotine(let other):
            return other.type
        case .food(let food):
            return "\(food.quantity) slice\(food.quantity > 1 ? "s" : "") of \(food.foodType)"
        case .water(let water):
            return "\(Int(water.volumeOz))oz Water"
        }
    }
}

// MARK: - Edit Timeline Item View

struct EditTimelineItemView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let item: TimelineItem
    let onSave: () -> Void

    @State private var editedTime: Date
    @State private var editedLocation: String

    init(item: TimelineItem, onSave: @escaping () -> Void) {
        self.item = item
        self.onSave = onSave
        _editedTime = State(initialValue: item.timestamp)
        // Pre-populate location from whatever field the item exposes
        let loc: String?
        switch item.type {
        case .drink(let d):   loc = d.locationName
        case .food(let f):    loc = f.locationName
        case .water(let w):   loc = w.locationName
        case .location(let l): loc = l.locationName
        case .nicotine:        loc = nil
        }
        _editedLocation = State(initialValue: loc ?? "")
    }

    /// Whether this item type stores a location field.
    private var hasLocation: Bool {
        if case .nicotine = item.type { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Time") {
                    DatePicker("Time", selection: $editedTime, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                }

                if hasLocation {
                    Section("Location") {
                        TextField("Location name", text: $editedLocation)
                            .autocorrectionDisabled()
                    }
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        applyEdits()
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }

    private func applyEdits() {
        let loc: String? = editedLocation.trimmingCharacters(in: .whitespaces).isEmpty ? nil : editedLocation.trimmingCharacters(in: .whitespaces)
        switch item.type {
        case .drink(let d):
            d.timestamp = editedTime
            d.locationName = loc
        case .food(let f):
            f.timestamp = editedTime
            f.locationName = loc
        case .water(let w):
            w.timestamp = editedTime
            w.locationName = loc
        case .location(let l):
            l.arrivalTime = editedTime
            l.locationName = loc
        case .nicotine(let n):
            n.timestamp = editedTime
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Add Drink View
struct DrinkSubtype {
    let name: String
    let abv: Double
    let oz: Double
}

struct CustomDrinkSubtype: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let category: String   // e.g. "Beer", "Shot"
    let name: String
    let abv: Double
    let oz: Double
}

struct CustomDrinkStorage {
    private static let key = "customDrinkSubtypes"

    static func load() -> [CustomDrinkSubtype] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let drinks = try? JSONDecoder().decode([CustomDrinkSubtype].self, from: data)
        else { return [] }
        return drinks
    }

    static func save(_ drinks: [CustomDrinkSubtype]) {
        if let data = try? JSONEncoder().encode(drinks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func add(_ drink: CustomDrinkSubtype) {
        var current = load()
        current.append(drink)
        save(current)
    }

    static func remove(id: UUID) {
        var current = load()
        current.removeAll { $0.id == id }
        save(current)
    }
}

struct AddDrinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: DrinkingSession
    let locationTracker: LocationTracker
    
    @State private var drinkType = "Beer"
    @State private var name = ""
    @State private var alcoholContent = 5.0
    @State private var volumeOz = 12.0
    @State private var selectedSubtype: String = "None"
    @State private var isDouble = false
    @State private var customDrinks: [CustomDrinkSubtype] = []
    
    @FocusState private var focusedField: AddDrinkField?
    
    enum AddDrinkField {
        case name
        case abv
        case volume
    }
    
    let drinkTypes = ["Beer", "Wine", "Shot", "Cocktail", "Mixed Drink", "Other"]
    
    static let subtypes: [String: [DrinkSubtype]] = [
        "Beer": [
            DrinkSubtype(name: "Light Beer", abv: 3.5, oz: 12),
            DrinkSubtype(name: "Seltzer", abv: 5.0, oz: 12),
            DrinkSubtype(name: "IPA", abv: 6.5, oz: 12),
            DrinkSubtype(name: "Craft / Stout", abv: 8.0, oz: 12),
        ],
        "Wine": [
            DrinkSubtype(name: "White", abv: 12.0, oz: 5),
            DrinkSubtype(name: "Rosé", abv: 12.0, oz: 5),
            DrinkSubtype(name: "Red", abv: 14.0, oz: 5),
            DrinkSubtype(name: "Champagne", abv: 12.0, oz: 5),
        ],
        "Shot": [
            DrinkSubtype(name: "Vodka", abv: 40.0, oz: 1.5),
            DrinkSubtype(name: "Tequila", abv: 40.0, oz: 1.5),
            DrinkSubtype(name: "Orange", abv: 20.0, oz: 2),
            DrinkSubtype(name: "Fireball", abv: 33.0, oz: 1.5),
            DrinkSubtype(name: "Green Tea", abv: 20.0, oz: 2),
            DrinkSubtype(name: "Jäger", abv: 35.0, oz: 1.5),
            DrinkSubtype(name: "Liqueur", abv: 20.0, oz: 1.5),
            DrinkSubtype(name: "Overproof", abv: 75.0, oz: 1.5),
        ],
        "Cocktail": [
            DrinkSubtype(name: "Martini", abv: 28.0, oz: 4),
            DrinkSubtype(name: "Espresso Martini", abv: 20.0, oz: 4),
            DrinkSubtype(name: "Margarita", abv: 15.0, oz: 4),
            DrinkSubtype(name: "Old Fashioned", abv: 32.0, oz: 4),
            DrinkSubtype(name: "Spritz / Aperol", abv: 8.0, oz: 5),
            DrinkSubtype(name: "Sour", abv: 15.0, oz: 4),
        ],
        "Mixed Drink": [
            DrinkSubtype(name: "Gin & Tonic", abv: 12.0, oz: 8),
            DrinkSubtype(name: "Vodka Soda", abv: 12.0, oz: 8),
            DrinkSubtype(name: "Pina Colada", abv: 10.0, oz: 8),
            DrinkSubtype(name: "Long Island", abv: 22.0, oz: 8),
            DrinkSubtype(name: "Rum & Coke", abv: 12.0, oz: 8),
            DrinkSubtype(name: "Jungle Juice", abv: 15.0, oz: 8),
        ],
        "Other": [
            DrinkSubtype(name: "Frosé", abv: 10.0, oz: 8),
            DrinkSubtype(name: "Hard Cider", abv: 5.0, oz: 12),
            DrinkSubtype(name: "Hard Kombucha", abv: 6.0, oz: 12),
            DrinkSubtype(name: "Sake", abv: 15.0, oz: 6),
            DrinkSubtype(name: "Mead", abv: 12.0, oz: 5),
        ],
    ]
    
    var currentSubtypes: [DrinkSubtype] {
        let builtIn = AddDrinkView.subtypes[drinkType] ?? []
        let custom = customDrinks
            .filter { $0.category == drinkType }
            .map { DrinkSubtype(name: $0.name, abv: $0.abv, oz: $0.oz) }
        return builtIn + custom
    }
    
    var supportsDouble: Bool {
        ["Shot", "Cocktail", "Mixed Drink"].contains(drinkType)
    }
    
    // Maps display name to asset name
    func assetName(for type: String) -> String {
        switch type {
        case "Mixed Drink": return "MixedDrink"
        default: return type
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Drink type grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(drinkTypes, id: \.self) { type in
                            Button(action: {
                                drinkType = type
                                selectedSubtype = "None"
                                isDouble = false
                                updateDefaults(for: type)
                            }) {
                                // Add Drink 'Buttons'
                                SelectableTileLabel(assetName: assetName(for: type), label: type, isSelected: drinkType == type, showBorder: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Subtype picker
                    if !currentSubtypes.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Style")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.bottom, 6)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    // "None" chip
                                    Button(action: {
                                        selectedSubtype = "None"
                                        updateDefaults(for: drinkType)
                                        isDouble = false
                                    }) {
                                        Text("None")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(selectedSubtype == "None" ? Color.black : Color.primary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule().fill(selectedSubtype == "None" ? Color.accent : Color(.secondarySystemGroupedBackground))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    
                                    ForEach(currentSubtypes, id: \.name) { subtype in
                                        Button(action: {
                                            selectedSubtype = subtype.name
                                            alcoholContent = subtype.abv
                                            volumeOz = subtype.oz
                                            isDouble = false
                                        }) {
                                            Text(subtype.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundStyle(selectedSubtype == subtype.name ? Color.black : Color.primary)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(
                                                    Capsule().fill(selectedSubtype == subtype.name ? Color.accent : Color(.secondarySystemGroupedBackground))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            if isCustomDrink(name: subtype.name, category: drinkType) {
                                                Button(role: .destructive) {
                                                    deleteCustomDrink(name: subtype.name, category: drinkType)
                                                } label: {
                                                    Label("Delete Custom Style", systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            
                            // Make it a double
                            if supportsDouble {
                                Button(action: {
                                    isDouble.toggle()
                                    volumeOz = isDouble ? volumeOz * 2 : volumeOz / 2
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: isDouble ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isDouble ? Color.accent : Color.secondary)
                                        Text("Make it a double")
                                            .font(.subheadline)
                                            .foregroundStyle(isDouble ? Color.primary : Color.secondary)
                                    }
                                    .padding(.horizontal)
                                    .padding(.top, 12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Details section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Details")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 6)
                        
                        VStack(spacing: 0) {
                            HStack {
                                Text("ABV %")
                                Spacer()
                                TextField("ABV", value: $alcoholContent, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                    .focused($focusedField, equals: .abv)
                            }
                            .padding()
                            
                            Divider().padding(.leading)
                            
                            HStack {
                                Text("Volume (oz)")
                                Spacer()
                                TextField("oz", value: $volumeOz, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                    .focused($focusedField, equals: .volume)
                            }
                            .padding()
                            
                            Divider().padding(.leading)
                            
                            HStack {
                                TextField("Name (optional)", text: $name)
                                    .focused($focusedField, equals: .name)
                                    .submitLabel(.done)
                                    .onSubmit { focusedField = nil }
                            }
                            .padding()
                            
                            if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                                Divider().padding(.leading)
                                Button(action: {
                                    focusedField = nil
                                    saveCustomDrink()
                                }) {
                                    HStack {
                                        Image(systemName: "star.fill")
                                            .foregroundStyle(.accent)
                                        Text("Save as Custom Style")
                                            .font(.subheadline)
                                            .foregroundStyle(.accent)
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(.accent)
                                    }
                                    .padding()
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Divider().padding(.leading)
                            
                            let drink = DrinkEntry(drinkType: drinkType, alcoholContent: alcoholContent, volumeOz: volumeOz)
                            HStack {
                                Text("Standard drinks")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.2f", drink.standardDrinks))
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        focusedField = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        focusedField = nil
                        addDrink()
                        dismiss()
                    }
                }
            }
            .onTapGesture {
                focusedField = nil
            }
            .onAppear {
                customDrinks = CustomDrinkStorage.load()
            }
        }
    }
    
    private func updateDefaults(for type: String) {
        switch type {
        case "Beer":
            alcoholContent = 5.0
            volumeOz = 12.0
        case "Wine":
            alcoholContent = 12.0
            volumeOz = 5.0
        case "Shot":
            alcoholContent = 40.0
            volumeOz = 1.5
        case "Cocktail":
            alcoholContent = 20.0
            volumeOz = 4.0
        case "Mixed Drink":
            alcoholContent = 10.0
            volumeOz = 8.0
        default:
            alcoholContent = 5.0
            volumeOz = 12.0
        }
    }
    
    private func addDrink() {
        let location = locationTracker.currentLocation
        let drink = DrinkEntry(
            drinkType: drinkType,
            subtype: selectedSubtype == "None" ? nil : selectedSubtype,
            name: name.isEmpty ? nil : name,
            alcoholContent: alcoholContent,
            volumeOz: volumeOz,
            locationName: location != nil ? "Loading..." : nil,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude
        )
        session.drinks.append(drink)
        modelContext.insert(drink)
        
        // Fetch the actual venue name asynchronously
        if let location = location {
            Task {
                let venueName = await locationTracker.getBestVenueName(for: location)
                await MainActor.run {
                    drink.locationName = venueName
                }
            }
        }
    }

    private func saveCustomDrink() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // Don't save if name matches an existing built-in subtype
        let builtInNames = (AddDrinkView.subtypes[drinkType] ?? []).map { $0.name.lowercased() }
        guard !builtInNames.contains(trimmedName.lowercased()) else { return }

        // Don't save duplicates within the same category
        let alreadyExists = customDrinks.contains {
            $0.category == drinkType && $0.name.lowercased() == trimmedName.lowercased()
        }
        guard !alreadyExists else {
            // Already exists — just select it
            selectedSubtype = customDrinks.first {
                $0.category == drinkType && $0.name.lowercased() == trimmedName.lowercased()
            }?.name ?? trimmedName
            return
        }

        let custom = CustomDrinkSubtype(category: drinkType, name: trimmedName, abv: alcoholContent, oz: volumeOz)
        CustomDrinkStorage.add(custom)
        customDrinks = CustomDrinkStorage.load()
        selectedSubtype = trimmedName
    }

    private func isCustomDrink(name: String, category: String) -> Bool {
        customDrinks.contains { $0.category == category && $0.name == name }
    }

    private func deleteCustomDrink(name: String, category: String) {
        if let drink = customDrinks.first(where: { $0.category == category && $0.name == name }) {
            CustomDrinkStorage.remove(id: drink.id)
            customDrinks = CustomDrinkStorage.load()
            if selectedSubtype == name {
                selectedSubtype = "None"
                updateDefaults(for: drinkType)
            }
        }
    }
}

// MARK: - Add Other View
struct AddOtherView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: DrinkingSession
    
    // Persists preferred Zyn strength across sessions
    @AppStorage("preferredZynMg") private var preferredZynMg: Double = 3.0
    
    @State private var selectedType = "Zyn"
    @State private var nicotineMg = 3.0
    @State private var zynStrength: Double = 3.0  // 3 or 6
    
    @FocusState private var isMgFocused: Bool
    
    struct NicotineType {
        let name: String
        let asset: String
        let defaultMg: Double
        let label: String
    }
    
    let nicotineTypes: [NicotineType] = [
        NicotineType(name: "Zyn",        asset: "Zyn3",  defaultMg: 3.0,  label: "Zyn"),
        NicotineType(name: "Vape",       asset: "Vape",  defaultMg: 3.0,  label: "Vape"),
        NicotineType(name: "Cigarette",  asset: "Cig",   defaultMg: 2.0,  label: "Cigarette"),
        NicotineType(name: "Cigar",      asset: "Cigar", defaultMg: 10.0, label: "Cigar"),
        NicotineType(name: "Gum",        asset: "Gum",   defaultMg: 3.0,  label: "Gum"),
        NicotineType(name: "Dip",        asset: "Dip",   defaultMg: 5.0,  label: "Dip"),
    ]
    
    // The display name logged — includes strength for Zyn
    var loggedTypeName: String {
        selectedType == "Zyn" ? "Zyn - \(Int(zynStrength))mg" : selectedType
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Type grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(nicotineTypes, id: \.name) { type in
                            Button(action: {
                                selectedType = type.name
                                if type.name == "Zyn" {
                                    zynStrength = preferredZynMg
                                    nicotineMg = preferredZynMg
                                } else {
                                    nicotineMg = type.defaultMg
                                }
                            }) {
                                SelectableTileLabel(
                                    assetName: selectedType == "Zyn" && type.name == "Zyn" ? (zynStrength == 6 ? "Zyn6" : "Zyn3") : type.asset,
                                    label: type.label,
                                    isSelected: selectedType == type.name,
                                    showBorder: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Zyn strength selector — only when Zyn is selected
                    if selectedType == "Zyn" {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Strength")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.bottom, 6)
                            
                            HStack(spacing: 12) {
                                ForEach([3.0, 6.0], id: \.self) { mg in
                                    Button(action: {
                                        zynStrength = mg
                                        nicotineMg = mg
                                    }) {
                                        Text("\(Int(mg))mg")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(zynStrength == mg ? Color.black : Color.primary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(zynStrength == mg ? Color.accent : Color(.secondarySystemGroupedBackground))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                            
                            // Set as default
                            Button(action: {
                                preferredZynMg = zynStrength
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: preferredZynMg == zynStrength ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(preferredZynMg == zynStrength ? Color.accent : Color.secondary)
                                    Text(preferredZynMg == zynStrength ? "Default strength" : "Set as my default")
                                        .font(.caption)
                                        .foregroundStyle(preferredZynMg == zynStrength ? Color.primary : Color.secondary)
                                }
                                .padding(.horizontal)
                                .padding(.top, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Details section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Details")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 6)
                        
                        VStack(spacing: 0) {
                            HStack {
                                Text("Nicotine (mg)")
                                Spacer()
                                TextField("mg", value: $nicotineMg, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                    .focused($isMgFocused)
                            }
                            .padding()
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Nicotine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isMgFocused = false
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        isMgFocused = false
                        addEntry()
                        dismiss()
                    }
                }
            }
            .onTapGesture {
                isMgFocused = false
            }
            .onAppear {
                // Apply saved Zyn preference on first load
                zynStrength = preferredZynMg
                nicotineMg = preferredZynMg
            }
        }
    }
    
    private func addEntry() {
        let entry = NicotineEntry(type: loggedTypeName, nicotineMg: nicotineMg, notes: nil)
        session.nicotine.append(entry)
        modelContext.insert(entry)
    }
}

// MARK: - Past Session Row
struct PastSessionRow: View {
    let session: DrinkingSession
    let userProfile: UserProfile
    
    var peakBAC: Double {
        session.peakBAC
    }
    
    var uniqueLocationsCount: Int {
        var uniqueLocationNames = Set<String>()
        
        // Add explicit location stops
        for location in session.locations {
            if let name = location.locationName, !name.isEmpty, name != "Unknown Location" {
                uniqueLocationNames.insert(name)
            }
        }
        
        // Add locations from drinks
        for drink in session.drinks {
            if let name = drink.locationName, !name.isEmpty, name != "Unknown Location", name != "Loading..." {
                uniqueLocationNames.insert(name)
            }
        }
        
        // Add locations from food
        for food in session.food {
            if let name = food.locationName, !name.isEmpty, name != "Unknown Location", name != "Loading..." {
                uniqueLocationNames.insert(name)
            }
        }
        
        // Add locations from water
        for water in session.water {
            if let name = water.locationName, !name.isEmpty, name != "Unknown Location", name != "Loading..." {
                uniqueLocationNames.insert(name)
            }
        }
        
        return uniqueLocationNames.count
    }
    
    struct TightLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 4) {
                configuration.icon
                configuration.title
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.startTime, style: .date)
                .font(.headline)
            
            HStack {
                Label("\(session.drinks.count) drinks", systemImage: "wineglass")
                Text("•")
                Label("\(uniqueLocationsCount) \(uniqueLocationsCount == 1 ? "stop" : "stops")", systemImage: "location")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(TightLabelStyle())
            
            Text("Peak BAC: \(String(format: "%.3f%%", peakBAC))")
                .font(.caption)
                .foregroundStyle(BacColors.bac(peakBAC))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Session Detail View
struct SessionDetailView: View {
    let session: DrinkingSession
    let userProfile: UserProfile
    
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    var peakBAC: Double {
        session.peakBAC
    }
    
    var sortedLocations: [LocationStop] {
        session.locations.sorted(by: { $0.arrivalTime < $1.arrivalTime })
    }
    
    var uniqueLocationsCount: Int {
        var uniqueLocationNames = Set<String>()
        for location in session.locations {
            if let name = location.locationName, !name.isEmpty, name != "Unknown Location" {
                uniqueLocationNames.insert(name)
            }
        }
        for drink in session.drinks {
            if let name = drink.locationName, !name.isEmpty, name != "Unknown Location", name != "Loading..." {
                uniqueLocationNames.insert(name)
            }
        }
        for food in session.food {
            if let name = food.locationName, !name.isEmpty, name != "Unknown Location", name != "Loading..." {
                uniqueLocationNames.insert(name)
            }
        }
        for water in session.water {
            if let name = water.locationName, !name.isEmpty, name != "Unknown Location", name != "Loading..." {
                uniqueLocationNames.insert(name)
            }
        }
        return uniqueLocationNames.count
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                peakBACHeader
                mapSection
                sessionInfoSection
                drinksSection
                locationsSection
                otherEntriesSection
            }
            .padding(.vertical)
        }
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var peakBACHeader: some View {
        VStack(spacing: 8) {
            Text("Peak BAC")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(String(format: "%.3f%%", peakBAC))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(BacColors.bac(peakBAC))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder private var mapSection: some View {
        if !sortedLocations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Route")
                    .font(.headline)
                    .padding(.horizontal)
                Map(coordinateRegion: $mapRegion, annotationItems: sortedLocations) { location in
                    MapAnnotation(coordinate: location.coordinate) {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(annotationColor(for: location))
                                    .frame(width: 32, height: 32)
                                    .shadow(radius: 3)
                                if location == sortedLocations.first {
                                    Image(systemName: "flag.fill")
                                        .foregroundColor(.white)
                                        .font(.system(size: 14))
                                } else if location == sortedLocations.last && session.endTime != nil {
                                    Image(systemName: "flag.checkered")
                                        .foregroundColor(.white)
                                        .font(.system(size: 14))
                                } else {
                                    Text("\(sortedLocations.firstIndex(where: { $0.id == location.id })! + 1)")
                                        .foregroundColor(.white)
                                        .font(.system(size: 14, weight: .bold))
                                }
                            }
                            Text(location.locationName ?? "Unknown")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemBackground))
                                .cornerRadius(4)
                                .shadow(radius: 2)
                        }
                    }
                }
                .frame(height: 300)
                .cornerRadius(12)
                .padding(.horizontal)
                .onAppear { calculateMapRegion() }
            }
        }
    }

    @ViewBuilder private var sessionInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Info")
                .font(.headline)
                .padding(.horizontal)
            GroupBox {
                VStack(spacing: 12) {
                    HStack {
                        Text("Total Drinks")
                        Spacer()
                        Text("\(session.drinks.count)")
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack {
                        Text("Start")
                        Spacer()
                        Text(session.startTime, format: .dateTime)
                            .foregroundStyle(.secondary)
                    }
                    if let endTime = session.endTime {
                        Divider()
                        HStack {
                            Text("End")
                            Spacer()
                            Text(endTime, format: .dateTime)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(durationText(from: session.startTime, to: endTime))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    HStack {
                        Text("Locations")
                        Spacer()
                        Text("\(uniqueLocationsCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder private var drinksSection: some View {
        if !session.drinks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Drinks (\(session.drinks.count))")
                    .font(.headline)
                    .padding(.horizontal)
                ForEach(session.drinks.sorted(by: { $0.timestamp < $1.timestamp })) { drink in
                    GroupBox {
                        HStack {
                            Image(drinkAccentAsset(for: drink.drinkType))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text([drink.drinkType, drink.subtype].compactMap { $0 }.joined(separator: " - "))
                                            .font(.headline)
                                        if let customName = drink.name {
                                            Text(customName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                HStack {
                                    Text("\(String(format: "%.1f", drink.alcoholContent))% ABV • \(String(format: "%.1f", drink.volumeOz)) oz • \(String(format: "%.2f std", drink.standardDrinks))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                if let locationName = drink.locationName {
                                    HStack {
                                        Image(systemName: "location.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                        Text(locationName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(drink.timestamp.formatted(date: .omitted, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder private var locationsSection: some View {
        if !sortedLocations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Locations (\(uniqueLocationsCount))")
                    .font(.headline)
                    .padding(.horizontal)
                ForEach(sortedLocations) { location in
                    GroupBox {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(annotationColor(for: location))
                                    .frame(width: 28, height: 28)
                                if location == sortedLocations.first {
                                    Image(systemName: "flag.fill")
                                        .foregroundColor(.white)
                                        .font(.system(size: 12))
                                } else if location == sortedLocations.last && session.endTime != nil {
                                    Image(systemName: "flag.checkered")
                                        .foregroundColor(.white)
                                        .font(.system(size: 12))
                                } else {
                                    Text("\(sortedLocations.firstIndex(where: { $0.id == location.id })! + 1)")
                                        .foregroundColor(.white)
                                        .font(.system(size: 12, weight: .bold))
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(location.locationName ?? "Unknown")
                                    .font(.headline)
                                Text(location.arrivalTime, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder private var otherEntriesSection: some View {
        if !session.nicotine.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nicotine (\(session.nicotine.count))")
                    .font(.headline)
                    .padding(.horizontal)
                ForEach(session.nicotine.sorted(by: { $0.timestamp < $1.timestamp })) { entry in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "smoke")
                                    .foregroundStyle(.gray)
                                Text(entry.type)
                                    .font(.headline)
                                Spacer()
                                Text(entry.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let notes = entry.notes {
                                Text(notes)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    private func annotationColor(for location: LocationStop) -> Color {
        if location == sortedLocations.first {
            return .green
        } else if location == sortedLocations.last && session.endTime != nil {
            return .red
        } else {
            return .blue
        }
    }
    
    private func calculateMapRegion() {
        guard !sortedLocations.isEmpty else { return }
        
        let coordinates = sortedLocations.map { $0.coordinate }
        
        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.01)
        )
        
        mapRegion = MKCoordinateRegion(center: center, span: span)
    }
    
    private func durationText(from start: Date, to end: Date) -> String {
        let duration = end.timeIntervalSince(start)
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Onboarding View
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var profile: UserProfile
    // Shared tracker passed from RootView so the map reacts immediately when permission is granted
    var locationTracker: LocationTracker
    
    @State private var weight: Double = 150
    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 8
    @State private var sex: String = "Male"
    @FocusState private var focusedField: OnboardingField?
    
    enum OnboardingField {
        case weight
    }
    
    var totalHeightInches: Double {
        Double(heightFeet * 12 + heightInches)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.accent)
                        
                        Text("Welcome to Pour Choices")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Help us provide accurate BAC estimates")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 30)
                    
                    // Form
                    VStack(spacing: 0) {
                        GroupBox {
                            VStack(spacing: 16) {
                                HStack {
                                    Text("Age")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(profile.age)")
                                        .foregroundStyle(.secondary)
                                }
                                
                                Divider()
                                
                                HStack {
                                    Text("Height")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        Picker("", selection: $heightFeet) {
                                            ForEach(4...7, id: \.self) { feet in
                                                Text("\(feet)'").tag(feet)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                        .foregroundStyle(.white)
                                        
                                        Picker("", selection: $heightInches) {
                                            ForEach(0...11, id: \.self) { inches in
                                                Text("\(inches)\"").tag(inches)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                        .foregroundStyle(.white)
                                    }
                                }
                                
                                Divider()
                                
                                HStack {
                                    Text("Weight (lbs)")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    TextField("150", value: $weight, format: .number)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 100)
                                        .focused($focusedField, equals: .weight)
                                        .submitLabel(.done)
                                        .onSubmit {
                                            focusedField = nil
                                        }
                                }
                                
                                Divider()
                                
                                HStack {
                                    Text("Sex")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Picker("Sex", selection: $sex) {
                                        Text("Male").tag("Male")
                                        Text("Female").tag("Female")
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 200)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .padding(.horizontal)
                        
                        Text("This information is used to calculate your estimated BAC. You can update it anytime in your profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 8)
                    }
                    
                    Spacer(minLength: 40)
                    
                    // Buttons
                    VStack(spacing: 12) {
                        Button(action: saveAndContinue) {
                            Text("Continue")
                                .font(.headline)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accent, in: Capsule())
                        }
                        
                        Button(action: skipOnboarding) {
                            Text("Skip for now")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text("Skipping will make BAC calculations less accurate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .contentMargins(.bottom, 0, for: .scrollContent)
            .onTapGesture {
                focusedField = nil
            }
        }
    }
    
    private func saveAndContinue() {
        focusedField = nil
        profile.weight = weight
        profile.heightInches = totalHeightInches
        profile.sex = sex
        profile.hasCompletedOnboarding = true
        // Ask for location right after the user finishes setting up their profile
        // so the home map can load their position immediately.
        locationTracker.requestPermission()
        dismiss()
    }
    
    private func skipOnboarding() {
        focusedField = nil
        profile.hasCompletedOnboarding = true
        locationTracker.requestPermission()
        dismiss()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: DrinkingSession.self, UserProfile.self, configurations: config)
    let profile = UserProfile(
        weight: 170,
        heightInches: 70,
        sex: "Male",
        birthdate: Calendar.current.date(byAdding: .year, value: -25, to: Date()),
        hasCompletedAgeVerification: true,
        hasCompletedOnboarding: true
    )
    container.mainContext.insert(profile)
    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithOpaqueBackground()
    tabAppearance.backgroundColor = UIColor.black
    UITabBar.appearance().standardAppearance = tabAppearance
    UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    UITabBar.appearance().overrideUserInterfaceStyle = .dark
    return ContentView(locationTracker: LocationTracker())
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
