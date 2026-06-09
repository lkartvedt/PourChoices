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

// MARK: - User Profile (for BAC calculation)
@Model
final class UserProfile {
    var weight: Double // in lbs
    var sex: String // "Male" or "Female" (affects BAC calculation)
    
    init(weight: Double = 150, sex: String = "Male") {
        self.weight = weight
        self.sex = sex
    }
}

// MARK: - BAC Calculator
struct BACCalculator {
    /// Widmark formula for BAC estimation
    /// BAC = (Alcohol consumed in grams / (Body weight in grams × r)) - (0.015 × Hours)
    /// r = 0.68 for men, 0.55 for women
    static func estimateBAC(drinks: [DrinkEntry], weight: Double, sex: String, at time: Date) -> Double {
        let r = sex.lowercased() == "female" ? 0.55 : 0.68
        let weightInGrams = weight * 453.592 // lbs to grams
        
        var totalAlcoholGrams: Double = 0
        var earliestDrinkTime: Date?
        
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
        
        let hoursElapsed = time.timeIntervalSince(startTime) / 3600.0
        let metabolismRate = 0.015 * hoursElapsed
        
        let bac = (totalAlcoholGrams / (weightInGrams * r)) * 100 - metabolismRate
        
        return max(0, bac) // Can't be negative
    }
}

