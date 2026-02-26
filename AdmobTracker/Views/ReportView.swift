import SwiftUI

struct ReportView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var accountsViewModel: AccountsViewModel
    @State private var isLoadingPayments = false
    @State private var paymentsError: String?
    @State private var unpaidAmount: String?
    @State private var lastPaymentAmount: String?
    @State private var lastPaymentDate: Date?

    init(apiClient: AdMobAPIClient) {
        _accountsViewModel = StateObject(wrappedValue: AccountsViewModel(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        profileImage
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.user?.displayName ?? "Google Account")
                                .font(.headline)
                            Text(appState.user?.email ?? "Not signed in")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                
                Section("Accounts") {
                    if accountsViewModel.isLoading {
                        ProgressView("Loading accounts...")
                    } else if let error = accountsViewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                    } else if accountsViewModel.accounts.isEmpty {
                        Text("No AdMob accounts found for this Google user.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(accountsViewModel.accounts) { account in
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

                Section("Payments") {
                    if isLoadingPayments {
                        HStack {
                            ProgressView()
                            Text("Loading payments…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let paymentsError {
                        Text(paymentsError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Unpaid") {
                            Text(unpaidAmount ?? "--")
                                .fontWeight(.semibold)
                        }
                        LabeledContent("Last Payment") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(lastPaymentAmount ?? "--")
                                    .fontWeight(.semibold)
                                if let lastPaymentDate {
                                    Text(formatDate(lastPaymentDate))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Section("Actions") {
                    ShareLink(item: shareMessage) {
                        LabeledContent("Share App") {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.tint)
                        }
                    }

                    Button(role: .destructive) {
                        Task {
                            await environment.authManager.signOut()
                            appState.user = nil
                            appState.selectedAccount = nil
                            appState.prefetchedReport = nil
                        }
                    } label: {
                        LabeledContent("Sign Out") {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.red)
                        }
                    }
                }


            }
            .navigationTitle("Account")
            .listStyle(.insetGrouped)
            .refreshable {
                await loadPayments()
                await accountsViewModel.load()
            }
            .task(id: appState.selectedAccount?.id) {
                await accountsViewModel.load()
                if appState.selectedAccount == nil {
                    appState.selectedAccount = accountsViewModel.accounts.first
                    return
                }
                await loadPayments()
            }
        }
    }

    private var shareMessage: String {
        "Check out AdmobTracker — a clean AdMob revenue viewer for iOS."
    }

    private var profileImage: some View {
        Group {
            if let url = appState.user?.photoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderImage
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholderImage
                    }
                }
            } else {
                placeholderImage
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .background(Circle().fill(Color(uiColor: .secondarySystemBackground)))
        .overlay(Circle().stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 1))
    }

    private var placeholderImage: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFill()
            .foregroundStyle(.secondary)
    }

    @MainActor
    private func loadPayments() async {
        guard appState.user != nil else { return }
        isLoadingPayments = true
        paymentsError = nil
        do {
            let accounts = try await environment.adSenseClient.fetchAccounts()
            guard let account = accounts.first else {
                paymentsError = "No AdSense account found."
                isLoadingPayments = false
                return
            }
            let payments = try await environment.adSenseClient.fetchPayments(accountName: account.name)
            let unpaid = payments.first { $0.name.hasSuffix("/payments/unpaid") }
            unpaidAmount = unpaid?.amount

            let datedPayments = payments.compactMap { payment -> (Date, AdSensePayment)? in
                guard let date = payment.date else { return nil }
                return (date, payment)
            }
            if let latest = datedPayments.sorted(by: { $0.0 > $1.0 }).first {
                lastPaymentDate = latest.0
                lastPaymentAmount = latest.1.amount
            } else {
                lastPaymentDate = nil
                lastPaymentAmount = nil
            }
        } catch {
            paymentsError = "Payments unavailable: \(error.localizedDescription)"
        }
        isLoadingPayments = false
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
