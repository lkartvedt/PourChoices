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

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DrinkingSession.startTime, order: .reverse) private var sessions: [DrinkingSession]
    @Query private var userProfiles: [UserProfile]
    
    @State private var showingNewSession = false
    @State private var showingAgeVerification = false
    @State private var showingOnboarding = false
    @State private var showingSessionWarning = false
    @State private var navigationPath = NavigationPath()
    
    var activeSession: DrinkingSession? {
        sessions.first { $0.isActive }
    }
    
    var userProfile: UserProfile {
        if let profile = userProfiles.first {
            return profile
        } else {
            // Create default profile
            let newProfile = UserProfile()
            modelContext.insert(newProfile)
            return newProfile
        }
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                if let session = activeSession {
                    // Show a card to navigate into the active session
                    VStack(spacing: 10) {
                        Image("Cheers")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .padding(.top, 30)
                        
                        Text("Active Session")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("You're currently tracking")
                            .foregroundStyle(.secondary)
                        
                        NavigationLink(value: session) {
                            Label("View Session", systemImage: "arrow.right.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green, in: Capsule())
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                    }
                    .padding(.bottom, 30)
                    
                    // Past sessions list
                    if !sessions.isEmpty {
                        List {
                            Section("Past Sessions") {
                                ForEach(sessions.filter { !$0.isActive }) { session in
                                    NavigationLink {
                                        SessionDetailView(session: session, userProfile: userProfile)
                                    } label: {
                                        PastSessionRow(session: session, userProfile: userProfile)
                                    }
                                }
                                .onDelete(perform: deleteSessions)
                            }
                        }
                    } else {
                        Spacer()
                    }
                } else {
                    // No active session - fixed header
                    VStack(spacing: 10) {
                        Image("Cheers")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .padding(.top, 30)
                        
                        Text("No Active Session")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Start tracking your night")
                            .foregroundStyle(.secondary)
                        
                        Button(action: startNewSession) {
                            Label("Start Session", systemImage: "play.fill")
                                .font(.headline)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accent, in: Capsule())
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                    }
                    .padding(.bottom, 30)
                    
                    // Past sessions list
                    if !sessions.isEmpty {
                        List {
                            Section("Past Sessions") {
                                ForEach(sessions.filter { !$0.isActive }) { session in
                                    NavigationLink {
                                        SessionDetailView(session: session, userProfile: userProfile)
                                    } label: {
                                        PastSessionRow(session: session, userProfile: userProfile)
                                    }
                                }
                                .onDelete(perform: deleteSessions)
                            }
                        }
                    } else {
                        Spacer()
                    }
                }
            }
            .navigationDestination(for: DrinkingSession.self) { session in
                ActiveSessionView(session: session, userProfile: userProfile)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("TextLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ProfileSettingsView(profile: userProfile)
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
            }
            .sheet(isPresented: $showingAgeVerification) {
                AgeVerificationView(profile: userProfile, showingOnboarding: $showingOnboarding)
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showingOnboarding) {
                OnboardingView(profile: userProfile)
                    .interactiveDismissDisabled()
            }
            .alert("Safety Disclaimer", isPresented: $showingSessionWarning) {
                Button("Accept") {
                    createNewSession()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("DO NOT DRIVE after consuming any alcohol. BAC calculations are estimates based on user-provided data and may not be accurate. This app cannot determine your actual BAC or fitness to drive. Never use this app to decide if you are safe to drive. Always use a designated driver, rideshare, or public transportation.")
            }
            .onAppear {
                // Check if user needs age verification first
                if !userProfile.hasCompletedAgeVerification {
                    showingAgeVerification = true
                } else if !userProfile.hasCompletedOnboarding {
                    showingOnboarding = true
                }
            }
        }
    }
    
    private func startNewSession() {
        showingSessionWarning = true
    }
    
    private func createNewSession() {
        withAnimation {
            let session = DrinkingSession()
            modelContext.insert(session)
            // Navigate into the new session
            navigationPath.append(session)
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

// MARK: - Active Session View
struct ActiveSessionView: View {
    @Bindable var session: DrinkingSession
    let userProfile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingAddDrink = false
    @State private var showingAddOther = false
    @State private var locationTracker = LocationTracker()
    @State private var showLocationPermissionAlert = false
    @State private var showLocationDeniedAlert = false
    
    var peakBACAndTime: (Double, Double) {
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

        // Update peak BAC if this is higher
        if bac > session.peakBAC {
            session.peakBAC = bac
        }

        return (bac, time)
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
                
                Text("BAC: \(bacStatus(peakBACAndTime.0))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(String(format: "%.3f%%", peakBACAndTime.0))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(bacColor(peakBACAndTime.0))
                
                Text("in \(Int(peakBACAndTime.1.rounded())) min")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(bacColor(peakBACAndTime.0))
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
                    }
                    .onDelete(perform: deleteTimelineItem)
                }
            }
            .listStyle(.plain)
            
            // End session button
            Button(action: endSession) {
                Text("End Session")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 200)
                    .padding()
                    .background(Color.red, in: Capsule())
            }
            .padding()
        }
        .sheet(isPresented: $showingAddDrink) {
            AddDrinkView(session: session, locationTracker: locationTracker)
        }
        .sheet(isPresented: $showingAddOther) {
            AddOtherView(session: session)
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
        .onAppear {
            setupLocationTracking()
        }
        .onDisappear {
            locationTracker.stopTracking()
        }
        .onChange(of: locationTracker.authorizationStatus) { oldValue, newValue in
            // Update UI when authorization status changes
            print("📍 Authorization changed from \(oldValue.rawValue) to \(newValue.rawValue)")
            
            // If permission was just granted, start tracking
            if (oldValue == .notDetermined || oldValue == .denied) &&
               (newValue == .authorizedWhenInUse || newValue == .authorizedAlways) {
                print("✅ Permission granted, tracking will start automatically")
            }
        }
    }
    
    private func setupLocationTracking() {
        // Set up callback for automatic location changes
        locationTracker.onSignificantLocationChange = { location, venueName in
            let stopName = venueName ?? "Unknown Location"
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
                
                // Check if we already have a location for this session
                await MainActor.run {
                    guard session.locations.isEmpty else {
                        print("✅ Session already has locations")
                        return
                    }
                }
                
                let venueName = await locationTracker.getBestVenueName(for: location)
                
                await MainActor.run {
                    let stop = LocationStop(
                        locationName: venueName,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                    session.locations.append(stop)
                    modelContext.insert(stop)
                    print("✅ Logged initial location after permission: \(venueName)")
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
                
                // Check if we already have a location for this session
                guard session.locations.isEmpty else {
                    print("✅ Session already has locations")
                    return
                }
                
                let venueName = await locationTracker.getBestVenueName(for: location)
                
                await MainActor.run {
                    let stop = LocationStop(
                        locationName: venueName,
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                    session.locations.append(stop)
                    modelContext.insert(stop)
                    print("✅ Logged initial location: \(venueName)")
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
    
    private func bacColor(_ bac: Double) -> Color {
        switch bac {
        case 0..<0.03: return .green
        case 0.03..<0.08: return .yellow
        case 0.08..<0.15: return .orange
        default: return .red
        }
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
                longitude: 0
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
                    longitude: location.coordinate.longitude
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
                    
                    // Navigate back to home
                    dismiss()
                }
            }
        } else {
            // No location available, just end session
            locationTracker.stopTracking()
            withAnimation {
                session.endTime = Date()
            }
            dismiss()
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
    
    private func deleteTimelineItem(at offsets: IndexSet) {
        let timeline = combinedTimeline()
        
        for index in offsets {
            let item = timeline[index]
            
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
}

struct TimelineItem {
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
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 30)
            
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
        case .drink: return .blue
        case .location: return .green
        case .nicotine: return .orange
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
struct AddDrinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: DrinkingSession
    let locationTracker: LocationTracker
    
    @State private var drinkType = "Beer"
    @State private var name = ""
    @State private var alcoholContent = 5.0
    @State private var volumeOz = 12.0
    
    @FocusState private var focusedField: AddDrinkField?
    
    enum AddDrinkField {
        case name
        case abv
        case volume
    }
    
    let drinkTypes = ["Beer", "Wine", "Shot", "Cocktail", "Mixed Drink", "Other"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Drink Type") {
                    Picker("Type", selection: $drinkType) {
                        ForEach(drinkTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: drinkType) { oldValue, newValue in
                        updateDefaults(for: newValue)
                    }
                    
                    TextField("Name (optional)", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
                        .onSubmit {
                            focusedField = nil
                        }
                }
                
                Section("Details") {
                    HStack {
                        Text("ABV %")
                        Spacer()
                        TextField("ABV", value: $alcoholContent, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($focusedField, equals: .abv)
                    }
                    
                    HStack {
                        Text("Volume (oz)")
                        Spacer()
                        TextField("oz", value: $volumeOz, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($focusedField, equals: .volume)
                    }
                }
                
                Section {
                    let drink = DrinkEntry(drinkType: drinkType, alcoholContent: alcoholContent, volumeOz: volumeOz)
                    Text("Standard drinks: \(String(format: "%.2f", drink.standardDrinks))")
                        .foregroundStyle(.secondary)
                }
            }
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
            alcoholContent = 15.0
            volumeOz = 4.0
        case "Mixed Drink":
            alcoholContent = 10.0
            volumeOz = 8.0
        default:
            break
        }
    }
    
    private func addDrink() {
        let location = locationTracker.currentLocation
        let drink = DrinkEntry(
            drinkType: drinkType,
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
}

// MARK: - Add Other View
struct AddOtherView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: DrinkingSession
    
    @State private var selectedType = "Zyn - 3mg"
    @State private var nicotineMg = 3.0
    
    @FocusState private var focusedField: AddOtherField?
    
    enum AddOtherField {
        case nicotine
    }
    
    let nicotineTypes: [(name: String, defaultMg: Double)] = [
        ("Zyn - 3mg", 3.0),
        ("Zyn - 6mg", 6.0),
        ("Vape - Puff", 0.2),
        ("Vape - Session", 3.0),
        ("Vape - Full cart", 20.0),
        ("Cigarette", 2.0),
        ("Cigar", 10.0),
        ("Nicotine gum", 3.0),
        ("Dip", 5.0)
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(nicotineTypes, id: \.name) { type in
                            Text(type.name).tag(type.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedType) { oldValue, newValue in
                        updateDefaults(for: newValue)
                    }
                }
                
                Section("Details") {
                    HStack {
                        Text("Nicotine (mg)")
                        Spacer()
                        TextField("mg", value: $nicotineMg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($focusedField, equals: .nicotine)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Nicotine")
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
                        addEntry()
                        dismiss()
                    }
                }
            }
            .onTapGesture {
                focusedField = nil
            }
        }
    }
    
    private func updateDefaults(for type: String) {
        if let nicType = nicotineTypes.first(where: { $0.name == type }) {
            nicotineMg = nicType.defaultMg
        }
    }
    
    private func addEntry() {
        let entry = NicotineEntry(type: selectedType, nicotineMg: nicotineMg, notes: nil)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.startTime, style: .date)
                .font(.headline)
            
            HStack {
                Label("\(session.drinks.count) drinks", systemImage: "wineglass")
                Text("•")
                Label("\(uniqueLocationsCount) stops", systemImage: "location")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            Text("Peak BAC: \(String(format: "%.3f%%", peakBAC))")
                .font(.caption)
                .foregroundStyle(bacColor(peakBAC))
        }
        .padding(.vertical, 4)
    }
    
    private func bacColor(_ bac: Double) -> Color {
        switch bac {
        case 0..<0.03: return .green
        case 0.03..<0.08: return .yellow
        case 0.08..<0.15: return .orange
        default: return .red
        }
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
                .foregroundStyle(bacColor(peakBAC))
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
                        Text("Total Drinks")
                        Spacer()
                        Text("\(session.drinks.count)")
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack {
                        Text("Locations")
                        Spacer()
                        Text("\(session.locations.count)")
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
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "wineglass.fill")
                                    .foregroundStyle(.blue)
                                Text(drink.name ?? drink.drinkType)
                                    .font(.headline)
                                Spacer()
                                Text(String(format: "%.2f std", drink.standardDrinks))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("\(String(format: "%.1f", drink.alcoholContent))% ABV • \(String(format: "%.1f", drink.volumeOz)) oz")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(drink.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let locationName = drink.locationName {
                                HStack {
                                    Image(systemName: "location.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                    Text(locationName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                Text("Locations (\(session.locations.count))")
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
                Text("Other (\(session.nicotine.count))")
                    .font(.headline)
                    .padding(.horizontal)
                ForEach(session.nicotine.sorted(by: { $0.timestamp < $1.timestamp })) { entry in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "smoke")
                                    .foregroundStyle(.orange)
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
    
    private func bacColor(_ bac: Double) -> Color {
        switch bac {
        case 0..<0.03: return .green
        case 0.03..<0.08: return .yellow
        case 0.08..<0.15: return .orange
        default: return .red
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

// MARK: - Profile Settings View
struct ProfileSettingsView: View {
    @Bindable var profile: UserProfile
    @FocusState private var isWeightFocused: Bool
    
    var heightFeet: Int {
        Int(profile.heightInches) / 12
    }
    
    var heightInches: Int {
        Int(profile.heightInches) % 12
    }
    
    var body: some View {
        Form {
            Section("Your Info") {
                DatePicker("Birthdate", 
                          selection: Binding(
                            get: { profile.birthdate ?? Date() },
                            set: { profile.birthdate = $0 }
                          ),
                          displayedComponents: .date)
                
                HStack {
                    Text("Age")
                    Spacer()
                    Text("\(profile.age)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Height")
                    Spacer()
                    HStack(spacing: 8) {
                        Picker("", selection: Binding(
                            get: { heightFeet },
                            set: { newFeet in
                                profile.heightInches = Double(newFeet * 12 + heightInches)
                            }
                        )) {
                            ForEach(3...8, id: \.self) { feet in
                                Text("\(feet)'").tag(feet)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .foregroundStyle(.white)
                        
                        Picker("", selection: Binding(
                            get: { heightInches },
                            set: { newInches in
                                profile.heightInches = Double(heightFeet * 12 + newInches)
                            }
                        )) {
                            ForEach(0...11, id: \.self) { inches in
                                Text("\(inches)\"").tag(inches)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .foregroundStyle(.white)
                    }
                }
                
                HStack {
                    Text("Weight (lbs)")
                    Spacer()
                    TextField("Weight", value: $profile.weight, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .focused($isWeightFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isWeightFocused = false
                        }
                }
                
                HStack {
                    Text("Sex")
                    Spacer()
                    Picker("Sex", selection: $profile.sex) {
                        Text("Male").tag("Male")
                        Text("Female").tag("Female")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Important", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.headline)
                    
                    Text("This app is for tracking purposes only. BAC calculations are estimates and should NOT be used to determine if you're safe to drive.")
                        .font(.caption)
                    
                    Text("DO NOT DRIVE after drinking, regardless of your estimated BAC. Use a rideshare, taxi, public transit, or designated driver.")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            isWeightFocused = false
        }
    }
}

// MARK: - Age Verification View
struct AgeVerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var profile: UserProfile
    @Binding var showingOnboarding: Bool
    
    @State private var birthdate = Calendar.current.date(byAdding: .year, value: -21, to: Date()) ?? Date()
    @State private var showUnder21Alert = false
    
    var calculatedAge: Int {
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birthdate, to: Date())
        return ageComponents.year ?? 0
    }
    
    var isOver21: Bool {
        calculatedAge >= 21
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                
                // Header
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.accent)
                    
                    Text("Age Verification")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("You must be 21 or older to use this app")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Birthdate picker
                VStack(spacing: 16) {
                    Text("Enter your birthdate")
                        .font(.headline)
                    
                    DatePicker("Birthdate", 
                              selection: $birthdate,
                              in: ...Date(),
                              displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .padding(.horizontal)
                }
                .padding(.vertical, 30)
                .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Continue button
                Button(action: verifyAge) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isOver21 ? Color.accent : Color.gray, in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .disabled(!isOver21)
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Age Requirement Not Met", isPresented: $showUnder21Alert) {
                Button("OK") { }
            } message: {
                Text("You must be 21 years or older to use Pour Choices. This app is intended for legal drinking age users only.")
            }
        }
    }
    
    private func verifyAge() {
        guard isOver21 else {
            showUnder21Alert = true
            return
        }
        
        // Save birthdate and mark verification as complete
        profile.birthdate = birthdate
        profile.hasCompletedAgeVerification = true
        
        // Dismiss this sheet first, then show onboarding
        dismiss()
        
        // Delay to allow sheet dismissal to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showingOnboarding = true
        }
    }
}

// MARK: - Onboarding View
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var profile: UserProfile
    
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
        dismiss()
    }
    
    private func skipOnboarding() {
        focusedField = nil
        profile.hasCompletedOnboarding = true
        dismiss()
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: DrinkingSession.self, UserProfile.self, configurations: config)
    
    // Create a pre-configured profile
    let profile = UserProfile(
        weight: 170,
        heightInches: 70,
        sex: "Male",
        birthdate: Calendar.current.date(byAdding: .year, value: -25, to: Date()),
        hasCompletedAgeVerification: true,
        hasCompletedOnboarding: true
    )
    container.mainContext.insert(profile)
    
    return ContentView()
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
