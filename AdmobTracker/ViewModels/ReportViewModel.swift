import Foundation
import Combine

@MainActor
final class ReportViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var report: AdMobReport?
    @Published var errorMessage: String?

    private let apiClient: AdMobAPIClient

    init(apiClient: AdMobAPIClient) {
        self.apiClient = apiClient
    }

    func load(accountId: String, range: DateRange, timeZone: String?) async {
        isLoading = true
        errorMessage = nil
        do {
            report = try await apiClient.fetchReport(accountId: accountId, range: range, timeZone: timeZone)
        } catch {
            errorMessage = "Unable to load report: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
