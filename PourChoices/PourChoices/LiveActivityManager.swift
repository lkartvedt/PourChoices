//
//  LiveActivityManager.swift
//  PourChoices
//
//  Manages the lifecycle of the PourChoices Live Activity:
//  starting when a session begins, updating when BAC is recalculated,
//  and ending when the session ends or is abandoned.
//

import ActivityKit
import Foundation

struct LiveActivityManager {

    // MARK: - Start

    /// Start a Live Activity for the given session.
    /// Called when the user creates a new drinking session.
    static func startActivity(session: DrinkingSession, peakBAC: Double, timeToBAC: Double) {
        let authInfo = ActivityAuthorizationInfo()
        print("LiveActivityManager: areActivitiesEnabled=\(authInfo.areActivitiesEnabled)")
        guard authInfo.areActivitiesEnabled else {
            print("LiveActivityManager: Live Activities not enabled — check NSSupportsLiveActivities in Info.plist and device Settings")
            return
        }

        let attributes = PourChoicesActivityAttributes(sessionStartTime: session.startTime)
        let state = PourChoicesActivityAttributes.ContentState(
            peakBAC: peakBAC,
            timeToBAC: timeToBAC,
            drinkCount: session.drinks.count,
            button1: SharedDefaults.loadButton(slot: 1),
            button2: SharedDefaults.loadButton(slot: 2)
        )
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            print("LiveActivityManager: started activity id=\(activity.id)")
        } catch {
            print("LiveActivityManager: failed to start activity — \(error)")
        }
    }

    // MARK: - Update

    /// Push a BAC update to the Live Activity.
    /// Called every time recalculateBAC() runs in ActiveSessionView.
    static func updateActivity(peakBAC: Double, timeToBAC: Double,
                               drinkCount: Int, sessionStart: Date) {
        let state = PourChoicesActivityAttributes.ContentState(
            peakBAC: peakBAC,
            timeToBAC: timeToBAC,
            drinkCount: drinkCount,
            button1: SharedDefaults.loadButton(slot: 1),
            button2: SharedDefaults.loadButton(slot: 2)
        )
        let content = ActivityContent(state: state, staleDate: nil)

        Task {
            for activity in Activity<PourChoicesActivityAttributes>.activities {
                await activity.update(content)
            }
        }
    }

    // MARK: - End

    /// End the active Live Activity when the user ends their session.
    static func endActivity() {
        Task {
            for activity in Activity<PourChoicesActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Cleanup

    /// End all Live Activities (used on app launch to clear stale activities
    /// left from a force-killed session).
    static func endAllActivities() {
        Task {
            for activity in Activity<PourChoicesActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
