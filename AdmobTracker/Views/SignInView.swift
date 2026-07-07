import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            VStack(spacing: 8) {
                Text("Ad Earnings for Admob")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Sign in with Google to view your AdMob revenue across all apps and ad units.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                Task { await handleSignIn() }
            } label: {
                HStack(spacing: 10) {
                    Image("googleLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                    Text(isSigningIn ? "Signing in..." : "Sign in with Google")
                        .font(.system(size: 14, weight: .medium))
                        .lineSpacing(6)
                        .foregroundStyle(buttonTextColor)
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(buttonFillColor)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(buttonStrokeColor, lineWidth: 1)
                )
            }
            .disabled(isSigningIn)
            Button {
                Task { await handleGuestSignIn() }
            } label: {
                Text(isSigningIn ? "Loading..." : "Try guest account")
                    .tint(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .disabled(isSigningIn)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(32)
    }

    private func handleSignIn() async {
        isSigningIn = true
        errorMessage = nil
        do {
            let profile = try await environment.authManager.signIn()
            environment.useLiveClients()
            let accounts = try await environment.apiClient.fetchAccounts()
            appState.selectedAccount = accounts.first
            appState.user = profile
            appState.isGuest = false
        } catch {
            errorMessage = "Sign-in failed: \(ErrorMessageFormatter.message(for: error))"
        }
        isSigningIn = false
    }

    private func handleGuestSignIn() async {
        isSigningIn = true
        errorMessage = nil
        environment.useGuestClients()
        appState.user = AuthUserProfile(email: "guest@local", displayName: "Guest", photoURL: nil)
        appState.isGuest = true
        do {
            let accounts = try await environment.apiClient.fetchAccounts()
            appState.selectedAccount = accounts.first
        } catch {
            errorMessage = "Unable to load guest data: \(ErrorMessageFormatter.message(for: error))"
        }
        isSigningIn = false
    }

    private var isDarkButton: Bool {
        colorScheme == .dark
    }

    private var buttonFillColor: Color {
        isDarkButton ? Color(red: 0.07, green: 0.07, blue: 0.08) : .white
    }

    private var buttonStrokeColor: Color {
        isDarkButton ? Color(red: 0.56, green: 0.57, blue: 0.56) : Color(red: 0.45, green: 0.47, blue: 0.46)
    }

    private var buttonTextColor: Color {
        isDarkButton ? Color(red: 0.89, green: 0.89, blue: 0.89) : Color(red: 0.12, green: 0.12, blue: 0.12)
    }
}
