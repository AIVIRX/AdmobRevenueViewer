import SwiftUI
import StoreKit

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.requestReview) private var requestReview
    @State private var didRestore = false
    @State private var isRestoring = true
    @State private var didScheduleInterstitial = false
    @State private var didRequestReview = false

    var body: some View {
        Group {
            if isRestoring {
                SplashLoadingView()
            } else if appState.isSignedIn && !appState.isGuest {
                mainTabs
            } else if appState.isGuest {
                mainTabs
            } else {
                NavigationStack {
                    SignInView()
                }
            }
        }
        .task {
            await restoreIfNeeded()
            scheduleReviewIfNeeded()
        }
        .onChange(of: appState.isGuest) { _, isGuest in
            guard !isRestoring else { return }
            if isGuest {
                scheduleReviewIfNeeded()
            }
        }
        .onChange(of: appState.isSignedIn) { _, _ in
            guard !isRestoring else { return }
            scheduleReviewIfNeeded()
        }
    }

    private var mainTabs: some View {
        VStack(spacing: 0) {
            if appState.isGuest {
                GuestBanner {
                    exitGuestMode()
                }
            }
            TabView {
                DashboardView(apiClient: environment.apiClient)
                    .tabItem {
                        Label("Overview", systemImage: "chart.bar.xaxis")
                    }
                TwelveMonthEarningsView(apiClient: environment.apiClient)
                    .tabItem {
                        Label("This Year", systemImage: "calendar")
                    }
                ReportView(apiClient: environment.apiClient)
                    .tabItem {
                        Label("Account", systemImage: "person.fill")
                }
            }
            .id(environment.clientRevision)
        }
    }

    private func restoreIfNeeded() async {
        guard !didRestore else { return }
        didRestore = true
        isRestoring = true
        await environment.authManager.restorePreviousSignIn()
        if let user = environment.authManager.currentUser {
            appState.user = user
            let accounts = try? await environment.apiClient.fetchAccounts()
            appState.selectedAccount = accounts?.first
        }
        isRestoring = false
    }

    private func exitGuestMode() {
        environment.useLiveClients()
        appState.isGuest = false
        appState.user = nil
        appState.selectedAccount = nil
    }

    private func scheduleReviewIfNeeded() {
        guard !didRequestReview else { return }
        didRequestReview = true
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            requestReview()
        }
    }
}

private struct SplashLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Text("Loading your dashboard...")
                .font(.callout)
                .foregroundStyle(.secondary)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

private struct GuestBanner: View {
    let onSignIn: () -> Void

    var body: some View {
        Button(action: onSignIn) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(.tint)
                Text("Guest mode: Sign in with Google to view your data")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(Color(uiColor: .tertiarySystemFill)),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Guest mode. Sign in with Google")
    }
}
