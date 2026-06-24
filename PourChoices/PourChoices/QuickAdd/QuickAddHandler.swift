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

        // Insert the entry.
        switch config.kind {
        case .drink:
            let drink = DrinkEntry(
                drinkType: config.category,
                subtype: config.subtype,
                alcoholContent: config.abv ?? 5.0,
                volumeOz: config.volumeOz ?? 12.0
            )
            session.drinks.append(drink)
            context.insert(drink)

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
