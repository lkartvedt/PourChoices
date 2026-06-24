//
//  NotificationManager.swift
//  PourChoices
//

import UserNotifications

// MARK: - Notification Preferences

/// Persists per-notification opt-in flags in UserDefaults.
/// All defaults are `true` (on) on first launch.
struct NotificationPreferences {
    private enum Keys {
        static let forgotToLog       = "notif.forgotToLog"
        static let drinkWater        = "notif.drinkWater"
        static let endSession        = "notif.endSession"
        static let partyNightEnabled = "notif.partyNight.enabled"
        static let partyNightDays    = "notif.partyNight.days"    // [Int] weekday numbers (1=Sun…7=Sat)
        static let partyNightHour    = "notif.partyNight.hour"    // Int
        static let partyNightMinute  = "notif.partyNight.minute"  // Int
    }

    static var forgotToLogEnabled: Bool {
        get { boolValue(for: Keys.forgotToLog) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.forgotToLog) }
    }

    static var drinkWaterEnabled: Bool {
        get { boolValue(for: Keys.drinkWater) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.drinkWater) }
    }

    static var endSessionEnabled: Bool {
        get { boolValue(for: Keys.endSession) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.endSession) }
    }

    static var partyNightEnabled: Bool {
        get { boolValue(for: Keys.partyNightEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.partyNightEnabled) }
    }

    /// Weekday numbers (1=Sun, 2=Mon … 7=Sat). Defaults to Friday (6) and Saturday (7).
    static var partyNightDays: Set<Int> {
        get {
            guard let stored = UserDefaults.standard.array(forKey: Keys.partyNightDays) as? [Int] else {
                return [6, 7]
            }
            return Set(stored)
        }
        set { UserDefaults.standard.set(Array(newValue), forKey: Keys.partyNightDays) }
    }

    /// Hour of day (0–23). Defaults to 19 (7 PM).
    static var partyNightHour: Int {
        get {
            guard UserDefaults.standard.object(forKey: Keys.partyNightHour) != nil else { return 19 }
            return UserDefaults.standard.integer(forKey: Keys.partyNightHour)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.partyNightHour) }
    }

    /// Minute of hour (0–59). Defaults to 0.
    static var partyNightMinute: Int {
        get {
            guard UserDefaults.standard.object(forKey: Keys.partyNightMinute) != nil else { return 0 }
            return UserDefaults.standard.integer(forKey: Keys.partyNightMinute)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.partyNightMinute) }
    }

    /// Returns `true` if the key has never been set (defaults on) or was explicitly set to `true`.
    private static func boolValue(for key: String) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }
}

// MARK: - Notification Manager

struct NotificationManager {

    // MARK: - Notification Identifiers

    private static let forgotToLogID   = "forgot-to-log"
    private static let endSessionID    = "end-session-reminder"
    private static let waterIDs        = (1...8).map { "drink-water-\($0)" }
    // One identifier per weekday slot (weekday 1–7)
    private static let partyNightIDs   = (1...7).map { "party-night-\($0)" }

    /// All identifiers owned by an active session.
    private static var allSessionIDs: [String] {
        [forgotToLogID, endSessionID] + waterIDs
    }

    // MARK: - Permission

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Session Notifications

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

            // 1. Forgot-to-log: Fires 1 hour after the last logged entry.
            if NotificationPreferences.forgotToLogEnabled {
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

            // 2. End session: Fires 3 hours after the last logged entry.
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

            // 3. Drink water: BAC >= 0.15 — up to 8 reminders, 30 min apart.
            if NotificationPreferences.drinkWaterEnabled && currentBAC >= 0.15 {
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

    // MARK: - Party Night Notifications

    /// Schedules (or removes) the weekly party night reminder based on current preferences.
    /// Safe to call on every app launch — it replaces existing schedules.
    static func schedulePartyNightNotification() {
        let center = UNUserNotificationCenter.current()

        // Always remove all existing party night slots first.
        center.removePendingNotificationRequests(withIdentifiers: partyNightIDs)

        guard NotificationPreferences.partyNightEnabled else { return }

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { return }

            let hour   = NotificationPreferences.partyNightHour
            let minute = NotificationPreferences.partyNightMinute
            let days   = NotificationPreferences.partyNightDays

            for weekday in days {
                var components = DateComponents()
                components.hour    = hour
                components.minute  = minute
                components.weekday = weekday

                let content = UNMutableNotificationContent()
                content.title = "Is it a party night?"
                content.body  = "Start logging now to track your night with PourChoices!"
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let id = partyNightIDs[weekday - 1]
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
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
