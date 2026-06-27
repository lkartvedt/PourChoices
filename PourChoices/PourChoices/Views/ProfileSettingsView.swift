//
//  ProfileSettingsView.swift
//  PourChoices
//
//  Created by Lindsey Kartvedt on 6/15/26.
//
import SwiftUI
import CryptoKit

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

    // Account / username
    @State private var firestoreUser: FirestoreUser? = nil
    @State private var showingUsernameChange = false
    // Account / phone
    @State private var showingPhoneSetup = false

    @Environment(\.openURL) private var openURL
    
    var heightFeet: Int {
        Int(profile.heightInches) / 12
    }
    
    var heightInches: Int {
        Int(profile.heightInches) % 12
    }
    
    var body: some View {
        Form {
            Section("Account") {
                accountUsernameRow
                accountPhoneRow
            }

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
        .task {
            if let uid = auth.firebaseUID {
                firestoreUser = await FirestoreService.shared.getUser(uid: uid)
            }
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
        .sheet(isPresented: $showingUsernameChange) {
            if let uid = auth.firebaseUID {
                ChangeUsernameView(currentUsername: firestoreUser?.username ?? "", uid: uid) { newUsername in
                    firestoreUser?.username = newUsername
                    showingUsernameChange = false
                }
            }
        }
        .sheet(isPresented: $showingPhoneSetup) {
            if let uid = auth.firebaseUID {
                PhoneSetupSheet(uid: uid) { phone in
                    firestoreUser?.phoneNumber = phone
                    showingPhoneSetup = false
                }
            }
        }
    }

    // MARK: - Account Rows

    @ViewBuilder
    private var accountUsernameRow: some View {
        HStack {
            Image(systemName: "at").foregroundStyle(.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Username")
                if let username = firestoreUser?.username {
                    Text("@\(username)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Change") { showingUsernameChange = true }
                .font(.subheadline)
                .disabled(!canChangeUsername)
                .foregroundStyle(canChangeUsername ? .accent : .secondary)
        }
        .contentShape(Rectangle())
        if !canChangeUsername, let nextDate = nextUsernameChangeDate {
            Text("Can change again \(nextDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var accountPhoneRow: some View {
        HStack {
            Image(systemName: "phone.fill").foregroundStyle(.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Phone Number")
                if let phone = firestoreUser?.phoneNumber {
                    Text(phone).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Not set").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(firestoreUser?.phoneNumber == nil ? "Add" : "Change") {
                showingPhoneSetup = true
            }
            .font(.subheadline)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Username Change Eligibility

    private var canChangeUsername: Bool {
        guard let lastChange = firestoreUser?.lastUsernameChange else { return true }
        return Date().timeIntervalSince(lastChange) > (6 * 30 * 24 * 3600)
    }

    private var nextUsernameChangeDate: Date? {
        guard let lastChange = firestoreUser?.lastUsernameChange else { return nil }
        return lastChange.addingTimeInterval(6 * 30 * 24 * 3600)
    }
}
// MARK: - Change Username Sheet

private struct ChangeUsernameView: View {
    let currentUsername: String
    let uid: String
    var onComplete: (String) -> Void

    @State private var newUsername = ""
    @State private var availabilityState: AvailState = .idle
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var checkTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    enum AvailState { case idle, checking, available, taken, invalid, same }

    private var isValidFormat: Bool {
        let trimmed = newUsername.lowercased()
        let regex = /^[a-z0-9_]{3,20}$/
        return (try? regex.wholeMatch(in: trimmed)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("new_username", text: $newUsername)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isFocused)
                        .onChange(of: newUsername) { _, v in
                            let clean = v.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
                            if clean != v { newUsername = clean }
                            scheduleCheck()
                        }

                    HStack(spacing: 6) {
                        switch availabilityState {
                        case .idle: EmptyView()
                        case .checking:
                            ProgressView().scaleEffect(0.7)
                            Text("Checking…").foregroundStyle(.secondary)
                        case .available:
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Available!").foregroundStyle(.green)
                        case .taken:
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            Text("Already taken").foregroundStyle(.red)
                        case .invalid:
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                            Text("3–20 chars, letters/numbers/underscores").foregroundStyle(.orange)
                        case .same:
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            Text("Same as current username").foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                } header: {
                    Text("New username (current: @\(currentUsername))")
                }

                if let error = errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }

                Section {
                    Text("Changing your username releases your current one. Someone else can claim it immediately. You can only change once every 6 months.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Change Username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onComplete(currentUsername) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveUsername() }
                    }
                    .disabled(availabilityState != .available || isSubmitting)
                }
            }
            .onAppear { isFocused = true }
        }
    }

    private func scheduleCheck() {
        checkTask?.cancel()
        availabilityState = .idle
        guard !newUsername.isEmpty else { return }
        if newUsername.lowercased() == currentUsername.lowercased() { availabilityState = .same; return }
        guard isValidFormat else { availabilityState = .invalid; return }
        availabilityState = .checking
        checkTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            let available = await FirestoreService.shared.isUsernameAvailable(newUsername)
            await MainActor.run { availabilityState = available ? .available : .taken }
        }
    }

    private func saveUsername() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await FirestoreService.shared.changeUsername(from: currentUsername, to: newUsername, uid: uid)
            onComplete(newUsername.lowercased())
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - Phone Setup Sheet

private struct PhoneSetupSheet: View {
    let uid: String
    var onComplete: (String) -> Void

    @Environment(AuthenticationManager.self) private var auth
    @State private var phoneNumber = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if !codeSent {
                    Section("Phone Number") {
                        TextField("+1 (555) 867-5309", text: $phoneNumber)
                            .keyboardType(.phonePad)
                    }
                } else {
                    Section("Verification Code") {
                        TextField("6-digit code", text: $code)
                            .keyboardType(.numberPad)
                    }
                }

                if let error = errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }

                Section {
                    Button(codeSent ? "Verify Code" : "Send Code") {
                        Task { await primaryAction() }
                    }
                    .disabled(isLoading)
                }
            }
            .navigationTitle("Phone Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func primaryAction() async {
        isLoading = true
        errorMessage = nil
        if codeSent {
            do {
                try await auth.verifyPhoneCode(code)
                let digits = phoneNumber.filter { $0.isNumber }
                let e164 = digits.count == 10 ? "+1\(digits)" : "+\(digits)"
                let hash = sha256(e164)
                await FirestoreService.shared.saveVerifiedPhone(uid: uid, phoneNumber: e164, phoneHash: hash)
                onComplete(e164)
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            let digits = phoneNumber.filter { $0.isNumber }
            let e164: String
            switch digits.count {
            case 11 where digits.hasPrefix("1"): e164 = "+\(digits)"
            case 10: e164 = "+1\(digits)"
            default:
                errorMessage = "Please enter a valid US phone number."
                isLoading = false
                return
            }
            do {
                try await auth.sendPhoneVerification(to: e164)
                phoneNumber = e164
                codeSent = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

