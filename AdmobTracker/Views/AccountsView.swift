import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: AccountsViewModel

    init(apiClient: AdMobAPIClient) {
        _viewModel = StateObject(wrappedValue: AccountsViewModel(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading {
                    ProgressView("Loading accounts...")
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                } else if viewModel.accounts.isEmpty {
                    Text("No AdMob accounts found for this Google user.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.accounts) { account in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(account.displayName)
                                    .font(.headline)
                                Text(account.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if account == appState.selectedAccount {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.selectedAccount = account
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .task {
                await viewModel.load()
                if appState.selectedAccount == nil {
                    appState.selectedAccount = viewModel.accounts.first
                }
            }
        }
    }
}
