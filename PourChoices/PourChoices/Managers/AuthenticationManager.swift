import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseAuth

// MARK: - Auth State

enum AuthState: Equatable {
    case unknown
    case signedOut
    case signedIn(userID: String, displayName: String?, email: String?)
}

// MARK: - Auth Error

enum AuthError: LocalizedError {
    case cancelled
    case credentialInvalid
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Sign-in was cancelled."
        case .credentialInvalid: return "The credential was invalid. Please try again."
        case .unknown(let e): return e.localizedDescription
        }
    }
}

// MARK: - AuthenticationManager

@Observable
final class AuthenticationManager: NSObject {

    // MARK: Persistence keys (stored in App Group so extensions can read if needed)
    private enum Keys {
        static let userID      = "auth.userID"
        static let displayName = "auth.displayName"
        static let email       = "auth.email"
        static let provider    = "auth.provider"
    }

    // Use the App Group suite so the widget extension can read auth state.
    // Falls back to standard UserDefaults if the App Group isn't provisioned yet
    // (e.g. first run on a new device before entitlements are registered).
    private let defaults: UserDefaults = {
        if let suite = UserDefaults(suiteName: "group.com.lkartvedt.PourChoices") {
            print("[Auth] Using App Group UserDefaults")
            return suite
        }
        print("[Auth] WARNING: App Group not available — falling back to standard UserDefaults")
        return .standard
    }()

    var state: AuthState = .unknown
    // Firebase UID -- used as the key for all Firestore documents
    private(set) var firebaseUID: String? = nil

    private var signInContinuation: CheckedContinuation<AuthState, Error>?
    private var currentNonce: String?

    override init() {
        super.init()
        restoreSession()
    }

    // MARK: - Session Restore

    private func restoreSession() {
        print("[Auth] restoreSession() — checking persisted credentials")

        // Restore Firebase session first
        if let firebaseUser = Auth.auth().currentUser {
            firebaseUID = firebaseUser.uid
            print("[Auth] Firebase session restored — UID: \(firebaseUser.uid)")
        } else {
            print("[Auth] No active Firebase session")
        }

        guard let userID = defaults.string(forKey: Keys.userID) else {
            print("[Auth] No persisted Apple userID — going to signedOut")
            state = .signedOut
            return
        }

        print("[Auth] Found persisted Apple userID, verifying credential state…")
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userID) { [weak self] credentialState, _ in
            DispatchQueue.main.async {
                switch credentialState {
                case .authorized:
                    let name  = self?.defaults.string(forKey: Keys.displayName)
                    let email = self?.defaults.string(forKey: Keys.email)
                    print("[Auth] Apple credential authorized — signing in as \(name ?? "unknown")")
                    self?.state = .signedIn(userID: userID, displayName: name, email: email)
                default:
                    print("[Auth] Apple credential not authorized (state: \(credentialState.rawValue)) — clearing session")
                    self?.clearPersistedSession()
                    self?.state = .signedOut
                }
            }
        }
    }

    // MARK: - Sign In with Apple

    @MainActor
    func signInWithApple() async throws {
        let nonce = randomNonce()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let _: AuthState = try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - Sign Out

    // NOTE ON DATA: Signing out clears the auth token only.
    // - SwiftData (local sessions, drink entries, etc.) stays on the device.
    // - The Firestore user document stays in the cloud.
    // - Signing back in with the same Apple ID restores full access to all data.
    @MainActor
    func signOut() {
        print("[Auth] signOut() called — current state: \(state)")
        do {
            try Auth.auth().signOut()
            print("[Auth] Firebase sign-out succeeded")
        } catch {
            print("[Auth] Firebase sign-out error (non-fatal): \(error)")
        }
        firebaseUID = nil
        clearPersistedSession()
        state = .signedOut
        print("[Auth] state is now: \(state)")
    }

    // MARK: - Firebase Sign In

    private func signInToFirebase(credential: ASAuthorizationAppleIDCredential,
                                  nonce: String?,
                                  displayName: String?,
                                  email: String?) async {
        guard
            let nonce,
            let appleIDToken = credential.identityToken,
            let tokenString = String(data: appleIDToken, encoding: .utf8)
        else {
            print("[Auth] signInToFirebase: missing nonce or identity token — skipping Firebase sign-in")
            return
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: tokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )

        do {
            let result = try await Auth.auth().signIn(with: firebaseCredential)
            let uid = result.user.uid
            await MainActor.run { self.firebaseUID = uid }
            // Create the Firestore user document if this is the first sign-in.
            await FirestoreService.shared.createUserIfNeeded(
                uid: uid,
                displayName: displayName,
                email: email
            )
        } catch {
            // Firebase sign-in failure is non-fatal -- local Apple auth still succeeds
            print("[AuthenticationManager] Firebase sign-in failed: \(error)")
        }
    }

    // MARK: - Helpers

    private func persistSession(userID: String, displayName: String?, email: String?, provider: String) {
        defaults.set(userID,      forKey: Keys.userID)
        defaults.set(displayName, forKey: Keys.displayName)
        defaults.set(email,       forKey: Keys.email)
        defaults.set(provider,    forKey: Keys.provider)
    }

    private func clearPersistedSession() {
        [Keys.userID, Keys.displayName, Keys.email, Keys.provider].forEach {
            defaults.removeObject(forKey: $0)
        }
    }

    // MARK: - Nonce

    private func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard errorCode == errSecSuccess else {
            fatalError("Unable to generate nonce: \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthenticationManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleID = authorization.credential as? ASAuthorizationAppleIDCredential else {
            print("[Auth] Sign-in failed — credential was not ASAuthorizationAppleIDCredential")
            signInContinuation?.resume(throwing: AuthError.credentialInvalid)
            signInContinuation = nil
            return
        }

        let userID = appleID.user
        let firstName = appleID.fullName?.givenName
        let lastName  = appleID.fullName?.familyName
        let displayName: String? = {
            let parts = [firstName, lastName].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }()
        let email = appleID.email

        print("[Auth] Apple sign-in succeeded — userID: \(userID), name: \(displayName ?? "nil"), email: \(email ?? "nil")")

        let storedName  = defaults.string(forKey: Keys.displayName)
        let storedEmail = defaults.string(forKey: Keys.email)
        persistSession(
            userID: userID,
            displayName: displayName ?? storedName,
            email: email ?? storedEmail,
            provider: "apple"
        )

        let newState = AuthState.signedIn(
            userID: userID,
            displayName: displayName ?? storedName,
            email: email ?? storedEmail
        )
        state = newState
        print("[Auth] state set to signedIn")
        signInContinuation?.resume(returning: newState)
        signInContinuation = nil

        // Capture nonce now before clearing it — the Task runs asynchronously and
        // currentNonce = nil below would execute before the Task body reads it.
        let capturedNonce = currentNonce
        currentNonce = nil

        // Sign into Firebase with the same Apple credential, and create Firestore user doc
        Task { await signInToFirebase(credential: appleID,
                                      nonce: capturedNonce,
                                      displayName: displayName ?? storedName,
                                      email: email ?? storedEmail) }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        let authErr: AuthError
        if let asError = error as? ASAuthorizationError, asError.code == .canceled {
            print("[Auth] Sign-in cancelled by user")
            authErr = .cancelled
        } else {
            print("[Auth] Sign-in error: \(error)")
            authErr = .unknown(error)
        }
        signInContinuation?.resume(throwing: authErr)
        signInContinuation = nil
        currentNonce = nil
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthenticationManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first(where: { $0.isKeyWindow }) ?? UIWindow()
    }
}
