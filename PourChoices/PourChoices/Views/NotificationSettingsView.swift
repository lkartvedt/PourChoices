//
//  NotificationSettingsView.swift
//  PourChoices
//

import SwiftUI

// MARK: - Notification Settings View

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // Session-based toggles
    @State private var forgotToLog = NotificationPreferences.forgotToLogEnabled
    @State private var drinkWater  = NotificationPreferences.drinkWaterEnabled
    @State private var endSession  = NotificationPreferences.endSessionEnabled

    // Party night
    @State private var partyNightEnabled = NotificationPreferences.partyNightEnabled
    @State private var partyNightDays    = NotificationPreferences.partyNightDays
    @State private var partyNightTime: Date = {
        var comps        = DateComponents()
        comps.hour       = NotificationPreferences.partyNightHour
        comps.minute     = NotificationPreferences.partyNightMinute
        return Calendar.current.date(from: comps) ?? Date()
    }()

    /// True only when every individual toggle is on.
    private var allEnabled: Bool {
        forgotToLog && drinkWater && endSession && partyNightEnabled
    }

    private func setAll(_ enabled: Bool) {
        forgotToLog      = enabled
        drinkWater       = enabled
        endSession       = enabled
        partyNightEnabled = enabled

        NotificationPreferences.forgotToLogEnabled  = enabled
        NotificationPreferences.drinkWaterEnabled   = enabled
        NotificationPreferences.endSessionEnabled   = enabled
        NotificationPreferences.partyNightEnabled   = enabled
        NotificationManager.schedulePartyNightNotification()
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Master toggle
                Section {
                    Toggle(isOn: Binding(
                        get: { allEnabled },
                        set: { setAll($0) }
                    )) {
                        Text("All Notifications")
                            .font(.body.weight(.medium))
                    }
                }

                // MARK: During Session
                Section {
                    Toggle(isOn: $forgotToLog) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Log Reminder")
                                .font(.body)
                            Text("Reminds you after 1 hour of no activity")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: forgotToLog) { _, newValue in
                        NotificationPreferences.forgotToLogEnabled = newValue
                    }

                    Toggle(isOn: $drinkWater) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Drink Water")
                                .font(.body)
                            Text("Sends a reminder every 30 minutes while your BAC is above 0.15")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: drinkWater) { _, newValue in
                        NotificationPreferences.drinkWaterEnabled = newValue
                    }

                    Toggle(isOn: $endSession) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("End Session")
                                .font(.body)
                            Text("Reminds you to end your session after 3 hours of no activity")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: endSession) { _, newValue in
                        NotificationPreferences.endSessionEnabled = newValue
                    }
                } header: {
                    Text("During a Session")
                } footer: {
                    Text("These notifications are only sent while a session is active.")
                }

                // MARK: Party Night Reminder
                Section {
                    Toggle(isOn: $partyNightEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weekly Reminder")
                                .font(.body)
                            Text("\"Is it a party night? Start logging now!\"")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: partyNightEnabled) { _, newValue in
                        NotificationPreferences.partyNightEnabled = newValue
                        NotificationManager.schedulePartyNightNotification()
                    }

                    if partyNightEnabled {
                        // Day picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Days")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            WeekdayPickerView(selectedDays: $partyNightDays)
                        }
                        .padding(.vertical, 4)
                        .onChange(of: partyNightDays) { _, newValue in
                            NotificationPreferences.partyNightDays = newValue
                            NotificationManager.schedulePartyNightNotification()
                        }

                        // Time picker
                        DatePicker("Time", selection: $partyNightTime, displayedComponents: .hourAndMinute)
                            .onChange(of: partyNightTime) { _, newValue in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                NotificationPreferences.partyNightHour   = comps.hour ?? 19
                                NotificationPreferences.partyNightMinute = comps.minute ?? 0
                                NotificationManager.schedulePartyNightNotification()
                            }
                    }
                } header: {
                    Text("")
                } footer: {
                    Text("Sends a nudge to start logging on nights you typically go out.")
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Weekday Picker

private struct WeekdayPickerView: View {
    @Binding var selectedDays: Set<Int>

    // Ordered Mon–Sun for display, mapped to Gregorian weekday numbers (1=Sun…7=Sat)
    private let days: [(label: String, weekday: Int)] = [
        ("Mon", 2), ("Tue", 3), ("Wed", 4),
        ("Thu", 5), ("Fri", 6), ("Sat", 7), ("Sun", 1)
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.weekday) { day in
                let selected = selectedDays.contains(day.weekday)
                Button {
                    if selected {
                        // Don't allow deselecting the last day
                        if selectedDays.count > 1 { selectedDays.remove(day.weekday) }
                    } else {
                        selectedDays.insert(day.weekday)
                    }
                } label: {
                    Text(day.label)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(selected ? Color.accentColor : Color(.tertiarySystemFill),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(selected ? .black : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

