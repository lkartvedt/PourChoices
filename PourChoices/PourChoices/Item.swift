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
    
    @Relationship(deleteRule: .cascade, inverse: \DrinkEntry.session)
    var drinks: [DrinkEntry] = []
    
    @Relationship(deleteRule: .cascade, inverse: \LocationStop.session)
    var locations: [LocationStop] = []
    
    @Relationship(deleteRule: .cascade, inverse: \OtherEntry.session)
    var otherEntries: [OtherEntry] = []
    
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
    var name: String? // Optional specific name
    var alcoholContent: Double // % ABV
    var volumeOz: Double // Volume in oz
    var locationName: String? // Where you had this drink
    var latitude: Double? // Location coordinates
    var longitude: Double? // Location coordinates
    
    var session: DrinkingSession?
    
    init(timestamp: Date = Date(), drinkType: String, name: String? = nil, alcoholContent: Double, volumeOz: Double, locationName: String? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.drinkType = drinkType
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

// MARK: - Other Entries (Zyns, cigs, etc.)
@Model
final class OtherEntry {
    var id: UUID
    var timestamp: Date
    var type: String // "Zyn", "Cigarette", "Vape", etc.
    var notes: String?
    
    var session: DrinkingSession?
    
    init(timestamp: Date = Date(), type: String, notes: String? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.type = type
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
    
    var session: DrinkingSession?
    
    init(timestamp: Date = Date(), foodType: String, quantity: Int = 1) {
        self.id = UUID()
        self.timestamp = timestamp
        self.foodType = foodType
        self.quantity = quantity
    }
}

// MARK: - Water Entry
@Model
final class WaterEntry {
    var id: UUID
    var timestamp: Date
    var volumeOz: Double
    
    var session: DrinkingSession?
    
    init(timestamp: Date = Date(), volumeOz: Double = 8.0) {
        self.id = UUID()
        self.timestamp = timestamp
        self.volumeOz = volumeOz
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
struct BACCalculator {
    /// Enhanced Widmark formula with food and hydration factors
    /// BAC = (Alcohol consumed in grams / (Body weight in grams × r)) × (1 - food factor) - (0.015 × Hours) - (hydration reduction)
    /// r = 0.68 for men, 0.55 for women
    /// Food slows absorption and reduces peak BAC by ~20-30% per substantial meal
    /// Water helps with metabolism and dilution
    static func estimateBAC(drinks: [DrinkEntry], food: [FoodEntry], water: [WaterEntry], weight: Double, sex: String, at time: Date) -> Double {
        let r = sex.lowercased() == "female" ? 0.55 : 0.68
        let weightInGrams = weight * 453.592 // lbs to grams
        
        var totalAlcoholGrams: Double = 0
        var earliestDrinkTime: Date?
        
        // Calculate total alcohol consumed
        for drink in drinks where drink.timestamp <= time {
            // Calculate pure alcohol in oz, convert to grams (1 oz = 28.35 grams)
            let pureAlcoholOz = drink.volumeOz * (drink.alcoholContent / 100.0)
            let alcoholGrams = pureAlcoholOz * 28.35
            totalAlcoholGrams += alcoholGrams
            
            if earliestDrinkTime == nil || drink.timestamp < earliestDrinkTime! {
                earliestDrinkTime = drink.timestamp
            }
        }
        
        guard let startTime = earliestDrinkTime, totalAlcoholGrams > 0 else {
            return 0
        }
        
        // Calculate food factor (reduces BAC absorption)
        // Each slice of pizza reduces absorption by ~15%
        let foodSlices = food.filter { $0.timestamp <= time }.reduce(0) { $0 + $1.quantity }
        let foodReduction = min(0.40, Double(foodSlices) * 0.15) // Max 40% reduction
        
        // Calculate water benefit (improves metabolism slightly)
        // Each 8oz of water adds ~0.005% per hour to metabolism rate
        let waterOz = water.filter { $0.timestamp <= time }.reduce(0.0) { $0 + $1.volumeOz }
        let waterGlasses = waterOz / 8.0
        let extraMetabolism = min(0.010, waterGlasses * 0.002) // Max 0.010% bonus per hour
        
        // Time-based metabolism
        let hoursElapsed = time.timeIntervalSince(startTime) / 3600.0
        let baseMetabolismRate = 0.015 * hoursElapsed
        let totalMetabolismRate = (0.015 + extraMetabolism) * hoursElapsed
        
        // Calculate BAC with food reduction
        let rawBAC = (totalAlcoholGrams / (weightInGrams * r)) * 100
        let foodAdjustedBAC = rawBAC * (1.0 - foodReduction)
        let finalBAC = foodAdjustedBAC - totalMetabolismRate
        
        return max(0, finalBAC) // Can't be negative
    }
    
    /// Legacy method for backward compatibility (no food/water)
    static func estimateBAC(drinks: [DrinkEntry], weight: Double, sex: String, at time: Date) -> Double {
        return estimateBAC(drinks: drinks, food: [], water: [], weight: weight, sex: sex, at: time)
    }
}

