//
//  PourChoicesApp.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/8/26.
//

import SwiftUI
import SwiftData

@main
struct PourChoicesApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DrinkingSession.self,
            DrinkEntry.self,
            LocationStop.self,
            OtherEntry.self,
            UserProfile.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
