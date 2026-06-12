//
//  QuickAddIntents.swift
//  PourChoicesLiveActivity (widget extension)
//
//  Intent declarations only — the perform() implementations live in the main
//  app target (QuickAddIntents.swift in PourChoices). LiveActivityIntent
//  execute in the app's process, so the widget extension only needs the type
//  declarations to use them in Button(intent:).
//

import AppIntents

struct QuickAddButton1Intent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Quick Add Button 1"
    static var description = IntentDescription("Adds the item configured for Lock Screen button 1.")
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct QuickAddButton2Intent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Quick Add Button 2"
    static var description = IntentDescription("Adds the item configured for Lock Screen button 2.")
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        .result()
    }
}
