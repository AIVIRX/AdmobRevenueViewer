import Foundation
import Combine

@MainActor
final class AppEnvironment: ObservableObject {
    let authManager: AuthManaging
    let apiClient: AdMobAPIClient

    init(authManager: AuthManaging, apiClient: AdMobAPIClient? = nil) {
        self.authManager = authManager
        self.apiClient = apiClient ?? LiveAdMobAPIClient(authManager: authManager)
    }
}
