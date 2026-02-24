import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var environment: AppEnvironment

    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("AdMob Revenue Viewer")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Sign in with Google to view your AdMob revenue across all apps and ad units.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await handleSignIn() }
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                    Text(isSigningIn ? "Signing In..." : "Continue with Google")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
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
            appState.user = profile
            let accounts = try await environment.apiClient.fetchAccounts()
            appState.selectedAccount = accounts.first
        } catch {
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
        }
        isSigningIn = false
    }
}
