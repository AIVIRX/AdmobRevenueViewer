import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var environment: AppEnvironment
    @State private var didRestore = false
    @State private var isRestoring = true

    var body: some View {
        Group {
            if isRestoring {
                SplashLoadingView()
            } else if appState.isSignedIn {
                TabView {
                    DashboardView(apiClient: environment.apiClient)
                        .tabItem {
                            Label("Overview", systemImage: "chart.bar.xaxis")
                        }
                    AccountsView(apiClient: environment.apiClient)
                        .tabItem {
                            Label("Accounts", systemImage: "person.2")
                        }
                    ReportView()
                        .tabItem {
                            Label("Account", systemImage: "person.circle")
                        }
                }
            } else {
                SignInView()
            }
        }
        .task {
            await restoreIfNeeded()
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
            if let account = appState.selectedAccount {
                let range = appState.dateRange
                if let report = try? await environment.apiClient.fetchReport(
                    accountId: account.id,
                    range: range,
                    timeZone: account.reportingTimeZone
                ) {
                    appState.prefetchedReport = PrefetchedReport(
                        accountId: account.id,
                        range: range,
                        timeZone: account.reportingTimeZone,
                        report: report
                    )
                }
            }
        }
        isRestoring = false
    }
}

private struct SplashLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.tint)
            Text("Loading your dashboard...")
                .font(.callout)
                .foregroundStyle(.secondary)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}
