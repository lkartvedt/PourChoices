//
//  QuickAddButtonPickerView.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/15/26.
//

import SwiftUI
import ActivityKit

// MARK: - Quick Add Button Picker View

struct QuickAddButtonPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let slot: Int
    @Binding var currentConfig: QuickAddButtonConfig

    // Tracks which drink category grid cell is tapped (to show subtypes below)
    @State private var focusedCategory: String? = nil

    private let drinkTypes = ["Beer", "Wine", "Shot", "Cocktail", "Mixed Drink", "Other"]

    private struct NicotineOption: Identifiable {
        let id = UUID()
        let name: String
        let defaultMg: Double
        let assetName: String
    }

    private let nicotineOptions: [NicotineOption] = [
        NicotineOption(name: "Zyn",       defaultMg: 3.0,  assetName: "Zyn3"),
        NicotineOption(name: "Vape",      defaultMg: 3.0,  assetName: "Vape"),
        NicotineOption(name: "Cigarette", defaultMg: 2.0,  assetName: "Cig"),
        NicotineOption(name: "Cigar",     defaultMg: 10.0, assetName: "Cigar"),
        NicotineOption(name: "Gum",       defaultMg: 3.0,  assetName: "Gum"),
        NicotineOption(name: "Dip",       defaultMg: 5.0,  assetName: "Dip"),
    ]

    private let columns = [
        GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // MARK: Drinks grid
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Drinks")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(drinkTypes, id: \.self) { category in
                                drinkGridCell(category: category)
                            }
                        }
                        .padding(.horizontal)

                        // Subtype panel — animates in when a category is focused
                        if let focused = focusedCategory {
                            subtypePanel(for: focused)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    // MARK: Nicotine grid
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Nicotine")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(nicotineOptions) { nic in
                                nicotineGridCell(nic: nic)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 16)
                .animation(.easeInOut(duration: 0.2), value: focusedCategory)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Button \(slot)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // Pre-focus current drink category so subtypes are visible
                if currentConfig.kind == .drink {
                    focusedCategory = currentConfig.category
                }
            }
        }
    }

    // MARK: - Drink Grid Cell

    @ViewBuilder
    private func drinkGridCell(category: String) -> some View {
        let asset = assetName(for: category)
        let isFocused = focusedCategory == category
        let isSelected = currentConfig.kind == .drink &&
                         currentConfig.category == category &&
                         currentConfig.subtype == nil

        Button {
            let subtypes = AddDrinkView.subtypes[category] ?? []
            if subtypes.isEmpty {
                // No subtypes — select directly
                let defaults = categoryDefaults(for: category)
                select(QuickAddButtonConfig(
                    kind: .drink, category: category, subtype: nil,
                    abv: defaults.abv, volumeOz: defaults.oz,
                    nicotineMg: nil, displayLabel: category, assetName: asset
                ))
            } else {
                // Toggle subtype panel
                focusedCategory = isFocused ? nil : category
            }
        } label: {
            SelectableTileLabel(assetName: asset, label: category, isSelected: isFocused)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subtype Panel

    @ViewBuilder
    private func subtypePanel(for category: String) -> some View {
        let subtypes = AddDrinkView.subtypes[category] ?? []
        let asset = assetName(for: category)

        VStack(spacing: 0) {
            // "None" row — selects the bare category with no subtype
            let defaults = categoryDefaults(for: category)
            Button {
                select(QuickAddButtonConfig(
                    kind: .drink, category: category, subtype: nil,
                    abv: defaults.abv, volumeOz: defaults.oz,
                    nicotineMg: nil, displayLabel: category, assetName: asset
                ))
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("None")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Text("Default \(category)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if currentConfig.kind == .drink &&
                       currentConfig.category == category &&
                       currentConfig.subtype == nil {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.accent)
                            .font(.title3)
                    }
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)

            ForEach(Array(subtypes.enumerated()), id: \.element.name) { index, sub in
                Divider().padding(.leading, 16)
                Button {
                    select(QuickAddButtonConfig(
                        kind: .drink, category: category, subtype: sub.name,
                        abv: sub.abv, volumeOz: sub.oz,
                        nicotineMg: nil, displayLabel: sub.name, assetName: asset
                    ))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.name)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text(String(format: "%.0f%% · %.1f oz", sub.abv, sub.oz))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if currentConfig.kind == .drink &&
                           currentConfig.category == category &&
                           currentConfig.subtype == sub.name {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.accent)
                                .font(.title3)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    // MARK: - Nicotine Grid Cell

    @ViewBuilder
    private func nicotineGridCell(nic: NicotineOption) -> some View {
        let isSelected = currentConfig.kind == .nicotine && currentConfig.category == nic.name

        Button {
            select(QuickAddButtonConfig(
                kind: .nicotine, category: nic.name, subtype: nil,
                abv: nil, volumeOz: nil,
                nicotineMg: nic.defaultMg, displayLabel: nic.name, assetName: nic.assetName
            ))
        } label: {
            SelectableTileLabel(assetName: nic.assetName, label: nic.name, isSelected: isSelected, showCheckmark: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func select(_ config: QuickAddButtonConfig) {
        currentConfig = config
        SharedDefaults.saveButton(config, slot: slot)
        // Update the Live Activity if one is running
        Task {
            for activity in Activity<PourChoicesActivityAttributes>.activities {
                let newState = PourChoicesActivityAttributes.ContentState(
                    peakBAC: activity.content.state.peakBAC,
                    peakBACDate: activity.content.state.peakBACDate,
                    drinkCount: activity.content.state.drinkCount,
                    button1: SharedDefaults.loadButton(slot: 1),
                    button2: SharedDefaults.loadButton(slot: 2)
                )
                await activity.update(ActivityContent(state: newState, staleDate: nil))
            }
        }
        dismiss()
    }

    private func categoryDefaults(for category: String) -> (abv: Double, oz: Double) {
        switch category {
        case "Beer":        return (5.0, 12.0)
        case "Wine":        return (12.0, 5.0)
        case "Shot":        return (40.0, 1.5)
        case "Cocktail":    return (20.0, 4.0)
        case "Mixed Drink": return (10.0, 8.0)
        default:            return (8.0, 8.0)
        }
    }

    private func assetName(for category: String) -> String {
        category == "Mixed Drink" ? "MixedDrink" : category
    }
}
