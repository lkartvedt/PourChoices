//
//  UsernameSetupView.swift
//  PourChoices
//
//  Full-screen setup shown once after sign-in.
//  Step 1: Choose a unique username.
//  Step 2: Optionally verify a phone number (can skip).
//

import SwiftUI
import CryptoKit
import FirebaseAuth

struct UsernameSetupView: View {
    let userProfile: UserProfile
    let uid: String
    var onComplete: () -> Void

    @State private var step: SetupStep = .username

    enum SetupStep { case username, phone }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch step {
            case .username:
                UsernameStepView(uid: uid) {
                    step = .phone
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            case .phone:
                PhoneStepView(uid: uid, userProfile: userProfile, onComplete: onComplete)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }
}

// MARK: - Step 1: Username

private struct UsernameStepView: View {
    let uid: String
    var onDone: () -> Void

    @State private var username = ""
    @State private var availabilityState: AvailabilityState = .idle
    @State private var errorMessage: String?
    @State private var isClaiming = false
    @FocusState private var isFocused: Bool

    @State private var checkTask: Task<Void, Never>?

    enum AvailabilityState {
        case idle, checking, available, taken, invalid
    }

    private var isValidFormat: Bool {
        let trimmed = username.lowercased()
        let regex = /^[a-z0-9_]{3,20}$/
        return (try? regex.wholeMatch(in: trimmed)) != nil
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.accent)

                Text("Choose a Username")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                Text("This is how your friends will find you.\nYou can change it once every 6 months.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                HStack {
                    Text("@")
                        .font(.title2.bold())
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("username", text: $username)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isFocused)
                        .onChange(of: username) { _, newValue in
                            let clean = newValue
                                .lowercased()
                                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                            if clean != newValue { username = clean }
                            scheduleAvailabilityCheck()
                        }
                }
                .padding()
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                availabilityRow
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Button {
                Task { await claimUsername() }
            } label: {
                Group {
                    if isClaiming {
                        ProgressView().tint(.black)
                    } else {
                        Text("Claim Username")
                            .font(.headline)
                            .foregroundStyle(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canClaim ? Color.accent : Color.gray.opacity(0.4), in: Capsule())
            }
            .disabled(!canClaim || isClaiming)
            .padding(.horizontal)

            Spacer()
        }
        .onAppear { isFocused = true }
    }

    private var canClaim: Bool { availabilityState == .available }

    @ViewBuilder
    private var availabilityRow: some View {
        HStack(spacing: 6) {
            switch availabilityState {
            case .idle:
                EmptyView()
            case .checking:
                ProgressView().scaleEffect(0.7)
                Text("Checking…").foregroundStyle(.white.opacity(0.5))
            case .available:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Available!").foregroundStyle(.green)
            case .taken:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text("Already taken").foregroundStyle(.red)
            case .invalid:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                Text("3–20 chars, letters/numbers/underscores only")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        .font(.subheadline)
        .frame(height: 24)
    }

    private func scheduleAvailabilityCheck() {
        checkTask?.cancel()
        availabilityState = .idle
        guard !username.isEmpty else { return }
        guard isValidFormat else { availabilityState = .invalid; return }
        availabilityState = .checking
        checkTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            let available = await FirestoreService.shared.isUsernameAvailable(username)
            await MainActor.run {
                availabilityState = available ? .available : .taken
            }
        }
    }

    private func claimUsername() async {
        isClaiming = true
        errorMessage = nil
        do {
            try await FirestoreService.shared.claimUsername(username, uid: uid)
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
        isClaiming = false
    }
}

// MARK: - Step 2: Phone (Optional)

private struct PhoneStepView: View {
    let uid: String
    let userProfile: UserProfile
    var onComplete: () -> Void

    @Environment(AuthenticationManager.self) private var authManager

    // Country picker
    @State private var selectedCountry: CountryCode = CountryCode.us
    @State private var showingCountryPicker = false

    // Input
    @State private var localNumber = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    // OTP state
    @State private var codeSent = false
    @State private var verificationCode = ""

    @FocusState private var numberFocused: Bool
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Image(systemName: "phone.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.accent)

                Text(codeSent ? "Enter the Code" : "Add Your Phone")
                    .font(.title.bold())
                    .foregroundStyle(.white)

                if codeSent {
                    Text("We sent a 6-digit code to \(e164Number).\nEnter it below to verify.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Text("Help friends find you by phone number.\nYour number is hashed for privacy and never shared.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            // Input area
            VStack(spacing: 16) {
                if codeSent {
                    otpInputRow
                } else {
                    phoneInputRow
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            // Actions
            VStack(spacing: 12) {
                Button {
                    Task { await primaryAction() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Text(codeSent ? "Verify Code" : "Send Code")
                                .font(.headline)
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(primaryEnabled ? Color.accent : Color.gray.opacity(0.4), in: Capsule())
                }
                .disabled(!primaryEnabled || isLoading)
                .padding(.horizontal)

                if codeSent {
                    Button("Resend Code") {
                        codeSent = false
                        verificationCode = ""
                        errorMessage = nil
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                }

                Button("Skip for now") {
                    finishSetup()
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()
        }
        .sheet(isPresented: $showingCountryPicker) {
            CountryPickerSheet(selected: $selectedCountry)
        }
        .onAppear { numberFocused = true }
    }

    // MARK: Phone input row

    @ViewBuilder
    private var phoneInputRow: some View {
        HStack(spacing: 0) {
            // Country code button
            Button {
                showingCountryPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(selectedCountry.flag)
                        .font(.title3)
                    Text(selectedCountry.dialCode)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer().frame(width: 8)

            // Local number field — formatted as digits only
            TextField(selectedCountry.placeholder, text: $localNumber)
                .font(.body.monospacedDigit())
                .foregroundStyle(.white)
                .keyboardType(.numberPad)
                .focused($numberFocused)
                .onChange(of: localNumber) { _, new in
                    let digits = new.filter { $0.isNumber }
                    if digits != new { localNumber = digits }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }

    // MARK: OTP input row

    @ViewBuilder
    private var otpInputRow: some View {
        TextField("6-digit code", text: $verificationCode)
            .font(.title2.monospacedDigit())
            .foregroundStyle(.white)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .focused($codeFocused)
            .onChange(of: verificationCode) { _, new in
                let digits = new.filter { $0.isNumber }
                let capped = String(digits.prefix(6))
                if capped != new { verificationCode = capped }
            }
            .padding()
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .onAppear { codeFocused = true }
    }

    // MARK: Helpers

    private var primaryEnabled: Bool {
        codeSent ? verificationCode.count == 6 : localNumber.count >= 7
    }

    private var e164Number: String {
        "\(selectedCountry.dialCode)\(localNumber)"
    }

    private func primaryAction() async {
        if codeSent {
            await verifyCode()
        } else {
            await sendCode()
        }
    }

    private func sendCode() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authManager.sendPhoneVerification(to: e164Number)
            codeSent = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func verifyCode() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authManager.verifyPhoneCode(verificationCode)
            // Phone verified — save hashed number to Firestore
            let hash = sha256(e164Number)
            await FirestoreService.shared.saveVerifiedPhone(uid: uid, phoneNumber: e164Number, phoneHash: hash)
            finishSetup()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func finishSetup() {
        userProfile.hasCompletedSignIn = true
        onComplete()
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Country Code Model

struct CountryCode: Identifiable, Hashable {
    let id: String        // ISO 3166-1 alpha-2
    let name: String
    let dialCode: String
    let flag: String
    let placeholder: String

    static let us = CountryCode(id: "US", name: "United States",             dialCode: "+1",   flag: "🇺🇸", placeholder: "2125551234")

    // Sorted alphabetically for the full list
    static let all: [CountryCode] = [
        us,
        CountryCode(id: "AF", name: "Afghanistan",                  dialCode: "+93",  flag: "🇦🇫", placeholder: "701234567"),
        CountryCode(id: "AL", name: "Albania",                      dialCode: "+355", flag: "🇦🇱", placeholder: "661234567"),
        CountryCode(id: "DZ", name: "Algeria",                      dialCode: "+213", flag: "🇩🇿", placeholder: "551234567"),
        CountryCode(id: "AD", name: "Andorra",                      dialCode: "+376", flag: "🇦🇩", placeholder: "312345"),
        CountryCode(id: "AO", name: "Angola",                       dialCode: "+244", flag: "🇦🇴", placeholder: "923456789"),
        CountryCode(id: "AG", name: "Antigua and Barbuda",          dialCode: "+1268",flag: "🇦🇬", placeholder: "2684641234"),
        CountryCode(id: "AR", name: "Argentina",                    dialCode: "+54",  flag: "🇦🇷", placeholder: "91123456789"),
        CountryCode(id: "AM", name: "Armenia",                      dialCode: "+374", flag: "🇦🇲", placeholder: "77123456"),
        CountryCode(id: "AU", name: "Australia",                    dialCode: "+61",  flag: "🇦🇺", placeholder: "412345678"),
        CountryCode(id: "AT", name: "Austria",                      dialCode: "+43",  flag: "🇦🇹", placeholder: "664123456"),
        CountryCode(id: "AZ", name: "Azerbaijan",                   dialCode: "+994", flag: "🇦🇿", placeholder: "401234567"),
        CountryCode(id: "BS", name: "Bahamas",                      dialCode: "+1242",flag: "🇧🇸", placeholder: "2423591234"),
        CountryCode(id: "BH", name: "Bahrain",                      dialCode: "+973", flag: "🇧🇭", placeholder: "36001234"),
        CountryCode(id: "BD", name: "Bangladesh",                   dialCode: "+880", flag: "🇧🇩", placeholder: "1812345678"),
        CountryCode(id: "BB", name: "Barbados",                     dialCode: "+1246",flag: "🇧🇧", placeholder: "2462501234"),
        CountryCode(id: "BY", name: "Belarus",                      dialCode: "+375", flag: "🇧🇾", placeholder: "291234567"),
        CountryCode(id: "BE", name: "Belgium",                      dialCode: "+32",  flag: "🇧🇪", placeholder: "470123456"),
        CountryCode(id: "BZ", name: "Belize",                       dialCode: "+501", flag: "🇧🇿", placeholder: "6221234"),
        CountryCode(id: "BJ", name: "Benin",                        dialCode: "+229", flag: "🇧🇯", placeholder: "90123456"),
        CountryCode(id: "BT", name: "Bhutan",                       dialCode: "+975", flag: "🇧🇹", placeholder: "17123456"),
        CountryCode(id: "BO", name: "Bolivia",                      dialCode: "+591", flag: "🇧🇴", placeholder: "71234567"),
        CountryCode(id: "BA", name: "Bosnia and Herzegovina",       dialCode: "+387", flag: "🇧🇦", placeholder: "61123456"),
        CountryCode(id: "BW", name: "Botswana",                     dialCode: "+267", flag: "🇧🇼", placeholder: "71123456"),
        CountryCode(id: "BR", name: "Brazil",                       dialCode: "+55",  flag: "🇧🇷", placeholder: "11912345678"),
        CountryCode(id: "BN", name: "Brunei",                       dialCode: "+673", flag: "🇧🇳", placeholder: "7123456"),
        CountryCode(id: "BG", name: "Bulgaria",                     dialCode: "+359", flag: "🇧🇬", placeholder: "87123456"),
        CountryCode(id: "BF", name: "Burkina Faso",                 dialCode: "+226", flag: "🇧🇫", placeholder: "70123456"),
        CountryCode(id: "BI", name: "Burundi",                      dialCode: "+257", flag: "🇧🇮", placeholder: "79561234"),
        CountryCode(id: "CV", name: "Cabo Verde",                   dialCode: "+238", flag: "🇨🇻", placeholder: "9911234"),
        CountryCode(id: "KH", name: "Cambodia",                     dialCode: "+855", flag: "🇰🇭", placeholder: "91234567"),
        CountryCode(id: "CM", name: "Cameroon",                     dialCode: "+237", flag: "🇨🇲", placeholder: "671234567"),
        CountryCode(id: "CA", name: "Canada",                       dialCode: "+1",   flag: "🇨🇦", placeholder: "4165551234"),
        CountryCode(id: "CF", name: "Central African Republic",     dialCode: "+236", flag: "🇨🇫", placeholder: "70012345"),
        CountryCode(id: "TD", name: "Chad",                         dialCode: "+235", flag: "🇹🇩", placeholder: "63012345"),
        CountryCode(id: "CL", name: "Chile",                        dialCode: "+56",  flag: "🇨🇱", placeholder: "912345678"),
        CountryCode(id: "CN", name: "China",                        dialCode: "+86",  flag: "🇨🇳", placeholder: "13123456789"),
        CountryCode(id: "CO", name: "Colombia",                     dialCode: "+57",  flag: "🇨🇴", placeholder: "3211234567"),
        CountryCode(id: "KM", name: "Comoros",                      dialCode: "+269", flag: "🇰🇲", placeholder: "3212345"),
        CountryCode(id: "CG", name: "Congo",                        dialCode: "+242", flag: "🇨🇬", placeholder: "061234567"),
        CountryCode(id: "CD", name: "Congo (DRC)",                  dialCode: "+243", flag: "🇨🇩", placeholder: "991234567"),
        CountryCode(id: "CR", name: "Costa Rica",                   dialCode: "+506", flag: "🇨🇷", placeholder: "83123456"),
        CountryCode(id: "CI", name: "Côte d'Ivoire",                dialCode: "+225", flag: "🇨🇮", placeholder: "0712345678"),
        CountryCode(id: "HR", name: "Croatia",                      dialCode: "+385", flag: "🇭🇷", placeholder: "91234567"),
        CountryCode(id: "CU", name: "Cuba",                         dialCode: "+53",  flag: "🇨🇺", placeholder: "51234567"),
        CountryCode(id: "CY", name: "Cyprus",                       dialCode: "+357", flag: "🇨🇾", placeholder: "96123456"),
        CountryCode(id: "CZ", name: "Czech Republic",               dialCode: "+420", flag: "🇨🇿", placeholder: "601123456"),
        CountryCode(id: "DK", name: "Denmark",                      dialCode: "+45",  flag: "🇩🇰", placeholder: "20123456"),
        CountryCode(id: "DJ", name: "Djibouti",                     dialCode: "+253", flag: "🇩🇯", placeholder: "77831001"),
        CountryCode(id: "DM", name: "Dominica",                     dialCode: "+1767",flag: "🇩🇲", placeholder: "7672251234"),
        CountryCode(id: "DO", name: "Dominican Republic",           dialCode: "+1809",flag: "🇩🇴", placeholder: "8092345678"),
        CountryCode(id: "EC", name: "Ecuador",                      dialCode: "+593", flag: "🇪🇨", placeholder: "991234567"),
        CountryCode(id: "EG", name: "Egypt",                        dialCode: "+20",  flag: "🇪🇬", placeholder: "1001234567"),
        CountryCode(id: "SV", name: "El Salvador",                  dialCode: "+503", flag: "🇸🇻", placeholder: "70123456"),
        CountryCode(id: "GQ", name: "Equatorial Guinea",            dialCode: "+240", flag: "🇬🇶", placeholder: "222123456"),
        CountryCode(id: "ER", name: "Eritrea",                      dialCode: "+291", flag: "🇪🇷", placeholder: "7123456"),
        CountryCode(id: "EE", name: "Estonia",                      dialCode: "+372", flag: "🇪🇪", placeholder: "51234567"),
        CountryCode(id: "SZ", name: "Eswatini",                     dialCode: "+268", flag: "🇸🇿", placeholder: "76123456"),
        CountryCode(id: "ET", name: "Ethiopia",                     dialCode: "+251", flag: "🇪🇹", placeholder: "911234567"),
        CountryCode(id: "FJ", name: "Fiji",                         dialCode: "+679", flag: "🇫🇯", placeholder: "7012345"),
        CountryCode(id: "FI", name: "Finland",                      dialCode: "+358", flag: "🇫🇮", placeholder: "412345678"),
        CountryCode(id: "FR", name: "France",                       dialCode: "+33",  flag: "🇫🇷", placeholder: "612345678"),
        CountryCode(id: "GA", name: "Gabon",                        dialCode: "+241", flag: "🇬🇦", placeholder: "06031234"),
        CountryCode(id: "GM", name: "Gambia",                       dialCode: "+220", flag: "🇬🇲", placeholder: "3012345"),
        CountryCode(id: "GE", name: "Georgia",                      dialCode: "+995", flag: "🇬🇪", placeholder: "551234567"),
        CountryCode(id: "DE", name: "Germany",                      dialCode: "+49",  flag: "🇩🇪", placeholder: "15123456789"),
        CountryCode(id: "GH", name: "Ghana",                        dialCode: "+233", flag: "🇬🇭", placeholder: "231234567"),
        CountryCode(id: "GR", name: "Greece",                       dialCode: "+30",  flag: "🇬🇷", placeholder: "6912345678"),
        CountryCode(id: "GD", name: "Grenada",                      dialCode: "+1473",flag: "🇬🇩", placeholder: "4734031234"),
        CountryCode(id: "GT", name: "Guatemala",                    dialCode: "+502", flag: "🇬🇹", placeholder: "51234567"),
        CountryCode(id: "GN", name: "Guinea",                       dialCode: "+224", flag: "🇬🇳", placeholder: "601123456"),
        CountryCode(id: "GW", name: "Guinea-Bissau",                dialCode: "+245", flag: "🇬🇼", placeholder: "5551234"),
        CountryCode(id: "GY", name: "Guyana",                       dialCode: "+592", flag: "🇬🇾", placeholder: "6091234"),
        CountryCode(id: "HT", name: "Haiti",                        dialCode: "+509", flag: "🇭🇹", placeholder: "34101234"),
        CountryCode(id: "HN", name: "Honduras",                     dialCode: "+504", flag: "🇭🇳", placeholder: "91234567"),
        CountryCode(id: "HU", name: "Hungary",                      dialCode: "+36",  flag: "🇭🇺", placeholder: "201234567"),
        CountryCode(id: "IS", name: "Iceland",                      dialCode: "+354", flag: "🇮🇸", placeholder: "6111234"),
        CountryCode(id: "IN", name: "India",                        dialCode: "+91",  flag: "🇮🇳", placeholder: "9123456789"),
        CountryCode(id: "ID", name: "Indonesia",                    dialCode: "+62",  flag: "🇮🇩", placeholder: "81234567890"),
        CountryCode(id: "IR", name: "Iran",                         dialCode: "+98",  flag: "🇮🇷", placeholder: "9123456789"),
        CountryCode(id: "IQ", name: "Iraq",                         dialCode: "+964", flag: "🇮🇶", placeholder: "7912345678"),
        CountryCode(id: "IE", name: "Ireland",                      dialCode: "+353", flag: "🇮🇪", placeholder: "851234567"),
        CountryCode(id: "IL", name: "Israel",                       dialCode: "+972", flag: "🇮🇱", placeholder: "521234567"),
        CountryCode(id: "IT", name: "Italy",                        dialCode: "+39",  flag: "🇮🇹", placeholder: "3123456789"),
        CountryCode(id: "JM", name: "Jamaica",                      dialCode: "+1876",flag: "🇯🇲", placeholder: "8762101234"),
        CountryCode(id: "JP", name: "Japan",                        dialCode: "+81",  flag: "🇯🇵", placeholder: "9012345678"),
        CountryCode(id: "JO", name: "Jordan",                       dialCode: "+962", flag: "🇯🇴", placeholder: "791234567"),
        CountryCode(id: "KZ", name: "Kazakhstan",                   dialCode: "+7",   flag: "🇰🇿", placeholder: "7011234567"),
        CountryCode(id: "KE", name: "Kenya",                        dialCode: "+254", flag: "🇰🇪", placeholder: "712345678"),
        CountryCode(id: "KI", name: "Kiribati",                     dialCode: "+686", flag: "🇰🇮", placeholder: "72001234"),
        CountryCode(id: "KW", name: "Kuwait",                       dialCode: "+965", flag: "🇰🇼", placeholder: "51234567"),
        CountryCode(id: "KG", name: "Kyrgyzstan",                   dialCode: "+996", flag: "🇰🇬", placeholder: "700123456"),
        CountryCode(id: "LA", name: "Laos",                         dialCode: "+856", flag: "🇱🇦", placeholder: "2012345678"),
        CountryCode(id: "LV", name: "Latvia",                       dialCode: "+371", flag: "🇱🇻", placeholder: "21234567"),
        CountryCode(id: "LB", name: "Lebanon",                      dialCode: "+961", flag: "🇱🇧", placeholder: "71123456"),
        CountryCode(id: "LS", name: "Lesotho",                      dialCode: "+266", flag: "🇱🇸", placeholder: "50123456"),
        CountryCode(id: "LR", name: "Liberia",                      dialCode: "+231", flag: "🇱🇷", placeholder: "770123456"),
        CountryCode(id: "LY", name: "Libya",                        dialCode: "+218", flag: "🇱🇾", placeholder: "912345678"),
        CountryCode(id: "LI", name: "Liechtenstein",                dialCode: "+423", flag: "🇱🇮", placeholder: "660234567"),
        CountryCode(id: "LT", name: "Lithuania",                    dialCode: "+370", flag: "🇱🇹", placeholder: "61234567"),
        CountryCode(id: "LU", name: "Luxembourg",                   dialCode: "+352", flag: "🇱🇺", placeholder: "628123456"),
        CountryCode(id: "MG", name: "Madagascar",                   dialCode: "+261", flag: "🇲🇬", placeholder: "321234567"),
        CountryCode(id: "MW", name: "Malawi",                       dialCode: "+265", flag: "🇲🇼", placeholder: "991234567"),
        CountryCode(id: "MY", name: "Malaysia",                     dialCode: "+60",  flag: "🇲🇾", placeholder: "123456789"),
        CountryCode(id: "MV", name: "Maldives",                     dialCode: "+960", flag: "🇲🇻", placeholder: "7712345"),
        CountryCode(id: "ML", name: "Mali",                         dialCode: "+223", flag: "🇲🇱", placeholder: "65012345"),
        CountryCode(id: "MT", name: "Malta",                        dialCode: "+356", flag: "🇲🇹", placeholder: "96961234"),
        CountryCode(id: "MH", name: "Marshall Islands",             dialCode: "+692", flag: "🇲🇭", placeholder: "2351234"),
        CountryCode(id: "MR", name: "Mauritania",                   dialCode: "+222", flag: "🇲🇷", placeholder: "22123456"),
        CountryCode(id: "MU", name: "Mauritius",                    dialCode: "+230", flag: "🇲🇺", placeholder: "52512345"),
        CountryCode(id: "MX", name: "Mexico",                       dialCode: "+52",  flag: "🇲🇽", placeholder: "5512345678"),
        CountryCode(id: "FM", name: "Micronesia",                   dialCode: "+691", flag: "🇫🇲", placeholder: "3201234"),
        CountryCode(id: "MD", name: "Moldova",                      dialCode: "+373", flag: "🇲🇩", placeholder: "62112345"),
        CountryCode(id: "MC", name: "Monaco",                       dialCode: "+377", flag: "🇲🇨", placeholder: "612345678"),
        CountryCode(id: "MN", name: "Mongolia",                     dialCode: "+976", flag: "🇲🇳", placeholder: "88112233"),
        CountryCode(id: "ME", name: "Montenegro",                   dialCode: "+382", flag: "🇲🇪", placeholder: "67622901"),
        CountryCode(id: "MA", name: "Morocco",                      dialCode: "+212", flag: "🇲🇦", placeholder: "650123456"),
        CountryCode(id: "MZ", name: "Mozambique",                   dialCode: "+258", flag: "🇲🇿", placeholder: "821234567"),
        CountryCode(id: "MM", name: "Myanmar",                      dialCode: "+95",  flag: "🇲🇲", placeholder: "912345678"),
        CountryCode(id: "NA", name: "Namibia",                      dialCode: "+264", flag: "🇳🇦", placeholder: "811234567"),
        CountryCode(id: "NR", name: "Nauru",                        dialCode: "+674", flag: "🇳🇷", placeholder: "5551234"),
        CountryCode(id: "NP", name: "Nepal",                        dialCode: "+977", flag: "🇳🇵", placeholder: "9812345678"),
        CountryCode(id: "NL", name: "Netherlands",                  dialCode: "+31",  flag: "🇳🇱", placeholder: "612345678"),
        CountryCode(id: "NZ", name: "New Zealand",                  dialCode: "+64",  flag: "🇳🇿", placeholder: "211234567"),
        CountryCode(id: "NI", name: "Nicaragua",                    dialCode: "+505", flag: "🇳🇮", placeholder: "81234567"),
        CountryCode(id: "NE", name: "Niger",                        dialCode: "+227", flag: "🇳🇪", placeholder: "93123456"),
        CountryCode(id: "NG", name: "Nigeria",                      dialCode: "+234", flag: "🇳🇬", placeholder: "8012345678"),
        CountryCode(id: "NO", name: "Norway",                       dialCode: "+47",  flag: "🇳🇴", placeholder: "41234567"),
        CountryCode(id: "OM", name: "Oman",                         dialCode: "+968", flag: "🇴🇲", placeholder: "92123456"),
        CountryCode(id: "PK", name: "Pakistan",                     dialCode: "+92",  flag: "🇵🇰", placeholder: "3012345678"),
        CountryCode(id: "PW", name: "Palau",                        dialCode: "+680", flag: "🇵🇼", placeholder: "7701234"),
        CountryCode(id: "PA", name: "Panama",                       dialCode: "+507", flag: "🇵🇦", placeholder: "61234567"),
        CountryCode(id: "PG", name: "Papua New Guinea",             dialCode: "+675", flag: "🇵🇬", placeholder: "70123456"),
        CountryCode(id: "PY", name: "Paraguay",                     dialCode: "+595", flag: "🇵🇾", placeholder: "961456789"),
        CountryCode(id: "PE", name: "Peru",                         dialCode: "+51",  flag: "🇵🇪", placeholder: "912345678"),
        CountryCode(id: "PH", name: "Philippines",                  dialCode: "+63",  flag: "🇵🇭", placeholder: "9051234567"),
        CountryCode(id: "PL", name: "Poland",                       dialCode: "+48",  flag: "🇵🇱", placeholder: "512345678"),
        CountryCode(id: "PT", name: "Portugal",                     dialCode: "+351", flag: "🇵🇹", placeholder: "912345678"),
        CountryCode(id: "QA", name: "Qatar",                        dialCode: "+974", flag: "🇶🇦", placeholder: "33123456"),
        CountryCode(id: "RO", name: "Romania",                      dialCode: "+40",  flag: "🇷🇴", placeholder: "712034567"),
        CountryCode(id: "RU", name: "Russia",                       dialCode: "+7",   flag: "🇷🇺", placeholder: "9123456789"),
        CountryCode(id: "RW", name: "Rwanda",                       dialCode: "+250", flag: "🇷🇼", placeholder: "720123456"),
        CountryCode(id: "KN", name: "Saint Kitts and Nevis",        dialCode: "+1869",flag: "🇰🇳", placeholder: "8697651234"),
        CountryCode(id: "LC", name: "Saint Lucia",                  dialCode: "+1758",flag: "🇱🇨", placeholder: "7582861234"),
        CountryCode(id: "VC", name: "Saint Vincent and Grenadines", dialCode: "+1784",flag: "🇻🇨", placeholder: "7844301234"),
        CountryCode(id: "WS", name: "Samoa",                        dialCode: "+685", flag: "🇼🇸", placeholder: "7212345"),
        CountryCode(id: "SM", name: "San Marino",                   dialCode: "+378", flag: "🇸🇲", placeholder: "66661212"),
        CountryCode(id: "ST", name: "São Tomé and Príncipe",        dialCode: "+239", flag: "🇸🇹", placeholder: "9812345"),
        CountryCode(id: "SA", name: "Saudi Arabia",                 dialCode: "+966", flag: "🇸🇦", placeholder: "512345678"),
        CountryCode(id: "SN", name: "Senegal",                      dialCode: "+221", flag: "🇸🇳", placeholder: "701234567"),
        CountryCode(id: "RS", name: "Serbia",                       dialCode: "+381", flag: "🇷🇸", placeholder: "601234567"),
        CountryCode(id: "SC", name: "Seychelles",                   dialCode: "+248", flag: "🇸🇨", placeholder: "2512345"),
        CountryCode(id: "SL", name: "Sierra Leone",                 dialCode: "+232", flag: "🇸🇱", placeholder: "76123456"),
        CountryCode(id: "SG", name: "Singapore",                    dialCode: "+65",  flag: "🇸🇬", placeholder: "81234567"),
        CountryCode(id: "SK", name: "Slovakia",                     dialCode: "+421", flag: "🇸🇰", placeholder: "912123456"),
        CountryCode(id: "SI", name: "Slovenia",                     dialCode: "+386", flag: "🇸🇮", placeholder: "31234567"),
        CountryCode(id: "SB", name: "Solomon Islands",              dialCode: "+677", flag: "🇸🇧", placeholder: "7421234"),
        CountryCode(id: "SO", name: "Somalia",                      dialCode: "+252", flag: "🇸🇴", placeholder: "71123456"),
        CountryCode(id: "ZA", name: "South Africa",                 dialCode: "+27",  flag: "🇿🇦", placeholder: "821234567"),
        CountryCode(id: "SS", name: "South Sudan",                  dialCode: "+211", flag: "🇸🇸", placeholder: "977123456"),
        CountryCode(id: "ES", name: "Spain",                        dialCode: "+34",  flag: "🇪🇸", placeholder: "612345678"),
        CountryCode(id: "LK", name: "Sri Lanka",                    dialCode: "+94",  flag: "🇱🇰", placeholder: "712345678"),
        CountryCode(id: "SD", name: "Sudan",                        dialCode: "+249", flag: "🇸🇩", placeholder: "912345678"),
        CountryCode(id: "SR", name: "Suriname",                     dialCode: "+597", flag: "🇸🇷", placeholder: "7412345"),
        CountryCode(id: "SE", name: "Sweden",                       dialCode: "+46",  flag: "🇸🇪", placeholder: "701234567"),
        CountryCode(id: "CH", name: "Switzerland",                  dialCode: "+41",  flag: "🇨🇭", placeholder: "781234567"),
        CountryCode(id: "SY", name: "Syria",                        dialCode: "+963", flag: "🇸🇾", placeholder: "944567890"),
        CountryCode(id: "TW", name: "Taiwan",                       dialCode: "+886", flag: "🇹🇼", placeholder: "912345678"),
        CountryCode(id: "TJ", name: "Tajikistan",                   dialCode: "+992", flag: "🇹🇯", placeholder: "917123456"),
        CountryCode(id: "TZ", name: "Tanzania",                     dialCode: "+255", flag: "🇹🇿", placeholder: "621234567"),
        CountryCode(id: "TH", name: "Thailand",                     dialCode: "+66",  flag: "🇹🇭", placeholder: "812345678"),
        CountryCode(id: "TL", name: "Timor-Leste",                  dialCode: "+670", flag: "🇹🇱", placeholder: "77212345"),
        CountryCode(id: "TG", name: "Togo",                         dialCode: "+228", flag: "🇹🇬", placeholder: "90112345"),
        CountryCode(id: "TO", name: "Tonga",                        dialCode: "+676", flag: "🇹🇴", placeholder: "7715123"),
        CountryCode(id: "TT", name: "Trinidad and Tobago",          dialCode: "+1868",flag: "🇹🇹", placeholder: "8682211234"),
        CountryCode(id: "TN", name: "Tunisia",                      dialCode: "+216", flag: "🇹🇳", placeholder: "20123456"),
        CountryCode(id: "TR", name: "Turkey",                       dialCode: "+90",  flag: "🇹🇷", placeholder: "5012345678"),
        CountryCode(id: "TM", name: "Turkmenistan",                 dialCode: "+993", flag: "🇹🇲", placeholder: "66123456"),
        CountryCode(id: "TV", name: "Tuvalu",                       dialCode: "+688", flag: "🇹🇻", placeholder: "901234"),
        CountryCode(id: "UG", name: "Uganda",                       dialCode: "+256", flag: "🇺🇬", placeholder: "712345678"),
        CountryCode(id: "UA", name: "Ukraine",                      dialCode: "+380", flag: "🇺🇦", placeholder: "501234567"),
        CountryCode(id: "AE", name: "United Arab Emirates",         dialCode: "+971", flag: "🇦🇪", placeholder: "501234567"),
        CountryCode(id: "GB", name: "United Kingdom",               dialCode: "+44",  flag: "🇬🇧", placeholder: "7911123456"),
        CountryCode(id: "UY", name: "Uruguay",                      dialCode: "+598", flag: "🇺🇾", placeholder: "94231234"),
        CountryCode(id: "UZ", name: "Uzbekistan",                   dialCode: "+998", flag: "🇺🇿", placeholder: "912345678"),
        CountryCode(id: "VU", name: "Vanuatu",                      dialCode: "+678", flag: "🇻🇺", placeholder: "5912345"),
        CountryCode(id: "VE", name: "Venezuela",                    dialCode: "+58",  flag: "🇻🇪", placeholder: "4121234567"),
        CountryCode(id: "VN", name: "Vietnam",                      dialCode: "+84",  flag: "🇻🇳", placeholder: "912345678"),
        CountryCode(id: "YE", name: "Yemen",                        dialCode: "+967", flag: "🇾🇪", placeholder: "712345678"),
        CountryCode(id: "ZM", name: "Zambia",                       dialCode: "+260", flag: "🇿🇲", placeholder: "955123456"),
        CountryCode(id: "ZW", name: "Zimbabwe",                     dialCode: "+263", flag: "🇿🇼", placeholder: "712345678"),
    ]
}

// MARK: - Country Picker Sheet

private struct CountryPickerSheet: View {
    @Binding var selected: CountryCode
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [CountryCode] {
        if search.isEmpty { return CountryCode.all }
        return CountryCode.all.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.dialCode.contains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { country in
                Button {
                    selected = country
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(country.flag).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(country.name)
                                .foregroundStyle(.primary)
                            Text(country.dialCode)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if country == selected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.accent)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $search, prompt: "Search country or code")
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
