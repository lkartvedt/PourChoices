//
//  NotificationManager.swift
//  PourChoices
//

import UserNotifications

// MARK: - Notification Preferences

/// Persists per-notification opt-in flags in UserDefaults.
/// All three default to `true` (on) on first launch.
struct NotificationPreferences {
    private enum Keys {
        static let forgotToLog  = "notif.forgotToLog"
        static let drinkWater   = "notif.drinkWater"
        static let endSession   = "notif.endSession"
    }

    static var forgotToLogEnabled: Bool {
        get { value(for: Keys.forgotToLog) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.forgotToLog) }
    }

    static var drinkWaterEnabled: Bool {
        get { value(for: Keys.drinkWater) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.drinkWater) }
    }

    static var endSessionEnabled: Bool {
        get { value(for: Keys.endSession) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.endSession) }
    }

    /// Returns `true` if the key has never been set (defaults on) or was explicitly set to `true`.
    private static func value(for key: String) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }
}

// MARK: - Notification Manager

struct NotificationManager {

    // MARK: - Notification Identifiers

    private static let forgotToLogID = "forgot-to-log"
    private static let endSessionID  = "end-session-reminder"
    private static let waterIDs      = (1...8).map { "drink-water-\($0)" }

    /// All identifiers owned by an active session.
    private static var allSessionIDs: [String] {
        [forgotToLogID, endSessionID] + waterIDs
    }

    // MARK: - Permission

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Schedule

    /// Call this every time BAC is recalculated.
    /// Each notification type is only scheduled when its preference flag is enabled.
    /// - Parameters:
    ///   - currentBAC: Most recently calculated BAC value.
    ///   - lastActivityDate: Timestamp of the most recent logged entry (drink, food, water, nicotine).
    static func scheduleSessionNotifications(currentBAC: Double, lastActivityDate: Date) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { return }

            // Remove all existing session notifications before rescheduling.
            center.removePendingNotificationRequests(withIdentifiers: allSessionIDs)

            let now = Date()
            let secondsSinceActivity = now.timeIntervalSince(lastActivityDate)

            // 1. Forgot-to-log: BAC < 0.08, fires 1 hour after the last logged entry.
            if NotificationPreferences.forgotToLogEnabled && currentBAC < 0.08 {
                let delay = max(1, 3600 - secondsSinceActivity)
                let content = UNMutableNotificationContent()
                content.title = "Did you forget to log?"
                content.body  = "You haven't logged anything in a while. Tap to open PourChoices."
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                center.add(UNNotificationRequest(identifier: forgotToLogID,
                                                 content: content,
                                                 trigger: trigger))
            }

            // 2. End session: fires 3 hours after the last logged entry.
            if NotificationPreferences.endSessionEnabled {
                let endDelay = max(1, 10800 - secondsSinceActivity)
                let endContent = UNMutableNotificationContent()
                endContent.title = "Still out?"
                endContent.body  = "You haven't logged anything in 3 hours. Don't forget to end your session when you're done!"
                endContent.sound = .default
                let endTrigger = UNTimeIntervalNotificationTrigger(timeInterval: endDelay, repeats: false)
                center.add(UNNotificationRequest(identifier: endSessionID,
                                                 content: endContent,
                                                 trigger: endTrigger))
            }

            // 3. Drink water: BAC >= 0.175 — up to 8 reminders, 30 min apart.
            if NotificationPreferences.drinkWaterEnabled && currentBAC >= 0.175 {
                for i in 0..<waterIDs.count {
                    let interval = TimeInterval((i + 1) * 1800)
                    let waterContent = UNMutableNotificationContent()
                    waterContent.title = "Drink some water"
                    waterContent.body  = "Your BAC is high — hydrating will help your body."
                    waterContent.sound = .default
                    let waterTrigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                    center.add(UNNotificationRequest(identifier: waterIDs[i],
                                                     content: waterContent,
                                                     trigger: waterTrigger))
                }
            }
        }
    }

    // MARK: - Cancel

    /// Removes all pending session notifications. Call when a session ends.
    static func cancelAllSessionNotifications() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: allSessionIDs)
    }
}
