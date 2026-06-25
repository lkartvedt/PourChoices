//
//  QuickAddHandler.swift
//  PourChoices
//
//  Handles quick-add button taps from the Live Activity.
//  Runs in the main app process (via LiveActivityIntent), so it has full
//  access to SwiftData and BAC calculation.
//

import Foundation
import SwiftData
import CoreLocation

struct QuickAddHandler {

    /// Called by QuickAddButton1Intent or QuickAddButton2Intent when the user
    /// taps a quick-add button on the Lock Screen widget.
    @MainActor
    static func handleQuickAdd(slot: Int) async {
        let config = SharedDefaults.loadButton(slot: slot)

        // Access the shared SwiftData container from the app.
        let context = PourChoicesApp.sharedModelContainer.mainContext

        // Find the active session.
        guard let sessions = try? context.fetch(FetchDescriptor<DrinkingSession>()),
              let session = sessions.first(where: { $0.isActive })
        else { return }

        // Grab the last known device location (cached by the OS — no delegate needed).
        // This is fast and works as long as the app already has location permission,
        // which it does by the time a session is active.
        let clManager = CLLocationManager()
        let currentLocation = clManager.location

        // Insert the entry.
        switch config.kind {
        case .drink:
            let drink = DrinkEntry(
                drinkType: config.category,
                subtype: config.subtype,
                alcoholContent: config.abv ?? 5.0,
                volumeOz: config.volumeOz ?? 12.0,
                latitude: currentLocation?.coordinate.latitude,
                longitude: currentLocation?.coordinate.longitude
            )
            session.drinks.append(drink)
            context.insert(drink)

            // Reverse-geocode the coordinates to get a venue/place name.
            if let location = currentLocation {
                Task {
                    let locationTracker = LocationTracker()
                    let venueName = await locationTracker.getBestVenueName(for: location)
                    await MainActor.run {
                        drink.locationName = venueName
                        try? context.save()
                    }
                }
            }

        case .nicotine:
            let entry = NicotineEntry(
                type: config.category,
                nicotineMg: config.nicotineMg ?? 3.0,
                notes: nil
            )
            session.nicotine.append(entry)
            context.insert(entry)
        }

        try? context.save()

        // Recalculate BAC and update the Live Activity.
        guard let profiles = try? context.fetch(FetchDescriptor<UserProfile>()) else { return }
        let profile = profiles.first ?? UserProfile()

        let (peakBAC, peakTime) = BACCalculator.estimateBAC(
            drinks: session.drinks,
            food: session.food,
            water: session.water,
            nicotine: session.nicotine,
            weight: profile.weight,
            sex: profile.sex,
            heightInches: profile.heightInches,
            ageYears: profile.age,
            sessionStart: session.startTime,
            at: Date()
        )

        if peakBAC > session.peakBAC {
            session.peakBAC = peakBAC
            try? context.save()
        }

        LiveActivityManager.updateActivity(
            peakBAC: peakBAC,
            timeToBAC: peakTime,
            drinkCount: session.drinks.count,
            sessionStart: session.startTime
        )
    }
}
