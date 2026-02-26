import Foundation
import Combine

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var report: AdMobReport?
    @Published var countrySummaries: [AdMobCountrySummary] = []
    @Published var errorMessage: String?
    @Published var appIconURLs: [String: URL] = [:]

    private let apiClient: AdMobAPIClient
    private let appStoreClient: AppStoreLookupClient
    private let playStoreClient: PlayStoreLookupClient
    private var loadedAppMetadataAccountId: String?

    init(apiClient: AdMobAPIClient, appStoreClient: AppStoreLookupClient? = nil, playStoreClient: PlayStoreLookupClient? = nil) {
        self.apiClient = apiClient
        self.appStoreClient = appStoreClient ?? LiveAppStoreLookupClient()
        self.playStoreClient = playStoreClient ?? LivePlayStoreLookupClient()
    }

    func load(accountId: String, range: DateRange, timeZone: String?) async {
        isLoading = true
        errorMessage = nil
        do {
            async let reportTask = apiClient.fetchReport(accountId: accountId, range: range, timeZone: timeZone)
            async let countryTask = apiClient.fetchCountryReport(accountId: accountId, range: range, timeZone: timeZone)
            report = try await reportTask
            countrySummaries = try await countryTask
            await loadAppMetadata(accountId: accountId)
        } catch {
            errorMessage = "Unable to load insights: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func loadAppMetadata(accountId: String) async {
        if loadedAppMetadataAccountId == accountId, !appIconURLs.isEmpty {
            return
        }
        do {
            let apps = try await apiClient.fetchApps(accountId: accountId)
            var icons: [String: URL] = [:]
            try await withThrowingTaskGroup(of: (String, URL?).self) { group in
                for app in apps {
                    guard let appStoreId = app.appStoreId else { continue }
                    let name = app.displayName
                    let platform = app.platform?.uppercased()
                    group.addTask {
                        if platform == "ANDROID" {
                            let url = try await self.playStoreClient.fetchIconURL(packageName: appStoreId)
                            return (name, url)
                        }
                        let url = try await self.appStoreClient.fetchIconURL(appStoreId: appStoreId)
                        return (name, url)
                    }
                }

                for try await (name, url) in group {
                    if let url {
                        icons[name] = url
                    }
                }
            }

            await MainActor.run {
                self.appIconURLs = icons
                self.loadedAppMetadataAccountId = accountId
            }
        } catch {
            // Keep metadata empty if the call fails.
        }
    }
}
