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
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(String(format: "%.3f%%", context.state.peakBAC))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(bacColor(context.state.peakBAC))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Spacer().frame(height: 0)
                }
            } compactLeading: {
                Text(String(format: "%.3f%%", context.state.peakBAC))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(bacColor(context.state.peakBAC))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            } compactTrailing: {
                EmptyView()
            } minimal: {
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
        HStack(spacing: 14) {
            // Left: BAC + time
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "%.3f%%", context.state.peakBAC))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(bacColor(context.state.peakBAC))
                countdownText(peakBACDate: context.state.peakBACDate)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(bacColor(context.state.peakBAC))
                Text("\(context.state.drinkCount) drink\(context.state.drinkCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Right: two square buttons side by side
            HStack(spacing: 20) {
                quickAddButton(config: context.state.button1, intent: QuickAddButton1Intent())
                quickAddButton(config: context.state.button2, intent: QuickAddButton2Intent())
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Quick Add Button

    @ViewBuilder
    private func quickAddButton<I: AppIntent>(config: QuickAddButtonConfig, intent: I) -> some View {
        
        Button(intent: intent) {
            VStack {
                VStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 66, height: 66)
                .background(
                    Circle()
                        .fill(Color.accent)
                )
                HStack(spacing: 3) {
                    Text(config.displayLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(Color.white)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Countdown Helper

    /// Returns a Text that counts down to peakBACDate, showing "in Xm" format.
    /// Once the date is in the past it shows "now". Uses SwiftUI's built-in
    /// timer date style so it ticks every minute without any manual timers.
    @ViewBuilder
    private func countdownText(peakBACDate: Date) -> some View {
        if peakBACDate > Date() {
            Text("in ") + Text(peakBACDate, style: .timer)
        } else {
            Text("now")
        }
    }

    // MARK: - BAC Color Helper

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
        peakBACDate: Date().addingTimeInterval(42 * 60),
        drinkCount: 2,
        button1: .defaultButton1,
        button2: .defaultButton2
    )
    PourChoicesActivityAttributes.ContentState(
        peakBAC: 0.12,
        peakBACDate: Date().addingTimeInterval(18 * 60),
        drinkCount: 5,
        button1: .defaultButton1,
        button2: .defaultButton2
    )
}
