//
//  QuickAddIntents.swift
//  PourChoices
//
//  LiveActivityIntents for the two quick-add buttons on the Lock Screen widget.
//  These run in the main app's process (not the widget extension process),
//  so they have access to SwiftData and can mutate session data.
//
//  Added to BOTH the main app target and the widget extension target.
//

import AppIntents

/// Tapping button 1 on the Lock Screen adds whatever is configured for slot 1
/// (default: a Beer).
struct QuickAddButton1Intent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Quick Add Button 1"
    static var description = IntentDescription("Adds the item configured for Lock Screen button 1.")
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await QuickAddHandler.handleQuickAdd(slot: 1)
        return .result()
    }
}

/// Tapping button 2 on the Lock Screen adds whatever is configured for slot 2
/// (default: a Shot).
struct QuickAddButton2Intent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Quick Add Button 2"
    static var description = IntentDescription("Adds the item configured for Lock Screen button 2.")
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await QuickAddHandler.handleQuickAdd(slot: 2)
        return .result()
    }
}
