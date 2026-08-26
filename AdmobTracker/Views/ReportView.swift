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
    @State private var didLoad = false

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
                            Text(unpaidAmount ?? "0.00")
                                .fontWeight(.semibold)
                        }
                        LabeledContent("Last Payment") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(lastPaymentAmount ?? "0.00")
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

                Section("Legal") {
                    Link(destination: URL(string: "https://www.aivirx.com/ad-earnings/privacy-policy")!) {
                        LabeledContent("Privacy Policy") {
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                        LabeledContent("Terms of Service") {
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://www.aivirx.com/contact")!) {
                        LabeledContent("Contact") {
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
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

                    if appState.isGuest {
                        Button {
                            environment.useLiveClients()
                            appState.isGuest = false
                            appState.user = nil
                            appState.selectedAccount = nil
                        } label: {
                            LabeledContent("Sign in with Google") {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        Task {
                            await environment.authManager.signOut()
                            WidgetBackgroundRefreshCoordinator.disable()
                            appState.user = nil
                            appState.selectedAccount = nil
                            appState.isGuest = false
                        }
                    } label: {
                        LabeledContent("Sign Out") {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.red)
                        }
                    }
                }


            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Account")
            .listStyle(.insetGrouped)
            .refreshable {
                await loadPayments()
                await accountsViewModel.load()
            }
            .task {
                guard !didLoad else { return }
                didLoad = true
                await accountsViewModel.load()
                if appState.selectedAccount == nil {
                    appState.selectedAccount = accountsViewModel.accounts.first
                }
                await loadPayments()
            }
            .onChange(of: appState.selectedAccount) { _, _ in
                Task { await loadPayments() }
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
                paymentsError = "No AdSense account found for this Google user."
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
            if let apiError = error as? AdSenseAPIError,
               case let .httpError(statusCode, body) = apiError,
               AdSenseAPIError.isUnauthenticated(statusCode: statusCode, body: body.lowercased()) {
                paymentsError = "No AdSense account found for this Google user."
            } else {
                paymentsError = "Payments unavailable: \(ErrorMessageFormatter.message(for: error))"
            }
        }
        isLoadingPayments = false
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
