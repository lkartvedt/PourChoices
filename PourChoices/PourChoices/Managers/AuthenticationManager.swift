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

    private let defaults = UserDefaults(suiteName: "group.com.lkartvedt.PourChoices")!

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
        // Restore Firebase session first
        if let firebaseUser = Auth.auth().currentUser {
            firebaseUID = firebaseUser.uid
        }

        guard let userID = defaults.string(forKey: Keys.userID) else {
            state = .signedOut
            return
        }
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userID) { [weak self] credentialState, _ in
            DispatchQueue.main.async {
                switch credentialState {
                case .authorized:
                    let name  = self?.defaults.string(forKey: Keys.displayName)
                    let email = self?.defaults.string(forKey: Keys.email)
                    self?.state = .signedIn(userID: userID, displayName: name, email: email)
                default:
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

    func signOut() {
        try? Auth.auth().signOut()
        firebaseUID = nil
        clearPersistedSession()
        state = .signedOut
    }

    // MARK: - Firebase Sign In

    private func signInToFirebase(credential: ASAuthorizationAppleIDCredential) async {
        guard
            let nonce = currentNonce,
            let appleIDToken = credential.identityToken,
            let tokenString = String(data: appleIDToken, encoding: .utf8)
        else { return }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: tokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )

        do {
            let result = try await Auth.auth().signIn(with: firebaseCredential)
            await MainActor.run { self.firebaseUID = result.user.uid }
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
        signInContinuation?.resume(returning: newState)
        signInContinuation = nil

        // Sign into Firebase with the same Apple credential
        Task { await signInToFirebase(credential: appleID) }
        currentNonce = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        let authErr: AuthError
        if let asError = error as? ASAuthorizationError, asError.code == .canceled {
            authErr = .cancelled
        } else {
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
