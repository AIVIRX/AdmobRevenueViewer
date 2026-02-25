import Foundation
import Combine

@MainActor
final class AppEnvironment: ObservableObject {
    let authManager: AuthManaging
    let apiClient: AdMobAPIClient
    let adSenseClient: AdSenseAPIClient

    init(authManager: AuthManaging, apiClient: AdMobAPIClient? = nil, adSenseClient: AdSenseAPIClient? = nil) {
        self.authManager = authManager
        self.apiClient = apiClient ?? LiveAdMobAPIClient(authManager: authManager)
        self.adSenseClient = adSenseClient ?? LiveAdSenseAPIClient(authManager: authManager)
    }
}
