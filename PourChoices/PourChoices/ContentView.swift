//
//  ContentView.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/8/26.
//

import SwiftUI
import SwiftData
import CoreLocation

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
                    VStack(spacing: 20) {
                        Image("Cheers")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 140)
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
    
    var currentBAC: Double {
        BACCalculator.estimateBAC(
            drinks: session.drinks,
            food: session.food,
            water: session.water,
            weight: userProfile.weight,
            sex: userProfile.sex,
            at: Date()
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Big BAC Display
            VStack(spacing: 8) {
                Text("Current BAC")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(String(format: "%.3f%%", currentBAC))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(bacColor(currentBAC))
                
                Text(bacStatus(currentBAC))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
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
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
            
            // Quick stats
            HStack(spacing: 20) {
                StatBox(title: "Drinks", value: "\(session.drinks.count)")
                StatBox(title: "Locations", value: "\(session.locations.count)")
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
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.darkGray), in: Capsule())
                    }
                }
            }
            .padding(.horizontal)
            
            // Timeline
            List {
                Section("Timeline") {
                    ForEach(combinedTimeline(), id: \.id) { item in
                        TimelineRow(item: item)
                    }
                }
            }
            .listStyle(.plain)
            
            // End session button
            Button(action: endSession) {
                Text("End Session")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red, in: Capsule())
            }
            .padding()
        }
        .sheet(isPresented: $showingAddDrink) {
            AddDrinkView(session: session)
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
        .onAppear {
            setupLocationTracking()
        }
        .onDisappear {
            locationTracker.stopTracking()
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
        
        // Start tracking
        locationTracker.startTracking()
        
        // Check permission status
        if locationTracker.authorizationStatus == .denied || 
           locationTracker.authorizationStatus == .restricted {
            showLocationPermissionAlert = true
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
            let pizza = FoodEntry(foodType: "Pizza", quantity: 1)
            session.food.append(pizza)
            modelContext.insert(pizza)
        }
    }
    
    private func addWater() {
        withAnimation {
            let water = WaterEntry(volumeOz: 8.0)
            session.water.append(water)
            modelContext.insert(water)
        }
    }
    
    private func addLocation() {
        // Manual location logging
        guard let location = locationTracker.currentLocation else {
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
        locationTracker.stopTracking()
        withAnimation {
            session.endTime = Date()
        }
        // Navigate back to home
        dismiss()
    }
    
    private func combinedTimeline() -> [TimelineItem] {
        var items: [TimelineItem] = []
        
        for drink in session.drinks {
            items.append(TimelineItem(id: drink.id.uuidString, timestamp: drink.timestamp, type: .drink(drink)))
        }
        
        for location in session.locations {
            items.append(TimelineItem(id: location.id.uuidString, timestamp: location.arrivalTime, type: .location(location)))
        }
        
        for other in session.otherEntries {
            items.append(TimelineItem(id: other.id.uuidString, timestamp: other.timestamp, type: .other(other)))
        }
        
        for food in session.food {
            items.append(TimelineItem(id: food.id.uuidString, timestamp: food.timestamp, type: .food(food)))
        }
        
        for water in session.water {
            items.append(TimelineItem(id: water.id.uuidString, timestamp: water.timestamp, type: .water(water)))
        }
        
        return items.sorted { $0.timestamp > $1.timestamp }
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
    case other(OtherEntry)
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
                Text(item.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    
    var icon: String {
        switch item.type {
        case .drink: return "wineglass"
        case .location: return "location.fill"
        case .other: return "smoke"
        case .food: return "fork.knife"
        case .water: return "drop.fill"
        }
    }
    
    var color: Color {
        switch item.type {
        case .drink: return .blue
        case .location: return .green
        case .other: return .orange
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
        case .other(let other):
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
    
    @State private var drinkType = "Beer"
    @State private var name = ""
    @State private var alcoholContent = 5.0
    @State private var volumeOz = 12.0
    
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
                }
                
                Section("Details") {
                    HStack {
                        Text("ABV %")
                        Spacer()
                        TextField("ABV", value: $alcoholContent, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("Volume (oz)")
                        Spacer()
                        TextField("oz", value: $volumeOz, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                
                Section {
                    let drink = DrinkEntry(drinkType: drinkType, alcoholContent: alcoholContent, volumeOz: volumeOz)
                    Text("Standard drinks: \(String(format: "%.2f", drink.standardDrinks))")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addDrink()
                        dismiss()
                    }
                }
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
        let drink = DrinkEntry(
            drinkType: drinkType,
            name: name.isEmpty ? nil : name,
            alcoholContent: alcoholContent,
            volumeOz: volumeOz
        )
        session.drinks.append(drink)
        modelContext.insert(drink)
    }
}

// MARK: - Add Other View
struct AddOtherView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: DrinkingSession
    
    @State private var type = "Zyn"
    @State private var notes = ""
    
    let types = ["Zyn", "Cigarette", "Vape", "Other"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(types, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                }
                
                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addEntry()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func addEntry() {
        let entry = OtherEntry(type: type, notes: notes.isEmpty ? nil : notes)
        session.otherEntries.append(entry)
        modelContext.insert(entry)
    }
}

// MARK: - Past Session Row
struct PastSessionRow: View {
    let session: DrinkingSession
    let userProfile: UserProfile
    
    var peakBAC: Double {
        guard let lastDrink = session.drinks.max(by: { $0.timestamp < $1.timestamp }) else {
            return 0
        }
        return BACCalculator.estimateBAC(
            drinks: session.drinks,
            weight: userProfile.weight,
            sex: userProfile.sex,
            at: lastDrink.timestamp
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.startTime, style: .date)
                .font(.headline)
            
            HStack {
                Label("\(session.drinks.count) drinks", systemImage: "wineglass")
                Text("•")
                Label("\(session.locations.count) stops", systemImage: "location")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            Text("Peak BAC: \(String(format: "%.3f%%", peakBAC))")
                .font(.caption)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Session Detail View
struct SessionDetailView: View {
    let session: DrinkingSession
    let userProfile: UserProfile
    
    var body: some View {
        List {
            Section("Session Info") {
                LabeledContent("Start", value: session.startTime, format: .dateTime)
                if let endTime = session.endTime {
                    LabeledContent("End", value: endTime, format: .dateTime)
                }
            }
            
            Section("Drinks (\(session.drinks.count))") {
                ForEach(session.drinks.sorted(by: { $0.timestamp < $1.timestamp })) { drink in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(drink.name ?? drink.drinkType)
                            .font(.headline)
                        Text("\(String(format: "%.1f", drink.alcoholContent))% ABV • \(String(format: "%.1f", drink.volumeOz)) oz")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(drink.timestamp, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if !session.locations.isEmpty {
                Section("Locations (\(session.locations.count))") {
                    ForEach(session.locations.sorted(by: { $0.arrivalTime < $1.arrivalTime })) { location in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(location.locationName ?? "Unknown")
                                .font(.headline)
                            Text(location.arrivalTime, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            if !session.otherEntries.isEmpty {
                Section("Other (\(session.otherEntries.count))") {
                    ForEach(session.otherEntries.sorted(by: { $0.timestamp < $1.timestamp })) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.type)
                                .font(.headline)
                            if let notes = entry.notes {
                                Text(notes)
                                    .font(.subheadline)
                            }
                            Text(entry.timestamp, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Session Details")
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
                            ForEach(4...7, id: \.self) { feet in
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
