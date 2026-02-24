import Foundation
import Combine

@MainActor
final class AccountsViewModel: ObservableObject {
    @Published var accounts: [AdMobAccount] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: AdMobAPIClient

    init(apiClient: AdMobAPIClient) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            accounts = try await apiClient.fetchAccounts()
        } catch {
            errorMessage = "Unable to load accounts: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
