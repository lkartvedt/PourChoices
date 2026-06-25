//
//  ProfileSettingsView.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/15/26.
//
import SwiftUI

// MARK: - Profile Settings View
struct ProfileSettingsView: View {
    @Bindable var profile: UserProfile
    @FocusState private var isWeightFocused: Bool
    @Environment(AuthenticationManager.self) private var auth

    // Quick-add button config state — loaded from shared App Group defaults
    @State private var button1Config: QuickAddButtonConfig = SharedDefaults.loadButton(slot: 1)
    @State private var button2Config: QuickAddButtonConfig = SharedDefaults.loadButton(slot: 2)
    @State private var showingButton1Picker = false
    @State private var showingButton2Picker = false
    @State private var showingNotificationSettings = false
    @State private var showingSignOutConfirmation = false

    @Environment(\.openURL) private var openURL
    
    var heightFeet: Int {
        Int(profile.heightInches) / 12
    }
    
    var heightInches: Int {
        Int(profile.heightInches) % 12
    }
    
    var body: some View {
        Form {
            Section("Your Info") {
                VStack(alignment: .leading, spacing: 4) {
                    DatePicker("Birthdate",
                              selection: Binding(
                                get: { profile.birthdate ?? Date() },
                                set: { profile.birthdate = $0 }
                              ),
                              in: ...Calendar.current.date(byAdding: .year, value: -21, to: Date())!,
                              displayedComponents: .date)
                        .tint(.blue)
                    
                    Text("Must be 21+")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Age")
                    Spacer()
                    Text("\(profile.age)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Height")
                    Spacer()
                    HStack(spacing: 8) {
                        Picker("", selection: Binding(
                            get: { heightFeet },
                            set: { newFeet in
                                profile.heightInches = Double(newFeet * 12 + heightInches)
                            }
                        )) {
                            ForEach(3...8, id: \.self) { feet in
                                Text("\(feet)'").tag(feet)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .foregroundStyle(.white)
                        
                        Picker("", selection: Binding(
                            get: { heightInches },
                            set: { newInches in
                                profile.heightInches = Double(heightFeet * 12 + newInches)
                            }
                        )) {
                            ForEach(0...11, id: \.self) { inches in
                                Text("\(inches)\"").tag(inches)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .foregroundStyle(.white)
                    }
                }
                
                HStack {
                    Text("Weight (lbs)")
                    Spacer()
                    TextField("Weight", value: $profile.weight, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .focused($isWeightFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isWeightFocused = false
                        }
                }
                
                HStack {
                    Text("Sex")
                    Spacer()
                    Picker("Sex", selection: $profile.sex) {
                        Text("Male").tag("Male")
                        Text("Female").tag("Female")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
            
            Section("Lock Screen Quick Add") {
                Button {
                    showingButton1Picker = true
                } label: {
                    HStack {
                        Image(systemName: "1.circle.fill")
                            .foregroundStyle(.accent)
                        Text("Button 1")
                        Spacer()
                        Text(button1Config.displayLabel)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button {
                    showingButton2Picker = true
                } label: {
                    HStack {
                        Image(systemName: "2.circle.fill")
                            .foregroundStyle(.accent)
                        Text("Button 2")
                        Spacer()
                        Text(button2Config.displayLabel)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            Section("Notifications") {
                Button {
                    showingNotificationSettings = true
                } label: {
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.accent)
                        Text("Notification Preferences")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Important", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.headline)
                    
                    Text("This app is for tracking purposes only. BAC calculations are estimates and should NOT be used to determine if you're safe to drive.")
                        .font(.caption)
                    
                    Text("DO NOT DRIVE after drinking, regardless of your estimated BAC. Use a rideshare, taxi, public transit, or designated driver.")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.secondary)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Get Help", systemImage: "staroflife.circle.fill")
                        .foregroundStyle(.red)
                        .font(.headline)
                    
                    Text("Drinking looks different for everyone. If you're finding it hard to cut back, or just want to talk to someone, you're not alone and support is available.")
                        .font(.caption)
                    
                    Spacer()

                    Button {
                        openURL(URL(string: "tel://18006624357")!)
                    } label: {
                        Label("1-800-662-4357", systemImage: "phone.fill")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    
                    Spacer()

                    Button {
                        openURL(URL(string: "https://www.samhsa.gov/find-help/national-helpline")!)
                    } label: {
                        Label("SAMHSA National Helpline", systemImage: "globe")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    
                    Spacer()
                    
                    Text("PourChoices is built for awareness, not encouragement. Please drink responsibly.")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.secondary)
            }

            Section {
                Button(role: .destructive) {
                    showingSignOutConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Sign Out")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .confirmationDialog("Sign Out", isPresented: $showingSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { auth.signOut() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You will need to sign in again to access PourChoices.")
        }
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            isWeightFocused = false
        }
        .sheet(isPresented: $showingButton1Picker) {
            QuickAddButtonPickerView(slot: 1, currentConfig: $button1Config)
        }
        .sheet(isPresented: $showingButton2Picker) {
            QuickAddButtonPickerView(slot: 2, currentConfig: $button2Config)
        }
        .sheet(isPresented: $showingNotificationSettings) {
            NotificationSettingsView()
        }
    }
}
