//
//  NotificationSettingsView.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/15/26.
//

import SwiftUI

// MARK: - Notification Settings View

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var forgotToLog  = NotificationPreferences.forgotToLogEnabled
    @State private var drinkWater   = NotificationPreferences.drinkWaterEnabled
    @State private var endSession   = NotificationPreferences.endSessionEnabled

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $forgotToLog) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Log Reminder")
                                .font(.body)
                            Text("Reminds you after 1 hour of no activity if your BAC is below 0.08")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: forgotToLog) { _, newValue in
                        NotificationPreferences.forgotToLogEnabled = newValue
                    }

                    Toggle(isOn: $drinkWater) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Drink water")
                                .font(.body)
                            Text("Sends a reminder every 45 minutes while your BAC is above 0.175")
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
                } footer: {
                    Text("Notifications are only sent during an active session.")
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
