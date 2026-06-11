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
    @State private var showSplash = true
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DrinkingSession.self,
            DrinkEntry.self,
            LocationStop.self,
            NicotineEntry.self,
            FoodEntry.self,
            WaterEntry.self,
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
            if showSplash {
                SplashScreenView(showSplash: $showSplash)
                    .preferredColorScheme(.dark)
            } else {
                ContentView()
                    .modelContainer(sharedModelContainer)
                    .preferredColorScheme(.dark)
            }
        }
    }
}
// MARK: - Splash Screen View
struct SplashScreenView: View {
    @Binding var showSplash: Bool
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            Image("SplashPage")
                .resizable()
                .scaledToFit()
        }
        .onAppear {
            // Dismiss splash after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    showSplash = false
                }
            }
        }
    }
}

