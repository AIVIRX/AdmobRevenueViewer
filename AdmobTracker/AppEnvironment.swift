import Foundation
import Combine

@MainActor
final class AppEnvironment: ObservableObject {
    let authManager: AuthManaging
    @Published var apiClient: AdMobAPIClient
    @Published var adSenseClient: AdSenseAPIClient
    @Published private(set) var clientRevision = UUID()

    init(authManager: AuthManaging, apiClient: AdMobAPIClient? = nil, adSenseClient: AdSenseAPIClient? = nil) {
        self.authManager = authManager
        self.apiClient = apiClient ?? LiveAdMobAPIClient(authManager: authManager)
        self.adSenseClient = adSenseClient ?? LiveAdSenseAPIClient(authManager: authManager)
    }

    func useLiveClients() {
        apiClient = LiveAdMobAPIClient(authManager: authManager)
        adSenseClient = LiveAdSenseAPIClient(authManager: authManager)
        clientRevision = UUID()
    }

    func useGuestClients() {
        apiClient = MockAdMobAPIClient()
        adSenseClient = MockAdSenseAPIClient()
        clientRevision = UUID()
    }
}
