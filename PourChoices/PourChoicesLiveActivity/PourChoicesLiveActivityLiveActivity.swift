//
//  PourChoicesLiveActivityLiveActivity.swift
//  PourChoicesLiveActivity
//
//  Lock Screen and Dynamic Island UI for the PourChoices active session Live Activity.
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct PourChoicesLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PourChoicesActivityAttributes.self) { context in
            // ----------------------------------------------------------------
            // LOCK SCREEN / BANNER presentation
            // ----------------------------------------------------------------
            lockScreenView(context: context)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            // ----------------------------------------------------------------
            // DYNAMIC ISLAND presentations
            // ----------------------------------------------------------------
            DynamicIsland {
                // Expanded — shows when user touches/holds the Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.3f%%", context.state.peakBAC))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(bacColor(context.state.peakBAC))
                        Text("peak BAC")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("in \(Int(context.state.timeToBAC)) min")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(bacColor(context.state.peakBAC))
                        Text("\(context.state.drinkCount) drinks")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        quickAddButton(config: context.state.button1, intent: QuickAddButton1Intent())
                        quickAddButton(config: context.state.button2, intent: QuickAddButton2Intent())
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }

            } compactLeading: {
                // Compact leading — small BAC number
                Text(String(format: "%.3f", context.state.peakBAC))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(bacColor(context.state.peakBAC))
                    .padding(.leading, 4)

            } compactTrailing: {
                // Compact trailing — time to peak
                Text("\(Int(context.state.timeToBAC))m")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)

            } minimal: {
                // Minimal — just the colored BAC
                Text(String(format: "%.2f", context.state.peakBAC))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(bacColor(context.state.peakBAC))
            }
            .widgetURL(URL(string: "pourchocies://active-session"))
            .keylineTint(Color.yellow)
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<PourChoicesActivityAttributes>) -> some View {
        HStack(spacing: 0) {
            // Left: BAC display — mirrors the ActiveSessionView layout
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "%.3f%%", context.state.peakBAC))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(bacColor(context.state.peakBAC))

                Text("in \(Int(context.state.timeToBAC)) min")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(bacColor(context.state.peakBAC))

                Text("\(context.state.drinkCount) drink\(context.state.drinkCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Right: Quick-add buttons stacked vertically
            VStack(spacing: 8) {
                quickAddButton(config: context.state.button1, intent: QuickAddButton1Intent())
                quickAddButton(config: context.state.button2, intent: QuickAddButton2Intent())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Quick Add Button

    @ViewBuilder
    private func quickAddButton<I: AppIntent>(config: QuickAddButtonConfig, intent: I) -> some View {
        Button(intent: intent) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
                Text(config.displayLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color(red: 1.0, green: 0.855, blue: 0.349)) // warm gold accent
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - BAC Color Helper

    /// Matches the bacColor() function in ActiveSessionView exactly.
    private func bacColor(_ bac: Double) -> Color {
        switch bac {
        case 0..<0.03: return .green
        case 0.03..<0.08: return .yellow
        case 0.08..<0.15: return .orange
        default: return .red
        }
    }
}

// MARK: - Previews

#Preview("Lock Screen", as: .content, using: PourChoicesActivityAttributes(sessionStartTime: .now)) {
    PourChoicesLiveActivityLiveActivity()
} contentStates: {
    PourChoicesActivityAttributes.ContentState(
        peakBAC: 0.065,
        timeToBAC: 42,
        drinkCount: 2,
        button1: .defaultButton1,
        button2: .defaultButton2
    )
    PourChoicesActivityAttributes.ContentState(
        peakBAC: 0.12,
        timeToBAC: 18,
        drinkCount: 5,
        button1: .defaultButton1,
        button2: .defaultButton2
    )
}
