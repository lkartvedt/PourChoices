import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @Environment(AuthenticationManager.self) private var auth
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo / branding
                Image("SplashPage")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280)
                    .padding(.bottom, 16)

                Spacer()

                // Sign-in buttons
                VStack(spacing: 14) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { _ in
                        // Handled via AuthenticationManager delegate; trigger the async path here.
                    }
                    // Use the custom async path so AuthenticationManager owns state
                    .overlay {
                        Button {
                            Task { await signInWithApple() }
                        } label: {
                            Color.clear
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .cornerRadius(AppLayout.buttonCornerRadius)
                    .disabled(isLoading)

                    if let msg = errorMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.horizontal, AppLayout.horizontalPadding)
                .padding(.bottom, 48)

                // Legal footer
                VStack(spacing: 6) {
                    Text("By continuing you agree to our Terms of Service and Privacy Policy.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.bottom, 32)
            }

            if isLoading {
                Color.black.opacity(0.4).ignoresSafeArea()
                ProgressView()
                    .tint(.white)
            }
        }
    }

    // MARK: - Actions

    private func signInWithApple() async {
        isLoading = true
        errorMessage = nil
        do {
            try await auth.signInWithApple()
        } catch AuthError.cancelled {
            // User tapped cancel — no message needed
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
