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
        NavigationStack {
            VStack(spacing: 0) {
                if let session = activeSession {
                    // Active session view
                    ActiveSessionView(session: session, userProfile: userProfile)
                } else {
                    // No active session
                    VStack(spacing: 20) {
                        Image(systemName: "wineglass")
                            .font(.system(size: 80))
                            .foregroundStyle(.secondary)
                        
                        Text("No Active Session")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Start tracking your night")
                            .foregroundStyle(.secondary)
                        
                        Button(action: startNewSession) {
                            Label("Start Session", systemImage: "play.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                    }
                    .frame(maxHeight: .infinity)
                    
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
                    }
                }
            }
            .navigationTitle("Pour Choices")
            .toolbar {
                if activeSession == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            ProfileSettingsView(profile: userProfile)
                        } label: {
                            Image(systemName: "person.circle")
                        }
                    }
                }
            }
        }
    }
    
    private func startNewSession() {
        withAnimation {
            let session = DrinkingSession()
            modelContext.insert(session)
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
    
    @State private var showingAddDrink = false
    @State private var showingAddOther = false
    @State private var locationTracker = LocationTracker()
    @State private var showLocationPermissionAlert = false
    
    var currentBAC: Double {
        BACCalculator.estimateBAC(
            drinks: session.drinks,
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
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                }
                
                HStack(spacing: 12) {
                    Button(action: { showingAddOther = true }) {
                        Label("Zyn/Cig", systemImage: "smoke")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Button(action: addLocation) {
                        Label("Log Location", systemImage: "location")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
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
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
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
        case 0..<0.03: return "Sober vibes"
        case 0.03..<0.08: return "Feeling it"
        case 0.08..<0.15: return "Drunk (don't drive)"
        default: return "Blackout territory"
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
                    
                    // Show location for drinks
                    if case .drink(let drink) = item.type, let location = drink.locationName {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 8))
                            Text(location)
                        }
                        .font(.caption)
                        .foregroundStyle(.green)
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
    
    var icon: String {
        switch item.type {
        case .drink: return "wineglass"
        case .location: return "location.fill"
        case .other: return "smoke"
        }
    }
    
    var color: Color {
        switch item.type {
        case .drink: return .blue
        case .location: return .green
        case .other: return .orange
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
    @State private var locationName = "Fetching location..."
    @State private var currentLat: Double?
    @State private var currentLon: Double?
    @State private var isLoadingLocation = true
    
    let drinkTypes = ["Beer", "Wine", "Shot", "Cocktail", "Mixed Drink", "Other"]
    
    // Pass the location tracker from parent
    var locationTracker: LocationTracker?
    
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
                
                Section("Location") {
                    HStack {
                        if isLoadingLocation {
                            ProgressView()
                                .padding(.trailing, 8)
                        } else {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.green)
                                .padding(.trailing, 4)
                        }
                        
                        TextField("Location", text: $locationName)
                    }
                    
                    Text("Auto-detected from Maps. Edit if incorrect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            .onAppear {
                fetchCurrentLocation()
            }
        }
    }
    
    private func fetchCurrentLocation() {
        guard let tracker = locationTracker,
              let location = tracker.currentLocation else {
            locationName = "Unknown Location"
            isLoadingLocation = false
            return
        }
        
        currentLat = location.coordinate.latitude
        currentLon = location.coordinate.longitude
        
        Task {
            let venueName = await tracker.getBestVenueName(for: location)
            await MainActor.run {
                locationName = venueName
                isLoadingLocation = false
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
            volumeOz: volumeOz,
            locationName: locationName.isEmpty ? nil : locationName,
            latitude: currentLat,
            longitude: currentLon
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
                        HStack(spacing: 4) {
                            Text(drink.timestamp, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if let location = drink.locationName {
                                Text("•")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 2) {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 8))
                                    Text(location)
                                }
                                .font(.caption)
                                .foregroundStyle(.green)
                            }
                        }
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
    
    var body: some View {
        Form {
            Section("Your Info") {
                HStack {
                    Text("Weight (lbs)")
                    Spacer()
                    TextField("Weight", value: $profile.weight, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                
                Picker("Sex", selection: $profile.sex) {
                    Text("Male").tag("Male")
                    Text("Female").tag("Female")
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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: DrinkingSession.self, inMemory: true)
}
