import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var environment: AppEnvironment
    @State private var didRestore = false

    var body: some View {
        Group {
            if appState.isSignedIn {
                TabView {
                    DashboardView(apiClient: environment.apiClient)
                        .tabItem {
                            Label("Overview", systemImage: "chart.bar.xaxis")
                        }
                    AccountsView(apiClient: environment.apiClient)
                        .tabItem {
                            Label("Accounts", systemImage: "person.2")
                        }
                    ReportView(apiClient: environment.apiClient)
                        .tabItem {
                            Label("Reports", systemImage: "list.bullet.rectangle")
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
        await environment.authManager.restorePreviousSignIn()
        if let user = environment.authManager.currentUser {
            appState.user = user
            let accounts = try? await environment.apiClient.fetchAccounts()
            appState.selectedAccount = accounts?.first
        }
    }
}
