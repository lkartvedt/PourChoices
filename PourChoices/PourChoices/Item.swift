//
//  Models.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/8/26.
//

import Foundation
import SwiftData
import CoreLocation

// MARK: - Session (Your night out)
@Model
final class DrinkingSession {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var notes: String?
    var peakBAC: Double = 0.0 // Track the highest BAC recorded during this session
    
    @Relationship(deleteRule: .cascade, inverse: \DrinkEntry.session)
    var drinks: [DrinkEntry] = []
    
    @Relationship(deleteRule: .cascade, inverse: \LocationStop.session)
    var locations: [LocationStop] = []
    
    @Relationship(deleteRule: .cascade, inverse: \NicotineEntry.session)
    var nicotine: [NicotineEntry] = []
    
    @Relationship(deleteRule: .cascade, inverse: \FoodEntry.session)
    var food: [FoodEntry] = []
    
    @Relationship(deleteRule: .cascade, inverse: \WaterEntry.session)
    var water: [WaterEntry] = []
    
    init(startTime: Date = Date()) {
        self.id = UUID()
        self.startTime = startTime
    }
    
    var isActive: Bool {
        endTime == nil
    }
}

// MARK: - Drink Entry
@Model
final class DrinkEntry {
    var id: UUID
    var timestamp: Date
    var drinkType: String // "Beer", "Wine", "Shot", "Cocktail", etc.
    var subtype: String? // Optional subtype e.g. "Light Beer", "Rosé"
    var name: String? // Optional specific name
    var alcoholContent: Double // % ABV
    var volumeOz: Double // Volume in oz
    var locationName: String? // Where you had this drink
    var latitude: Double? // Location coordinates
    var longitude: Double? // Location coordinates
    
    var session: DrinkingSession?
    
    init(timestamp: Date = Date(), drinkType: String, subtype: String? = nil, name: String? = nil, alcoholContent: Double, volumeOz: Double, locationName: String? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.drinkType = drinkType
        self.subtype = subtype
        self.name = name
        self.alcoholContent = alcoholContent
        self.volumeOz = volumeOz
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
    }
    
    // Calculate standard drinks (1 standard drink = 0.6 oz pure alcohol)
    var standardDrinks: Double {
        (volumeOz * (alcoholContent / 100.0)) / 0.6
    }
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
// MARK: - Location Stop (Bar hop)
@Model
final class LocationStop {
    var id: UUID
    var arrivalTime: Date
    var departureTime: Date?
    var locationName: String?
    var latitude: Double
    var longitude: Double
    
    var session: DrinkingSession?
    
    init(arrivalTime: Date = Date(), locationName: String? = nil, latitude: Double, longitude: Double) {
        self.id = UUID()
        self.arrivalTime = arrivalTime
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Other Entries (Nicotine, etc.)
@Model
final class NicotineEntry {
    var id: UUID
    var timestamp: Date
    var type: String // "Zyn - 3mg", "Cigarette", "Vape - Puff", etc.
    var nicotineMg: Double // Amount of nicotine in mg
    var notes: String?
    
    var session: DrinkingSession?
    
    init(timestamp: Date = Date(), type: String, nicotineMg: Double = 0, notes: String? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.type = type
        self.nicotineMg = nicotineMg
        self.notes = notes
    }
}

// MARK: - Food Entry (Pizza, etc.)
@Model
final class FoodEntry {
    var id: UUID
    var timestamp: Date
    var foodType: String // "Pizza", "Burger", etc.
    var quantity: Int // Number of slices/items
    var locationName: String? // Where you had this food
    var latitude: Double? // Location coordinates
    var longitude: Double? // Location coordinates
    
    var session: DrinkingSession?
    
    init(timestamp: Date = Date(), foodType: String, quantity: Int = 1, locationName: String? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.foodType = foodType
        self.quantity = quantity
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
    }
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - Water Entry
@Model
final class WaterEntry {
    var id: UUID
    var timestamp: Date
    var volumeOz: Double
    var locationName: String? // Where you had this water
    var latitude: Double? // Location coordinates
    var longitude: Double? // Location coordinates
    
    var session: DrinkingSession?
    
    init(timestamp: Date = Date(), volumeOz: Double = 8.0, locationName: String? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.volumeOz = volumeOz
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
    }
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - User Profile (for BAC calculation)
@Model
final class UserProfile {
    var weight: Double // in lbs
    var heightInches: Double // height in inches
    var sex: String // "Male" or "Female" (affects BAC calculation)
    var birthdate: Date? // User's birthdate for age verification
    var hasCompletedAgeVerification: Bool // Track if they've passed age verification
    var hasCompletedOnboarding: Bool // Track if they've gone through initial setup
    
    init(weight: Double = 150, heightInches: Double = 68, sex: String = "Male", birthdate: Date? = nil, hasCompletedAgeVerification: Bool = false, hasCompletedOnboarding: Bool = false) {
        self.weight = weight
        self.heightInches = heightInches
        self.sex = sex
        self.birthdate = birthdate
        self.hasCompletedAgeVerification = hasCompletedAgeVerification
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
    
    // Computed property for age
    var age: Int {
        guard let birthdate = birthdate else { return 21 }
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birthdate, to: Date())
        return ageComponents.year ?? 21
    }
    
    // Check if user is 21 or older
    var isOver21: Bool {
        age >= 21
    }
}

// MARK: - BAC Calculator
/// Bridges session data to BACSolver for physiologically-grounded BAC estimation.
struct BACCalculator {

    /// Estimate current BAC using the BACSolver ODE model.
    ///
    /// All session events recorded at or before `time` are converted to
    /// `BACEvent` values and handed to `BACSolver.simulate`. The simulation
    /// runs from session start through `time` plus a short tail so the solver
    /// can settle, and `currentBAC` from the result is returned.
    static func estimateBAC(drinks: [DrinkEntry],
                             food: [FoodEntry],
                             water: [WaterEntry],
                             nicotine: [NicotineEntry],
                             weight: Double,      // lbs
                             sex: String,
                             heightInches: Double,
                             ageYears: Int,
                             sessionStart: Date,
                             at time: Date) -> (Double, Double) {

        // Convert user profile units to what BACSolver expects.
        let weightKg     = weight * 0.453592
        let heightCm     = heightInches * 2.54
        let solverSex: Sex = sex.lowercased() == "female" ? .female : .male

        let person = Person(
            sex: solverSex,
            ageYears: Double(ageYears),
            heightCm: heightCm,
            weightKg: weightKg
        )

        // Build BACEvent list from session data. Time is seconds since sessionStart.
        var events: [BACEvent] = []

        for drink in drinks where drink.timestamp <= time {
            let tSec = drink.timestamp.timeIntervalSince(sessionStart)
            let duration = drink.drinkType == "Shot" ? 5.0/60.0 : 0.0
            let volumeML = drink.volumeOz * 29.5735
            let grams    = BACSolver.grams(volumeML: volumeML, abvPercent: drink.alcoholContent)
            events.append(BACEvent(time: tSec, kind: .finishedDrink(grams: grams), duration: duration))
        }

        for f in food where f.timestamp <= time {
            let tSec = f.timestamp.timeIntervalSince(sessionStart)
            // Each quantity unit is one "slice" — emit one food event per slice.
            for _ in 0 ..< f.quantity {
                events.append(BACEvent(time: tSec, kind: .food))
            }
        }

        for w in water where w.timestamp <= time {
            let tSec = w.timestamp.timeIntervalSince(sessionStart)
            events.append(BACEvent(time: tSec, kind: .water))
        }
        
        for n in nicotine where n.timestamp <= time {
            let tSec = n.timestamp.timeIntervalSince(sessionStart)
            events.append(BACEvent(time: tSec, kind: .nicotine))
        }

        // No events means zero BAC.
        guard !events.isEmpty else { return (0,0) }

        let solver = BACSolver(person: person)
        // Simulate up to the current moment; no extra tail needed for live display.
        //let nowSec  = time.timeIntervalSince(sessionStart)
        let result  = solver.simulate(events: events, until: 6*3600, stepSeconds: 1)
        
        var bacs: [(Double,Double)] = []
        for sample in result.curve {
            bacs.append((sample.bac, sample.ka))
        }
        print(bacs.map{$0.0})
        print(bacs.map{$0.1})
        

        // Find the BAC sample closest to `nowSec`.
        //guard let sample = result.curve.min(by: { abs($0.time - nowSec) < abs($1.time - nowSec) }) else {
        //    return 0
        //}
        return (result.peakBAC, result.peakTime)
    }

    /// Convenience overload used by `ActiveSessionView` (derives session start
    /// from the earliest drink timestamp, matching legacy behaviour).
    static func estimateBAC(drinks: [DrinkEntry],
                             food: [FoodEntry],
                             water: [WaterEntry],
                             nicotine: [NicotineEntry],
                             weight: Double,
                             sex: String,
                             heightInches: Double,
                             ageYears: Int,
                             at time: Date) -> (Double, Double) {

        // Use the earliest drink as the session-start anchor.
        let sessionStart = drinks.map(\.timestamp).min() ?? time
        return estimateBAC(
            drinks: drinks, food: food, water: water, nicotine: nicotine,
            weight: weight, sex: sex,
            heightInches: heightInches, ageYears: ageYears,
            sessionStart: sessionStart, at: time
        )
    }
}

