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
            if let apiError = error as? AdMobAPIError,
               case let .httpError(statusCode, body) = apiError,
               AdMobAPIError.isUnauthenticatedPublisher(statusCode: statusCode, body: body.lowercased()) {
                accounts = []
                errorMessage = nil
            } else {
                errorMessage = "Unable to load accounts: \(ErrorMessageFormatter.message(for: error))"
            }
        }
        isLoading = false
    }
}
