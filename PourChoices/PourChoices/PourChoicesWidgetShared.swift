//
//  PourChoicesWidgetShared.swift
//  PourChoices
//
//  Shared between the main app target and the PourChoicesLiveActivity widget extension.
//  Contains all types that cross the app/extension boundary.
//

import Foundation
import ActivityKit

// MARK: - Quick Add Button Config

/// Describes what one of the two quick-add Lock Screen buttons does.
/// Codable so it round-trips through App Group UserDefaults.
struct QuickAddButtonConfig: Codable, Hashable {
    enum Kind: String, Codable {
        case drink
        case nicotine
    }

    let kind: Kind
    let category: String       // e.g. "Beer", "Shot", "Zyn"
    let subtype: String?       // e.g. "Light Beer", nil means use category default
    let abv: Double?           // drink ABV %
    let volumeOz: Double?      // drink volume in oz
    let nicotineMg: Double?    // nicotine mg (for nicotine kind)
    let displayLabel: String   // short label shown on the button, e.g. "Light Beer"
    let assetName: String      // image asset name in main app Assets catalog

    /// Default button 1: a standard Beer
    static let defaultButton1 = QuickAddButtonConfig(
        kind: .drink,
        category: "Beer",
        subtype: nil,
        abv: 5.0,
        volumeOz: 12.0,
        nicotineMg: nil,
        displayLabel: "Beer",
        assetName: "Beer"
    )

    /// Default button 2: a standard Shot
    static let defaultButton2 = QuickAddButtonConfig(
        kind: .drink,
        category: "Shot",
        subtype: nil,
        abv: 40.0,
        volumeOz: 1.5,
        nicotineMg: nil,
        displayLabel: "Shot",
        assetName: "Shot"
    )
}

// MARK: - Shared Defaults

/// Wraps the App Group UserDefaults shared between the app and widget extension.
struct SharedDefaults {
    static let suiteName = "group.com.lkartvedt.PourChoices"

    static var shared: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static let button1Key = "quickAddButton1"
    private static let button2Key = "quickAddButton2"

    static func saveButton(_ config: QuickAddButtonConfig, slot: Int) {
        let key = slot == 1 ? button1Key : button2Key
        if let data = try? JSONEncoder().encode(config) {
            shared.set(data, forKey: key)
        }
    }

    static func loadButton(slot: Int) -> QuickAddButtonConfig {
        let key = slot == 1 ? button1Key : button2Key
        guard let data = shared.data(forKey: key),
              let config = try? JSONDecoder().decode(QuickAddButtonConfig.self, from: data)
        else {
            return slot == 1 ? .defaultButton1 : .defaultButton2
        }
        return config
    }
}

// MARK: - Live Activity Attributes

/// ActivityKit attributes for the PourChoices active session Live Activity.
struct PourChoicesActivityAttributes: ActivityAttributes {

    /// Static data set at activity start — does not change.
    let sessionStartTime: Date

    /// Dynamic state updated whenever BAC changes or buttons are reconfigured.
    struct ContentState: Codable, Hashable {
        let peakBAC: Double         // predicted peak BAC (matches cachedBAC in the app)
        let timeToBAC: Double       // minutes until peak (matches cachedTimeToBAC in the app)
        let drinkCount: Int
        let button1: QuickAddButtonConfig
        let button2: QuickAddButtonConfig
    }
}
